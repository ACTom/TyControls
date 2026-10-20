// Upstream's own answers for THE THUMBNAIL and THE PARALLEL AXIS EXPANSION
// (D7, batch 140).
//
// THE THUMBNAIL (component/thumbnail, v6): a box (right 1, bottom 1, 25% by
// 25% by default) laid by getLayoutRect on the chart, filled with the
// option's backgroundColor (or the neutral00 token) and rimmed by its
// itemStyle (border token, 2 px); inside it, shrunk by half that rim, the
// content rect, which clips a copy of the target graph (the first graph
// series, or the one seriesIndex / seriesId names) -- every node's symbol
// sub-path cloned with its shape set to the symbol's scaleX / scaleY (half
// the symbol size) round the node's layout position, every edge's line path
// cloned, all at z2 151 -- fitted into the content rect by a View (the
// copy's bounding rect, the content rect's centred rect of the same aspect)
// and the window: the canvas carried through the graph's inverse overall
// transform and the thumbnail's raw transform (windowStyle: neutral30 at 0.3,
// rimmed neutral40). A roam of the graph moves the window
// (__updateOnOwnRoam -> updateWindow); a render of the graph copies it again.
// The thumbnail's own RoamController (z 10, above the graph's) pans and zooms
// the graph through graphRoam when the series' `roam` is truthy: a drag
// anywhere in the content rect moves the graph against the window, a wheel
// zooms by 1 / scale about the pointer carried into the graph's canvas.
//
// THE AXIS EXPANSION (coord/parallel, component/parallel/ParallelView.ts,
// parallelAxisAction.ts): axisExpandable lays the axes in the window at
// axisExpandWidth and folds the rest; ParallelView listens on zrender's
// mousedown / mouseup (axisExpandTriggerOn 'click': a press and a release
// within sqrt(5) px) or mousemove ('mousemove': through a fixRate throttle of
// axisExpandRate ms, a jump debounced by axisExpandDebounce), asks
// getSlidedAxisExpandWindow where the window goes (jump, slide or none) and
// dispatches parallelAxisExpand {axisExpandWindow[, animation]}, whose
// handler writes the keys the payload owns into every queried parallel
// model's option -- the same array, which _makeLayoutInfo then rewrites
// ([1] = [0] + the restricted size) every time it runs. The event
// parallelaxisexpand follows the update, then brushselected.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 600 x 400,
// TZ=UTC, Math.random the port's xorshift32 (the force layout draws from
// it), and drives zrender's own Handler with synthetic pointer events
// (mousemove / mousedown / mouseup / click / mousewheel), as
// parallel-brush.js and datazoom-interact.js do. Time is fake (Date and
// setTimeout replaced): a step's dt (200 ms for a pointer step unless it
// says, 0 for a click, 1000 for the idle step every scenario ends with) runs
// the timers due first. Every option has `animation: false`; the force
// layouts have layoutAnimation false.
//
//   node tools/advchart-oracle/thumbnail-axisexpand.js
//
// writes tests/fixtures/advchart-thumbnail-axisexpand.json (ORACLE_OUT
// overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex   a double as the 16 hex digits of its IEEE-754 bits (NaN
//         7ff8000000000000); null where there is no number.
//   js    String(v).
//
// Top level: source, W, H, clock, notes[], scenarios[], guards[], recipes{}
// A scenario: id, family ('thumbnail' | 'expand'), note, option, initial (a
//   record), steps[] {i, step (with dt), hover, record}
//   hover: what zrender's Handler finds under a pointer step before it runs:
//   'thumbnail<k>' (a thumbnail's box or window), 'series<k>', 'other' or
//   null (nothing, or off the canvas).
// A record
//   W, H        the canvas
//   thumbs[]    per thumbnail component: {k, enabled (_isEnabled), drawn
//               (its group has children), box [x,y,w,h] | null, boxR (js of
//               the rect's r) , bgStyle, bgZ2, content [x,y,w,h], window
//               [x,y,w,h], winR, winStyle, winZ2, view null | {dataRect,
//               viewRect, trans [x, y, scaleX, scaleY] (the copy group's,
//               VIEW_COORD_SYS_TRANS_RAW), target [6] (the graph's overall
//               matrix as the bridge holds it), toTarget [6] (the
//               thumbnail-to-graph matrix) | null, roamType (js), roamOn (the
//               controller is enabled; which listeners follows roamType)},
//               items[] {kind 'symbol', type, rect [x,y,w,h], style} |
//               {kind 'line', shape [x1,y1,x2,y2,cpx1,cpy1,percent], style}}
//               a style is {fill, stroke, lineWidth (hex), opacity (hex),
//               lineDash (js)} with null for what the clone does not hold.
//   graphs[]    per graph series on a view: {seriesIndex, overall [6]}
//   pars[]      per parallel component: {k, expandable, expandWidth,
//               collapseWidth, window [2], winInner [2], window0Pos (the
//               layout info computed from the option as it stands, on a copy
//               of its window), optWindow (the option's axisExpandWindow
//               array, hex, or null), optCenter, optCount, optWidth (js),
//               axes[] {k (parallelAxis index), pos [x,y], labelShow,
//               nameAvail, nameTrunc}}
//   axes[]      per parallelAxis component with a brush controller: {k,
//               intervals [[a,b]], mount [x,y] (the controller's group
//               translation), covers [[a,b]] (the covers' ranges)}
//   rows[]      per parallel series: {seriesIndex, items [{opacity, active}]}
//   actions[]   what a view dispatched (api.dispatchAction): {t (ms since T0),
//               type, by ('thumbnail' | 'graph' | 'parallel' | 'axis'),
//               ... the payload: graphRoam {seriesId, dx, dy, zoom, originX,
//               originY} hex; parallelAxisExpand {window [2] hex, animation
//               (js of the payload's animation, 'absent' when it has none)};
//               axisAreaSelect {parallelAxisId, intervals}}
//   events[]    {t, type: 'parallelaxisexpand', window [2] hex | null,
//               windowJs, animation, keys} | {t, type: 'brushselected',
//               batch n} | {t, type: 'axisareaselected', intervals} |
//               {t, type: 'graphroam', seriesId, dx, dy, zoom, originX,
//               originY}
//   error       null | an exception's message
//
// Self-checks (any failure: nothing is written, exit 1), transcriptions
// recomputed and compared with the records:
//   T1 every enabled thumbnail's content rect from its box and rim
//      (expandOrShrinkRect), its view rect from the copy's data rect
//      (getLayoutRect centred, aspect, 0.8), its raw transform
//      (calculateTransform, decomposed), its window (the canvas through
//      raw * inverse(target), BoundingRect.applyTransform), toTarget
//      (the inverse of that product);
//   T2 the copy's data rect from its items where every symbol is a circle or
//      a rect (Path.getBoundingRect: the stroke, at least 5 for a line;
//      Group's union, an empty group's (0, 0, 0, 0));
//   T3 every graphRoam the thumbnail dispatched from the pointer: a pan's
//      dx / dy through toTarget, a zoom's 1 / factor and origin;
//   E1 every parallel's layout info and axis places from its option
//      (_makeLayoutInfo, layoutAxisWithExpand / WithoutExpand);
//   E2 every parallelAxisExpand a click dispatched, from the record before
//      and the pointer (getSlidedAxisExpandWindow, sliderMove);
//   E3 the mousemove dispatches: the throttle (fixRate, debounceNextCall on
//      a jump, a null call cancelling) replayed over the moves gives every
//      dispatch's time and the move it came from.
// guards[] mutate the transcription one way each and name the scenarios
// that must notice; anchors; no U+0000; the JSON parses back; two
// generations give the same bytes. process.exit() ends the run.
// ---------------------------------------------------------------------------
'use strict';
process.env.TZ = 'UTC';
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
    best.fn();
  }
  NOW = to;
}

// the port's xorshift32, reseeded per chart (TyGraphForceSeed(0))
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

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-thumbnail-axisexpand.json');
const W0 = 600;
const H0 = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- numbers ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hexN = v => (typeof v === 'number' ? hex(v) : null);
const same = (a, b) => (Number.isNaN(a) && Number.isNaN(b)) || a === b;
function sameDeep(a, b) {
  if (typeof a === 'number' || typeof b === 'number') return typeof a === 'number' && typeof b === 'number' && same(a, b);
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => sameDeep(x, b[i]));
  return a == b; // eslint-disable-line eqeqeq
}
const nul = s => (s == null ? null : String(s).split('\u0000').join('<NUL>'));
const js = v => (v === undefined ? 'undefined' : v === null ? 'null' : typeof v === 'object' ? JSON.stringify(v) : String(v));
const rect4 = r => [hex(r.x), hex(r.y), hex(r.width), hex(r.height)];
// [R2-I4] a scenario that asks for the pens' dashes (def.pen): the pattern
// normalizeLineDash makes and the phase, too
let PEN = false;
// zrender canvas/dashStyle.ts normalizeLineDash, transcribed
function normalizeLineDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  lineWidth = lineWidth || 1;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
    : typeof lineType === 'number' ? [lineType]
    : Array.isArray(lineType) ? lineType : null;
}
function styleRec(st) {
  if (!st) return null;
  const col = c => (c == null ? null : typeof c === 'string' ? c : JSON.stringify(c));
  const o = {
    fill: col(st.fill), stroke: col(st.stroke),
    lineWidth: st.lineWidth == null ? null : hex(st.lineWidth),
    opacity: st.opacity == null ? null : hex(st.opacity),
    lineDash: st.lineDash == null ? null : js(st.lineDash),
  };
  if (PEN) {
    const pat = normalizeLineDash(st.lineDash, st.lineWidth);
    o.pattern = pat == null ? null : pat.map(hex);
    o.lineDashOffset = st.lineDashOffset == null ? null : hex(st.lineDashOffset);
    // [R2-I5] a pen that is a gradient, as the clone holds it
    const s = st.stroke;
    if (s && typeof s === 'object' && s.colorStops) {
      o.strokeGrad = { type: s.type, x: s.x, y: s.y, x2: s.x2 == null ? null : s.x2, y2: s.y2 == null ? null : s.y2,
        r: s.r == null ? null : s.r, global: !!s.global, stops: s.colorStops.map(c => [c.offset, c.color]) };
    }
  }
  return o;
}

