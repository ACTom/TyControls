// Upstream's own answers for dataZoom INTERACTION (wf62/upstream-interact.md; the
// static slider picture is datazoom-slider.js, the window processing
// datazoom-window.js): what the slider does when a handle, the move handle /
// filler or the body is dragged, clicked or brushed, when the pointer enters or
// leaves a handle / the move zone (labels, emphasis flags), and what an inside
// dataZoom does on the wheel and on a drag in the grid -- the dispatched
// 'dataZoom' actions, which dataZooms they reach (findEffectedDataZooms +
// setRawRange), the rangePropMode after them, the window the processor then
// computes, the slider's own _handleEnds / _range (kept on its own action,
// rebuilt on any other), the handle labels, and the inside view's range.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 800 x 600, with
// Math.random replaced by the port's xorshift32 (seed 2463534242, reset before
// each chart), and drives zrender's own Handler (handler.mousemove / mousedown /
// mouseup / click / mousewheel with synthetic events {zrX, zrY, zrDelta, which
// 1, shiftKey, ctrlKey, altKey, preventDefault, stopPropagation}): the Handler
// finds the hovered element (findHover), dispatches the element events and
// bubbles, and its handler-level listeners (zrender's Draggable, echarts'
// hover emphasis, the RoamController, the slider's zr-level brush listeners)
// run exactly as in a browser. A browser's DOM 'click' follows every mouseup;
// the scenarios send it (dt 0) and zrender's Handler decides whether it
// reaches an element (same element on down and up, moved <= 4 px).
//
// Time is FAKE and deterministic: global Date is replaced (new Date() / Date.now
// read a clock that starts at 1700000000000 and only moves between events), and
// global setTimeout / clearTimeout are a queue fired when the clock passes the
// due time (in due order, FIFO on ties; the clock is set to each timer's due
// time while it runs). So the throttle of _dispatchZoomAction / the roam
// dispatch (util/throttle 'fixRate', 100 ms by default) behaves as in a
// browser: a call less than 100 ms after the last executed one is deferred to
// lastExec + 100 and runs with the latest arguments. zrender's animation loop
// (requestAnimationFrame -> setTimeout 16 in node) runs from the same queue, so
// frames happen between events as in a browser (echarts' _onframe applies the
// hover states then). Before each event the clock advances by the step's dt
// (default 200 ms; 0 for a click; set explicitly where time matters), the due
// timers fire, and storage.getDisplayList(true) updates every element's
// transform (what a paint does), so hit testing sees the current geometry.
// Every scenario ends with an 'idle' step (dt 1000) that only fires timers.
//
//   node tools/advchart-oracle/datazoom-interact.js
//
// writes tests/fixtures/advchart-datazoom-interact.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as datazoom-slider.js / datazoom-window.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (NaN 7ff8000000000000). Every hex field has a readable
//            twin (xText beside x; String(v), '-0' for negative zero); null when
//            absent (twin null).
//   quad     {start, end, startValue, endValue}: hex | null each, + ...Text
//   matrix   [a, b, c, d, tx, ty] hex + ...Text (zrender 2x3: a point maps to
//            (a*x + c*y + tx, b*x + d*y + ty))
//   role     the element under the pointer, by name: 'dz<k>.handle0' /
//            'handle1' / 'filler' / 'moveZone' / 'clickPanel' / 'background' /
//            'frame' / 'moveHandle' / 'label0' ... for slider k's elements,
//            otherwise the component that drew it ('series0', 'xAxis0',
//            'grid0', ...), 'other', or null (nothing).
//   dz index the dataZoom's componentIndex (never its id: an auto id holds NULs)
//
// Top level
//   source, W, H, seed, clock {start, defaultDt {type: ms}}, api (the upstream
//   call behind each field), notes[]
//   scenarios[] one per chart:
//     id, groups, note, option (as fed to setOption)
//     layout   read after setOption, constant through the scenario (checked):
//       grid   grid 0's rect (coordinateSystem.getRect()) + gridText
//       dataZooms[] every dataZoom in component order:
//         index, subType ('slider' | 'inside'), targets [{dim, index}]
//         (eachTargetAxis order), throttle (the throttle rate), spansOption
//         {minSpan, maxSpan, minValueSpan, maxValueSpan} (the option, JSON)
//         slider: orient, realtime, zoomLock, brushSelect, showDetail,
//           handleLabelShow (handleLabel.show || false), emphasisHandleLabelShow
//           (emphasis.handleLabel.show || false), labelPrecision (JSON),
//           labelFormatter (string | null), size [length, thickness] hex + Text,
//           handleWidth hex + Text, local (sliderGroup.getLocalTransform()),
//           global (sliderGroup.transform), inv (sliderGroup.invTransform):
//           matrices, cursors {handle, move (moveZone, or the filler without
//           brushSelect), clickPanel} (the element `cursor` props), styles
//           {handle {fill, stroke}, handleEmphasis {fill, stroke, z2} (the
//           emphasis state after echarts' stateProxy: fill lifted), moveHandle
//           {fill, opacity} | null, moveHandleEmphasis (the raw state style,
//           JSON) | null, brush (brushStyle getItemStyle(), JSON)}
//         inside: disabled, zoomLock, zoomOnMouseWheel, moveOnMouseMove,
//           moveOnMouseWheel, preventDefaultMouseMove (the option values, JSON),
//           axis {dim, index, inverse} (the first target axis on the grid:
//           coordSysInfo.axisModels[0], what getDirectionInfo reads)
//       controller  null (no inside dataZoom) or grid 0's RoamController as
//         enabled: {mouse (mousedown/move/up listeners registered), wheel
//         (mousewheel listener registered), preventDefaultMouseMove, throttle}
//       axes[] every axis some dataZoom targets: key ('x0', 'y0', ...), dim,
//         index, type, inverse, host (the dataZoom index hosting its AxisProxy),
//         categories (category axis names, else null)
//     initial  the state after setOption (a step record without the event
//              fields)
//     steps[]  one per raw event:
//       i, event {type ('mousemove' | 'mousedown' | 'mouseup' | 'click' |
//         'mousewheel' | 'idle'), x, y (hex + Text; integers here), delta
//         (zrDelta, wheel only), keys {shift, ctrl, alt} (true ones only), t
//         (the clock, ms), dt}
//       hover, topTarget  roles of handler.findHover(x, y) just before the
//         event (the Handler's own hit test: target = topmost non-silent,
//         topTarget = topmost incl. silent); null for 'idle' and for a
//         mousemove / mouseup outside the canvas (the Handler does not hit-test
//         those: isOutsideBoundary)
//       cursors[]  every proxy.setCursor call during the step, in order
//       prevented  preventDefault was called on the raw event (eventTool.stop)
//       actions[]  every api.dispatchAction during the step (timers fired by
//         the clock advance first): {deferred (run from a throttle timer),
//         type, from (the dispatching slider's dz index | null), dataZoomIndex
//         (null if absent), animation (JSON | null), start, end, startValue,
//         endValue (hex | null + Text), batch null | [{dataZoomIndex, start,
//         end (+Text)}]}
//       grid   grid 0's rect after the step (+Text)
//       dataZooms[] every dataZoom after the step:
//         index, subType, settled (quad: settledOption), option (quad: the
//         model option -- setCalculatedRange writes the window into it),
//         rangePropMode [m0, m1], window {value, percent, percentInverted
//         [hex, hex], valuePrecision hex} + windowText (the representative
//         proxy's getWindow())
//         slider: handleEnds, range ([hex, hex] + Text: view._handleEnds /
//           _range), dragging (_dragging), overArea (_isOverDataInfoTriggerArea,
//           null before first set), brushing, brushRect null | {x, width (hex +
//           Text: brushRect.shape), ignore}, labels [{invisible, text, x, y (hex
//           + Text: the label's style x / y, view-group coords)}], handleHover
//           [h0, h1] (the handles' hoverState: 0 normal, 2 emphasis),
//           moveHandle null | {hoverState, highByOuter (the __highByOuter
//           bits: 1 = the move zone's mouseover, 2 = _showDataInfo)}, style
//           {handles [{fill, stroke}], moveHandleOpacity} (RECORD ONLY: the
//           style the last frame applied; frames run during the clock advance)
//         inside: range [hex, hex] + Text (the view's `range`)
//       axes[] per layout axis: key, extent (scale.getExtent() after the step,
//         RECORD ONLY), proxyExtent (the AxisProxy's _extent: the 0-100% base),
//         spans (getMinMaxSpan(): minSpan, minValueSpan, maxSpan, maxValueSpan
//         hex | null + Text), pxSpans [hex] + Text (|axis.getExtent()| read in
//         every calculateDataWindow on this axis during the step, in order)
//   guards[]  one per mutation of the transcription: id, mutation, named
//             (scenarios that must change), changed, ok (named subset of
//             changed), differs (first differing fields of each named scenario)
//
// ---------------------------------------------------------------------------
// The transcription (checked field by field, every step, bit for bit): the
// zrender Handler's event rules (mouseout / mousemove / mouseover order, the
// click rule), Draggable (dragstart / drift / dragend), the slider's handlers
// (_onDragMove with the inverted sliderGroup transform, _updateInterval,
// sliderMove, _onDragEnd, _onClickPanel, _onBrushStart / _onBrush /
// _updateBrushRect / _onBrushEnd with the 200 ms / 5 px rule, _showDataInfo,
// _onOverDataInfoTriggerArea, the move handle's __highByOuter bits, the
// handles' hover emphasis), the RoamController (mousedown / mousemove / mouseup
// / mousewheel, the pointer check against the grid, isAvailableBehavior with
// modifier keys, the wheel factors), InsideZoomView's zoom / pan / scrollMove,
// the roams batch, util/throttle 'fixRate', the dataZoom action
// (findEffectedDataZooms, setRawRange, _updateRangeUse), the processor
// (AxisProxy.reset -> _updateMinMaxSpan + calculateDataWindow for hosted axes,
// setCalculatedRange from findRepresentativeAxisProxy), the views' re-render
// (a slider keeps _handleEnds / _range on its own action, else _resetInterval
// and fresh elements; the inside view takes getPercentRange()), and the handle
// labels (formatLabel, the non-realtime calculateDataWindow, positions). Its
// inputs: the layout, each step's event, hover role and grid (the grid at an
// event is the previous record's), each axis's proxyExtent and pxSpans (the
// processing is datazoom-window.js's topic), and -- time axes only -- the
// scale's label of a rounded window value (read from upstream in memory).
//
// Self-checks (any failure: nothing is written, exit 1): the transcription
// reproduces every scenario; the layout is constant through each scenario;
// inv = invert(global) bit for bit; the transcribed controller settings match
// the registered listeners; anchors (H0R50 window percent 28.33 / 60; CLICK-6PX
// no click; BRUSH-STALE re-applies the old brush; IN-XY-LOCK zooms the locked
// x; RT-FALSE dispatches only on mouseup; THROTTLE has deferred actions);
// every guard is ok; no \u0000; the written JSON parses back; two generations
// in the process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

// ---------- the fake clock and timers (installed before the build loads) ----------
const RealDate = Date;
const CLOCK0 = 1700000000000;
let NOW = CLOCK0;
class FakeDate extends RealDate {
  constructor(...a) {
    if (a.length) super(...a);
    else super(NOW);
  }
  static now() { return NOW; }
}
global.Date = FakeDate;
let TIMERS = [];
let timerSeq = 0;
let FIRING = false;
global.setTimeout = function (fn, ms) {
  const id = ++timerSeq;
  TIMERS.push({ id, due: NOW + (+ms || 0), fn });
  return id;
};
global.clearTimeout = function (id) {
  TIMERS = TIMERS.filter(t => t.id !== id);
};
function advanceClock(to) {
  for (;;) {
    let best = null;
    for (const t of TIMERS) if (t.due <= to && (!best || t.due < best.due || (t.due === best.due && t.id < best.id))) best = t;
    if (!best) break;
    TIMERS = TIMERS.filter(t => t !== best);
    if (best.due > NOW) NOW = best.due;
    FIRING = true;
    try {
      best.fn();
    } finally {
      FIRING = false;
    }
  }
  NOW = to;
}

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-datazoom-interact.json');

const W = 800;
const H = 600;
const DEFAULT_DT = { mousemove: 200, mousedown: 200, mouseup: 200, click: 0, mousewheel: 200, idle: 1000 };

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- the seeded Math.random (the port's xorshift32) ----------
const SEED = 2463534242;
let rngState = SEED;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
};

// ---------- number records ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  if (h == null) return null;
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const hexOrNull = v => (v == null ? null : hex(v));
const textOrNull = v => (v == null ? null : text(v));
const numRec = (name, v) => ({ [name]: hex(v), [name + 'Text']: text(v) });
const numRecN = (name, v) => ({ [name]: hexOrNull(v), [name + 'Text']: textOrNull(v) });
const pairRec = (name, a) => ({ [name]: Array.from(a, hex), [name + 'Text']: Array.from(a, text) });
const matRec = (name, m) => ({ [name]: Array.from(m).map(hex), [name + 'Text']: Array.from(m).map(text) });
const RK = ['x', 'y', 'width', 'height'];
const rectRec = (name, r) => ({
  [name]: { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) },
  [name + 'Text']: { x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) },
});
const rectOf = rr => ({ x: num(rr.x), y: num(rr.y), width: num(rr.width), height: num(rr.height) });
const QK = ['start', 'end', 'startValue', 'endValue'];
function quadRec(name, o) {
  const a = {};
  const t = {};
  for (const k of QK) {
    const v = o[k];
    must(v == null || typeof v === 'number', name + '.' + k + ' is not a number: ' + JSON.stringify(v));
    a[k] = hexOrNull(v);
    t[k] = textOrNull(v);
  }
  return { [name]: a, [name + 'Text']: t };
}
const quadOf = q => { const o = {}; for (const k of QK) o[k] = num(q[k]); return o; };
const SPAN_KEYS = ['minSpan', 'minValueSpan', 'maxSpan', 'maxValueSpan'];
function spansRec(s) {
  const a = {};
  const t = {};
  for (const k of SPAN_KEYS) { a[k] = hexOrNull(s[k]); t[k] = textOrNull(s[k]); }
  return { spans: a, spansText: t };
}
const windowRec = w => ({
  window: { value: w.value.map(hex), percent: w.percent.map(hex), percentInverted: w.percentInverted.map(hex), valuePrecision: hex(w.valuePrecision) },
  windowText: { value: w.value.map(text), percent: w.percent.map(text), percentInverted: w.percentInverted.map(text), valuePrecision: text(w.valuePrecision) },
});
const windowOf = w => ({ value: w.value.map(num), percent: w.percent.map(num), percentInverted: w.percentInverted.map(num), valuePrecision: num(w.valuePrecision) });
const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
const J = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)));