// the inner store of a View (makeInner): the object holding mtOverall
function viewInner(view) {
  if (view.mtOverall) return view;
  for (const k of Object.keys(view)) {
    const v = view[k];
    if (k.indexOf('__ec_inner_') === 0 && v && typeof v === 'object' && v.mtOverall) return v;
  }
  return null;
}

// =====================================================================
// Recording
// =====================================================================
function thumbViews(chart) {
  const out = [];
  chart.getModel().eachComponent('thumbnail', m => out.push({ model: m, view: chart.getViewOfComponentModel(m) }));
  return out;
}
function thumbRec(tv) {
  const v = tv.view;
  const rec = { k: tv.model.componentIndex, enabled: !!(v && v._isEnabled()), drawn: !!(v && v.group.childCount() > 0) };
  if (!v || !rec.drawn) return rec;
  const bg = v._bgRect;
  rec.box = rect4(bg.shape);
  rec.boxR = js(bg.shape.r);
  rec.bgStyle = styleRec(bg.style);
  rec.bgZ2 = js(bg.z2);
  rec.content = rect4(v._contentRect);
  const win = v._windowRect;
  rec.window = rect4(win.shape);
  rec.winR = js(win.shape.r);
  rec.winStyle = styleRec(win.style);
  rec.winZ2 = js(win.z2);
  rec.view = null;
  rec.items = [];
  const br = v._bridgeRendered;
  const bridgeGroup = v._targetGroup && v._targetGroup.childAt(0);
  if (br && br.renderVersion === v._renderVersion && bridgeGroup) {
    const cs = v._coordSys;
    const inner = viewInner(cs);
    const rc = v._roamController;
    rec.view = {
      dataRect: rect4(cs.getBoundingRect()), viewRect: rect4(cs.getViewRect()),
      trans: [hex(bridgeGroup.x), hex(bridgeGroup.y), hex(bridgeGroup.scaleX), hex(bridgeGroup.scaleY)],
      overall: Array.from(inner.mtOverall).map(hex),
      target: Array.from(br.targetTrans).map(hex),
      toTarget: v._transThisToTarget ? Array.from(v._transThisToTarget).map(hex) : null,
      roamType: js(br.roamType),
      // the controller is on (enable never records its controlType: which
      // listeners are on follows roamType)
      roamOn: !!(rc && rc._enabled),
      _dataRect: cs.getBoundingRect().clone(), _viewRect: cs.getViewRect().clone(),
      _trans: [bridgeGroup.x, bridgeGroup.y, bridgeGroup.scaleX, bridgeGroup.scaleY, bridgeGroup.rotation],
      _overall: Array.from(inner.mtOverall), _target: Array.from(br.targetTrans),
      _toTarget: v._transThisToTarget ? Array.from(v._transThisToTarget) : null,
    };
    const items = [];
    bridgeGroup.eachChild(g => g.eachChild(e => {
      if (e.type === 'ec-line') {
        const s = e.shape;
        items.push({ kind: 'line', shape: [s.x1, s.y1, s.x2, s.y2, s.cpx1, s.cpy1, s.percent].map(hexN), style: styleRec(e.style),
          _shape: Object.assign({}, s), _style: Object.assign({}, e.style) });
      } else {
        const s = e.shape;
        items.push({ kind: 'symbol', type: s.symbolType == null ? null : String(s.symbolType), rect: [s.x, s.y, s.width, s.height].map(hexN),
          style: styleRec(e.style), _shape: Object.assign({}, s), _style: Object.assign({}, e.style), _group: g === bridgeGroup.childAt(0) ? 0 : 1 });
      }
    }));
    rec.items = items;
    rec._groupCounts = [bridgeGroup.childAt(0).childCount(), bridgeGroup.childAt(1).childCount()];
  }
  rec._box = bg.shape ? { x: bg.shape.x, y: bg.shape.y, width: bg.shape.width, height: bg.shape.height } : null;
  rec._bgLineWidth = bg.style.lineWidth;
  rec._content = v._contentRect.clone();
  rec._window = Object.assign({}, win.shape);
  return rec;
}
function graphsRec(chart) {
  const out = [];
  chart.getModel().eachSeriesByType('graph', s => {
    const cs = s.coordinateSystem;
    if (!cs || cs.type !== 'view') return;
    const inner = viewInner(cs);
    out.push({ seriesIndex: s.seriesIndex, overall: Array.from(inner.mtOverall).map(hex) });
  });
  return out;
}
// _makeLayoutInfo on a copy of the window, so the option is not rewritten
function layoutInfoOf(pm) {
  const cs = pm.coordinateSystem;
  const o = pm.option;
  const had = Object.prototype.hasOwnProperty.call(o, 'axisExpandWindow');
  const saved = o.axisExpandWindow;
  if (Array.isArray(saved)) o.axisExpandWindow = saved.slice();
  let li;
  try { li = cs._makeLayoutInfo(); } finally {
    if (had) o.axisExpandWindow = saved; else delete o.axisExpandWindow;
  }
  return li;
}
function parsRec(chart) {
  const out = [];
  chart.getModel().eachComponent('parallel', pm => {
    const cs = pm.coordinateSystem;
    if (!cs) return;
    const li = layoutInfoOf(pm);
    const o = pm.option;
    const rec = {
      k: pm.componentIndex, expandable: !!li.axisExpandable, expandWidth: hex(li.axisExpandWidth),
      collapseWidth: hex(li.axisCollapseWidth), window: li.axisExpandWindow.map(hexN), winInner: li.winInnerIndices.map(hexN),
      window0Pos: hexN(li.axisExpandWindow0Pos),
      optWindow: Array.isArray(o.axisExpandWindow) ? o.axisExpandWindow.map(hexN) : null,
      optCenter: js(o.axisExpandCenter), optCount: js(o.axisExpandCount), optWidth: js(o.axisExpandWidth),
      optExpandable: js(o.axisExpandable),
      axes: cs.dimensions.map(d => {
        const lay = cs._axesLayout[d];
        return { k: cs.getAxis(d).model.componentIndex, pos: lay.position.map(hex), labelShow: !!lay.axisLabelShow,
          nameAvail: hexN(lay.axisNameAvailableWidth), nameTrunc: hexN(lay.nameTruncateMaxWidth) };
      }),
      _li: li, _rect: cs.getRect().clone(), _opt: {
        axisExpandable: o.axisExpandable, axisExpandWidth: o.axisExpandWidth, axisExpandCount: o.axisExpandCount,
        axisExpandCenter: o.axisExpandCenter, axisExpandWindow: Array.isArray(o.axisExpandWindow) ? o.axisExpandWindow.slice() : o.axisExpandWindow,
        layout: o.layout, axisExpandSlideTriggerArea: o.axisExpandSlideTriggerArea, axisExpandTriggerOn: o.axisExpandTriggerOn,
        axisExpandRate: o.axisExpandRate, axisExpandDebounce: o.axisExpandDebounce,
      },
      _lays: cs.dimensions.map(d => cs._axesLayout[d]), _n: cs.dimensions.length,
    };
    out.push(rec);
  });
  return out;
}
function axesRec(chart) {
  const out = [];
  chart.getModel().eachComponent('parallelAxis', m => {
    const v = chart.getViewOfComponentModel(m);
    const bc = v && v._brushController;
    if (!bc) return;
    out.push({ k: m.componentIndex, intervals: (m.activeIntervals || []).map(iv => iv.map(hex)),
      mount: bc._transform ? [hex(bc._transform[4]), hex(bc._transform[5])] : null,
      covers: bc._covers.map(c => c.__brushOption.range.map(hex)) });
  });
  return out;
}
function rowsRec(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'parallel') return;
    const data = sm.getData();
    const act = [];
    sm.coordinateSystem.eachActiveState(data, (st, i) => { act[i] = st; });
    const items = [];
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      const st = el && (el.currentStates || []).length && el._normalState && el._normalState.style ? el._normalState.style : el && el.style;
      items.push({ opacity: st ? hex(st.opacity == null ? 1 : st.opacity) : null, active: act[i] });
    }
    out.push({ seriesIndex: sm.seriesIndex, items });
  });
  return out;
}

function roleOf(chart, el) {
  if (!el) return null;
  for (const tv of thumbViews(chart)) {
    let p = el;
    while (p) { if (tv.view && p === tv.view.group) return 'thumbnail' + tv.model.componentIndex; p = p.parent; }
  }
  let p = el;
  while (p) {
    if (p.__ecComponentInfo) return p.__ecComponentInfo.mainType + p.__ecComponentInfo.index;
    p = p.parent;
  }
  // a series' element: its view's group
  let found = null;
  chart.getModel().eachSeries(sm => {
    const v = chart.getViewOfSeriesModel(sm);
    let q = el;
    while (q) { if (v && q === v.group) { found = 'series' + sm.seriesIndex; return; } q = q.parent; }
  });
  return found || 'other';
}
function zev(type, x, y, extra) {
  return Object.assign({ type, zrX: x, zrY: y, which: 1, shiftKey: false, ctrlKey: false, altKey: false, cancelBubble: false,
    preventDefault() {}, stopPropagation() {} }, extra || {});
}

let CTX = null;
function snapshot(chart, error) {
  chart.getZr().storage.getDisplayList(true);
  return {
    W: chart.getWidth(), H: chart.getHeight(),
    thumbs: thumbViews(chart).map(thumbRec),
    graphs: graphsRec(chart),
    pars: parsRec(chart),
    axes: axesRec(chart),
    rows: rowsRec(chart),
    actions: CTX.actions,
    events: CTX.events,
    error,
  };
}