// =====================================================================
// The transcription (mutations as switches in `mut`)
// =====================================================================

// util/number.ts linearMap
function linearMap(val, domain, range, clamp) {
  const d0 = domain[0];
  const d1 = domain[1];
  const r0 = range[0];
  const r1 = range[1];
  const subDomain = d1 - d0;
  const subRange = r1 - r0;
  if (subDomain === 0) return subRange === 0 ? r0 : (r0 + r1) / 2;
  if (clamp) {
    if (subDomain > 0) {
      if (val <= d0) return r0;
      else if (val >= d1) return r1;
    } else {
      if (val >= d0) return r0;
      else if (val <= d1) return r1;
    }
  } else {
    if (val === d0) return r0;
    if (val === d1) return r1;
  }
  return (val - d0) / subDomain * subRange + r0;
}
// util/number.ts round (returnStr false / true)
function round(x, precision) {
  if (isNaN(precision)) return +x;
  precision = Math.min(Math.max(0, precision), 20);
  return +(+x).toFixed(precision);
}
function roundStr(x, precision) {
  if (isNaN(precision)) return '' + x;
  precision = Math.min(Math.max(0, precision), 20);
  return (+x).toFixed(precision);
}
function getPrecisionSafe(val) {
  const str = val.toString().toLowerCase();
  const eIndex = str.indexOf('e');
  const exp = eIndex > 0 ? +str.slice(eIndex + 1) : 0;
  const significandPartLen = eIndex > 0 ? eIndex : str.length;
  const dotIndex = str.indexOf('.');
  const decimalPartLen = dotIndex < 0 ? 0 : significandPartLen - 1 - dotIndex;
  return Math.max(0, decimalPartLen - exp);
}
function getPrecision(val) {
  val = +val;
  if (isNaN(val)) return 0;
  if (val > 1e-14) {
    let e = 1;
    for (let i = 0; i < 15; i++, e *= 10) {
      if (Math.round(val * e) / e === val) return i;
    }
  }
  return getPrecisionSafe(val);
}
function addSafe(val0, val1) {
  const maxPrecision = Math.max(getPrecision(val0), getPrecision(val1));
  const sum = val0 + val1;
  return maxPrecision > 20 ? sum : round(sum, maxPrecision);
}
function getAcceptableTickPrecision(dataExtent, pxSpan, pxDiffAcceptable) {
  const dataSpan = Math.abs(dataExtent[1] - dataExtent[0]);
  if (!isFinite(dataSpan) || dataSpan === 0) return NaN;
  const dataExp2 = Math.log(2 * Math.abs(pxDiffAcceptable || 1) * Math.abs(dataSpan)) / Math.LN10;
  const pxExp = Math.log(Math.abs(pxSpan)) / Math.LN10;
  let precision = Math.max(0, Math.ceil(-dataExp2 + pxExp));
  if (!isFinite(precision)) precision = NaN;
  return precision;
}
// asc on two numbers with the (a, b) => a - b comparator
function asc2(a) {
  if (a[1] - a[0] < 0) { const t = a[0]; a[0] = a[1]; a[1] = t; }
  return a;
}
// component/helper/sliderMove.ts
function restrict(value, extend) {
  return Math.min(extend[1] != null ? extend[1] : Infinity, Math.max(extend[0] != null ? extend[0] : -Infinity, value));
}
function getSpanSign(handleEnds, handleIndex) {
  const dist = handleEnds[handleIndex] - handleEnds[1 - handleIndex];
  return { span: Math.abs(dist), sign: dist > 0 ? -1 : dist < 0 ? 1 : handleIndex ? -1 : 1 };
}
function sliderMove(delta, handleEnds, extent, handleIndex, minSpan, maxSpan) {
  delta = delta || 0;
  const extentSpan = addSafe(extent[1], -extent[0]);
  if (minSpan != null) minSpan = restrict(minSpan, [0, extentSpan]);
  if (maxSpan != null) maxSpan = Math.max(maxSpan, minSpan != null ? minSpan : 0);
  if (handleIndex === 'all') {
    let handleSpan = Math.abs(addSafe(handleEnds[1], -handleEnds[0]));
    handleSpan = restrict(handleSpan, [0, extentSpan]);
    minSpan = maxSpan = restrict(handleSpan, [minSpan, maxSpan]);
    handleIndex = 0;
  }
  handleEnds[0] = restrict(handleEnds[0], extent);
  handleEnds[1] = restrict(handleEnds[1], extent);
  const originalDistSign = getSpanSign(handleEnds, handleIndex);
  handleEnds[handleIndex] += delta;
  const extentMinSpan = minSpan || 0;
  const realExtent = extent.slice();
  if (originalDistSign.sign < 0) realExtent[0] = addSafe(realExtent[0], extentMinSpan);
  else realExtent[1] = addSafe(realExtent[1], -extentMinSpan);
  handleEnds[handleIndex] = restrict(handleEnds[handleIndex], realExtent);
  let currDistSign = getSpanSign(handleEnds, handleIndex);
  if (minSpan != null && (currDistSign.sign !== originalDistSign.sign || currDistSign.span < minSpan)) {
    handleEnds[1 - handleIndex] = addSafe(handleEnds[handleIndex], originalDistSign.sign * minSpan);
  }
  currDistSign = getSpanSign(handleEnds, handleIndex);
  if (maxSpan != null && currDistSign.span > maxSpan) {
    handleEnds[1 - handleIndex] = addSafe(handleEnds[handleIndex], currDistSign.sign * maxSpan);
  }
  return handleEnds;
}
// zrender core/matrix.ts invert, mul; core/vector.ts applyTransform
function invert(a) {
  const aa = a[0]; const ac = a[2]; const atx = a[4];
  const ab = a[1]; const ad = a[3]; const aty = a[5];
  let det = aa * ad - ab * ac;
  if (!det) return null;
  det = 1.0 / det;
  return [ad * det, -ab * det, -ac * det, aa * det, (ac * aty - ad * atx) * det, (ab * atx - aa * aty) * det];
}
function mul(m1, m2) {
  return [
    m1[0] * m2[0] + m1[2] * m2[1],
    m1[1] * m2[0] + m1[3] * m2[1],
    m1[0] * m2[2] + m1[2] * m2[3],
    m1[1] * m2[2] + m1[3] * m2[3],
    m1[0] * m2[4] + m1[2] * m2[5] + m1[4],
    m1[1] * m2[4] + m1[3] * m2[5] + m1[5],
  ];
}
const applyT = (v, m) => [m[0] * v[0] + m[2] * v[1] + m[4], m[1] * v[0] + m[3] * v[1] + m[5]];

// Scale#parse for the option values used here (numbers only)
function scaleParse(ax, val) {
  if (val == null) return NaN;
  must(typeof val === 'number', 'a non-number range value is not transcribed');
  if (ax.type === 'category' || ax.type === 'time') return Math.round(val);
  return val;
}
// AxisProxy._updateMinMaxSpan (the HOST dataZoom's options)
function minMaxSpan(ax, o, dataExtent) {
  const spans = {};
  for (const mm of ['min', 'max']) {
    let percentSpan = o[mm + 'Span'];
    let valueSpan = o[mm + 'ValueSpan'];
    if (valueSpan != null) valueSpan = scaleParse(ax, valueSpan);
    if (valueSpan != null) percentSpan = linearMap(dataExtent[0] + valueSpan, dataExtent, [0, 100], true);
    else if (percentSpan != null) valueSpan = linearMap(percentSpan, [0, 100], dataExtent, true) - dataExtent[0];
    spans[mm + 'Span'] = percentSpan == null ? null : percentSpan;
    spans[mm + 'ValueSpan'] = valueSpan == null ? null : valueSpan;
  }
  return spans;
}
// AxisProxy.calculateDataWindow (ensureExtentAscSimply is a no-op: it only acts on a valid, i.e. ascending, extent)
function calculateDataWindow(ax, opt, modes, dataExtent, spans, pxSpan) {
  const percentExtent = [0, 100];
  const percentWindow = [];
  const valueWindow = [];
  let hasPropModeValue = false;
  const needRound = [false, false];
  ['start', 'end'].forEach((prop, idx) => {
    let boundPercent = opt[prop];
    let boundValue = opt[prop + 'Value'];
    if (modes[idx] === 'percent') {
      if (boundPercent == null) boundPercent = percentExtent[idx];
      boundValue = linearMap(boundPercent, percentExtent, dataExtent);
      needRound[idx] = true;
    } else {
      hasPropModeValue = true;
      if (boundValue == null) boundValue = dataExtent[idx];
      else boundValue = scaleParse(ax, boundValue);
      boundPercent = linearMap(boundValue, dataExtent, percentExtent);
    }
    valueWindow[idx] = boundValue == null || isNaN(boundValue) ? dataExtent[idx] : boundValue;
    percentWindow[idx] = boundPercent == null || isNaN(boundPercent) ? percentExtent[idx] : boundPercent;
  });
  asc2(valueWindow);
  asc2(percentWindow);
  const restrictSet = (fromWindow, toWindow, fromExtent, toExtent, toValue) => {
    const suffix = toValue ? 'Span' : 'ValueSpan';
    sliderMove(0, fromWindow, fromExtent, 'all', spans['min' + suffix], spans['max' + suffix]);
    for (let i = 0; i < 2; i++) {
      toWindow[i] = linearMap(fromWindow[i], fromExtent, toExtent, true);
      if (toValue) needRound[i] = true;
    }
  };
  if (hasPropModeValue) restrictSet(valueWindow, percentWindow, dataExtent, percentExtent, false);
  else restrictSet(percentWindow, valueWindow, percentExtent, dataExtent, true);
  const isOrdOrTime = ax.type === 'category' || ax.type === 'time';
  const precision = isOrdOrTime ? 0 : getAcceptableTickPrecision(valueWindow, pxSpan, 0.5);
  [[0, Math.ceil], [1, Math.floor]].forEach(([idx, ceilOrFloor]) => {
    if (!needRound[idx] || !isFinite(precision)) return;
    valueWindow[idx] = round(valueWindow[idx], precision);
    valueWindow[idx] = Math.min(dataExtent[1], Math.max(dataExtent[0], valueWindow[idx]));
    if (percentWindow[idx] === percentExtent[idx]) {
      valueWindow[idx] = dataExtent[idx];
      if (isOrdOrTime) valueWindow[idx] = ceilOrFloor(valueWindow[idx]);
    }
  });
  const percentInverted = [linearMap(valueWindow[0], dataExtent, percentExtent, true), linearMap(valueWindow[1], dataExtent, percentExtent, true)];
  return { value: valueWindow, percent: percentWindow, percentInverted, valuePrecision: precision };
}

const cloneWin = w => ({ value: w.value.slice(), percent: w.percent.slice(), percentInverted: w.percentInverted.slice(), valuePrecision: w.valuePrecision });

// The whole interaction: returns the transcribed dynamic record of every step.
function simulate(sc, side, mut) {
  const L = sc.layout;
  const axes = {};
  for (const a of L.axes) axes[a.key] = a;
  const S = {
    now: CLOCK0, timers: [], seq: 0, log: null, step: null,
    grid: rectOf(L.grid),
    hs: { hovered: null, downEl: null, upEl: null, downPoint: null },
    drag: { target: null, x: 0, y: 0 },
    roam: { dragging: false, x: 0, y: 0 },
    throttles: {},
    dz: [], proxies: {},
  };
  const init = sc.initial;
  // ---- the model (from the initial record: the processing is datazoom-window.js's) ----
  for (const lz of L.dataZooms) {
    const r = init.dataZooms[lz.index];
    const d = {
      index: lz.index, subType: lz.subType, L: lz, targets: lz.targets.map(t => t.dim + t.index),
      settled: quadOf(r.settled), option: quadOf(r.option), modes: r.rangePropMode.slice(),
    };
    if (lz.subType === 'slider') {
      const lm = lz.local.map(num);
      d.sl = {
        size: lz.size.map(num), local: lm, inv: lz.inv.map(num), handleWidth: num(lz.handleWidth),
        handleEnds: r.handleEnds.map(num), range: r.range.map(num), dragging: r.dragging, overArea: r.overArea,
        brushing: r.brushing, brushStart: null, brushStartTime: 0, brushRect: r.brushRect ? { x: num(r.brushRect.x), width: num(r.brushRect.width), ignore: r.brushRect.ignore } : null,
        labels: r.labels.map(l => ({ invisible: l.invisible, text: l.text, x: num(l.x), y: num(l.y) })),
        handleHover: r.handleHover.slice(), moveHandle: r.moveHandle ? Object.assign({}, r.moveHandle) : null,
      };
    } else {
      d.range = r.range.map(num);
    }
    S.dz.push(d);
  }
  for (const a of L.axes) {
    const ar = init.axes.find(x => x.key === a.key);
    S.proxies[a.key] = { key: a.key, ax: a, host: a.host, extent: ar.proxyExtent.map(num), spans: null, window: null };
    S.proxies[a.key].spans = minMaxSpan(a, S.dz[a.host].L.spansOption, S.proxies[a.key].extent);
  }
  const rep = d => {
    for (const k of d.targets) if (S.proxies[k].host === d.index) return S.proxies[k];
    return S.proxies[d.targets[0]];
  };
  // a proxy's initial window: the one recorded for a dataZoom whose representative proxy it is
  for (const d of S.dz) {
    const p = rep(d);
    if (!p.window) p.window = windowOf(init.dataZooms[d.index].window);
  }
  // ---- timers and the throttle (util/throttle.ts 'fixRate') ----
  function addTimer(due, fn) {
    const t = { id: ++S.seq, due, fn };
    S.timers.push(t);
    return t;
  }
  function advance(to) {
    for (;;) {
      let best = null;
      for (const t of S.timers) if (t.due <= to && (!best || t.due < best.due || (t.due === best.due && t.id < best.id))) best = t;
      if (!best) break;
      S.timers = S.timers.filter(t => t !== best);
      if (best.due > S.now) S.now = best.due;
      S.deferred = true;
      best.fn();
      S.deferred = false;
    }
    S.now = to;
  }
  function throttled(key, delay, args, fn) {
    if (mut.noThrottle) { fn(args); return; }
    const th = S.throttles[key] || (S.throttles[key] = { lastExec: 0, lastCall: 0, timer: null, args: null });
    const curr = S.now;
    th.args = args;
    delay = delay || 0;
    const diff = curr - th.lastExec - delay;
    if (th.timer) { S.timers = S.timers.filter(t => t !== th.timer); th.timer = null; }
    const exec = () => { th.lastExec = S.now; th.timer = null; fn(th.args); };
    if (diff >= 0) exec();
    else th.timer = addTimer(curr + -diff, exec);
    th.lastCall = curr;
  }
  // ---- the processing and the re-render ----
  function consumePx(key) {
    const q = S.step.px[key];
    if (!q || !q.length) return NaN;
    return q.shift();
  }
  function effected(dzIndex) {
    if (mut.noFollow) return [dzIndex];
    const out = [dzIndex];
    const axisRec = new Set(S.dz[dzIndex].targets);
    let found;
    do {
      found = false;
      for (const d of S.dz) {
        if (out.includes(d.index)) continue;
        if (d.targets.some(k => axisRec.has(k))) {
          out.push(d.index);
          d.targets.forEach(k => axisRec.add(k));
          found = true;
        }
      }
    } while (found);
    return out;
  }
  function setRawRange(d, opt) {
    [['start', 'startValue'], ['end', 'endValue']].forEach(names => {
      if (opt[names[0]] != null || opt[names[1]] != null) {
        d.settled[names[0]] = opt[names[0]] == null ? null : opt[names[0]];
        d.settled[names[1]] = opt[names[1]] == null ? null : opt[names[1]];
        d.option[names[0]] = d.settled[names[0]];
        d.option[names[1]] = d.settled[names[1]];
      }
    });
    if (mut.modeKept) return;
    // _updateRangeUse
    [['start', 'startValue'], ['end', 'endValue']].forEach((names, i) => {
      const p = opt[names[0]] != null;
      const v = opt[names[1]] != null;
      if (p && !v) d.modes[i] = 'percent';
      else if (!p && v) d.modes[i] = 'value';
      else if (d.L.rangeMode) d.modes[i] = d.L.rangeMode[i];
      else if (p) d.modes[i] = 'percent';
    });
  }
  function dispatch(payload) {
    S.log.actions.push(actionOut(payload, S.deferred));
    const items = payload.batch ? payload.batch.map(it => Object.assign({}, payload, it, { batch: null })) : [payload];
    for (const it of items) for (const k of effected(it.dataZoomIndex)) setRawRange(S.dz[k], it);
    // dataZoomProcessor.overallReset
    for (const d of S.dz) {
      for (const k of d.targets) {
        const p = S.proxies[k];
        if (p.host !== d.index) continue;
        p.extent = S.step.proxyExtent[k].slice();
        p.spans = minMaxSpan(p.ax, d.L.spansOption, p.extent);
        p.window = calculateDataWindow(p.ax, d.settled, d.modes, p.extent, p.spans, consumePx(k));
      }
    }
    for (const d of S.dz) {
      const w = rep(d).window;
      d.option = { start: w.percent[0], end: w.percent[1], startValue: w.value[0], endValue: w.value[1] };
    }
    // the views
    for (const d of S.dz) {
      if (d.sl) {
        if (mut.noOwnSkip || !(payload.type === 'dataZoom' && payload.from === d.index)) rebuild(d);
        updateView(d, false);
      } else {
        d.range = rep(d).window.percent.slice();
      }
    }
  }
  function rebuild(d) {
    const sl = d.sl;
    sl.brushing = false;
    sl.brushRect = null;
    sl.range = rep(d).window.percent.slice();
    sl.handleEnds = [linearMap(sl.range[0], [0, 100], [0, sl.size[0]], true), linearMap(sl.range[1], [0, 100], [0, sl.size[0]], true)];
    sl.labels.forEach(l => { l.invisible = !d.L.handleLabelShow; });
    sl.handleHover = [0, 0];
    if (sl.moveHandle) sl.moveHandle = { hoverState: 0, highByOuter: 0 };
  }
  function formatLabel(d, idx, w) {
    const a = rep(d).ax;
    let labelPrecision = d.L.labelPrecision;
    if (labelPrecision == null || labelPrecision === 'auto') labelPrecision = w.valuePrecision;
    const value = w.value[idx];
    let valueStr;
    if (value == null || isNaN(value)) valueStr = '';
    else if (a.type === 'category') { const c = a.categories[Math.round(value)]; valueStr = c == null ? '' : c + ''; }
    else if (a.type === 'time') valueStr = side.timeLabels.get(a.key + '/' + Math.round(value));
    else if (isFinite(labelPrecision)) valueStr = roundStr(value, labelPrecision);
    else valueStr = value + '';
    const f = d.L.labelFormatter;
    return typeof f === 'string' ? f.replace('{value}', valueStr) : valueStr;
  }
  function updateView(d, nonRealtime) {
    const sl = d.sl;
    let texts = ['', ''];
    if (d.L.showDetail) {
      const p = rep(d);
      let w;
      if (nonRealtime) w = calculateDataWindow(p.ax, { start: sl.range[0], end: sl.range[1] }, S.dz[p.host].modes, p.extent, p.spans, consumePx(p.key));
      else w = p.window;
      texts = [formatLabel(d, 0, w), formatLabel(d, 1, w)];
    }
    const ordered = asc2(sl.handleEnds.slice());
    const barT = mulLeft(sl.local);
    const offset = sl.handleWidth / 2 + 5;
    for (const i of [0, 1]) {
      const pt = applyT([ordered[i] + (i === 0 ? -offset : offset), sl.size[1] / 2], barT);
      sl.labels[i].x = pt[0];
      sl.labels[i].y = pt[1];
      sl.labels[i].text = texts[i];
    }
  }
  // graphic.getTransform(sliderGroup, group): mul(identity, local, identity) as upstream's loop does it
  function mulLeft(local) {
    return mul(local, [1, 0, 0, 1, 0, 0]);
  }
  // ---- the slider's handlers ----
  function slSpansPx(d) {
    const s = rep(d).spans;
    const len = d.sl.size[0];
    if (mut.spansIgnored) return [null, null];
    return [s.minSpan != null ? linearMap(s.minSpan, [0, 100], [0, len], true) : null, s.maxSpan != null ? linearMap(s.maxSpan, [0, 100], [0, len], true) : null];
  }
  function updateInterval(d, handleIndex, delta) {
    const sl = d.sl;
    const sp = slSpansPx(d);
    const ext = [0, sl.size[0]];
    sliderMove(delta, sl.handleEnds, ext, d.L.zoomLock && !mut.noZoomLock ? 'all' : handleIndex, sp[0], sp[1]);
    const last = sl.range;
    const range = sl.range = asc2([linearMap(sl.handleEnds[0], ext, [0, 100], true), linearMap(sl.handleEnds[1], ext, [0, 100], true)]);
    return !last || last[0] !== range[0] || last[1] !== range[1];
  }
  function slDispatch(d, realtime) {
    throttled('slider' + d.index, d.L.throttle, realtime, rt => {
      dispatch({ type: 'dataZoom', from: d.index, dataZoomIndex: d.index, animation: rt ? { easing: 'cubicOut', duration: 100, delay: 0 } : null, start: d.sl.range[0], end: d.sl.range[1] });
    });
  }
  function onDragMove(d, handleIndex, dx, dy) {
    const sl = d.sl;
    sl.dragging = true;
    S.log.prevented = true;
    let v;
    if (mut.screenDx) v = [dx, dy];
    else if (mut.noInvert) v = applyT([dx, dy], sl.local);
    else v = applyT([dx, dy], invert(sl.local));
    const changed = updateInterval(d, handleIndex, v[0]);
    const realtime = mut.realtimeIgnored ? true : d.L.realtime;
    updateView(d, !realtime);
    if (changed && realtime) slDispatch(d, true);
  }
  function onDragEnd(d) {
    d.sl.dragging = false;
    if (!d.sl.overArea) showDataInfo(d, false);
    const realtime = mut.realtimeIgnored ? true : d.L.realtime;
    if (!realtime) slDispatch(d, false);
  }
  function enterEmph(mh, digit) {
    mh.highByOuter |= 1 << digit;
    mh.hoverState = 2;
  }
  function leaveEmph(mh, digit) {
    mh.highByOuter &= ~(1 << digit);
    if (mut.bitsIgnored) mh.highByOuter = 0;
    if (!mh.highByOuter && mh.hoverState === 2) mh.hoverState = 0;
  }
  function showDataInfo(d, isEmphasis) {
    const toShow = (isEmphasis || (d.sl.dragging && !mut.dragHides)) ? d.L.emphasisHandleLabelShow : d.L.handleLabelShow;
    d.sl.labels.forEach(l => { l.invisible = !toShow; });
    if (d.sl.moveHandle) (toShow ? enterEmph : leaveEmph)(d.sl.moveHandle, 1);
  }
  function overArea(d, isOver) {
    d.sl.overArea = isOver;
    showDataInfo(d, isOver);
  }
  function clickPanel(d, ev) {
    const sl = d.sl;
    const lp = applyT([ev.x, ev.y], sl.inv);
    if (lp[0] < 0 || lp[0] > sl.size[0] || lp[1] < 0 || lp[1] > sl.size[1]) return;
    const center = (sl.handleEnds[0] + sl.handleEnds[1]) / 2;
    const changed = updateInterval(d, 'all', lp[0] - center);
    updateView(d, false);
    if (changed) slDispatch(d, false);
  }
  function brushStart(d, ev) {
    d.sl.brushStart = [ev.x, ev.y];
    d.sl.brushing = true;
    d.sl.brushStartTime = S.now;
    if (mut.freshBrush) d.sl.brushRect = null;
  }
  function onBrush(d, ev) {
    const sl = d.sl;
    if (!sl.brushing) return;
    S.log.prevented = true;
    if (!sl.brushRect) sl.brushRect = { x: 0, width: 0, ignore: false };
    sl.brushRect.ignore = false;
    const end = applyT([ev.x, ev.y], sl.inv);
    const start = applyT(sl.brushStart, sl.inv);
    end[0] = Math.max(Math.min(sl.size[0], end[0]), 0);
    sl.brushRect.x = start[0];
    sl.brushRect.width = end[0] - start[0];
  }
  function brushEnd(d) {
    const sl = d.sl;
    if (!sl.brushing) return;
    const br = sl.brushRect;
    sl.brushing = false;
    if (!br) return;
    br.ignore = true;
    if ((mut.brushWidthOnly || S.now - sl.brushStartTime < 200) && Math.abs(br.width) < 5) return;
    const ext = [0, sl.size[0]];
    sl.handleEnds = [br.x, br.x + br.width];
    const sp = slSpansPx(d);
    sliderMove(0, sl.handleEnds, ext, 0, sp[0], sp[1]);
    sl.range = asc2([linearMap(sl.handleEnds[0], ext, [0, 100], true), linearMap(sl.handleEnds[1], ext, [0, 100], true)]);
    updateView(d, false);
    slDispatch(d, false);
  }
  // ---- roles ----
  function parseRole(role) {
    const m = /^dz(\d+)\.(.+)$/.exec(role || '');
    return m ? { d: S.dz[+m[1]], part: m[2] } : null;
  }
  function isDraggable(role) {
    const r = parseRole(role);
    if (!r || !r.d.sl) return false;
    return r.part === 'handle0' || r.part === 'handle1' || (r.d.L.brushSelect ? r.part === 'moveZone' : r.part === 'filler');
  }
  const isMoveZone = r => r && r.d.sl && (r.d.L.brushSelect ? r.part === 'moveZone' : r.part === 'filler');
  // element-level handlers, then the Handler's own listeners (zrender Handler.dispatchToElement)
  function dispatchEl(role, name, ev) {
    const r = parseRole(role);
    if (r && r.d.sl) {
      const d = r.d;
      const hi = r.part === 'handle0' ? 0 : r.part === 'handle1' ? 1 : -1;
      if (hi >= 0 || isMoveZone(r)) {
        if (name === 'mouseover') overArea(d, true);
        if (name === 'mouseout') overArea(d, false);
        if (isMoveZone(r) && d.sl.moveHandle) {
          if (name === 'mouseover') enterEmph(d.sl.moveHandle, 0);
          if (name === 'mouseout') leaveEmph(d.sl.moveHandle, 0);
        }
      }
      if (r.part === 'clickPanel') {
        if (name === 'mousedown' && d.L.brushSelect) brushStart(d, ev);
        if (name === 'click') clickPanel(d, ev);
      }
    }
    // handler-level listeners
    if (name === 'mouseover' && r && r.d.sl && (r.part === 'handle0' || r.part === 'handle1')) {
      const i = r.part === 'handle0' ? 0 : 1;
      r.d.sl.handleHover[i] = 2;
    }
    if (name === 'mouseout' && r && r.d.sl && (r.part === 'handle0' || r.part === 'handle1')) {
      const i = r.part === 'handle0' ? 0 : 1;
      if (r.d.sl.handleHover[i] === 2) r.d.sl.handleHover[i] = 0;
    }
    if (name === 'mousedown') { dragStart(role, ev); roamDown(role, ev); }
    if (name === 'mousemove') { dragDrag(ev); roamMove(ev); for (const d of S.dz) if (d.sl && d.L.brushSelect) onBrush(d, ev); }
    if (name === 'mouseup') { dragEnd(); roamUp(); for (const d of S.dz) if (d.sl && d.L.brushSelect) brushEnd(d); }
    if (name === 'mousewheel') roamWheel(ev);
  }
  // zrender Draggable
  function dragStart(role, ev) {
    if (!isDraggable(role)) return;
    S.drag = { target: role, x: ev.x, y: ev.y };
    const r = parseRole(role);
    if (isMoveZone(r)) showDataInfo(r.d, true);
  }
  function dragDrag(ev) {
    if (!S.drag.target) return;
    const dx = ev.x - S.drag.x;
    const dy = ev.y - S.drag.y;
    S.drag.x = ev.x;
    S.drag.y = ev.y;
    const r = parseRole(S.drag.target);
    onDragMove(r.d, r.part === 'handle0' ? 0 : r.part === 'handle1' ? 1 : 'all', dx, dy);
  }
  function dragEnd() {
    if (S.drag.target) onDragEnd(parseRole(S.drag.target).d);
    S.drag.target = null;
  }
  // ---- the RoamController of grid 0 and InsideZoomView ----
  const C = L.controller;
  const insides = S.dz.filter(d => d.subType === 'inside');
  function containPoint(x, y) {
    const g = S.grid;
    if (mut.containRect) return x >= g.x && x <= g.x + g.width && y >= g.y && y <= g.y + g.height;
    const lx = x - g.x;
    const ly = (0 + g.height) - y + g.y;
    return lx >= 0 && lx <= g.width && ly >= 0 && ly <= g.height;
  }
  function isAvailable(behavior, ev, settings) {
    const setting = settings[behavior];
    return !!(setting && (typeof setting !== 'string' || ev.keys[setting]));
  }
  function roamDown(role, ev) {
    if (!C || !C.mouse) return;
    if (isDraggable(role)) return;
    if (containPoint(ev.x, ev.y)) {
      S.roam.x = ev.x;
      S.roam.y = ev.y;
      S.roam.dragging = true;
    }
  }
  function roamUp() {
    if (!C || !C.mouse) return;
    S.roam.dragging = false;
  }
  function dirInfo(d, oldPoint, newPoint) {
    const a = d.L.axis;
    const g = S.grid;
    oldPoint = oldPoint || [0, 0];
    if (a.dim === 'x') return { pixel: newPoint[0] - oldPoint[0], pixelLength: g.width, pixelStart: g.x, signal: (a.inverse && !mut.panSign) ? 1 : -1 };
    return { pixel: newPoint[1] - oldPoint[1], pixelLength: g.height, pixelStart: g.y, signal: (a.inverse && !mut.panSign) ? -1 : 1 };
  }
  function mover(d, percentDelta) {
    const lastRange = d.range;
    const range = lastRange.slice();
    sliderMove(percentDelta, range, [0, 100], 'all');
    d.range = range;
    if (lastRange[0] !== range[0] || lastRange[1] !== range[1]) return range;
  }
  const handlers = {
    zoom(d, e) {
      const lastRange = d.range;
      const range = lastRange.slice();
      const di = dirInfo(d, null, [e.originX, e.originY]);
      const pp = mut.zoomCentre ? (range[0] + range[1]) / 2 : ((di.signal > 0 ? (di.pixelStart + di.pixelLength - di.pixel) : (di.pixel - di.pixelStart)) / di.pixelLength * (range[1] - range[0]) + range[0]);
      const scale = Math.max(1 / e.scale, 0);
      range[0] = (range[0] - pp) * scale + pp;
      range[1] = (range[1] - pp) * scale + pp;
      const s = rep(d).spans;
      sliderMove(0, range, [0, 100], 0, s.minSpan, s.maxSpan);
      d.range = range;
      if (lastRange[0] !== range[0] || lastRange[1] !== range[1]) return range;
    },
    pan(d, e) {
      const di = dirInfo(d, [e.oldX, e.oldY], [e.newX, e.newY]);
      const range = d.range;
      return mover(d, di.signal * (range[1] - range[0]) * di.pixel / di.pixelLength);
    },
    scrollMove(d, e) {
      const di = dirInfo(d, [0, 0], [e.scrollDelta, e.scrollDelta]);
      const range = d.range;
      return mover(d, di.signal * (range[1] - range[0]) * e.scrollDelta);
    },
  };
  function trigger(eventName, behavior, ev, ce) {
    const batch = [];
    for (const d of insides) {
      if (!isAvailable(behavior, ev, d.L)) continue;
      const range = handlers[eventName](d, ce);
      if (!d.L.disabled && range) batch.push({ dataZoomIndex: d.index, start: range[0], end: range[1] });
    }
    if (batch.length) throttled('grid0', C.throttle, batch, b => dispatch({ type: 'dataZoom', from: null, dataZoomIndex: null, animation: { easing: 'cubicOut', duration: 100 }, batch: b }));
  }
  function roamMove(ev) {
    if (!C || !C.mouse) return;
    if (!S.roam.dragging) return;
    const oldX = S.roam.x;
    const oldY = S.roam.y;
    S.roam.x = ev.x;
    S.roam.y = ev.y;
    if (C.preventDefaultMouseMove) S.log.prevented = true;
    trigger('pan', 'moveOnMouseMove', ev, { oldX, oldY, newX: ev.x, newY: ev.y });
  }
  function roamWheel(ev) {
    if (!C || !C.wheel) return;
    const wheelDelta = ev.delta;
    const abs = Math.abs(wheelDelta);
    if (wheelDelta === 0) return;
    const factor = mut.factorFixed ? 1.1 : abs > 3 ? 1.4 : abs > 1 ? 1.2 : 1.1;
    const scale = wheelDelta > 0 ? factor : 1 / factor;
    if (containPoint(ev.x, ev.y)) {
      S.log.prevented = true;
      trigger('zoom', 'zoomOnMouseWheel', ev, { scale, originX: ev.x, originY: ev.y });
    }
    const scrollDelta = (wheelDelta > 0 ? 1 : -1) * (abs > 3 ? 0.4 : abs > 1 ? 0.15 : 0.05);
    if (containPoint(ev.x, ev.y)) {
      S.log.prevented = true;
      trigger('scrollMove', 'moveOnMouseWheel', ev, { scrollDelta, originX: ev.x, originY: ev.y });
    }
  }
  // ---- the steps ----
  const out = [];
  let prevGrid = L.grid;
  for (const st of sc.steps) {
    S.grid = rectOf(prevGrid);
    S.step = { px: {}, proxyExtent: {} };
    for (const a of st.axes) {
      S.step.px[a.key] = a.pxSpans.map(num);
      S.step.proxyExtent[a.key] = a.proxyExtent.map(num);
    }
    S.log = { actions: [], prevented: false };
    advance(st.event.t);
    const e = st.event;
    if (e.type !== 'idle') {
      const ev = { x: num(e.x), y: num(e.y), delta: e.delta, keys: e.keys || {} };
      const T = st.hover;
      const hs = S.hs;
      if (e.type === 'mousemove') {
        const last = hs.hovered;
        hs.hovered = T;
        if (last && T !== last) dispatchEl(last, 'mouseout', ev);
        dispatchEl(T, 'mousemove', ev);
        if (T && T !== last) dispatchEl(T, 'mouseover', ev);
      } else if (e.type === 'mousedown') {
        hs.downEl = T;
        hs.downPoint = [ev.x, ev.y];
        hs.upEl = T;
        dispatchEl(T, 'mousedown', ev);
      } else if (e.type === 'mouseup') {
        hs.upEl = T;
        dispatchEl(T, 'mouseup', ev);
      } else if (e.type === 'click') {
        const dp = hs.downPoint;
        const lim = mut.clickLimit || 4;
        if (!(hs.downEl !== hs.upEl || !dp || Math.sqrt((dp[0] - ev.x) * (dp[0] - ev.x) + (dp[1] - ev.y) * (dp[1] - ev.y)) > lim)) {
          hs.downPoint = null;
          dispatchEl(T, 'click', ev);
        }
      } else if (e.type === 'mousewheel') {
        dispatchEl(T, 'mousewheel', ev);
      }
    }
    const left = Object.keys(S.step.px).filter(k => S.step.px[k].length);
    out.push({ actions: S.log.actions, prevented: S.log.prevented, dataZooms: S.dz.map(d => dzOut(d, rep(d).window)), pxLeft: left });
    prevGrid = st.grid;
  }
  return out;
}