function runScenario(def) {
  PEN = !!def.pen;
  NOW = CLOCK0;
  TIMERS = [];
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W0, height: H0 });
  try {
    CTX = { actions: [], events: [] };
    const api = chart._api;
    const origDispatch = api.dispatchAction;
    api.dispatchAction = function (payload) {
      // which view dispatched: read off the stack (the handlers are bound
      // before any wrapper could reach them)
      const stack = new Error().stack;
      const by = /ThumbnailView\._on(Pan|Zoom)/.test(stack) ? 'thumbnail'
        : /ParallelView\._dispatchExpand/.test(stack) ? 'parallel'
          : /ParallelAxisView\._onBrush/.test(stack) ? 'axis' : 'graph';
      const t = NOW - CLOCK0;
      if (payload.type === 'graphRoam') {
        CTX.actions.push({ t, type: payload.type, by, seriesId: nul(payload.seriesId), dx: hexN(payload.dx), dy: hexN(payload.dy),
          zoom: hexN(payload.zoom), originX: hexN(payload.originX), originY: hexN(payload.originY), _p: Object.assign({}, payload) });
      } else if (payload.type === 'parallelAxisExpand') {
        CTX.actions.push({ t, type: payload.type, by, window: payload.axisExpandWindow ? payload.axisExpandWindow.map(hexN) : null,
          animation: Object.prototype.hasOwnProperty.call(payload, 'animation') ? js(payload.animation) : 'absent',
          _p: { axisExpandWindow: payload.axisExpandWindow ? payload.axisExpandWindow.slice() : null, animation: payload.animation } });
      } else if (payload.type === 'axisAreaSelect') {
        CTX.actions.push({ t, type: payload.type, by, parallelAxisId: nul(payload.parallelAxisId),
          intervals: (payload.intervals || []).map(iv => iv.map(hex)) });
      }
      // any other action a view dispatches (brushSelect, select ...) is not recorded
      return origDispatch.apply(this, arguments);
    };
    chart.on('parallelaxisexpand', p => {
      const keys = Object.keys(p).filter(k => k !== 'type').sort();
      CTX.events.push({ t: NOW - CLOCK0, type: 'parallelaxisexpand', window: Array.isArray(p.axisExpandWindow) ? p.axisExpandWindow.map(hexN) : null,
        windowJs: js(p.axisExpandWindow), animation: Object.prototype.hasOwnProperty.call(p, 'animation') ? js(p.animation) : 'absent', keys: keys.join(',') });
    });
    chart.on('brushselected', p => CTX.events.push({ t: NOW - CLOCK0, type: 'brushselected', batch: (p.batch || []).length }));
    chart.on('axisareaselected', p => CTX.events.push({ t: NOW - CLOCK0, type: 'axisareaselected',
      intervals: (p.intervals || []).map(iv => iv.map(hex)) }));
    chart.on('graphroam', p => CTX.events.push({ t: NOW - CLOCK0, type: 'graphroam', seriesId: nul(p.seriesId), dx: hexN(p.dx), dy: hexN(p.dy),
      zoom: hexN(p.zoom), originX: hexN(p.originX), originY: hexN(p.originY) }));
    chart.setOption(JSON.parse(JSON.stringify(def.option)));
    const initial = snapshot(chart, null);
    const recs = [];
    const steps = def.steps.concat([{ type: 'idle' }]);
    const h = chart.getZr().handler;
    steps.forEach((st, i) => {
      CTX.actions = [];
      CTX.events = [];
      let error = null;
      const ptr = ['mousemove', 'mousedown', 'mouseup', 'click', 'mousewheel'].includes(st.type);
      const dt = st.dt != null ? st.dt : st.type === 'click' ? 0 : st.type === 'idle' ? 1000 : 200;
      const out = { i, step: Object.assign({}, st, { dt }), hover: null };
      const before = snapshot(chart, null);
      CTX.actions = [];
      CTX.events = [];
      try {
        advanceClock(NOW + dt);
        if (ptr) {
          const x = st.x;
          const y = st.y;
          out.hover = (x < 0 || y < 0 || x > chart.getWidth() || y > chart.getHeight()) ? null : roleOf(chart, h.findHover(x, y).target);
          if (st.type === 'mousewheel') h.mousewheel(zev('mousewheel', x, y, { zrDelta: st.delta / 120 }));
          else h[st.type](zev(st.type, x, y));
        } else if (st.type === 'action') {
          chart.dispatchAction(JSON.parse(JSON.stringify(st.payload)));
        } else if (st.type === 'set') {
          rngState = SEED;
          chart.setOption(JSON.parse(JSON.stringify(st.option)), !!st.notMerge);
              } else if (st.type === 'resize') {
          chart.resize({ width: st.w, height: st.h });
        }
      } catch (e) {
        if (e instanceof OracleError) throw e;
        error = String(e.message);
      }
      out.record = snapshot(chart, error);
      out._before = before;
      recs.push(out);
    });
    return { id: def.id, family: def.family, note: def.note, option: def.option, initial, steps: recs, _chart: chart };
  } catch (e) {
    chart.dispose();
    throw e;
  }
}

// =====================================================================
// The scenarios
// =====================================================================
const NONE_NODES = [
  { name: 'a', x: 0, y: 0, symbolSize: 20 },
  { name: 'b', x: 100, y: 50, symbol: 'rect', symbolSize: 30 },
  { name: 'c', x: 40, y: 120, symbolSize: [40, 20], itemStyle: { borderWidth: 3, borderColor: '#ff0000' } },
  { name: 'd', x: 160, y: 140, symbol: 'triangle', itemStyle: { opacity: 0.5 } },
  { name: 'e', x: -30, y: 90, symbol: 'emptyCircle', symbolSize: 16 },
  { name: 'f', x: 70, y: -40, symbol: 'diamond', itemStyle: { color: '#30a050' } },
];
const NONE_LINKS = [
  { source: 'a', target: 'b' },
  { source: 'b', target: 'c', lineStyle: { curveness: 0.3, width: 3 } },
  { source: 'c', target: 'd', lineStyle: { type: 'dashed' } },
  { source: 'a', target: 'e', lineStyle: { width: 4, opacity: 0.8, color: '#3060c0' } },
  { source: 'f', target: 'b', lineStyle: { curveness: -0.2 } },
];
const graphNone = extra => ({
  animation: false,
  series: [Object.assign({ type: 'graph', layout: 'none', roam: true, symbolSize: 24, edgeSymbol: ['none', 'arrow'],
    data: JSON.parse(JSON.stringify(NONE_NODES)), links: JSON.parse(JSON.stringify(NONE_LINKS)) }, extra || {})],
  thumbnail: {},
});
const drag = (x0, y0, pts, ux, uy) => [].concat([{ type: 'mousemove', x: x0, y: y0 }, { type: 'mousedown', x: x0, y: y0 }],
  pts.map(p => ({ type: 'mousemove', x: p[0], y: p[1] })),
  [{ type: 'mouseup', x: ux, y: uy }, { type: 'click', x: ux, y: uy }]);
const click = (x, y, dx, dy) => [{ type: 'mousemove', x, y }, { type: 'mousedown', x, y },
  { type: 'mouseup', x: x + (dx || 0), y: y + (dy || 0) }, { type: 'click', x: x + (dx || 0), y: y + (dy || 0) }];

const FORCE_NODES = [];
for (let i = 0; i < 9; i++) FORCE_NODES.push({ name: 'n' + i, value: i + 1, symbolSize: 10 + 3 * i, category: i % 3 });
const FORCE_LINKS = [[0, 1], [1, 2], [2, 0], [3, 4], [4, 5], [5, 3], [0, 3], [6, 7], [7, 8], [8, 6], [2, 6]].map(p => ({ source: 'n' + p[0], target: 'n' + p[1] }));

const AXES8 = [];
for (let i = 0; i < 8; i++) AXES8.push({ dim: i, id: 'x' + i, name: 'Dimension ' + i, min: 0, max: 100 });
const ROWS8 = [
  [12, 85, 40, 66, 5, 30, 70, 50], [30, 22, 95, 14, 52, 88, 10, 64], [47, 61, 8, 90, 33, 20, 45, 91],
  [55, 38, 72, 47, 81, 60, 35, 7], [68, 9, 26, 58, 17, 75, 92, 28], [79, 74, 53, 3, 69, 41, 18, 83],
];
const par8 = (parallel, extra) => Object.assign({
  animation: false,
  parallel: Object.assign({ axisExpandable: true, axisExpandCount: 4, axisExpandCenter: 3, axisExpandWidth: 60 }, parallel || {}),
  parallelAxis: JSON.parse(JSON.stringify(AXES8)),
  series: [{ type: 'parallel', data: JSON.parse(JSON.stringify(ROWS8)) }],
}, extra || {});
// horizontal default box: x 80 .. 520, y 60 .. 340; the window at 177.5 .. 357.5
const moves = (pts, dt) => pts.map(p => ({ type: 'mousemove', x: p[0], y: p[1], dt }));