// the transcribed / recorded dynamic records share these shapes
function actionOut(p, deferred) {
  const q = { deferred: !!deferred, type: p.type, from: p.from == null ? null : p.from, dataZoomIndex: p.dataZoomIndex == null ? null : p.dataZoomIndex, animation: J(p.animation) };
  Object.assign(q, numRecN('start', p.start), numRecN('end', p.end), numRecN('startValue', p.startValue), numRecN('endValue', p.endValue));
  q.batch = p.batch ? p.batch.map(b => Object.assign({ dataZoomIndex: b.dataZoomIndex }, numRec('start', b.start), numRec('end', b.end))) : null;
  return q;
}
function dzOut(d, w) {
  const o = { index: d.index };
  Object.assign(o, quadRec('settled', d.settled), quadRec('option', d.option), { rangePropMode: d.modes.slice() }, { window: windowRec(w).window });
  if (d.sl) {
    const sl = d.sl;
    Object.assign(o, pairRec('handleEnds', sl.handleEnds), pairRec('range', sl.range), {
      dragging: !!sl.dragging, overArea: sl.overArea == null ? null : !!sl.overArea, brushing: !!sl.brushing,
      brushRect: sl.brushRect ? Object.assign(numRec('x', sl.brushRect.x), numRec('width', sl.brushRect.width), { ignore: !!sl.brushRect.ignore }) : null,
      labels: sl.labels.map(l => Object.assign({ invisible: !!l.invisible, text: l.text }, numRec('x', l.x), numRec('y', l.y))),
      handleHover: sl.handleHover.slice(),
      moveHandle: sl.moveHandle ? { hoverState: sl.moveHandle.hoverState, highByOuter: sl.moveHandle.highByOuter } : null,
    });
  } else {
    Object.assign(o, pairRec('range', d.range));
  }
  return o;
}
// the transcribed fields of a recorded step
function dynOf(st) {
  return {
    actions: st.actions, prevented: st.prevented,
    dataZooms: st.dataZooms.map(r => {
      const o = { index: r.index, settled: r.settled, settledText: r.settledText, option: r.option, optionText: r.optionText, rangePropMode: r.rangePropMode, window: r.window };
      if (r.subType === 'slider') {
        for (const k of ['handleEnds', 'handleEndsText', 'range', 'rangeText', 'dragging', 'overArea', 'brushing', 'brushRect', 'labels', 'handleHover', 'moveHandle']) o[k] = r[k];
      } else {
        o.range = r.range;
        o.rangeText = r.rangeText;
      }
      return o;
    }),
    pxLeft: [],
  };
}
// the window is transcribed too: the representative proxy's, compared through the option (setCalculatedRange) and here
function flat(v, p, out) {
  if (v === null || typeof v !== 'object') { out[p] = JSON.stringify(v === undefined ? null : v); return out; }
  if (Array.isArray(v)) { out[p + '.length'] = String(v.length); v.forEach((x, i) => flat(x, p + '[' + i + ']', out)); return out; }
  for (const k of Object.keys(v)) flat(v[k], p ? p + '.' + k : k, out);
  return out;
}
function scenarioDiffs(sc, side, mut) {
  let sim;
  try {
    sim = simulate(sc, side, mut);
  } catch (e) {
    if (e instanceof OracleError) throw e;
    return [{ field: 'threw', upstream: null, mutated: String(e.stack).split('\n').slice(0, 3).join(' | ') }];
  }
  const diffs = [];
  sc.steps.forEach((st, i) => {
    const a = flat(dynOf(st), '', {});
    const b = flat(sim[i], '', {});
    const keys = new Set(Object.keys(a).concat(Object.keys(b)));
    for (const k of keys) {
      if (k.startsWith('dataZooms') && /\.(settledText|optionText|handleEndsText|rangeText)/.test(k)) continue;
      if (a[k] !== b[k]) diffs.push({ field: 'steps[' + i + '].' + k, upstream: a[k] == null ? null : a[k], mutated: b[k] == null ? null : b[k] });
    }
  });
  // the windows: every recorded dataZoom window equals the transcribed option start/end/startValue/endValue after the step
  return diffs;
}

// =====================================================================
// Recording
// =====================================================================
let CUR = null; // the current step's log
let hooked = false;
function hookProto() {
  if (hooked) return;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption({ xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: {}, series: [{ type: 'line', data: [1, 2] }], dataZoom: [{}] });
    const dz = chart.getModel().getComponent('dataZoom', 0);
    const px = dz.findRepresentativeAxisProxy();
    const pproto = Object.getPrototypeOf(px);
    must(hasOwn(pproto, 'calculateDataWindow'), 'AxisProxy has no calculateDataWindow');
    const orig = pproto.calculateDataWindow;
    pproto.calculateDataWindow = function (opt) {
      const m = this.getAxisModel();
      const e = m.axis.getExtent();
      const key = m.axis.dim + m.componentIndex;
      const res = orig.call(this, opt);
      if (CUR) {
        (CUR.px[key] || (CUR.px[key] = [])).push(Math.abs(e[1] - e[0]));
        if (m.axis.scale.type === 'time') {
          for (const v of res.value) {
            const r = Math.round(v);
            CUR.timeLabels.set(key + '/' + r, m.axis.scale.getLabel({ value: r }));
          }
        }
      }
      return res;
    };
  } finally {
    chart.dispose();
  }
  hooked = true;
}