const SCENARIOS = [
  // ---------------- the thumbnail ----------------
  {
    id: 'TH-NONE', family: 'thumbnail',
    note: "a 'none' graph with six symbols, a rim, a curve, a dash, an arrow: the copy, its view and window; the graph's own roam (action pan and zoom, a wheel, a drag) moves the window; a drag and wheels on the thumbnail roam the graph; a wheel and a drag on the rim outside the content; hovering the box hides what is under it",
    option: graphNone(),
    steps: [].concat(
      [{ type: 'mousemove', x: 520, y: 350 }, { type: 'mousemove', x: 300, y: 200 }],
      [{ type: 'action', payload: { type: 'graphRoam', dx: 30, dy: -20 } }],
      [{ type: 'action', payload: { type: 'graphRoam', zoom: 2, originX: 300, originY: 200 } }],
      [{ type: 'mousewheel', x: 200, y: 150, delta: 120 }],
      drag(250, 150, [[270, 160], [290, 175]], 290, 175),
      drag(520, 350, [[530, 355], [541, 341]], 541, 341),
      [{ type: 'mousewheel', x: 520, y: 350, delta: 120 }, { type: 'mousewheel', x: 500, y: 330, delta: -360 }],
      [{ type: 'mousewheel', x: 449, y: 350, delta: 120 }],
      drag(449, 330, [[440, 320]], 440, 320),
      drag(520, 350, [[700, 500]], 700, 500)),
  },
  {
    id: 'TH-STYLE', family: 'thumbnail',
    note: 'the styles: a merge of windowStyle (colour, radius, rim, opacity) and itemStyle (fill, radius, rim); the backgroundColor fill; a resize; notMerge',
    option: Object.assign(graphNone(), { backgroundColor: '#fafafa' }),
    steps: [
      { type: 'set', option: { thumbnail: { windowStyle: { color: '#ff0000', borderRadius: 4, borderWidth: 3, opacity: 0.5 }, itemStyle: { borderRadius: 6, borderWidth: 6, color: '#eeeeff', borderColor: '#333333' } } } },
      { type: 'resize', w: 500, h: 360 },
      { type: 'action', payload: { type: 'graphRoam', dx: -40, dy: 25 } },
      { type: 'set', notMerge: true, option: Object.assign(graphNone({ zoom: 1.5, center: [60, 40] }), { thumbnail: { itemStyle: { borderWidth: 0 }, windowStyle: { borderWidth: 0, opacity: 1, color: 'rgba(0,0,0,0.2)' } } }) },
    ],
  },
  {
    id: 'TH-BOX', family: 'thumbnail',
    note: 'box positions through notMerge (the init mergeLayoutParam): left / top, centred, percentages, sides only, a wide rim and a radius list; a zoomed and centred graph',
    option: Object.assign(graphNone({ zoom: 2.5, center: ['30%', 40] }), { thumbnail: { left: 20, top: 30 } }),
    steps: [
      { type: 'set', notMerge: true, option: Object.assign(graphNone({ zoom: 0.5 }), { thumbnail: { left: 'center', bottom: 10, width: 200, height: 80 } }) },
      { type: 'set', notMerge: true, option: Object.assign(graphNone(), { thumbnail: { top: '10%', right: '5%', width: '40%', height: 120, itemStyle: { borderWidth: 0 } } }) },
      { type: 'set', notMerge: true, option: Object.assign(graphNone(), { thumbnail: { left: 10, top: 10, right: 300, bottom: 200 } }) },
      { type: 'set', notMerge: true, option: Object.assign(graphNone({ scaleLimit: { min: 0.5, max: 3 } }), { thumbnail: { width: 120, height: 160, itemStyle: { borderWidth: 10, borderRadius: [4, 8] }, windowStyle: { borderRadius: 3 } } }) },
      { type: 'mousewheel', x: 520, y: 300, delta: -480 },
      { type: 'mousewheel', x: 520, y: 300, delta: -480 },
      { type: 'mousewheel', x: 520, y: 300, delta: 480 },
    ],
  },
  {
    id: 'TH-FORCE', family: 'thumbnail',
    note: "a force layout (layoutAnimation false) with categories, roam 'move': a drag on the thumbnail pans, its wheel does not zoom; a zoom by the action",
    option: {
      animation: false,
      series: [{ type: 'graph', layout: 'force', roam: 'move', force: { repulsion: 120, edgeLength: 40, layoutAnimation: false },
        categories: [{ name: 'A' }, { name: 'B' }, { name: 'C' }],
        data: JSON.parse(JSON.stringify(FORCE_NODES)), links: JSON.parse(JSON.stringify(FORCE_LINKS)) }],
      thumbnail: { width: '30%', height: '30%', left: 10, top: 10 },
    },
    steps: [].concat(
      [{ type: 'mousewheel', x: 80, y: 60, delta: 120 }],
      drag(80, 60, [[90, 70], [100, 75]], 100, 75),
      [{ type: 'action', payload: { type: 'graphRoam', zoom: 0.6, originX: 300, originY: 200 } }],
      drag(60, 50, [[40, 40]], 40, 40)),
  },
  {
    id: 'TH-CIRC', family: 'thumbnail',
    note: "a circular layout, roam 'scale': the thumbnail zooms and does not pan; the graph's wheel; a merge that re-renders the copy",
    option: {
      animation: false,
      series: [{ type: 'graph', layout: 'circular', roam: 'scale', symbolSize: 18,
        data: JSON.parse(JSON.stringify(FORCE_NODES)).map(n => ({ name: n.name, value: n.value, symbolSize: n.symbolSize })),
        links: JSON.parse(JSON.stringify(FORCE_LINKS)), lineStyle: { curveness: 0.2 } }],
      thumbnail: { right: 20, bottom: 20 },
    },
    steps: [].concat(
      drag(500, 330, [[520, 340]], 520, 340),
      [{ type: 'mousewheel', x: 500, y: 330, delta: 240 }, { type: 'mousewheel', x: 300, y: 200, delta: -120 }],
      [{ type: 'set', option: { series: [{ symbolSize: 26 }] } }]),
  },
  {
    id: 'TH-TARGET', family: 'thumbnail',
    note: 'which graph: seriesIndex, seriesId, none (the first graph), no graph at all, a graph on cartesian2d (an empty box), a graph with no links (the empty line group puts (0, 0) in the copy), two thumbnails (the last one gets the copy), show false, roam false',
    option: {
      animation: false,
      series: [
        { type: 'graph', layout: 'none', id: 'g1', data: [{ name: 'p', x: 10, y: 10 }, { name: 'q', x: 50, y: 30 }], links: [{ source: 'p', target: 'q' }], left: 20, right: 320 },
        { type: 'graph', layout: 'none', id: 'g2', roam: true, data: [{ name: 'r', x: 200, y: 200 }, { name: 's', x: 260, y: 150 }, { name: 't', x: 230, y: 260 }],
          links: [{ source: 'r', target: 's' }, { source: 's', target: 't' }], left: 320, right: 20 },
      ],
      thumbnail: { seriesIndex: 1 },
    },
    steps: [
      { type: 'set', option: { thumbnail: { seriesIndex: null, seriesId: 'g1' } } },
      { type: 'set', option: { thumbnail: { seriesId: null } } },
      { type: 'set', notMerge: true, option: { animation: false, xAxis: {}, yAxis: {}, series: [{ type: 'scatter', data: [[1, 2], [3, 4]] }], thumbnail: {} } },
      { type: 'set', notMerge: true, option: { animation: false, xAxis: { type: 'value' }, yAxis: { type: 'value' },
        series: [{ type: 'graph', coordinateSystem: 'cartesian2d', data: [[1, 2], [3, 4]], links: [{ source: 0, target: 1 }] }], thumbnail: {} } },
      { type: 'set', notMerge: true, option: { animation: false, series: [{ type: 'graph', layout: 'none', roam: true, data: [{ name: 'u', x: 300, y: 260 }, { name: 'v', x: 340, y: 300 }] }], thumbnail: {} } },
      { type: 'set', notMerge: true, option: { animation: false, series: [{ type: 'graph', layout: 'none', roam: true, symbolSize: 4, data: [{ name: 'u', x: 30, y: 20 }, { name: 'v', x: 80, y: 60 }], links: [{ source: 'u', target: 'v' }] }],
        thumbnail: [{ left: 10, top: 10, width: 100, height: 80 }, { right: 10, bottom: 10, width: 140, height: 90 }] } },
      { type: 'set', option: { thumbnail: [{}, { show: false }] } },
      { type: 'set', notMerge: true, option: graphNone({ roam: false }) },
      { type: 'mousewheel', x: 520, y: 350, delta: 120 },
    ].concat(drag(520, 350, [[540, 360]], 540, 360)),
  },
  // ---------------- the axis expansion ----------------
  {
    id: 'AE-LAYOUT', family: 'expand',
    note: 'the static layouts a merge leaves: centres 0, 7 and 2.5, counts 2 and 7, widths 30 and 200 (the window restricted to the layout), an explicit window, a count of 0 (not expandable), three axes, the layout off',
    option: par8(),
    steps: [
      { type: 'set', option: { parallel: { axisExpandCenter: 0 } } },
      { type: 'set', option: { parallel: { axisExpandCenter: 7 } } },
      { type: 'set', option: { parallel: { axisExpandCenter: 2.5, axisExpandCount: 2 } } },
      { type: 'set', option: { parallel: { axisExpandCount: 7, axisExpandWidth: 30 } } },
      { type: 'set', option: { parallel: { axisExpandWidth: 200, axisExpandCount: 4 } } },
      { type: 'set', option: { parallel: { axisExpandWindow: [37.3, 160.9], axisExpandWidth: 55 } } },
      { type: 'set', option: { parallel: { axisExpandWindow: [-20, 900] } } },
      { type: 'set', notMerge: true, option: par8({ axisExpandCount: 0 }) },
      { type: 'set', notMerge: true, option: Object.assign(par8(), { parallelAxis: AXES8.slice(0, 3), series: [{ type: 'parallel', data: ROWS8.map(r => r.slice(0, 3)) }] }) },
      { type: 'set', notMerge: true, option: par8({ axisExpandable: false }) },
      { type: 'set', notMerge: true, option: par8({ layout: 'vertical', axisExpandCenter: 5, axisExpandCount: 3, axisExpandWidth: 45 }) },
    ],
  },
  {
    id: 'AE-CLICK', family: 'expand',
    note: "the click trigger, horizontal: a click in the window's middle (none), at its left and right edges (slide), far left and far right (jump), a press and a release 3 px apart (dist 9 > 5: nothing) and 2 / 1 px apart (5: a click), outside the parallel (none), repeated jumps to the ends of the extent; brushselected follows every event",
    option: par8(),
    steps: [].concat(click(267, 200), click(182, 200), click(354, 200), click(100, 200), click(500, 200),
      click(150, 200, 3, 0), click(150, 200, 2, 1), click(560, 200), click(300, 380),
      click(85, 200), click(85, 200), click(515, 200), click(515, 200), click(515, 200)),
  },
  {
    id: 'AE-VERT', family: 'expand',
    note: 'the click trigger, vertical, a custom slide trigger area [-0.3, 0.2, 0.5] and an axisExpandWindow in the option; and a trigger area with no jump ([null, 0.1, 0.5])',
    option: par8({ layout: 'vertical', axisExpandCount: 3, axisExpandWidth: 50, axisExpandSlideTriggerArea: [-0.3, 0.2, 0.5], axisExpandWindow: [100, 200] }),
    steps: [].concat(click(300, 150), click(300, 210), click(300, 70), click(300, 330), click(300, 330),
      [{ type: 'set', option: { parallel: { axisExpandSlideTriggerArea: [null, 0.1, 0.5] } } }],
      click(300, 70), click(300, 335)),
  },
  {
    id: 'AE-MOVE', family: 'expand',
    note: "the mousemove trigger: a slide every 5 ms through the throttle (17 ms: a timer, then the last call's window), a jump debounced 50 ms and cancelled by a move into the middle ('none' clears the timer), a jump that lands, a slide with animation duration 0, moves off the parallel; a merged axisExpandRate 40 and axisExpandDebounce 0",
    option: par8({ axisExpandTriggerOn: 'mousemove' }),
    steps: [].concat(
      moves([[300, 200], [354, 200], [355, 200], [356, 200], [357, 200]], 5),
      [{ type: 'idle', dt: 30 }],
      moves([[100, 200], [110, 200]], 20), moves([[300, 200]], 20), [{ type: 'idle', dt: 80 }],
      moves([[100, 200], [102, 200]], 20), [{ type: 'idle', dt: 60 }],
      moves([[560, 200], [300, 395]], 30),
      [{ type: 'set', option: { parallel: { axisExpandRate: 40, axisExpandDebounce: 0 } } }],
      moves([[505, 200], [506, 200], [507, 200]], 10), [{ type: 'idle', dt: 50 }],
      moves([[90, 200]], 10), [{ type: 'idle', dt: 10 }]),
  },
  {
    id: 'AE-NARROW', family: 'expand',
    note: 'a collapse width under 3 px (folded to 0): the narrow branch maps the pointer over the whole extent; click and move triggers',
    option: Object.assign(par8({ axisExpandCount: 7, axisExpandWidth: 70, axisExpandCenter: 1 }), { parallelAxis: AXES8.concat(AXES8.map((a, i) => Object.assign({}, a, { dim: 8 + i, id: 'y' + i }))),
      series: [{ type: 'parallel', data: ROWS8.map(r => r.concat(r)) }] }),
    steps: [].concat(click(300, 200), click(150, 200), click(510, 200),
      [{ type: 'set', option: { parallel: { axisExpandTriggerOn: 'mousemove' } } }],
      moves([[200, 200], [420, 200]], 30)),
  },
  {
    id: 'AE-ACTION', family: 'expand',
    note: "the action: a window with fractions (the option's array rewritten by every layout, the event's with it), a centre (the window from before still wins), a null window (back to the centre), a count, a width, expandable off and on, by parallelIndex / parallelId on two parallels and with no query (both); the event's keys",
    option: {
      animation: false,
      parallel: [
        { id: 'pa', axisExpandable: true, axisExpandCount: 3, axisExpandWidth: 40, bottom: 230 },
        { id: 'pb', axisExpandable: true, axisExpandCount: 4, axisExpandWidth: 50, top: 220, layout: 'horizontal' },
      ],
      parallelAxis: AXES8.slice(0, 6).map(a => Object.assign({}, a, { parallelIndex: 0 })).concat(AXES8.slice(0, 7).map((a, i) => Object.assign({}, a, { id: 'z' + i, parallelIndex: 1 }))),
      series: [{ type: 'parallel', parallelIndex: 0, data: ROWS8.map(r => r.slice(0, 6)) }, { type: 'parallel', parallelIndex: 1, data: ROWS8.map(r => r.slice(0, 7)) }],
    },
    steps: [
      { type: 'action', payload: { type: 'parallelAxisExpand', parallelIndex: 0, axisExpandWindow: [11.7, 63.9] } },
      { type: 'action', payload: { type: 'parallelAxisExpand', parallelIndex: 0, axisExpandCenter: 1 } },
      { type: 'action', payload: { type: 'parallelAxisExpand', parallelIndex: 0, axisExpandWindow: null } },
      { type: 'action', payload: { type: 'parallelAxisExpand', parallelId: 'pb', axisExpandCount: 2, axisExpandWidth: 70 } },
      { type: 'action', payload: { type: 'parallelAxisExpand', parallelIndex: 1, axisExpandable: false } },
      { type: 'action', payload: { type: 'parallelAxisExpand', parallelIndex: 1, axisExpandable: true, axisExpandCenter: 5.5 } },
      { type: 'action', payload: { type: 'parallelAxisExpand', axisExpandWindow: [10.1, 60.2], animation: { duration: 0 } } },
      { type: 'set', option: { parallel: [{ axisExpandWidth: 45 }] } },
      { type: 'set', option: { parallel: [{ axisExpandWindow: [0, 80] }] } },
    ],
  },
  {
    id: 'AE-BRUSH', family: 'expand',
    note: 'brushing with collapsed axes, click trigger: a cover on a window axis, a jump that folds it (the cover follows the axis), a cover on a folded axis, the action on a folded axis, a slide; the rows keep their opacities',
    option: par8({}, {}),
    steps: [].concat(
      [{ type: 'mousemove', x: 237, y: 300 }, { type: 'mousedown', x: 237, y: 300 }, { type: 'mousemove', x: 237, y: 250 },
        { type: 'mousemove', x: 237, y: 150 }, { type: 'mouseup', x: 237, y: 150 }, { type: 'click', x: 237, y: 150 }],
      click(500, 200),
      [{ type: 'mousemove', x: 80, y: 300 }, { type: 'mousedown', x: 80, y: 300 }, { type: 'mousemove', x: 80, y: 220 },
        { type: 'mousemove', x: 80, y: 120 }, { type: 'mouseup', x: 80, y: 120 }, { type: 'click', x: 80, y: 120 }],
      [{ type: 'action', payload: { type: 'axisAreaSelect', parallelAxisIndex: 7, intervals: [[10, 60]] } }],
      click(90, 200), click(340, 200)),
  },
  // [R2-I4]
  {
    id: 'TH-PEN', family: 'thumbnail', pen: true,
    note: "[R2-I4] the nodes' pens the copy clones from the Symbol paths: a node with only a borderColor (zrender's 1 px), one dashed at 2 with its own phase, one in a category by name (its border [3, 1] at 2 and its opacity), an emptyCircle (its colour at 2), a rect of no border; a dashed edge with its phase",
    option: {
      animation: false,
      series: [{ type: 'graph', layout: 'none', roam: true, symbolSize: 20,
        categories: [{ name: 'k', itemStyle: { borderColor: '#0000ff', borderType: [3, 1], borderDashOffset: 2, opacity: 0.6 } }],
        data: [{ name: 'a', x: 0, y: 0, itemStyle: { borderColor: '#ff0000' } },
          { name: 'b', x: 100, y: 0, itemStyle: { borderColor: '#00aa00', borderWidth: 2, borderType: 'dashed', borderDashOffset: 5 } },
          { name: 'c', x: 50, y: 80, category: 'k' },
          { name: 'd', x: 150, y: 80, symbol: 'emptyCircle' },
          { name: 'e', x: 200, y: 40, symbol: 'rect' }],
        links: [{ source: 'a', target: 'b', lineStyle: { type: 'dashed', dashOffset: 3 } }, { source: 'c', target: 'd' }] }],
      thumbnail: {},
    },
    steps: [{ type: 'action', payload: { type: 'graphRoam', dx: 10, dy: 5 } }],
  },
  // [R2-I5]
  {
    id: 'TH-GRAD', family: 'thumbnail', pen: true,
    note: "[R2-I5] nodes whose pens are gradients, cloned as they are: a linear borderColor at 2, a radial one at 3 dashed, a category's (by name) linear one; a solid pen beside them",
    option: {
      animation: false,
      series: [{ type: 'graph', layout: 'none', roam: true, symbolSize: 24,
        categories: [{ name: 'g', itemStyle: { borderWidth: 2, borderColor: { type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
          colorStops: [{ offset: 0, color: '#00ff00' }, { offset: 1, color: '#0000ff' }] } } }],
        data: [{ name: 'a', x: 0, y: 0, itemStyle: { borderWidth: 2, borderColor: { type: 'linear', x: 0, y: 0, x2: 1, y2: 0,
            colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 0.5, color: '#ffff00' }, { offset: 1, color: '#0000ff' }] } } },
          { name: 'b', x: 100, y: 0, itemStyle: { borderWidth: 3, borderType: 'dashed', borderColor: { type: 'radial', x: 0.5, y: 0.5,
            r: 0.5, colorStops: [{ offset: 0, color: '#000000' }, { offset: 1, color: '#ff00ff' }] } } },
          { name: 'c', x: 50, y: 80, category: 'g' },
          { name: 'd', x: 150, y: 80, itemStyle: { borderColor: '#333333', borderWidth: 2 } }],
        links: [{ source: 'a', target: 'b' }, { source: 'c', target: 'd' }] }],
      thumbnail: {},
    },
    steps: [{ type: 'action', payload: { type: 'graphRoam', dx: 10, dy: 5 } }],
  },
];

const NOTES = [
  'Every option has animation false; the force layouts layoutAnimation false; Math.random is the xorshift32 from SEED, reseeded per chart and before every set.',
  "A thumbnail's copy is taken at the graph's render: symbol shapes are the sub-path's scaleX / scaleY (half the symbol size) round the node, lines the line path's shape.",
  'pars[].window etc. are _makeLayoutInfo run on a copy of the option\'s window (recording must not rewrite it); optWindow is the option\'s own array.',
  'actions are what views dispatched through api.dispatchAction, tagged by the view; an action step\'s own dispatch is chart.dispatchAction and is not listed.',
];

// =====================================================================
// The transcription (mutations as switches in `mut`)
// =====================================================================
let mut = {};
const RECIPES = { T1: 0, T2: 0, T3: 0, E1: 0, E2: 0, E3: 0 };

function invert(a) {
  const aa = a[0]; const ac = a[2]; const atx = a[4]; const ab = a[1]; const ad = a[3]; const aty = a[5];
  let det = aa * ad - ab * ac;
  if (!det) return null;
  det = 1.0 / det;
  return [ad * det, -ab * det, -ac * det, aa * det, (ac * aty - ad * atx) * det, (ab * atx - aa * aty) * det];
}
function mul(m1, m2) {
  return [m1[0] * m2[0] + m1[2] * m2[1], m1[1] * m2[0] + m1[3] * m2[1], m1[0] * m2[2] + m1[2] * m2[3],
    m1[1] * m2[2] + m1[3] * m2[3], m1[0] * m2[4] + m1[2] * m2[5] + m1[4], m1[1] * m2[4] + m1[3] * m2[5] + m1[5]];
}
function applyT(m, x, y) { return [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]]; }
function rectApply(r, m) {
  if (m[1] < 1e-5 && m[1] > -1e-5 && m[2] < 1e-5 && m[2] > -1e-5) {
    const out = { x: r.x * m[0] + m[4], y: r.y * m[3] + m[5], width: r.width * m[0], height: r.height * m[3] };
    if (out.width < 0) { out.x += out.width; out.width = -out.width; }
    if (out.height < 0) { out.y += out.height; out.height = -out.height; }
    return out;
  }
  const pts = [[r.x, r.y], [r.x + r.width, r.y], [r.x + r.width, r.y + r.height], [r.x, r.y + r.height]].map(p => applyT(m, p[0], p[1]));
  const xs = pts.map(p => p[0]); const ys = pts.map(p => p[1]);
  const x0 = Math.min(...xs); const y0 = Math.min(...ys);
  return { x: x0, y: y0, width: Math.max(...xs) - x0, height: Math.max(...ys) - y0 };
}
// expandOrShrinkRect(rect, d, shrink, noNegative)
function shrink(r, d) {
  d = Math.max(0, d);
  const out = { x: r.x, y: r.y, width: r.width, height: r.height };
  const one = (xy, wh) => {
    const sum = -d + -d;
    const old = out[wh];
    out[wh] += sum;
    const minSize = Math.max(0, Math.min(0, old));
    if (out[wh] < minSize) {
      out[wh] = minSize;
      out[xy] += (-d >= 0 ? d : -d >= 0 ? old + -d : Math.abs(sum) > 1e-8 ? (old - minSize) * -d / sum : 0);
    } else out[xy] -= -d;
  };
  one('x', 'width');
  one('y', 'height');
  return out;
}
// getLayoutRect({left: 'center', top: 'center', aspect}, container)
function centredAspect(c, aspect) {
  const cw = c.width; const ch = c.height;
  let width = NaN; let height = NaN;
  const ratio = mut.ratio75 ? 0.75 : 0.8;
  if (aspect > cw / ch) width = cw * ratio; else height = ch * ratio;
  if (isNaN(width)) width = aspect * height;
  if (isNaN(height)) height = width / aspect;
  let left = cw / 2 - width / 2;
  let top = ch / 2 - height / 2;
  left = left || 0;
  top = top || 0;
  const out = { x: (c.x || 0) + left, y: (c.y || 0) + top, width, height };
  if (out.width < 0) { out.x += out.width; out.width = -out.width; }
  if (out.height < 0) { out.y += out.height; out.height = -out.height; }
  return out;
}
// BoundingRect.calculateTransform, then decomposeTransform of a pure scale + move
function rawTrans(d, v) {
  const sx = v.width / d.width;
  const sy = v.height / d.height;
  const m = [1, 0, 0, 1, 0, 0];
  m[4] = -d.x; m[5] = -d.y;
  // scale(m, m, [sx, sy]); translate(m, m, [v.x, v.y])
  const s = [m[0] * sx, m[1] * sy, m[2] * sx, m[3] * sy, m[4] * sx, m[5] * sy];
  s[4] += v.x; s[5] += v.y;
  return s;
}
// the copy's rect: circles, rects, lines and quadratics (T2)
function quadExtremum(p0, p1, p2) {
  const divider = p0 + p2 - 2 * p1;
  return divider === 0 ? 0.5 : (p0 - p1) / divider;
}
function quadAt(p0, p1, p2, t) { const ot = 1 - t; return ot * (ot * p0 + 2 * t * p1) + t * t * p2; }
function itemRect(it) {
  const s = it._shape;
  const st = it._style;
  let r;
  let hasFill = false;
  if (it.kind === 'symbol') {
    if (s.symbolType === 'rect') r = { x: s.x, y: s.y, width: s.width, height: s.height };
    else {
      const cx = s.x + s.width / 2; const cy = s.y + s.height / 2; const rr = Math.min(s.width, s.height) / 2;
      r = { x: cx - rr, y: cy - rr, width: cx + rr - (cx - rr), height: cy + rr - (cy - rr) };
    }
    hasFill = st.fill != null && st.fill !== 'none';
  } else {
    if (s.percent === 0) return null;
    let x0 = Math.min(s.x1, s.x2); let x1 = Math.max(s.x1, s.x2); let y0 = Math.min(s.y1, s.y2); let y1 = Math.max(s.y1, s.y2);
    // ECLinePath's isStraightLine: isNaN(+cpx1) || isNaN(+cpy1) -- a null is a 0
    if (!(isNaN(+s.cpx1) || isNaN(+s.cpy1))) {
      const cx = +s.cpx1; const cy = +s.cpy1;
      const tx = quadExtremum(s.x1, cx, s.x2); const ty = quadExtremum(s.y1, cy, s.y2);
      const ex = quadAt(s.x1, cx, s.x2, Math.max(Math.min(tx, 1), 0));
      const ey = quadAt(s.y1, cy, s.y2, Math.max(Math.min(ty, 1), 0));
      x0 = Math.min(x0, ex); x1 = Math.max(x1, ex); y0 = Math.min(y0, ey); y1 = Math.max(y1, ey);
    }
    r = { x: x0, y: y0, width: x1 - x0, height: y1 - y0 };
  }
  // [R2-I4] the copy's own style has no lineWidth where the visual wrote
  // none (zrender's clone takes own keys): the path's default, 1
  const lw = st.lineWidth == null ? 1 : st.lineWidth;
  const hasStroke = st.stroke != null && st.stroke !== 'none' && lw > 0;
  if (hasStroke) {
    let w = lw;
    if (!hasFill) w = Math.max(w, mut.threshold4 ? 4 : 5);
    r = { x: r.x - w / 2, y: r.y - w / 2, width: r.width + w, height: r.height + w };
  }
  return r;
}
function union(a, b) {
  const x = Math.min(b.x, a.x); const y = Math.min(b.y, a.y);
  const w = Math.max(b.x + b.width, a.x + a.width) - x;
  const h = Math.max(b.y + b.height, a.y + a.height) - y;
  return { x, y, width: w, height: h };
}
function groupRect(items) {
  let r = null;
  for (const it of items) {
    const ir = itemRect(it);
    if (!ir) return undefined;
    r = r ? union(r, ir) : union(ir, ir);
  }
  return r || { x: 0, y: 0, width: 0, height: 0 };
}