function sliderRole(view, el) {
  const d = view._displayables;
  if (!d || !d.sliderGroup) return null;
  const sg = d.sliderGroup;
  if (d.handleLabels && d.handleLabels.indexOf(el) >= 0) return 'label' + d.handleLabels.indexOf(el);
  if (d.handles && d.handles.indexOf(el) >= 0) return 'handle' + d.handles.indexOf(el);
  if (el === d.filler) return 'filler';
  if (el === d.moveHandle) return 'moveHandle';
  if (el === d.moveHandleIcon) return 'moveHandleIcon';
  if (el === d.moveZone) return 'moveZone';
  if (el === d.brushRect) return 'brushRect';
  const segs = d.dataShadowSegs || [];
  if (el.parent && segs.indexOf(el.parent) >= 0) return (el.type === 'polygon' ? 'shadowPolygon' : 'shadowPolyline') + segs.indexOf(el.parent);
  if (el.parent === sg && el.type === 'rect') {
    const i = sg.childrenRef().indexOf(el);
    if (i === 0) return 'background';
    if (i === 1) return 'clickPanel';
    if (el.subPixelOptimize) return 'frame';
  }
  let p = el;
  while (p) { if (p === view.group) return 'part'; p = p.parent; }
  return null;
}

function makeCtx(chart) {
  const zr = chart.getZr();
  const ecModel = chart.getModel();
  const dzs = [];
  ecModel.eachComponent('dataZoom', dz => dzs.push(dz));
  const views = dzs.map(dz => chart.getViewOfComponentModel(dz));
  const uidToIndex = new Map(views.map((v, i) => [v.uid, dzs[i].componentIndex]));
  const idToIndex = new Map(dzs.map(dz => [dz.id, dz.componentIndex]));
  const ctx = { chart, zr, h: zr.handler, ecModel, dzs, views, uidToIndex, idToIndex, last: [0, 0] };
  ctx.role = el => {
    if (!el) return null;
    for (let i = 0; i < dzs.length; i++) {
      if (dzs[i].subType !== 'slider') continue;
      const r = sliderRole(views[i], el);
      if (r) return 'dz' + dzs[i].componentIndex + '.' + r;
    }
    let p = el;
    while (p) {
      if (p.__ecComponentInfo) return p.__ecComponentInfo.mainType + p.__ecComponentInfo.index;
      p = p.parent;
    }
    return 'other';
  };
  ctx.element = role => {
    const m = /^dz(\d+)\.(.+)$/.exec(role);
    must(m, 'not a slider role: ' + role);
    const v = views[+m[1]];
    const D = v._displayables;
    const part = m[2];
    if (part === 'handle0' || part === 'handle1') return D.handles[+part.slice(-1)];
    if (part === 'clickPanel') return D.sliderGroup.childAt(1);
    const el = D[part];
    must(el, 'no element ' + role);
    return el;
  };
  ctx.globalRect = role => {
    const el = ctx.element(role);
    const r = el.getBoundingRect().clone();
    if (el.transform) r.applyTransform(el.transform);
    return r;
  };
  ctx.gridRect = () => ecModel.getComponent('grid', 0).coordinateSystem.getRect();
  return ctx;
}
// point specs (resolved when the step runs, rounded to integers)
const at = {
  el: (role, fx = 0.5, fy = 0.5) => ctx => { const r = ctx.globalRect(role); return [r.x + r.width * fx, r.y + r.height * fy]; },
  loc: (k, u, fv = 0.5) => ctx => { const D = ctx.views[k]._displayables; return applyT([u, ctx.views[k]._size[1] * fv], D.sliderGroup.transform); },
  grid: (fx, fy) => ctx => { const g = ctx.gridRect(); return [g.x + g.width * fx, g.y + g.height * fy]; },
  abs: (x, y) => () => [x, y],
  rel: (dx, dy) => ctx => [ctx.last[0] + dx, ctx.last[1] + dy],
};
const R0 = at.rel(0, 0);

function eventRaw(type, x, y, st) {
  const keys = st.keys || {};
  const e = {
    type, zrX: x, zrY: y, which: 1, shiftKey: !!keys.shift, ctrlKey: !!keys.ctrl, altKey: !!keys.alt, cancelBubble: false, __prevented: false,
    preventDefault() { this.__prevented = true; },
    stopPropagation() {},
  };
  if (type === 'mousewheel') e.zrDelta = st.delta;
  return e;
}

function recordLayout(ctx) {
  const { ecModel, dzs, views, zr, chart } = ctx;
  const axisKeys = [];
  const axesMap = new Map();
  const lz = dzs.map((dz, i) => {
    const targets = [];
    dz.eachTargetAxis((dim, index) => targets.push({ dim, index }));
    for (const t of targets) {
      const key = t.dim + t.index;
      if (!axesMap.has(key)) {
        const am = ecModel.getComponent(t.dim + 'Axis', t.index);
        const px = dz.getAxisProxy(t.dim, t.index);
        axesMap.set(key, {
          key, dim: t.dim, index: t.index, type: am.axis.scale.type === 'ordinal' ? 'category' : am.axis.type, inverse: !!am.axis.inverse,
          host: px._dataZoomModel.componentIndex, categories: am.axis.type === 'category' ? am.getCategories().map(String) : null,
        });
        axisKeys.push(key);
      }
    }
    const o = { index: dz.componentIndex, subType: dz.subType, targets, throttle: dz.get('throttle'), rangeMode: J(dz.get('rangeMode')) };
    o.spansOption = {};
    for (const k of SPAN_KEYS) o.spansOption[k] = J(dz.get(k));
    if (dz.subType === 'slider') {
      const v = views[i];
      const D = v._displayables;
      const sg = D.sliderGroup;
      const hl = dz.get('handleLabel') || {};
      Object.assign(o, {
        orient: dz.getOrient(), realtime: !!dz.get('realtime'), zoomLock: !!dz.get('zoomLock'), brushSelect: !!dz.get('brushSelect'),
        showDetail: !!dz.get('showDetail'), handleLabelShow: !!(hl.show || false),
        emphasisHandleLabelShow: !!(dz.getModel(['emphasis', 'handleLabel']).get('show') || false),
        labelPrecision: J(dz.get('labelPrecision')), labelFormatter: typeof dz.get('labelFormatter') === 'string' ? dz.get('labelFormatter') : null,
      }, pairRec('size', v._size), numRec('handleWidth', v._handleWidth), matRec('local', sg.getLocalTransform()), matRec('global', sg.transform), matRec('inv', sg.invTransform));
      must(typeof dz.get('labelFormatter') !== 'function', 'function labelFormatter');
      const h0 = D.handles[0];
      const moveEl = D.moveZone || D.filler;
      o.cursors = { handle: h0.cursor, move: moveEl.cursor, clickPanel: sg.childAt(1).cursor || null };
      const emph = h0.stateProxy ? h0.stateProxy('emphasis', ['emphasis']) : h0.states.emphasis;
      o.styles = {
        handle: { fill: h0.style.fill, stroke: h0.style.stroke },
        handleEmphasis: { fill: emph.style.fill, stroke: emph.style.stroke, z2: emph.z2 == null ? null : emph.z2 },
        moveHandle: D.moveHandle ? { fill: D.moveHandle.style.fill, opacity: D.moveHandle.style.opacity } : null,
        moveHandleEmphasis: D.moveHandle ? J(D.moveHandle.states.emphasis.style) : null,
        brush: J(dz.getModel('brushStyle').getItemStyle()),
      };
    } else if (dz.subType === 'inside') {
      for (const k of ['disabled', 'zoomLock', 'zoomOnMouseWheel', 'moveOnMouseMove', 'moveOnMouseWheel', 'preventDefaultMouseMove']) o[k] = J(dz.get(k));
      const t0 = targets[0];
      o.axis = { dim: t0.dim, index: t0.index, inverse: !!ecModel.getComponent(t0.dim + 'Axis', t0.index).axis.inverse };
    }
    return o;
  });
  // grid 0's RoamController, as registered
  let controller = null;
  if (dzs.some(dz => dz.subType === 'inside')) {
    const api = chart._api;
    let rec = null;
    for (const k of Object.keys(api)) {
      const v = api[k];
      if (v && typeof v === 'object' && v.coordSysRecordMap) v.coordSysRecordMap.each(r => { if (r.model.mainType === 'grid' && r.model.componentIndex === 0) rec = r; });
    }
    must(rec, 'no coordSysRecord for grid 0');
    let store = null;
    for (const k of Object.keys(zr)) if (zr[k] && typeof zr[k] === 'object' && zr[k].roam) store = zr[k];
    // no store: the controller was never enabled (every inside disabled)
    const has = n => !!(store && store.roam[n] && store.roam[n].length);
    controller = { mouse: has('mousedown'), wheel: has('mousewheel'), preventDefaultMouseMove: !!rec.controller._opt.preventDefaultMouseMove, throttle: rec.dispatchAction['\0__throttleRate'] };
    must(has('mousemove') === controller.mouse && has('mouseup') === controller.mouse, 'roam mouse listeners inconsistent');
  }
  return Object.assign(rectRec('grid', ctx.gridRect()), { dataZooms: lz, controller, axes: axisKeys.map(k => axesMap.get(k)) });
}

function snapshot(ctx, log) {
  const { ecModel, dzs, views } = ctx;
  const rec = {};
  if (log) {
    rec.cursors = log.cursors.slice();
    rec.prevented = log.prevented;
    rec.actions = log.actions;
  }
  Object.assign(rec, rectRec('grid', ctx.gridRect()));
  rec.dataZooms = dzs.map((dz, i) => {
    const o = { index: dz.componentIndex, subType: dz.subType };
    Object.assign(o, quadRec('settled', dz.settledOption), quadRec('option', dz.option), { rangePropMode: dz.getRangePropMode() },
      windowRec(dz.findRepresentativeAxisProxy().getWindow()));
    const v = views[i];
    if (dz.subType === 'slider') {
      const D = v._displayables;
      const br = D.brushRect;
      Object.assign(o, pairRec('handleEnds', v._handleEnds), pairRec('range', v._range), {
        dragging: !!v._dragging, overArea: v._isOverDataInfoTriggerArea == null ? null : !!v._isOverDataInfoTriggerArea, brushing: !!v._brushing,
        brushRect: br ? Object.assign(numRec('x', br.shape.x), numRec('width', br.shape.width), { ignore: !!br.ignore }) : null,
        labels: D.handleLabels.map(l => Object.assign({ invisible: !!l.invisible, text: l.style.text }, numRec('x', l.style.x), numRec('y', l.style.y))),
        handleHover: D.handles.map(h => h.hoverState || 0),
        moveHandle: D.moveHandle ? { hoverState: D.moveHandle.hoverState || 0, highByOuter: D.moveHandle.__highByOuter || 0 } : null,
        style: { handles: D.handles.map(h => ({ fill: h.style.fill, stroke: h.style.stroke })), moveHandleOpacity: D.moveHandle ? J(D.moveHandle.style.opacity) : null },
      });
    } else {
      Object.assign(o, pairRec('range', v.range));
    }
    return o;
  });
  rec.axes = ctx.layout.axes.map(a => {
    const am = ecModel.getComponent(a.dim + 'Axis', a.index);
    const px = ctx.dzs.find(dz => dz.getAxisModel(a.dim, a.index)).getAxisProxy(a.dim, a.index);
    const pxs = (log && log.px[a.key]) || [];
    return Object.assign({ key: a.key }, pairRec('extent', am.axis.scale.getExtent()), pairRec('proxyExtent', px._extent), spansRec(px.getMinMaxSpan()),
      { pxSpans: pxs.map(hex), pxSpansText: pxs.map(text) });
  });
  return rec;
}

function recordScenario(def, side) {
  NOW = CLOCK0;
  TIMERS = [];
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    const log0 = { px: {}, timeLabels: side.timeLabels, actions: [], cursors: [], prevented: false };
    CUR = log0;
    chart.setOption(JSON.parse(JSON.stringify(def.option)));
    const ctx = makeCtx(chart);
    ctx.h.proxy.setCursor = c => { if (CUR) CUR.cursors.push(c); };
    const api = chart._api;
    const origDispatch = api.dispatchAction;
    api.dispatchAction = function (payload) {
      // the full build's brush visual dispatches 'brushSelect' (update 'none') after every update with a payload: not recorded
      must(payload.type === 'dataZoom' || payload.type === 'brushSelect', 'unexpected action ' + payload.type);
      if (CUR && payload.type === 'dataZoom') {
        const p = Object.assign({}, payload);
        p.from = payload.from == null ? null : ctx.uidToIndex.get(payload.from);
        must(payload.from == null || p.from != null, 'unknown dispatching view');
        p.dataZoomIndex = payload.dataZoomId == null ? null : ctx.idToIndex.get(payload.dataZoomId);
        must(payload.dataZoomId == null || p.dataZoomIndex != null, 'unknown dataZoomId');
        if (payload.batch) p.batch = payload.batch.map(b => ({ dataZoomIndex: ctx.idToIndex.get(b.dataZoomId), start: b.start, end: b.end }));
        const known = ['type', 'from', 'dataZoomId', 'animation', 'start', 'end', 'batch'];
        must(Object.keys(payload).every(k => known.includes(k)), 'unexpected payload keys ' + Object.keys(payload));
        CUR.actions.push(actionOut(p, FIRING));
      }
      return origDispatch.apply(this, arguments);
    };
    ctx.zr.storage.getDisplayList(true);
    ctx.layout = recordLayout(ctx);
    const layoutKey = JSON.stringify(ctx.layout);
    const initial = snapshot(ctx, null);
    const steps = [];
    const list = def.steps.concat([{ type: 'idle' }]);
    list.forEach((st, i) => {
      const dt = st.dt != null ? st.dt : DEFAULT_DT[st.type];
      const log = { px: {}, timeLabels: side.timeLabels, actions: [], cursors: [], prevented: false };
      CUR = log;
      advanceClock(NOW + dt);
      ctx.zr.storage.getDisplayList(true);
      const rec = { i };
      if (st.type === 'idle') {
        rec.event = { type: 'idle', x: null, xText: null, y: null, yText: null, t: NOW, dt };
        rec.hover = null;
        rec.topTarget = null;
      } else {
        const p = st.at(ctx).map(Math.round);
        ctx.last = p;
        const ev = eventRaw(st.type, p[0], p[1], st);
        // Handler.mousemove / mouseup skip findHover outside the canvas (isOutsideBoundary): no target
        const outside = p[0] < 0 || p[0] > W || p[1] < 0 || p[1] > H;
        const hv = outside && (st.type === 'mousemove' || st.type === 'mouseup') ? { target: null, topTarget: null } : ctx.h.findHover(p[0], p[1]);
        rec.event = Object.assign({ type: st.type }, numRec('x', p[0]), numRec('y', p[1]));
        if (st.type === 'mousewheel') rec.event.delta = st.delta;
        if (st.keys) rec.event.keys = st.keys;
        Object.assign(rec.event, { t: NOW, dt });
        rec.hover = ctx.role(hv.target);
        rec.topTarget = ctx.role(hv.topTarget);
        ctx.h[st.type](ev);
        log.prevented = ev.__prevented;
      }
      CUR = null;
      Object.assign(rec, snapshot(ctx, log));
      must(JSON.stringify(recordLayoutStatic(ctx)) === JSON.stringify(staticPart(ctx.layout)), def.id + ' step ' + i + ': the layout changed');
      steps.push(rec);
    });
    CUR = null;
    return { id: def.id, groups: def.groups, note: def.note, option: def.option, layout: ctx.layout, initial, steps };
  } finally {
    CUR = null;
    chart.dispose();
  }
}
// the parts of the layout that must stay constant (slider matrices / size / grid)
function staticPart(layout) {
  return { grid: layout.grid, sl: layout.dataZooms.filter(z => z.subType === 'slider').map(z => [z.size, z.local, z.global, z.inv, z.handleWidth]) };
}
function recordLayoutStatic(ctx) {
  const sl = [];
  ctx.dzs.forEach((dz, i) => {
    if (dz.subType !== 'slider') return;
    const v = ctx.views[i];
    const sg = v._displayables.sliderGroup;
    ctx.zr.storage.getDisplayList(true);
    sl.push([Array.from(v._size, hex), Array.from(sg.getLocalTransform()).map(hex), Array.from(sg.transform).map(hex), Array.from(sg.invTransform).map(hex), hex(v._handleWidth)]);
  });
  return { grid: rectRec('grid', ctx.gridRect()).grid, sl };
}

// ---------- the scenarios ----------
const cat = n => Array.from({ length: n }, (_, i) => 'c' + i);
const CATS = cat(20);
const V20 = [12.34, 45.67, 23.456, 78.9, 34.5, 56.78, 90.12, 11.1, 67.89, 43.21, 29.99, 88.8, 14.7, 63.3, 51.05, 37.7, 72.25, 19.9, 84.4, 58.6];
const catLine = (dz, x) => ({ xAxis: Object.assign({ type: 'category', data: CATS }, x || {}), yAxis: { type: 'value' }, series: [{ type: 'line', data: V20 }], dataZoom: dz });
const XS = Array.from({ length: 21 }, (_, i) => [i * 5, Math.round(((i * 37) % 23) * 4.37 * 100) / 100]);
const valScatter = (dz, x, y) => ({ xAxis: Object.assign({ type: 'value' }, x || {}), yAxis: Object.assign({ type: 'value' }, y || {}), series: [{ type: 'scatter', data: XS }], dataZoom: dz });
const hBar = (dz, y) => ({ xAxis: { type: 'value' }, yAxis: Object.assign({ type: 'category', data: CATS }, y || {}), series: [{ type: 'bar', data: V20 }], dataZoom: dz });
const DAY = 86400000;
const T0 = Date.UTC(2020, 0, 1);
const timeData = Array.from({ length: 20 }, (_, i) => [T0 + i * DAY, V20[i]]);
const timeLine = dz => ({ useUTC: true, xAxis: { type: 'time' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: timeData }], dataZoom: dz });
const twoX = dz => ({
  xAxis: [{ type: 'category', data: CATS }, { type: 'category', data: CATS, position: 'top' }], yAxis: { type: 'value' },
  series: [{ type: 'line', data: V20 }, { type: 'line', xAxisIndex: 1, data: V20.slice().reverse() }], dataZoom: dz,
});
const SL = { start: 20, end: 60 };
const sl = o => Object.assign({ type: 'slider' }, SL, o || {});
const ins = o => Object.assign({ type: 'inside' }, o || {});

const mv = (p, o) => Object.assign({ type: 'mousemove', at: p }, o || {});
function drag(from, moves, o = {}) {
  return [mv(from), { type: 'mousedown', at: R0, dt: o.downDt }]
    .concat(moves.map(m => ({ type: 'mousemove', at: at.rel(m[0], m[1]), dt: o.moveDt })))
    .concat([{ type: 'mouseup', at: R0, dt: o.upDt }, { type: 'click', at: R0 }]);
}
const rep = (n, m) => Array.from({ length: n }, () => m);
const clickAt = (p, o = {}) => [mv(p), { type: 'mousedown', at: R0 }, { type: 'mouseup', at: R0, dt: o.upDt != null ? o.upDt : 50 }, { type: 'click', at: R0 }];
const wheel = (p, delta, n = 1, keys) => [mv(p)].concat(rep(n, Object.assign({ type: 'mousewheel', at: R0, delta }, keys ? { keys } : {})));
const OUT_OF_GRID = at.abs(40, 40);