// _makeLayoutInfo
function restrict(v, e) { return Math.min(Math.max(v, e[0]), e[1]); }
function roundTo(x, p) { return +(+x).toFixed(p); }
function layoutInfoRecipe(rect, o, n) {
  const horizontal = o.layout === 'horizontal';
  const L = horizontal ? rect.width : rect.height;
  const ext = [0, L];
  const w = restrict(o.axisExpandWidth, ext);
  const count = restrict(o.axisExpandCount || 0, [0, n]);
  const expandable = o.axisExpandable && n > 3 && n > count && count > 1 && w > 0 && L > 0;
  let win = o.axisExpandWindow;
  let ws;
  if (!win) {
    ws = restrict(w * (count - 1), ext);
    const centre = o.axisExpandCenter || Math.floor(n / 2);
    win = [w * centre - ws / 2];
    win[1] = win[0] + ws;
  } else {
    win = win.slice();
    ws = restrict(win[1] - win[0], ext);
    if (!mut.noRewrite) win[1] = win[0] + ws;
  }
  let collapse = (L - ws) / (n - count);
  if (collapse < 3) collapse = 0;
  const inner = [Math.floor(roundTo(win[0] / w, 1)) + 1, Math.ceil(roundTo(win[1] / w, 1)) - 1];
  const pos0 = collapse / w * win[0];
  return { horizontal, layoutBase: horizontal ? rect.x : rect.y, layoutLength: L, axisBase: horizontal ? rect.y : rect.x,
    axisLength: horizontal ? rect.height : rect.width, expandable, w, collapse, win, inner, pos0, n };
}
function axisPosRecipe(li, i) {
  if (li.expandable) {
    if (i < li.inner[0]) return { position: i * li.collapse, avail: li.collapse, show: false, trunc: li.collapse };
    if (i <= li.inner[1]) return { position: li.pos0 + i * li.w - li.win[0], avail: li.w, show: true, trunc: undefined };
    return { position: li.layoutLength - (li.n - 1 - i) * li.collapse, avail: li.collapse, show: false, trunc: li.collapse };
  }
  const step = li.layoutLength / (li.n - 1);
  return { position: step * i, avail: step, show: true, trunc: undefined };
}
// addSafe and sliderMove(delta, ends, extent, 'all')
function getPrecision(val) {
  val = +val;
  if (isNaN(val)) return 0;
  if (val > 1e-14) {
    let e = 1;
    for (let i = 0; i < 15; i++, e *= 10) if (Math.round(val * e) / e === val) return i;
  }
  const str = val.toString().toLowerCase();
  const eIndex = str.indexOf('e');
  const exp = eIndex > 0 ? +str.slice(eIndex + 1) : 0;
  const significandPartLen = eIndex > 0 ? eIndex : str.length;
  const dotIndex = str.indexOf('.');
  const decimalPartLen = dotIndex < 0 ? 0 : significandPartLen - 1 - dotIndex;
  return Math.max(0, decimalPartLen - exp);
}
function addSafe(a, b) {
  const p = Math.max(getPrecision(a), getPrecision(b));
  const sum = a + b;
  return p > 20 ? sum : roundTo(sum, p);
}
function sliderMoveAll(delta, ends, extent) {
  delta = delta || 0;
  const extentSpan = addSafe(extent[1], -extent[0]);
  let span = Math.abs(addSafe(ends[1], -ends[0]));
  span = restrict(span, [0, extentSpan]);
  const minSpan = span; const maxSpan = span;
  ends[0] = restrict(ends[0], extent);
  ends[1] = restrict(ends[1], extent);
  const sign = e => { const d = e[0] - e[1]; return { span: Math.abs(d), sign: d > 0 ? -1 : d < 0 ? 1 : 1 }; };
  const o = sign(ends);
  ends[0] += delta;
  const real = extent.slice();
  o.sign < 0 ? (real[0] = addSafe(real[0], minSpan)) : (real[1] = addSafe(real[1], -minSpan));
  ends[0] = restrict(ends[0], real);
  let c = sign(ends);
  if (c.sign !== o.sign || c.span < minSpan) ends[1] = addSafe(ends[0], o.sign * minSpan);
  c = sign(ends);
  if (c.span > maxSpan) ends[1] = addSafe(ends[0], c.sign * maxSpan);
  return ends;
}
function slidRecipe(li, o, px, py, rect) {
  const win = li.win.slice();
  const ws = win[1] - win[0];
  const extent = [0, li.w * (li.n - 1)];
  const inside = (horizontal => {
    const pA = horizontal ? py : px; const pL = horizontal ? px : py;
    return pA >= li.axisBase && pA <= li.axisBase + li.axisLength && pL >= li.layoutBase && pL <= li.layoutBase + li.layoutLength;
  })(li.horizontal);
  if (!inside) return { behavior: 'none', win };
  const pc = (li.horizontal ? px : py) - li.layoutBase - li.pos0;
  const ta = o.axisExpandSlideTriggerArea;
  const inner = mut.innerTen ? 0.1 : ta[1];
  const useJump = ta[0] != null;
  let behavior = 'slide';
  let delta;
  if (li.collapse) {
    if (useJump && pc < ws * ta[0]) { behavior = 'jump'; delta = pc - ws * ta[2]; }
    else if (useJump && pc > ws * (1 - ta[0])) { behavior = 'jump'; delta = pc - ws * (1 - ta[2]); }
    else {
      (delta = pc - ws * inner) >= 0 && (delta = pc - ws * (1 - inner)) <= 0 && (delta = 0);
    }
    delta *= li.w / li.collapse;
    if (delta) sliderMoveAll(delta, win, extent); else behavior = 'none';
    return { behavior, win };
  }
  const ws2 = win[1] - win[0];
  const pos = extent[1] * pc / ws2;
  const out = [Math.max(0, pos - ws2 / 2)];
  out[1] = Math.min(extent[1], out[0] + ws2);
  out[0] = out[1] - ws2;
  return { behavior, win: out };
}