const SCENARIOS = [
  // ---- slider handles ----
  { id: 'H0R50', groups: ['handle'], note: 'handle 0 dragged right by 50 px in one move: the pointer leaves the handle before the drift, so mouseout hides the labels (dragging not yet set)', option: catLine([sl()]), steps: drag(at.el('dz0.handle0'), [[50, 0]]) },
  { id: 'H0R50s', groups: ['handle'], note: 'handle 0 dragged right by 50 px in 10 moves of 5 px: the pointer stays on the handle, labels stay shown while dragging and hide on mouseup', option: catLine([sl()]), steps: drag(at.el('dz0.handle0'), rep(10, [5, 0])) },
  { id: 'H1L80', groups: ['handle'], note: 'handle 1 dragged left by 80 px', option: catLine([sl()]), steps: drag(at.el('dz0.handle1'), [[-40, 0], [-40, 0]]) },
  { id: 'H0CLAMP0', groups: ['handle', 'clamp'], note: 'handle 0 dragged 300 px left: clamped at 0', option: catLine([sl()]), steps: drag(at.el('dz0.handle0'), [[-150, 0], [-150, 0]]) },
  { id: 'H1CLAMPLEN', groups: ['handle', 'clamp'], note: 'handle 1 dragged 400 px right: clamped at the slider length', option: catLine([sl()]), steps: drag(at.el('dz0.handle1'), [[-2, 0], [402, 0]]) },
  { id: 'H0CROSS', groups: ['handle', 'cross'], note: 'handle 0 dragged across handle 1 (ends kept descending in _handleEnds, _range asc), then the same handle (now the right one) dragged back across', option: catLine([sl()]), steps: drag(at.el('dz0.handle0'), [[150, 0], [150, 0]]).concat(drag(at.el('dz0.handle0'), [[-100, 0], [-100, 0]])) },
  { id: 'SPANS', groups: ['handle', 'spans'], note: 'minSpan 20 / maxSpan 50: handle 1 dragged left past the min span (handle 0 pushed), then right past the max span (handle 0 pulled)', option: catLine([sl({ minSpan: 20, maxSpan: 50 })]), steps: drag(at.el('dz0.handle1'), [[-125, 0], [-125, 0]]).concat(drag(at.el('dz0.handle1'), [[150, 0], [150, 0]])) },
  { id: 'MINVALUESPAN', groups: ['handle', 'spans'], note: 'minValueSpan 5 on a category axis: handle 1 dragged left 200 px', option: catLine([sl({ minValueSpan: 5 })]), steps: drag(at.el('dz0.handle1'), [[-100, 0], [-100, 0]]) },
  { id: 'ZOOMLOCK', groups: ['handle', 'zoomLock'], note: 'zoomLock: a handle drag moves the whole window; then handle 1 dragged 400 px right (the window stops at the end)', option: catLine([sl({ zoomLock: true })]), steps: drag(at.el('dz0.handle0'), [[25, 0], [25, 0]]).concat(drag(at.el('dz0.handle1'), [[200, 0], [200, 0]])) },
  { id: 'RT-FALSE', groups: ['handle', 'realtime'], note: 'realtime false: no action while dragging (labels from calculateDataWindow of the view range), one on mouseup', option: catLine([sl({ realtime: false })]), steps: drag(at.el('dz0.handle0'), rep(3, [20, 0])) },
  { id: 'RT-FALSE-VALUE', groups: ['handle', 'realtime', 'rangeMode'], note: "realtime false with startValue / endValue: rangePropMode 'value', so the mid-drag labels' calculateDataWindow({start, end}) ignores the percents and shows the data extent; mouseup's action switches both ends to 'percent'", option: catLine([{ type: 'slider', realtime: false, startValue: 4, endValue: 11 }]), steps: drag(at.el('dz0.handle1'), [[-30, 0], [-30, 0]]) },
  { id: 'RT-FALSE-CLICKHANDLE', groups: ['handle', 'realtime'], note: 'realtime false: a click on a handle (no move) still dispatches on dragend', option: catLine([sl({ realtime: false })]), steps: clickAt(at.el('dz0.handle0')) },
  { id: 'RT-TRUE-CLICKHANDLE', groups: ['handle'], note: 'realtime true: a click on a handle dispatches nothing', option: catLine([sl()]), steps: clickAt(at.el('dz0.handle0')) },
  { id: 'THROTTLE', groups: ['handle', 'throttle'], note: 'moves 20 ms apart: the first dispatches, the next ones are deferred to lastExec + 100 and run with the latest range', option: catLine([sl()]), steps: drag(at.el('dz0.handle1'), rep(5, [-10, 0]), { moveDt: 20, upDt: 20 }) },
  // ---- move handle / filler ----
  { id: 'MOVEZONE', groups: ['move'], note: 'the move zone dragged +60 px, then -10 px and -1000 px (clamped at 0; the pointer leaves the zone while dragging: labels stay, the move handle stays emphasised through bit 2 until mouseup)', option: catLine([sl()]), steps: drag(at.el('dz0.moveZone', 0.5, 0.3), [[30, 0], [30, 0]]).concat(drag(at.el('dz0.moveZone', 0.5, 0.3), [[-10, 0], [-1000, 0]])) },
  { id: 'FILLER', groups: ['move'], note: 'brushSelect false: the filler is the move zone', option: catLine([sl({ brushSelect: false })]), steps: drag(at.el('dz0.filler', 0.5, 0.5), [[30, 0], [30, 0]]) },
  // ---- clicks on the body ----
  { id: 'CLICK-BODY', groups: ['click'], note: 'clicks on the body right of the window (recentred, clamped at the end) and near the start (clamped at 0)', option: catLine([sl()]), steps: clickAt(at.loc(0, 500)).concat(clickAt(at.loc(0, 30))) },
  { id: 'CLICK-3PX', groups: ['click', 'brush'], note: 'down, 3 px move, up within 200 ms: the brush is a click (< 5 px, < 200 ms) and the click (<= 4 px) recentres at the up point', option: catLine([sl()]), steps: [mv(at.loc(0, 500)), { type: 'mousedown', at: R0 }, { type: 'mousemove', at: at.rel(3, 0), dt: 20 }, { type: 'mouseup', at: R0, dt: 20 }, { type: 'click', at: R0 }] },
  { id: 'CLICK-6PX', groups: ['click', 'brush'], note: 'down, 6 px move, up within 200 ms: a 6 px brush is applied; zrender drops the click (moved > 4 px)', option: catLine([sl()]), steps: [mv(at.loc(0, 500)), { type: 'mousedown', at: R0 }, { type: 'mousemove', at: at.rel(6, 0), dt: 20 }, { type: 'mouseup', at: R0, dt: 20 }, { type: 'click', at: R0 }] },
  { id: 'CLICK-NOBRUSH', groups: ['click'], note: 'brushSelect false: 3 px between down and up still clicks, 6 px does not', option: catLine([sl({ brushSelect: false })]), steps: [mv(at.loc(0, 500)), { type: 'mousedown', at: R0 }, { type: 'mousemove', at: at.rel(3, 0), dt: 20 }, { type: 'mouseup', at: R0, dt: 20 }, { type: 'click', at: R0 }, mv(at.loc(0, 60)), { type: 'mousedown', at: R0 }, { type: 'mousemove', at: at.rel(6, 0), dt: 20 }, { type: 'mouseup', at: R0, dt: 20 }, { type: 'click', at: R0 }] },
  { id: 'CLICK-SPLIT', groups: ['click'], note: 'down in the move zone near its lower edge, 3 px down onto the body, up: the mousedown and mouseup targets differ, so zrender drops the click (it would recentre at the pointer)', option: catLine([sl()]), steps: [mv(at.el('dz0.moveZone', 0.2, 0.95)), { type: 'mousedown', at: R0 }, { type: 'mousemove', at: at.rel(0, 3), dt: 20 }, { type: 'mouseup', at: R0, dt: 20 }, { type: 'click', at: R0 }] },
  // ---- brush ----
  { id: 'BRUSH', groups: ['brush'], note: 'a brush from 400 to 500 px, then right to left from 300 to 150 px (_handleEnds stays descending)', option: catLine([sl()]), steps: drag(at.loc(0, 400), [[50, 0], [50, 0]]).concat(drag(at.loc(0, 300), [[-75, 0], [-75, 0]])) },
  { id: 'BRUSH-SLOW3', groups: ['brush'], note: 'a 3 px brush held over 200 ms is applied (a 3 px window)', option: catLine([sl()]), steps: [mv(at.loc(0, 450)), { type: 'mousedown', at: R0 }, { type: 'mousemove', at: at.rel(3, 0), dt: 150 }, { type: 'mouseup', at: R0, dt: 150 }, { type: 'click', at: R0 }] },
  { id: 'BRUSH-STALE', groups: ['brush'], note: 'a 100 px brush, then a click with no move: _onBrushEnd finds the old (ignored) brushRect and re-applies its shape; the click then recentres (deferred by the throttle: same ms as the mouseup)', option: catLine([sl()]), steps: drag(at.loc(0, 400), [[50, 0], [50, 0]]).concat(clickAt(at.loc(0, 150), { upDt: 50 })) },
  { id: 'BRUSH-CLAMP', groups: ['brush', 'clamp'], note: 'a brush from 500 px dragged 300 px right and 50 px down: the end is clamped to the slider length, y is ignored', option: catLine([sl()]), steps: drag(at.loc(0, 500), [[150, 25], [150, 25]]) },
  { id: 'BRUSH-CLAMP0', groups: ['brush', 'clamp'], note: 'a brush from 100 px dragged 300 px left: the end is clamped at 0 (a descending window)', option: catLine([sl()]), steps: drag(at.loc(0, 100), [[-150, 0], [-150, 0]]) },
  { id: 'BRUSH-MINSPAN', groups: ['brush', 'spans'], note: 'minSpan 30: a 50 px brush is widened to 30 %', option: catLine([sl({ minSpan: 30 })]), steps: drag(at.loc(0, 200), [[25, 0], [25, 0]]) },
  // ---- hover ----
  { id: 'HOVER', groups: ['hover'], note: 'over handle 0 (labels, handle and move handle emphasis), out, over the move zone, out', option: catLine([sl()]), steps: [mv(at.el('dz0.handle0')), mv(at.grid(0.5, 0.5)), mv(at.el('dz0.moveZone', 0.5, 0.3)), mv(at.grid(0.5, 0.5))] },
  { id: 'HOVER-OVERLAP', groups: ['hover'], note: 'a 50-50.5 window: the two handles overlap; over handle 0 from the left, then 4 px right into the overlap -- handle 0 is hovered, so its z2 is 15 and it stays the target (handle 1, drawn later, would win at z2 5)', option: catLine([sl({ start: 50, end: 50.5 })]), steps: [mv(at.el('dz0.handle0', 0.1, 0.5)), mv(at.rel(4, 0)), mv(at.grid(0.5, 0.5))] },
  { id: 'HOVER-SHOW', groups: ['hover'], note: 'handleLabel.show true: labels always shown', option: catLine([sl({ handleLabel: { show: true } })]), steps: [mv(at.el('dz0.handle0')), mv(at.grid(0.5, 0.5))].concat(drag(at.el('dz0.handle1'), [[-20, 0]])) },
  { id: 'HOVER-EMPH-OFF', groups: ['hover'], note: 'emphasis.handleLabel.show false: neither hover nor dragging shows the labels', option: catLine([sl({ emphasis: { handleLabel: { show: false } } })]), steps: [mv(at.el('dz0.handle0')), mv(at.grid(0.5, 0.5))].concat(drag(at.el('dz0.handle0'), rep(4, [5, 0]))) },
  // ---- orientation ----
  { id: 'VERTICAL', groups: ['vertical'], note: 'a vertical slider (yAxisIndex): handle 0 dragged 40 px down, handle 1 dragged (5, -30) (dx leaks through cos(pi/2)), the move zone dragged, a click on the body', option: hBar([sl({ yAxisIndex: 0 })]), steps: drag(at.el('dz0.handle0'), [[0, 20], [0, 20]]).concat(drag(at.el('dz0.handle1'), [[5, -15], [0, -15]])).concat(drag(at.el('dz0.moveZone', 0.3, 0.5), [[0, 25]])).concat(clickAt(at.loc(0, 420))) },
  { id: 'VERTICAL-INV', groups: ['vertical', 'inverse'], note: 'a vertical slider on an inverse category y axis: handle 0 dragged 40 px down', option: hBar([sl({ yAxisIndex: 0 })], { inverse: true }), steps: drag(at.el('dz0.handle0'), [[0, 20], [0, 20]]) },
  { id: 'INVERSE', groups: ['inverse'], note: 'an inverse x axis: handle 0 (drawn on the right) dragged 50 px right, a click on the body', option: catLine([sl()], { inverse: true }), steps: drag(at.el('dz0.handle0'), [[25, 0], [25, 0]]).concat(clickAt(at.loc(0, 100))) },
  // ---- several dataZooms ----
  { id: 'TWO-SLIDERS', groups: ['follow'], note: 'two sliders on x 0: dragging the second one (from its own action it keeps its ends) makes the first follow (rebuilt from the window)', option: catLine([sl(), sl({ top: 30 })]), steps: drag(at.el('dz1.handle1'), [[-40, 0], [-40, 0]]) },
  { id: 'SLIDER-INSIDE', groups: ['follow', 'inside'], note: 'a slider and an inside on x 0: the slider drag moves the inside range; a wheel in the grid rebuilds the slider', option: catLine([sl(), ins()]), steps: drag(at.el('dz0.handle0'), [[25, 0], [25, 0]]).concat(wheel(at.grid(0.5, 0.5), 1)) },
  { id: 'CHAIN', groups: ['follow'], note: 'dz0 slider on x 0 and x 1, dz1 slider on x 1 only: dragging dz1 reaches dz0 through x 1 (findEffectedDataZooms), and x 0 follows too', option: twoX([sl({ xAxisIndex: [0, 1] }), sl({ xAxisIndex: 1, top: 30 })]), steps: drag(at.el('dz1.handle0'), [[30, 0], [30, 0]]) },
  { id: 'CHAIN2', groups: ['follow'], note: 'dz0 slider on x 1, dz1 inside on x 0, dz2 inside on x 0 and x 1: dragging dz0 finds dz2 through x 1 on the first pass and dz1 through x 0 only on the second (findEffectedDataZooms loops until no new link)', option: twoX([sl({ xAxisIndex: 1 }), ins({ xAxisIndex: 0, start: 10, end: 90 }), ins({ xAxisIndex: [0, 1] })]), steps: drag(at.el('dz0.handle0'), [[30, 0], [30, 0]]) },
  { id: 'SPANS-HOST', groups: ['follow', 'spans'], note: 'an inside (the host of x 0, minSpan 40) and a slider on x 0: the slider has no spans of its own, but a drag of handle 1 400 px left stops at the 40 % of the host', option: catLine([ins({ minSpan: 40 }), sl({ start: 0, end: 100 })]), steps: drag(at.el('dz1.handle1'), [[-200, 0], [-200, 0]]) },
  // ---- inside ----
  { id: 'IN-WHEEL', groups: ['inside', 'wheel'], note: 'one notch up then one down at the grid centre', option: catLine([ins({ start: 20, end: 80 })]), steps: wheel(at.grid(0.5, 0.5), 1).concat(wheel(at.grid(0.5, 0.5), -1)) },
  { id: 'IN-WHEEL-EDGE', groups: ['inside', 'wheel'], note: 'two notches up near the left edge: the range shrinks about the pointer', option: valScatter([ins({ start: 20, end: 80 })]), steps: wheel(at.grid(0.05, 0.5), 1, 2) },
  { id: 'IN-WHEEL-MANY', groups: ['inside', 'wheel'], note: 'five notches up, then zrDelta 2 (factor 1.2) and 4 (1.4) down', option: valScatter([ins()]), steps: wheel(at.grid(0.7, 0.3), 1, 5).concat(wheel(at.grid(0.7, 0.3), -2)).concat(wheel(at.grid(0.7, 0.3), -4)) },
  { id: 'IN-WHEEL-CLAMP', groups: ['inside', 'wheel', 'clamp'], note: '0-100 wheel down: no change, no action; then 40-60 wheel down twelve times near the right: clamped at 0 / 100', option: catLine([ins()]), steps: wheel(at.grid(0.8, 0.5), -1).concat([{ type: 'idle' }]) },
  { id: 'IN-WHEEL-CLAMP2', groups: ['inside', 'wheel', 'clamp'], note: '40-60, zrDelta -4 (factor 1.4) eight times at 80 % of the width: the start clamps at 0 on the 4th notch (sliderMove restricts each end on its own), after which only the end grows', option: catLine([ins({ start: 40, end: 60 })]), steps: wheel(at.grid(0.8, 0.5), -4, 8) },
  { id: 'IN-MINSPAN', groups: ['inside', 'wheel', 'spans'], note: 'minSpan 10: ten zrDelta-4 notches up (factor 1.4): the span stops at 10 %, but every further notch still moves the window toward the pointer (the start follows the zoom, sliderMove handle 0 pushes the end to start + 10) and dispatches', option: valScatter([ins({ minSpan: 10 })]), steps: wheel(at.grid(0.3, 0.5), 4, 10) },
  { id: 'IN-VALUESPAN', groups: ['inside', 'wheel', 'spans'], note: 'minValueSpan 20 on a value axis: ten zrDelta-4 notches up stop at 20 %', option: valScatter([ins({ minValueSpan: 20 })]), steps: wheel(at.grid(0.5, 0.5), 4, 10) },
  { id: 'IN-OUTSIDE', groups: ['inside', 'wheel'], note: 'a wheel outside the grid: nothing (not even preventDefault)', option: catLine([ins({ start: 20, end: 80 })]), steps: wheel(OUT_OF_GRID, 1) },
  { id: 'IN-PAN', groups: ['inside', 'pan'], note: 'a drag in the grid by -100 then +40 px', option: valScatter([ins({ start: 20, end: 60 })]), steps: drag(at.grid(0.5, 0.5), [[-50, 0], [-50, 0], [40, 7]]) },
  { id: 'IN-PAN-END', groups: ['inside', 'pan', 'clamp'], note: 'a drag by +1000 px: the window stops at 0 keeping its span', option: valScatter([ins({ start: 20, end: 60 })]), steps: drag(at.grid(0.5, 0.5), [[300, 0], [300, 0]]) },
  { id: 'IN-Y', groups: ['inside', 'pan'], note: 'an inside on y 0: a drag 60 px down, a wheel', option: valScatter([ins({ yAxisIndex: 0, start: 20, end: 70 })]), steps: drag(at.grid(0.5, 0.5), [[0, 30], [0, 30]]).concat(wheel(at.grid(0.5, 0.2), 1)) },
  { id: 'IN-INVERSE', groups: ['inside', 'pan', 'inverse'], note: 'an inverse x axis: a drag 100 px right, a wheel near the left', option: valScatter([ins({ start: 20, end: 60 })], { inverse: true }), steps: drag(at.grid(0.5, 0.5), [[50, 0], [50, 0]]).concat(wheel(at.grid(0.1, 0.5), 1)) },
  { id: 'IN-SHIFT', groups: ['inside', 'wheel', 'keys'], note: "zoomOnMouseWheel 'shift': a wheel without shift does nothing (but the event is still stopped), with shift it zooms", option: catLine([ins({ start: 20, end: 80, zoomOnMouseWheel: 'shift' })]), steps: wheel(at.grid(0.5, 0.5), 1).concat(wheel(at.grid(0.5, 0.5), 1, 1, { shift: true })) },
  { id: 'IN-CTRL-MOVE', groups: ['inside', 'pan', 'keys'], note: "moveOnMouseMove 'ctrl': a plain drag does nothing, a ctrl drag pans", option: valScatter([ins({ start: 20, end: 60, moveOnMouseMove: 'ctrl' })]), steps: drag(at.grid(0.5, 0.5), [[-40, 0]]).concat(drag(at.grid(0.5, 0.5), [[-40, 0]]).map(s => Object.assign({}, s, { keys: { ctrl: true } }))) },
  { id: 'IN-NOMOVE', groups: ['inside', 'pan'], note: 'moveOnMouseMove false: a drag does nothing (the event is still stopped)', option: valScatter([ins({ start: 20, end: 60, moveOnMouseMove: false })]), steps: drag(at.grid(0.5, 0.5), [[-40, 0]]) },
  { id: 'IN-DISABLED', groups: ['inside'], note: 'disabled: no roam listeners at all', option: valScatter([ins({ start: 20, end: 60, disabled: true })]), steps: wheel(at.grid(0.5, 0.5), 1).concat(drag(at.grid(0.5, 0.5), [[-40, 0]])) },
  { id: 'IN-ZOOMLOCK', groups: ['inside', 'zoomLock'], note: "zoomLock: controlType 'move', no wheel listener; a drag still pans", option: valScatter([ins({ start: 20, end: 60, zoomLock: true })]), steps: wheel(at.grid(0.5, 0.5), 1).concat(drag(at.grid(0.5, 0.5), [[-40, 0]])) },
  { id: 'IN-ZOOMLOCK-WHEELMOVE', groups: ['inside', 'zoomLock'], note: 'zoomLock with moveOnMouseWheel: still no wheel listener, the wheel does nothing', option: valScatter([ins({ start: 20, end: 60, zoomLock: true, moveOnMouseWheel: true })]), steps: wheel(at.grid(0.5, 0.5), 1) },
  { id: 'IN-WHEELMOVE', groups: ['inside', 'wheel'], note: 'moveOnMouseWheel true: one wheel zooms then scroll-moves (the second dispatch is throttled: same ms)', option: valScatter([ins({ start: 20, end: 60, moveOnMouseWheel: true })]), steps: wheel(at.grid(0.5, 0.5), 1) },
  { id: 'IN-WHEELMOVE-ONLY', groups: ['inside', 'wheel'], note: 'zoomOnMouseWheel false, moveOnMouseWheel true: the wheel scrolls (up = right on x), zrDelta 2 then -4', option: valScatter([ins({ start: 20, end: 60, zoomOnMouseWheel: false, moveOnMouseWheel: true })]), steps: wheel(at.grid(0.5, 0.5), 2).concat(wheel(at.grid(0.5, 0.5), -4)) },
  { id: 'IN-XY', groups: ['inside', 'wheel', 'batch'], note: 'insides on x 0 and y 0 of one grid: one controller, one batch of two', option: valScatter([ins({ start: 10, end: 90 }), ins({ yAxisIndex: 0, start: 10, end: 90 })]), steps: wheel(at.grid(0.3, 0.3), 1).concat(drag(at.grid(0.5, 0.5), [[-30, 20]])) },
  { id: 'IN-XY-LOCK', groups: ['inside', 'wheel', 'zoomLock'], note: 'x zoomLock, y not: controlType true, and the zoom handler never reads zoomLock -- the locked x zooms too', option: valScatter([ins({ start: 10, end: 90, zoomLock: true }), ins({ yAxisIndex: 0, start: 10, end: 90 })]), steps: wheel(at.grid(0.3, 0.3), 1) },
  { id: 'IN-XY-DISABLED', groups: ['inside', 'wheel'], note: 'x disabled, y not: x computes a range (its view range drifts) but is not dispatched', option: valScatter([ins({ start: 10, end: 90, disabled: true }), ins({ yAxisIndex: 0, start: 10, end: 90 })]), steps: wheel(at.grid(0.3, 0.3), 1, 2) },
  { id: 'IN-NOPREVENT', groups: ['inside', 'pan'], note: 'preventDefaultMouseMove false: the pan does not stop the event', option: valScatter([ins({ start: 20, end: 60, preventDefaultMouseMove: false })]), steps: drag(at.grid(0.5, 0.5), [[-40, 0]]) },
  // ---- other axis types ----
  { id: 'IN-TIME', groups: ['inside', 'time'], note: 'a time x axis: a wheel at the centre, a drag', option: timeLine([ins({ start: 10, end: 90 })]), steps: wheel(at.grid(0.5, 0.5), 1).concat(drag(at.grid(0.5, 0.5), [[-60, 0]])) },
  { id: 'SL-TIME', groups: ['handle', 'time'], note: 'a time slider: handle 1 dragged left 70 px (time labels)', option: timeLine([sl()]), steps: drag(at.el('dz0.handle1'), [[-35, 0], [-35, 0]]) },
  { id: 'SL-VALUE', groups: ['handle', 'value'], note: 'a value slider: handle 0 dragged 37 px right (value labels, valuePrecision from the grid width)', option: valScatter([sl()]), steps: drag(at.el('dz0.handle0'), [[20, 0], [17, 0]]) },
];

// ---------- the guards ----------
const GUARDS = [
  { id: 'no-invert', mutation: 'the drag delta through the sliderGroup local transform instead of its inverse', mut: { noInvert: true }, named: ['VERTICAL'] },
  { id: 'screen-dx', mutation: 'the drag delta = screen dx (no transform)', mut: { screenDx: true }, named: ['VERTICAL', 'INVERSE'] },
  { id: 'no-zoomlock', mutation: 'slider zoomLock ignored', mut: { noZoomLock: true }, named: ['ZOOMLOCK'] },
  { id: 'realtime-ignored', mutation: 'realtime false ignored (dispatch while dragging, not on dragend)', mut: { realtimeIgnored: true }, named: ['RT-FALSE', 'RT-FALSE-CLICKHANDLE'] },
  { id: 'no-own-skip', mutation: 'a slider rebuilds its ends from the window on its own action too', mut: { noOwnSkip: true }, named: ['H0CROSS', 'BRUSH'] },
  { id: 'click-limit-7', mutation: 'the click rule allows 7 px instead of 4', mut: { clickLimit: 7 }, named: ['CLICK-NOBRUSH'] },
  { id: 'brush-width-only', mutation: 'a brush is a click on width < 5 alone (no 200 ms condition)', mut: { brushWidthOnly: true }, named: ['BRUSH-SLOW3'] },
  { id: 'fresh-brush', mutation: 'the brush rect cleared on every brush start', mut: { freshBrush: true }, named: ['BRUSH-STALE'] },
  { id: 'wheel-factor', mutation: 'the wheel factor always 1.1', mut: { factorFixed: true }, named: ['IN-WHEEL-MANY'] },
  { id: 'zoom-centre', mutation: 'the wheel zooms about the range centre instead of the pointer', mut: { zoomCentre: true }, named: ['IN-WHEEL-EDGE', 'IN-XY'] },
  { id: 'pan-sign', mutation: 'axis.inverse ignored in the direction signal', mut: { panSign: true }, named: ['IN-INVERSE'] },
  { id: 'no-throttle', mutation: 'every dispatch immediate (no fixRate throttle)', mut: { noThrottle: true }, named: ['THROTTLE', 'IN-WHEELMOVE', 'BRUSH-STALE'] },
  { id: 'drag-hides', mutation: '_showDataInfo ignores _dragging', mut: { dragHides: true }, named: ['H1CLAMPLEN', 'MOVEZONE'] },
  { id: 'bits-ignored', mutation: 'leaveEmphasis clears the move handle whatever other __highByOuter bits are set', mut: { bitsIgnored: true }, named: ['MOVEZONE'] },
  { id: 'spans-ignored', mutation: 'min / max spans ignored by the slider interaction', mut: { spansIgnored: true }, named: ['SPANS', 'MINVALUESPAN', 'BRUSH-MINSPAN'] },
  { id: 'no-follow', mutation: 'the action reaches only the dispatching dataZoom', mut: { noFollow: true }, named: ['TWO-SLIDERS', 'SLIDER-INSIDE', 'CHAIN'] },
  { id: 'mode-kept', mutation: 'setRawRange leaves rangePropMode alone', mut: { modeKept: true }, named: ['RT-FALSE-VALUE'] },
];

// ---------- the run ----------
function generate() {
  hookProto();
  const side = { timeLabels: new Map() };
  const scenarios = SCENARIOS.map(d => recordScenario(d, side));
  return {
    out: {
      source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version + ' (V8 ' + process.versions.v8 + ')',
      W, H, seed: SEED,
      clock: { start: CLOCK0, defaultDt: DEFAULT_DT },
      api: {
        events: 'chart.getZr().handler.mousemove / mousedown / mouseup / click / mousewheel(rawEvent); rawEvent {zrX, zrY, zrDelta (wheel), which 1, shiftKey, ctrlKey, altKey, preventDefault, stopPropagation}',
        hover: 'handler.findHover(x, y) before the event: .target / .topTarget',
        cursors: 'handler.proxy.setCursor wrapped (the node EmptyProxy)',
        actions: "chart._api.dispatchAction wrapped (the ExtensionAPI every view and the roams curry call); from = the view uid's dataZoom, dataZoomId -> componentIndex",
        slider: 'chart.getViewOfComponentModel(dz): _handleEnds, _range, _dragging, _isOverDataInfoTriggerArea, _brushing, _displayables (handles, handleLabels, moveHandle, moveZone, filler, brushRect, sliderGroup)',
        inside: 'the InsideZoomView `range`',
        model: 'dz.settledOption, dz.option, dz.getRangePropMode(), dz.findRepresentativeAxisProxy().getWindow()',
        axes: 'axis.scale.getExtent(); proxy._extent, proxy.getMinMaxSpan(); AxisProxy.prototype.calculateDataWindow wrapped for |axis.getExtent()|',
        controller: 'the roams coordSysRecord (an ExtensionAPI inner store): controller._opt.preventDefaultMouseMove, dispatchAction throttle rate; the zr roam store lists (which listeners are registered)',
        layout: 'sliderGroup.getLocalTransform() / .transform / .invTransform after storage.getDisplayList(true); handle.stateProxy("emphasis", ["emphasis"])',
      },
      notes: [
        'Only the dist build was run; every function transcribed here reads the same in src at 30076ae (wf62/upstream-interact.md).',
        "A slider's _onDragMove turns the screen delta into slider-local units with graphic.applyTransform([dx, dy], sliderGroup.getLocalTransform(), true): the INVERSE of the local transform, translation included (0 here). Vertical sliders rotate by Math.PI / 2 whose cosine is 6.123e-17, so a horizontal pointer component leaks into the delta at that scale.",
        "RoamController never assigns _controlType, so every enable() call re-registers its listeners; the effective listeners follow roams.mergeControllerParams: any enabled inside without zoomLock -> mouse + wheel, only zoomLock ones -> mouse only ('move'), all disabled -> none.",
        "The inside zoom handler never reads zoomLock: with another unlocked inside on the same grid the wheel zooms the locked one too (IN-XY-LOCK). A disabled inside still computes its range (its view `range` drifts) but is left out of the batch (IN-XY-DISABLED).",
        'A slider keeps its _handleEnds / _range on its own action (render skips _buildView when payload.from is its uid), so after a cross or a right-to-left brush _handleEnds stays descending; any other action rebuilds the view (new elements, labels back to handleLabel.show, brushRect gone).',
        "_onBrushEnd does not clear brushRect: a later mousedown / mouseup with no move re-applies the old (ignored) rect's shape if it was >= 5 px (BRUSH-STALE).",
        'Throttle: _dispatchZoomAction (per slider view) and the roams dispatch (per grid) are fixRate throttles of dz.get("throttle") (100 here: _setDefaultThrottle gives 100 when option.animation is truthy ("auto" by default) and animationDurationUpdate (500) > 0, else 20). A deferred call runs at lastExec + rate with the latest arguments; the slider reads this._range at run time.',
        'Hover emphasis of the handles is a flag (hoverState 2) set by echarts\' zr mouseover listener; the style follows at the next frame (applyChangedStates); `style` records what the last frame applied and is not transcribed.',
        "The full build also installs the brush component, whose visual encoding dispatches a throttled 'brushSelect' action (update 'none') after every update carrying a payload; those are not recorded (actions[] holds 'dataZoom' actions only).",
        'pxSpans / proxyExtent / the grid are inputs of the transcription (the processing oracle covers them); time labels are read from the scale.',
      ],
      scenarios,
    },
    side,
  };
}

function check(g) {
  const { out, side } = g;
  const byId = {};
  for (const sc of out.scenarios) {
    byId[sc.id] = sc;
    const d = scenarioDiffs(sc, side, {});
    must(!d.length, sc.id + ': the transcription differs at ' + d.slice(0, 4).map(x => x.field + ' (' + x.upstream + ' vs ' + x.mutated + ')').join('; '));
    for (const z of sc.layout.dataZooms) {
      if (z.subType !== 'slider') continue;
      const inv = invert(z.global.map(num));
      must(JSON.stringify(inv.map(hex)) === JSON.stringify(z.inv), sc.id + ': inv is not invert(global)');
    }
    const c = sc.layout.controller;
    const insides = sc.layout.dataZooms.filter(z => z.subType === 'inside');
    if (insides.length) {
      // roams.mergeControllerParams
      const prio = { true: 2, move: 1, false: 0, undefined: -1 };
      let ct;
      let pdmm = true;
      for (const z of insides) {
        const one = z.disabled ? false : z.zoomLock ? 'move' : true;
        if (prio[String(one)] > prio[String(ct)]) ct = one;
        pdmm = pdmm && z.preventDefaultMouseMove;
      }
      must(c.mouse === (ct === true || ct === 'move') && c.wheel === (ct === true) && c.preventDefaultMouseMove === !!pdmm, sc.id + ': controller ' + JSON.stringify(c) + ' vs ' + ct);
    }
  }
  // anchors
  const lastSt = id => byId[id].steps[byId[id].steps.length - 1];
  const w0 = id => lastSt(id).dataZooms[0].windowText;
  must(w0('H0R50').percent.join() === '28.333333333333332,60', 'H0R50 window ' + w0('H0R50').percent);
  must(!byId['CLICK-6PX'].steps.some(s => s.event.type === 'click' && s.actions.length) && byId['CLICK-6PX'].steps.some(s => s.actions.length), 'CLICK-6PX: a brush and no click action');
  const rtf = byId['RT-FALSE'].steps;
  must(rtf.filter(s => s.actions.length).length === 1 && rtf.find(s => s.actions.length).event.type === 'mouseup', 'RT-FALSE dispatches once, on mouseup');
  must(byId.THROTTLE.steps.some(s => s.actions.some(a => a.deferred)), 'THROTTLE has no deferred action');
  const lock = lastSt('IN-XY-LOCK').dataZooms[0].windowText.percent;
  must(lock.join() !== '10,90', 'IN-XY-LOCK: the locked x did not zoom');
  const stale = byId['BRUSH-STALE'].steps.filter(s => s.actions.length).map(s => s.event.type);
  must(stale.join() === 'mouseup,mouseup,idle', 'BRUSH-STALE actions at ' + stale);

  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const sc of out.scenarios) {
      const d = scenarioDiffs(sc, side, gd.mut);
      if (d.length) {
        changed.push(sc.id);
        if (gd.named.includes(sc.id)) differs.push({ scenario: sc.id, fields: d.slice(0, 3) });
      }
    }
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(n => changed.includes(n)), differs };
  });
}

// the compact writer of box-merge.js
const LINE = 250;
function oneLine(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + Array.from(v, x => oneLine(x === undefined ? null : x)).join(',') + ']';
  return '{' + Object.keys(v).filter(k => v[k] !== undefined).map(k => JSON.stringify(k) + ':' + oneLine(v[k])).join(',') + '}';
}
function fmt(v, ind) {
  const f = oneLine(v);
  if (f.length + ind.length <= LINE || v === null || typeof v !== 'object') return f;
  const inner = ind + ' ';
  if (Array.isArray(v)) {
    const items = Array.from(v, x => fmt(x === undefined ? null : x, inner));
    if (items.every(t => !t.includes('\n'))) {
      const lines = [];
      let cur = '';
      for (const t of items) {
        if (cur && inner.length + cur.length + 1 + t.length + 1 > LINE) { lines.push(cur); cur = ''; }
        cur += (cur ? ',' : '') + t;
      }
      lines.push(cur);
      return '[\n' + lines.map(l => inner + l).join(',\n') + '\n' + ind + ']';
    }
    return '[\n' + items.map(x => inner + x).join(',\n') + '\n' + ind + ']';
  }
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner))
    .join(',\n') + '\n' + ind + '}';
}
const serialise = out => fmt(out, '') + '\n';

let g1;
let json1;
let json2;
try {
  g1 = generate();
  g1.out.guards = check(g1);
  json1 = serialise(g1.out);
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(JSON.parse(JSON.stringify(g1.out))), 'the written JSON does not parse back to the record');
  const g2 = generate();
  g2.out.guards = check(g2);
  json2 = serialise(g2.out);
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const out = g1.out;
const bad = out.guards.filter(gd => !gd.ok);
out.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ' (' + gd.mutation + '): named '
  + gd.named.join(' / ') + '; changes ' + gd.changed.length + ': ' + gd.changed.join(', ')));
const deterministic = json1 === json2;
const nSteps = out.scenarios.reduce((n, s) => n + s.steps.length, 0);
const nActions = out.scenarios.reduce((n, s) => n + s.steps.reduce((m, st) => m + st.actions.length, 0), 0);
console.log(out.scenarios.length + ' scenarios, ' + nSteps + ' steps, ' + nActions + ' actions; ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  bad.forEach(gd => console.log('FAIL ' + gd.id + ': changed ' + gd.changed.join(', ')));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