function checkScenario(sc) {
  const diffs = [];
  const all = [sc.initial].concat(sc.steps.map(s => s.record));
  if (sc.family === 'thumbnail') {
    all.forEach((rec, ri) => {
      rec.thumbs.forEach(th => {
        if (!th.drawn) return;
        const lw = th._bgLineWidth || 0;
        const content = shrink(th._box, mut.fullRim ? lw : lw / 2);
        if (!sameDeep([content.x, content.y, content.width, content.height], [th._content.x, th._content.y, th._content.width, th._content.height])) {
          diffs.push(sc.id + ' rec ' + ri + ' thumb ' + th.k + ' content');
        }
        RECIPES.T1++;
        const v = th.view;
        if (!v) return;
        const d = v._dataRect;
        const vr = centredAspect(th._content, d.width / d.height);
        if (!sameDeep([vr.x, vr.y, vr.width, vr.height], [v._viewRect.x, v._viewRect.y, v._viewRect.width, v._viewRect.height])) {
          diffs.push(sc.id + ' rec ' + ri + ' thumb ' + th.k + ' viewRect');
        }
        const raw = rawTrans(d, v._viewRect);
        if (!sameDeep([raw[4], raw[5], raw[0], raw[3]], v._trans.slice(0, 4))) diffs.push(sc.id + ' rec ' + ri + ' thumb ' + th.k + ' raw');
        // the window: the canvas through overall * inverse(target)
        const t2this = mul(v._overall, invert(v._target));
        const wr = rectApply({ x: 0, y: 0, width: rec.W, height: rec.H }, mut.noInverse ? v._overall : t2this);
        const got = th._window;
        if (!sameDeep([wr.x, wr.y, wr.width, wr.height], [got.x, got.y, got.width, got.height])) diffs.push(sc.id + ' rec ' + ri + ' thumb ' + th.k + ' window');
        if (!sameDeep(invert(t2this), v._toTarget)) diffs.push(sc.id + ' rec ' + ri + ' thumb ' + th.k + ' toTarget');
        RECIPES.T1++;
        // T2
        if (th.items.every(it => it.kind === 'line' || it.type === 'circle' || it.type === 'rect')) {
          const syms = th.items.filter(it => it.kind === 'symbol');
          const lines = th.items.filter(it => it.kind === 'line');
          const gs = groupRect(syms); const gl = groupRect(lines);
          if (gs !== undefined && gl !== undefined) {
            const r = union(union(gs, gs), gl);
            if (!sameDeep([r.x, r.y, r.width, r.height], [d.x, d.y, d.width, d.height])) diffs.push(sc.id + ' rec ' + ri + ' thumb ' + th.k + ' dataRect');
            RECIPES.T2++;
          }
        }
      });
    });
    // T3: the thumbnail's dispatches from the pointer
    sc.steps.forEach((s, si) => {
      const st = s.step;
      s.record.actions.filter(a => a.by === 'thumbnail').forEach(a => {
        const th = s._before.thumbs.find(t => t.view && t.view._toTarget);
        must(th, sc.id + ' step ' + si + ': a thumbnail dispatch with no view');
        const m = th.view._toTarget;
        if (st.type === 'mousemove') {
          const last = sc.steps.slice(0, si).reverse().find(q => q.step.type === 'mousemove' || q.step.type === 'mousedown');
          const ox = last.step.x; const oy = last.step.y;
          const o1 = applyT(m, ox, oy);
          const ddx = st.x - ox; const ddy = st.y - oy;
          const o2 = applyT(m, ox - (mut.panSign ? -ddx : ddx), oy - (mut.panSign ? -ddy : ddy));
          if (!sameDeep([o2[0] - o1[0], o2[1] - o1[1]], [a._p.dx, a._p.dy])) diffs.push(sc.id + ' step ' + si + ' pan');
        } else if (st.type === 'mousewheel') {
          const wd = Math.abs(st.delta / 120);
          const f = wd > 3 ? 1.4 : wd > 1 ? 1.2 : 1.1;
          const scale = st.delta > 0 ? f : 1 / f;
          const o = applyT(m, st.x, st.y);
          if (!sameDeep([1 / scale, o[0], o[1]], [a._p.zoom, a._p.originX, a._p.originY])) diffs.push(sc.id + ' step ' + si + ' zoom');
        } else diffs.push(sc.id + ' step ' + si + ' a thumbnail dispatch on ' + st.type);
        RECIPES.T3++;
      });
    });
    return diffs;
  }
  // ---- the expansion ----
  all.forEach((rec, ri) => {
    rec.pars.forEach(p => {
      const li = layoutInfoRecipe(p._rect, p._opt, p._n);
      const L = p._li;
      if (li.expandable !== !!L.axisExpandable || !sameDeep([li.w, li.collapse, li.win[0], li.win[1], li.inner[0], li.inner[1], li.pos0],
        [L.axisExpandWidth, L.axisCollapseWidth, L.axisExpandWindow[0], L.axisExpandWindow[1], L.winInnerIndices[0], L.winInnerIndices[1], L.axisExpandWindow0Pos])) {
        diffs.push(sc.id + ' rec ' + ri + ' par ' + p.k + ' layout info');
      }
      RECIPES.E1++;
    });
  });
  // E1 too: an action's window is the option's array, rewritten by the layout
  sc.steps.forEach((s, si) => {
    const st = s.step;
    if (st.type !== 'action' || !st.payload || !Array.isArray(st.payload.axisExpandWindow)) return;
    if (st.payload.parallelId != null) return;
    s.record.pars.forEach(p => {
      if (st.payload.parallelIndex != null && st.payload.parallelIndex !== p.k) return;
      const w = st.payload.axisExpandWindow;
      const L = p._opt.layout === 'vertical' ? p._rect.height : p._rect.width;
      const want = mut.noRewrite ? w.slice() : [w[0], w[0] + restrict(w[1] - w[0], [0, L])];
      if (!sameDeep(want, p._opt.axisExpandWindow)) diffs.push(sc.id + ' step ' + si + ' par ' + p.k + ' the rewritten window');
      RECIPES.E1++;
    });
  });
  // E2 / E3
  const moveCalls = [];
  sc.steps.forEach((s, si) => {
    const st = s.step;
    const pb = s._before.pars;
    if (st.type === 'mouseup') {
      const acts = s.record.actions.filter(a => a.type === 'parallelAxisExpand');
      const down = sc.steps.slice(0, si).reverse().find(q => q.step.type === 'mousedown');
      const views = pb.filter(p => p._opt.axisExpandable && p._opt.axisExpandTriggerOn === 'click');
      const want = [];
      if (down) {
        const dist = Math.pow(down.step.x - st.x, 2) + Math.pow(down.step.y - st.y, 2);
        if (dist <= (mut.threshold4click ? 4 : 5)) {
          views.forEach(p => {
            const li = layoutInfoRecipe(p._rect, p._opt, p._n);
            const r = slidRecipe(li, p._opt, st.x, st.y);
            if (r.behavior !== 'none') want.push(r.win);
          });
        }
      }
      if (!sameDeep(want, acts.map(a => a._p.axisExpandWindow))) diffs.push(sc.id + ' step ' + si + ' click expand');
      RECIPES.E2++;
    }
    if (st.type === 'mousemove') {
      pb.forEach(p => {
        if (!(p._opt.axisExpandable && p._opt.axisExpandTriggerOn === 'mousemove')) return;
        const li = layoutInfoRecipe(p._rect, p._opt, p._n);
        const r = slidRecipe(li, p._opt, st.x, st.y);
        moveCalls.push({ t: s.record.actions.length >= 0 ? stepTime(sc, si) : 0, k: p.k, r, rate: p._opt.axisExpandRate, debounce: p._opt.axisExpandDebounce });
      });
    }
  });
  // the throttle over the calls, per view (one view here: k)
  const byView = {};
  moveCalls.forEach(c => { (byView[c.k] = byView[c.k] || []).push(c); });
  const predicted = [];
  for (const k of Object.keys(byView)) {
    // the throttle's lastCall / lastExec start at the epoch: -CLOCK0 on this clock
    let lastCall = -CLOCK0; let lastExec = -CLOCK0; let timer = null; let debounceNext = null; let rate = null;
    const fire = (t, call) => { lastExec = t; if (call.r.behavior !== 'none') predicted.push({ t, win: call.r.win, anim: call.r.behavior === 'jump' ? 'null' : '{"duration":0}' }); };
    for (const c of byView[k]) {
      // timers due before this call
      if (timer && timer.due <= c.t) { fire(timer.due, timer.call); timer = null; }
      if (rate !== c.rate) { rate = c.rate; lastCall = -CLOCK0; lastExec = -CLOCK0; timer = null; debounceNext = null; }
      if (c.r.behavior === 'jump' && !mut.noDebounce) debounceNext = c.debounce;
      const thisDelay = debounceNext || rate;
      const thisDebounce = debounceNext || false;
      debounceNext = null;
      const diff = c.t - (thisDebounce ? lastCall : lastExec) - thisDelay;
      timer = null;
      if (thisDebounce) timer = { due: c.t + thisDelay, call: c };
      else if (diff >= 0) fire(c.t, c);
      else timer = { due: c.t - diff, call: c };
      lastCall = c.t;
    }
    if (timer) fire(timer.due, timer.call);
  }
  const gotMoves = [];
  sc.steps.forEach(s => s.record.actions.forEach(a => {
    if (a.type === 'parallelAxisExpand' && a.by === 'parallel' && !sc.steps.some(q => q === s && q.step.type === 'mouseup')) gotMoves.push({ t: a.t, win: a._p.axisExpandWindow, anim: a.animation });
  }));
  if (moveCalls.length) {
    if (!sameDeep(predicted.map(p => [p.t].concat(p.win)), gotMoves.map(p => [p.t].concat(p.win)))
      || predicted.some((p, i) => !gotMoves[i] || p.anim !== gotMoves[i].anim)) diffs.push(sc.id + ' the throttled dispatches' + (process.env.D7_DEBUG ? JSON.stringify([predicted, gotMoves]) : ''));
    RECIPES.E3++;
  }
  return diffs;
}
function stepTime(sc, si) {
  let t = 0;
  for (let i = 0; i <= si; i++) t += sc.steps[i].step.dt;
  return t;
}

const GUARDS = [
  { id: 'G1', mutation: 'the content rect shrunk by the whole rim', set: { fullRim: true }, named: ['TH-NONE', 'TH-STYLE', 'TH-BOX'] },
  { id: 'G2', mutation: "the view rect takes 0.75 of the content's side", set: { ratio75: true }, named: ['TH-NONE', 'TH-FORCE', 'TH-CIRC'] },
  { id: 'G3', mutation: 'the window ignores the graph transform', set: { noInverse: true }, named: ['TH-NONE', 'TH-BOX'] },
  { id: 'G4', mutation: "a line's stroke counted at 4", set: { threshold4: true }, named: ['TH-TARGET'] },
  { id: 'G5', mutation: "a thumbnail pan's sign flipped", set: { panSign: true }, named: ['TH-NONE', 'TH-FORCE'] },
  { id: 'G6', mutation: 'the layout does not rewrite the window', set: { noRewrite: true }, named: ['AE-ACTION'] },
  { id: 'G7', mutation: 'the slide zone at 10% instead of the trigger area', set: { innerTen: true }, named: ['AE-CLICK'] },
  { id: 'G8', mutation: 'a jump is not debounced', set: { noDebounce: true }, named: ['AE-MOVE'] },
  { id: 'G9', mutation: 'a click within 4 px squared', set: { threshold4click: true }, named: ['AE-CLICK'] },
];

function generate() {
  for (const k of Object.keys(RECIPES)) RECIPES[k] = 0;
  const scenarios = [];
  for (const def of SCENARIOS) scenarios.push(runScenario(def));
  mut = {};
  for (const sc of scenarios) {
    const d = checkScenario(sc);
    must(d.length === 0, 'the transcription disagrees: ' + d.slice(0, 8).join('; '));
  }
  const recipes = Object.assign({}, RECIPES);
  for (const k of Object.keys(recipes)) must(recipes[k] > 0, 'recipe ' + k + ' never ran');
  const guards = GUARDS.map(g => {
    mut = g.set;
    const changed = [];
    for (const sc of scenarios) if (checkScenario(sc).length) changed.push(sc.id);
    mut = {};
    return { id: g.id, mutation: g.mutation, named: g.named, changed, ok: g.named.every(n => changed.includes(n)) };
  });
  // the anchors
  const byId = id => scenarios.find(s => s.id === id);
  const tn = byId('TH-NONE');
  must(tn.steps.some(s => s.record.actions.some(a => a.by === 'thumbnail' && a.dx != null)), 'TH-NONE: the thumbnail never pans');
  must(tn.steps.some(s => s.record.actions.some(a => a.by === 'thumbnail' && a.zoom != null)), 'TH-NONE: the thumbnail never zooms');
  must(tn.steps.some(s => s.hover === 'thumbnail0'), 'TH-NONE: never over the thumbnail');
  must(tn.initial.thumbs[0].items.length === 11, 'TH-NONE: not six symbols and five lines');
  const tf = byId('TH-FORCE');
  must(!tf.steps.some(s => s.record.actions.some(a => a.by === 'thumbnail' && a.zoom != null)), "TH-FORCE: roam 'move' zoomed");
  must(tf.steps.some(s => s.record.actions.some(a => a.by === 'thumbnail' && a.dx != null)), 'TH-FORCE: never pans');
  const tc = byId('TH-CIRC');
  must(!tc.steps.some(s => s.record.actions.some(a => a.by === 'thumbnail' && a.dx != null)), "TH-CIRC: roam 'scale' panned");
  must(tc.steps.some(s => s.record.actions.some(a => a.by === 'thumbnail' && a.zoom != null)), 'TH-CIRC: never zooms');
  const tt = byId('TH-TARGET');
  must(tt.steps.some(s => s.record.thumbs.length && s.record.thumbs[0].enabled && s.record.thumbs[0].drawn && !s.record.thumbs[0].view), 'TH-TARGET: no empty box');
  must(tt.steps.some(s => s.record.thumbs.length && !s.record.thumbs[0].enabled), 'TH-TARGET: never disabled');
  must(tt.steps.some(s => s.record.thumbs.length === 2 && !s.record.thumbs[0].view && s.record.thumbs[1].view), 'TH-TARGET: two thumbnails, not the last one');
  const ac = byId('AE-CLICK');
  const beh = new Set();
  ac.steps.forEach(s => s.record.actions.forEach(a => beh.add(a.type)));
  must(beh.has('parallelAxisExpand'), 'AE-CLICK never expands');
  must(ac.steps.some(s => s.record.events.length >= 2 && s.record.events[0].type === 'parallelaxisexpand' && s.record.events[1].type === 'brushselected'), 'AE-CLICK: no brushselected after the event');
  const am = byId('AE-MOVE');
  must(am.steps.some(s => s.step.type === 'idle' && s.record.actions.some(a => a.type === 'parallelAxisExpand')), 'AE-MOVE: no timer dispatch');
  must(am.steps.some(s => s.record.actions.some(a => a.animation === 'null')) && am.steps.some(s => s.record.actions.some(a => a.animation === '{"duration":0}')), 'AE-MOVE: not both a jump and a slide');
  const aa = byId('AE-ACTION');
  must(aa.steps.some(s => s.record.pars.some(p => p.optWindow && s.step.payload && s.step.payload.axisExpandWindow
    && !sameDeep(p.optWindow, s.step.payload.axisExpandWindow.map(hex)))), 'AE-ACTION: the window was never rewritten');
  const an = byId('AE-NARROW');
  must(an.initial.pars[0].collapseWidth === hex(0), 'AE-NARROW: not narrow');
  // [R2-I4] every node of TH-PEN but the rect is stroked; a's at 1
  const tp = byId('TH-PEN').initial.thumbs[0].items;
  must(tp.filter(it => it.kind === 'symbol' && it.style.stroke != null && it.style.stroke !== 'none').length === 4
    && tp[0].style.lineWidth === hex(1) && tp[1].style.lineDashOffset === hex(5) && tp[2].style.lineDashOffset === hex(2),
    'TH-PEN: the pens are not as cloned: ' + JSON.stringify(tp.map(it => it.style)));
  // [R2-I5] three of TH-GRAD's pens are gradients
  const tg = byId('TH-GRAD').initial.thumbs[0].items;
  must(tg.filter(it => it.kind === 'symbol' && it.style.strokeGrad).length === 3
    && tg[0].style.strokeGrad.type === 'linear' && tg[1].style.strokeGrad.type === 'radial',
    'TH-GRAD: the gradient pens are not as cloned: ' + JSON.stringify(tg.map(it => it.style)));
  // strip the private fields
  for (const sc of scenarios) {
    for (const s of sc.steps) delete s._before;
    for (const rec of [sc.initial].concat(sc.steps.map(s => s.record))) {
      rec.thumbs.forEach(th => {
        delete th._box; delete th._bgLineWidth; delete th._content; delete th._window; delete th._groupCounts;
        if (th.view) for (const k of Object.keys(th.view)) if (k[0] === '_') delete th.view[k];
        (th.items || []).forEach(it => { delete it._shape; delete it._style; delete it._group; });
      });
      rec.pars.forEach(p => { delete p._li; delete p._rect; delete p._opt; delete p._lays; delete p._n; });
      rec.actions.forEach(a => { delete a._p; });
    }
    sc._chart.dispose();
    delete sc._chart;
  }
  return {
    out: {
      source: 'ECharts ' + echarts.version + ' dist (' + path.basename(DIST) + '), node SSR, SVG renderer',
      W: W0, H: H0, clock: { start: CLOCK0, pointerDt: 200, clickDt: 0, idleDt: 1000 }, seed: SEED,
      notes: NOTES, scenarios, guards, recipes,
    },
  };
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
  json1 = serialise(g1.out);
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(JSON.parse(JSON.stringify(g1.out))), 'the written JSON does not parse back to the record');
  const g2 = generate();
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
const nActions = out.scenarios.reduce((n, s) => n + s.steps.reduce((m, st) => m + st.record.actions.length, 0), 0);
const nEvents = out.scenarios.reduce((n, s) => n + s.steps.reduce((m, st) => m + st.record.events.length, 0), 0);
console.log(out.scenarios.length + ' scenarios, ' + nSteps + ' steps, ' + nActions + ' actions, ' + nEvents + ' events; recipes '
  + JSON.stringify(out.recipes) + '; ' + (out.guards.length - bad.length) + '/' + out.guards.length + ' guards; two generations '
  + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
