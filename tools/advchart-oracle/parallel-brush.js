// Upstream's own answers for BRUSHING ALONG A PARALLEL AXIS (C20, batch 130):
// every parallelAxis view keeps a BrushController of its own, mounted on the
// axis' place and turn (a horizontal layout's axes are turned a quarter), its
// one panel the band along the axis -- the axis extent widened by
// min(30, 10% of it) at both ends, areaSelectStyle.width across --, brushing
// lineX in that turned frame with the areaSelectStyle as the covers' style
// and removeOnClick. A drag along an axis draws a cover; its ends go through
// axis.coordToData (clamped) into the axisAreaSelect action
// (parallelAxisId, intervals): while the drag moves when the axis is
// `realtime` (the default), only when it ends when it is not, and always for
// the tiny drag that clears the covers. The covers move and resize as any
// brush cover; their cursors come through the frame's turn
// (transformDirection). The axis the action names is not rendered by the
// update it causes (fromAxisAreaSelect), every other axis lays its covers
// again from its active intervals (getCoverInfoList, dataToCoord clamped).
// The rows take their active / inactive opacities. The parallel axes'
// controllers never take globalPan (enableGlobalPan): an inside dataZoom
// still pans beside them, and a brush component holding globalPan does not
// stop them.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 600 x 400,
// TZ=UTC, and drives zrender's own Handler with synthetic mouse events
// (mousemove / mousedown / mouseup / click), as brush-cover.js does: the
// Handler finds the hovered element and sets its cursor, then zrender's
// Draggable (a cover's drift and dragend) and every controller's zr-level
// mousedown / mousemove / mouseup run as in a browser. Time is fake (Date
// and setTimeout replaced; 200 ms before every pointer event unless the step
// says otherwise, 0 before a click, 1000 for idle). Every option has
// `animation: false`.
//
//   node tools/advchart-oracle/parallel-brush.js
//
// writes tests/fixtures/advchart-parallel-brush.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex     a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//           lowercase (NaN 7ff8000000000000); a range keeps its nesting.
//   NUL     no string holds U+0000: a model id's NULs are written '<NUL>'.
//   js      a number as JavaScript prints it (String(v)).
//   piece   'axis<k>.cover<i>.<name>': cover i (its index in the controller's
//           _covers) of parallelAxis component k, its element main / w / e.
//
// Top level: source, W, H, clock, notes[], scenarios[], guards[], recipes{}
// A scenario: id, note, option, initial (a record), steps[] {i, step (x / y
//   resolved for a step naming a piece), hover (handler.findHover's target
//   before the step: a piece, 'axis<k>.other', 'series<k>', 'other' or
//   null), record}
// A record
//   axes[] per parallelAxis component (null when the same as the record
//     before's):
//     k, intervals [[a, b]] hex (the model's activeIntervals),
//     ctl null (no view controller) | {
//       enabled   the controller's _brushType (null when off)
//       option    {brushType, brushMode, transformable, removeOnClick, z,
//                 style {fill, stroke, lineWidth, opacity}} | null
//       transform the group's local transform (_transform) [6] hex
//       inv       the group's invTransform [6] hex | null
//       panel     {x0, y0, x1, y1} hex -- the panel's rect as clipPath reads
//                 it (x0, y0 and x0 + width, y0 + height) -- and other [2]
//                 hex (getLinearBrushOtherExtent(0)) | null
//       dragging, creating (the index of the cover being drawn, or null)
//       covers[] {brushType, panelId, range (hex), order (among the group's
//         children), main {rect [x, y, w, h] hex, silent, cursor,
//         draggable, style {fill, stroke, lineWidth, opacity}}, handles
//         {w, e: {rect, silent, invisible, cursor}} | null}}
//   rows[] per parallel series: {seriesIndex, items [{opacity hex, active}]}
//   cursor   the last proxy.setCursor of the step, or null
//   actions[] the axisAreaSelect a view dispatched: {parallelAxisId (NUL),
//            intervals hex, js [[js, js]]}
//   events[] {type: 'axisareaselected', parallelAxisId, intervals js} |
//            {type: 'brushselected', batch [{areas: n}]}
//   rendered[] the parallelAxis views whose render ran (not
//            fromAxisAreaSelect)
//   zoom     [start, end] of dataZoom 0 (hex), when the option has one
//   panTaken whether globalPan is held
//   error    null | an exception's message
//
// Self-checks (any failure: nothing is written, exit 1), transcriptions
// recomputed and compared with the records:
//   P1 every controller's transform from the axis layout (getLocalTransform:
//      rotate, then translate) and its inverse (matrix.invert); the panel
//      from the axis extent and areaSelectStyle.width (BoundingRect.create,
//      the extra);
//   P2 every cover's main shape and handles from its range, the line width
//      and the panel (updateBaseRect, clipPointsByRect, the other extent);
//   P3 every action a view dispatched: its intervals from its covers' ranges
//      (linearMap clamped, the scale's extent) on a value axis;
//   P4 the realtime rule: a move dispatches only for a realtime axis, a
//      release only for one that is not or for a clearing tiny drag, and a
//      move that drew or moved a cover on a realtime axis did dispatch;
//   P5 every row's opacity from the intervals (getActiveState,
//      parallelVisual);
//   P6 every rendered value axis' covers from its intervals (dataToCoord
//      clamped);
//   P7 the handles' cursors through the group's transform
//      (transformDirection).
// guards[] mutate the transcription one way each and name the scenarios
// that must notice; anchors (H-VALUE draws a cover and dispatches while
// moving; RT-OFF dispatches on release; M-MULTI shows two covers on one
// axis; G-PAN pans beside the parallel); no U+0000; the JSON parses back;
// two generations give the same bytes. process.exit() ends the run.
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

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-parallel-brush.json');
const W = 600;
const H = 400;

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
function hexDeep(v) {
  if (v == null) return null;
  if (typeof v === 'number') return hex(v);
  if (Array.isArray(v)) return Array.from(v, x => (x === undefined ? null : hexDeep(x)));
  must(false, 'not a range: ' + JSON.stringify(v));
  return null;
}
const nul = s => (s == null ? null : String(s).split('\u0000').join('<NUL>'));
const same = (a, b) => (Number.isNaN(a) && Number.isNaN(b)) || a === b;
function sameDeep(a, b) {
  if (typeof a === 'number' || typeof b === 'number') return typeof a === 'number' && typeof b === 'number' && same(a, b);
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => sameDeep(x, b[i]));
  return a == b; // eslint-disable-line eqeqeq
}
const rect4 = s => [hex(s.x), hex(s.y), hex(s.width), hex(s.height)];
const styleRec = st => ({
  fill: st.fill == null ? null : String(st.fill), stroke: st.stroke == null ? null : String(st.stroke),
  lineWidth: st.lineWidth == null ? null : hex(st.lineWidth), opacity: st.opacity == null ? null : hex(st.opacity),
});

// =====================================================================
// Recording
// =====================================================================
let RENDERED = [];
let hooked = false;
function hookRender(chart) {
  if (hooked) return;
  let view = null;
  chart.getModel().eachComponent('parallelAxis', m => { view = view || chart.getViewOfComponentModel(m); });
  if (!view) return;
  const proto = Object.getPrototypeOf(view);
  const orig = proto.render;
  proto.render = function (axisModel) {
    const before = this._axisGroup;
    const r = orig.apply(this, arguments);
    if (this._axisGroup !== before) RENDERED.push(axisModel.componentIndex);
    return r;
  };
  hooked = true;
}

function axisViews(chart) {
  const out = [];
  chart.getModel().eachComponent('parallelAxis', m => {
    const v = chart.getViewOfComponentModel(m);
    out.push({ model: m, view: v, bc: v && v._brushController });
  });
  return out;
}
const PIECES = ['main', 'w', 'e'];
function coverRec(bc, cover) {
  const opt = cover.__brushOption;
  const rec = {
    brushType: opt.brushType, panelId: nul(opt.panelId), range: hexDeep(opt.range),
    order: bc.group.children().indexOf(cover),
  };
  const main = cover.childOfName('main');
  rec.main = { rect: rect4(main.shape), silent: !!main.silent, cursor: main.cursor == null ? null : main.cursor,
    draggable: !!main.draggable, style: styleRec(main.style) };
  let handles = null;
  for (const n of PIECES.slice(1)) {
    const el = cover.childOfName(n);
    if (!el) continue;
    handles = handles || {};
    handles[n] = { rect: rect4(el.shape), silent: !!el.silent, invisible: !!el.invisible, cursor: el.cursor == null ? null : el.cursor };
  }
  rec.handles = handles;
  // what the transcription reads
  rec._range = opt.range.slice();
  rec._lineWidth = opt.brushStyle ? opt.brushStyle.lineWidth : undefined;
  rec._shapes = {};
  for (const n of PIECES) {
    const el = cover.childOfName(n);
    if (el) rec._shapes[n] = Object.assign({}, el.shape);
  }
  rec._cursors = {};
  for (const n of PIECES.slice(1)) {
    const el = cover.childOfName(n);
    if (el) rec._cursors[n] = el.cursor;
  }
  return rec;
}
// the panel's rect as its clipPath reads it: far points clipped to its corners
function panelRec(bc) {
  const pl = bc._panels && bc._panels.pl;
  if (!pl) return null;
  const c = pl.clipPath([[-1e300, -1e300], [1e300, 1e300]], bc._transform);
  const other = pl.getLinearBrushOtherExtent(0);
  return { x0: hex(c[0][0]), y0: hex(c[0][1]), x1: hex(c[1][0]), y1: hex(c[1][1]), other: other.map(hex),
    _r: [c[0][0], c[0][1], c[1][0], c[1][1]] };
}
function ctlRec(av) {
  const bc = av.bc;
  if (!bc) return null;
  const rec = {
    enabled: bc._brushType ? bc._brushType : null,
    option: null,
    transform: bc._transform ? Array.from(bc._transform).map(hex) : null,
    inv: bc.group.invTransform ? Array.from(bc.group.invTransform).map(hex) : null,
    panel: panelRec(bc),
    dragging: !!bc._dragging,
    creating: bc._creatingCover ? bc._covers.indexOf(bc._creatingCover) : null,
    covers: bc._covers.map(c => coverRec(bc, c)),
  };
  const o = bc._brushOption;
  if (o) {
    rec.option = { brushType: o.brushType, brushMode: o.brushMode, transformable: !!o.transformable,
      removeOnClick: !!o.removeOnClick, z: o.z == null ? null : o.z, style: styleRec(o.brushStyle || {}) };
  }
  rec._transform = bc._transform ? Array.from(bc._transform) : null;
  rec._inv = bc.group.invTransform ? Array.from(bc.group.invTransform) : null;
  return rec;
}
function axisRec(av) {
  return {
    k: av.model.componentIndex,
    intervals: (av.model.activeIntervals || []).map(iv => iv.map(hex)),
    ctl: ctlRec(av),
    _intervals: (av.model.activeIntervals || []).map(iv => iv.slice()),
  };
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
function panTaken(zr) {
  for (const k of Object.keys(zr)) {
    const v = zr[k];
    if (k.indexOf('__ec_inner_') === 0 && v && typeof v === 'object' && 'globalPan' in v) return !!v.globalPan;
  }
  return false;
}
function zoomRec(chart) {
  const o = chart.getOption();
  if (!o.dataZoom || !o.dataZoom.length) return null;
  return [hex(o.dataZoom[0].start), hex(o.dataZoom[0].end)];
}

function makeCtx(chart) {
  const ctx = { chart, zr: chart.getZr(), h: chart.getZr().handler, cursor: null, actions: [], events: [] };
  ctx.role = el => {
    if (!el) return null;
    const avs = axisViews(chart);
    for (const av of avs) {
      const bc = av.bc;
      if (!bc) continue;
      for (let i = 0; i < bc._covers.length; i++) if (el.parent === bc._covers[i]) return 'axis' + av.model.componentIndex + '.cover' + i + '.' + el.name;
      let p = el;
      while (p) { if (p === bc.group) return 'axis' + av.model.componentIndex + '.other'; p = p.parent; }
    }
    let p = el;
    while (p) {
      if (p.__ecComponentInfo) return p.__ecComponentInfo.mainType + p.__ecComponentInfo.index;
      p = p.parent;
    }
    return 'other';
  };
  // a piece's centre through the group's transform, rounded
  ctx.pieceAt = (key, dx, dy) => {
    const mm = /^axis(\d+)\.cover(\d+)\.(\w+)$/.exec(key);
    must(mm, 'bad piece ' + key);
    const av = axisViews(chart).find(a => a.model.componentIndex === +mm[1]);
    must(av && av.bc, 'no controller ' + key);
    const cv = av.bc._covers[+mm[2]];
    must(cv, 'no cover ' + key);
    const el = cv.childOfName(mm[3]);
    must(el, 'no piece ' + key);
    const lx = el.shape.x + el.shape.width / 2;
    const ly = el.shape.y + el.shape.height / 2;
    const g = av.bc.group.transformCoordToGlobal(lx, ly);
    return [Math.round(g[0] + (dx || 0)), Math.round(g[1] + (dy || 0))];
  };
  return ctx;
}
function eventRaw(type, x, y) {
  return { type, zrX: x, zrY: y, which: 1, shiftKey: false, ctrlKey: false, altKey: false, cancelBubble: false, preventDefault() {}, stopPropagation() {} };
}
const jsOf = v => String(v);

function snapshot(ctx, error) {
  ctx.zr.storage.getDisplayList(true);
  return {
    axes: axisViews(ctx.chart).map(axisRec),
    rows: rowsRec(ctx.chart),
    cursor: ctx.cursor,
    actions: ctx.actions,
    events: ctx.events,
    rendered: RENDERED.slice(),
    zoom: zoomRec(ctx.chart),
    panTaken: panTaken(ctx.zr),
    error,
  };
}

function runScenario(def) {
  NOW = CLOCK0;
  TIMERS = [];
  RENDERED = [];
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    const ctx = makeCtx(chart);
    ctx.h.proxy.setCursor = c => { ctx.cursor = c; };
    const api = chart._api;
    const origDispatch = api.dispatchAction;
    api.dispatchAction = function (payload) {
      if (payload.type === 'axisAreaSelect') {
        ctx.actions.push({ parallelAxisId: nul(payload.parallelAxisId), intervals: hexDeep(payload.intervals),
          js: payload.intervals.map(iv => iv.map(jsOf)), _intervals: payload.intervals.map(iv => iv.slice()),
          _axis: (axisViews(chart).find(a => a.model.id === payload.parallelAxisId) || {}).model });
      }
      return origDispatch.apply(this, arguments);
    };
    chart.on('axisareaselected', p => ctx.events.push({ type: 'axisareaselected', parallelAxisId: nul(p.parallelAxisId),
      intervals: (p.intervals || []).map(iv => iv.map(jsOf)) }));
    chart.on('brushselected', p => ctx.events.push({ type: 'brushselected', batch: (p.batch || []).map(b => ({ areas: (b.areas || []).length })) }));
    chart.setOption(JSON.parse(JSON.stringify(def.option)));
    hookRender(chart);
    // the first render is not a step's
    RENDERED = [];
    ctx.zr.storage.getDisplayList(true);
    const initial = snapshot(ctx, null);
    const recs = [];
    const steps = def.steps.concat([{ type: 'idle' }]);
    steps.forEach((st, i) => {
      ctx.cursor = null;
      ctx.actions = [];
      ctx.events = [];
      RENDERED = [];
      let error = null;
      const dt = st.dt != null ? st.dt : st.type === 'click' ? 0 : st.type === 'idle' ? 1000 : 200;
      advanceClock(NOW + dt);
      ctx.zr.storage.getDisplayList(true);
      let hover = null;
      const out = { i, step: Object.assign({}, st, { dt }) };
      const before = axisViews(chart).map(av => (av.bc ? av.bc._covers.map(c => JSON.stringify(c.__brushOption.range)) : []));
      try {
        if (['mousemove', 'mousedown', 'mouseup', 'click'].includes(st.type)) {
          let p;
          if (st.piece && st.relative) p = [ctx.anchor[0] + st.dx, ctx.anchor[1] + st.dy];
          else if (st.piece) {
            p = ctx.pieceAt(st.piece, st.dx, st.dy);
            ctx.anchor = p;
          } else p = [st.x, st.y];
          out.step.x = p[0];
          out.step.y = p[1];
          delete out.step.piece;
          delete out.step.dx;
          delete out.step.dy;
          delete out.step.relative;
          hover = (p[0] < 0 || p[1] < 0 || p[0] > W || p[1] > H) ? null : ctx.role(ctx.h.findHover(p[0], p[1]).target);
          ctx.h[st.type](eventRaw(st.type, p[0], p[1]));
        } else if (st.type === 'action') {
          chart.dispatchAction(JSON.parse(JSON.stringify(st.payload)));
        } else if (st.type === 'set') {
          chart.setOption(JSON.parse(JSON.stringify(st.option)), !!st.notMerge);
        }
      } catch (e) {
        if (e instanceof OracleError) throw e;
        error = String(e.message);
      }
      ctx.zr.storage.getDisplayList(true);
      out.hover = hover;
      out.record = snapshot(ctx, error);
      out.record._before = before;
      recs.push(out);
    });
    return { id: def.id, note: def.note, option: def.option, initial, steps: recs, _chart: chart };
  } catch (e) {
    chart.dispose();
    throw e;
  }
}

// ---------- the scenarios ----------
// eight rows over five value dimensions (0..100)
const ROWS = [
  [12, 85, 40, 66, 5], [30, 22, 95, 14, 52], [47, 61, 8, 90, 33], [55, 38, 72, 47, 81],
  [68, 9, 26, 58, 17], [79, 74, 53, 3, 69], [91, 47, 64, 29, 96], [20, 96, 15, 77, 44],
];
const AXES5 = [0, 1, 2, 3, 4].map(d => ({ dim: d, id: 'a' + d, name: 'D' + d, min: 0, max: 100 }));
const base = extra => Object.assign({
  animation: false,
  parallelAxis: JSON.parse(JSON.stringify(AXES5)),
  series: [{ type: 'parallel', data: ROWS }],
}, extra || {});
// horizontal: the axes stand at x 80, 190, 300, 410, 520 from y 340 up to 60
const AX = [80, 190, 300, 410, 520];
// vertical: the axes lie at y 60, 130, 200, 270, 340 from x 80 to 520
const AY = [60, 130, 200, 270, 340];
// a press, two moves, the release and the click a browser sends
const drag = (x0, y0, x1, y1, ux, uy) => [
  { type: 'mousemove', x: x0, y: y0 }, { type: 'mousedown', x: x0, y: y0 },
  { type: 'mousemove', x: Math.round((x0 + x1) / 2), y: Math.round((y0 + y1) / 2) },
  { type: 'mousemove', x: x1, y: y1 }, { type: 'mouseup', x: ux == null ? x1 : ux, y: uy == null ? y1 : uy },
  { type: 'click', x: ux == null ? x1 : ux, y: uy == null ? y1 : uy },
];
const dragPiece = (piece, dx, dy) => [
  { type: 'mousemove', piece }, { type: 'mousedown', piece },
  { type: 'mousemove', piece, dx: Math.round(dx / 2), dy: Math.round(dy / 2), relative: true },
  { type: 'mousemove', piece, dx, dy, relative: true }, { type: 'mouseup', piece, dx, dy, relative: true },
  { type: 'click', piece, dx, dy, relative: true },
];
const hoverPiece = piece => ({ type: 'mousemove', piece });
const clickAt = (x, y) => [{ type: 'mousemove', x, y }, { type: 'mousedown', x, y }, { type: 'mouseup', x, y }, { type: 'click', x, y }];
const clickPiece = piece => [{ type: 'mousemove', piece }, { type: 'mousedown', piece }, { type: 'mouseup', piece }, { type: 'click', piece }];

const SCENARIOS = [
  {
    id: 'H-VALUE', note: 'horizontal layout, value axes: the crosshair, a cover drawn up axis 1 (realtime: an action every move), its cursors, a second axis, a release away from the last move and the update that lays it back',
    option: base(),
    steps: [].concat([{ type: 'mousemove', x: 300, y: 380 }, { type: 'mousemove', x: 190, y: 250 }, { type: 'mousemove', x: 205, y: 250 }],
      drag(190, 300, 192, 150), [hoverPiece('axis1.cover0.main'), hoverPiece('axis1.cover0.w'), hoverPiece('axis1.cover0.e'), { type: 'mousemove', x: 140, y: 200 }],
      drag(410, 120, 408, 260), drag(300, 310, 300, 200, 301, 170), [{ type: 'set', option: {} }]),
  },
  {
    id: 'V-VALUE', note: 'vertical layout: the axes lie flat; a cover across axis 2, its cursors, its east handle dragged, a tiny drag that clears it',
    option: base({ parallel: { layout: 'vertical' } }),
    steps: [].concat([{ type: 'mousemove', x: 300, y: 200 }], drag(150, 200, 330, 198), [hoverPiece('axis2.cover0.w'), hoverPiece('axis2.cover0.e'), hoverPiece('axis2.cover0.main')],
      dragPiece('axis2.cover0.e', 40, 2), drag(420, 270, 470, 275), drag(100, 201, 102, 202)),
  },
  {
    id: 'T-TYPES', note: 'a category axis, a time axis and an inverse value axis: covers on each, the intervals coordToData gives, the rows they leave active',
    option: {
      animation: false,
      parallelAxis: [
        { dim: 0, type: 'category', data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'] },
        { dim: 1, type: 'time' },
        { dim: 2, type: 'value', inverse: true },
        { dim: 3, type: 'value', min: 0, max: 50 },
      ],
      series: [{ type: 'parallel', data: [
        ['Mon', 1704067200000, 12, 5], ['Tue', 1704326400000, 48, 22], ['Wed', 1704585600000, 30, 41],
        ['Thu', 1704844800000, 66, 18], ['Fri', 1705104000000, 85, 33], ['Tue', 1705363200000, 7, 47],
      ] }],
    },
    steps: [].concat(drag(80, 290, 80, 180), drag(227, 300, 226, 120), drag(373, 100, 373, 250), [{ type: 'set', option: {} }],
      dragPiece('axis2.cover0.main', 0, 40), drag(520, 330, 519, 90)),
  },
  {
    id: 'M-MULTI', note: 'two intervals on one axis by the action (its own view is not rendered: no covers until the next update), the action without a query (the first axis is not rendered), by id, by an index list; a new cover replaces both',
    option: base(),
    steps: [].concat([
      { type: 'action', payload: { type: 'axisAreaSelect', parallelAxisIndex: 1, intervals: [[60, 80], [10, 30]] } },
      { type: 'set', option: {} },
      hoverPiece('axis1.cover1.main'),
      { type: 'action', payload: { type: 'axisAreaSelect', intervals: [[20, 50]] } },
      { type: 'action', payload: { type: 'axisAreaSelect', parallelAxisId: 'a3', intervals: [] } },
      { type: 'action', payload: { type: 'axisAreaSelect', parallelAxisIndex: [2, 0], intervals: [[0, 100], [40, 45]] } },
    ], drag(190, 330, 190, 250), [{ type: 'set', option: {} }]),
  },
  {
    id: 'D-DRAG', note: 'a cover moved along its axis, its handles dragged (the west past the east), moved past the axis end: the range leaves the panel, the shape is clipped, the interval clamped',
    option: base(),
    steps: [].concat(drag(300, 300, 300, 200), dragPiece('axis2.cover0.main', 0, -30), dragPiece('axis2.cover0.e', 1, -20),
      dragPiece('axis2.cover0.w', 0, -150), dragPiece('axis2.cover0.main', 0, -200), [hoverPiece('axis2.cover0.main')], [{ type: 'set', option: {} }]),
  },
  {
    id: 'RT-OFF', note: 'realtime false (parallelAxisDefault): one action at the release, at a dragend, for a click on a cover, for the tiny drag that clears; a realtime axis beside it: a click on its cover dispatches nothing',
    option: base({ parallel: { parallelAxisDefault: { realtime: false } }, parallelAxis: AXES5.map((a, k) => (k === 3 ? Object.assign({}, a, { realtime: true }) : a)) }),
    steps: [].concat(drag(190, 300, 190, 180), dragPiece('axis1.cover0.main', 0, 25), clickPiece('axis1.cover0.main'), drag(190, 100, 191, 101),
      clickAt(250, 380), drag(410, 280, 410, 160), clickPiece('axis3.cover0.main'), drag(410, 90, 409, 92)),
  },
  {
    id: 'S-STYLE', note: "areaSelectStyle: a 40 px band, an 8 px border, the author's colours and opacity on axis 1; the default on axis 3; handles 8 px wide",
    option: base({ parallelAxis: AXES5.map((a, k) => (k === 1 ? Object.assign({}, a, { areaSelectStyle: { width: 40, borderWidth: 8, borderColor: '#ff0000', color: 'rgba(0,0,255,0.5)', opacity: 0.6 } }) : a)) }),
    steps: [].concat(drag(205, 310, 175, 140), [hoverPiece('axis1.cover0.w'), hoverPiece('axis1.cover0.e')], drag(410, 200, 410, 120), [{ type: 'mousemove', x: 172, y: 250 }]),
  },
  {
    id: 'G-PAN', note: "globalPan: the parallel's controllers never take it -- an inside dataZoom pans beside them; a brush component taking it stops the pan, not the parallel's brushing",
    option: {
      animation: false,
      grid: { left: 40, right: 340, top: 60, bottom: 60 },
      xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
      dataZoom: [{ type: 'inside', xAxisIndex: 0, start: 20, end: 60 }],
      parallel: { left: 330, right: 40 },
      parallelAxis: [{ dim: 0, min: 0, max: 100 }, { dim: 1, min: 0, max: 100 }, { dim: 2, min: 0, max: 100 }],
      series: [{ type: 'scatter', data: [[1, 2], [5, 9], [8, 4], [3, 6]] }, { type: 'parallel', data: ROWS.map(r => r.slice(0, 3)) }],
    },
    steps: [].concat(drag(100, 200, 160, 200), drag(445, 300, 445, 200),
      [{ type: 'set', option: { brush: { xAxisIndex: 0 } } },
        { type: 'action', payload: { type: 'takeGlobalCursor', key: 'brush', brushOption: { brushType: 'rect', brushMode: 'single' } } }],
      drag(90, 120, 200, 260), drag(560, 320, 559, 150),
      [{ type: 'action', payload: { type: 'takeGlobalCursor', key: 'brush', brushOption: { brushType: false } } }],
      drag(250, 300, 290, 300)),
  },
];

const NOTES = [
  'Every option has animation false; the clock is fake; TZ=UTC.',
  'A step naming a piece points at its shape centre (local) through the group transform, rounded, plus dx / dy.',
  "actions are the axisAreaSelect a parallelAxis view dispatched (api.dispatchAction); an 'action' step's own dispatch is chart.dispatchAction.",
  'The brush component of G-PAN has the toolbox its preprocessor adds on a merge (no buttons).',
];

// =====================================================================
// The transcription (mutations as switches in `mut`)
// =====================================================================
let mut = {};
const RECIPES = { P1: 0, P2: 0, P3: 0, P4: 0, P5: 0, P6: 0, P7: 0 };
const MIN_RESIZE = 6;

// getLocalTransform of {x, y, rotation} (no scale, origin, skew)
function localTransform(x, y, rotation) {
  const m = [1, 0, 0, 1, 0, 0];
  if (rotation) {
    const st = Math.sin(rotation);
    const ct = Math.cos(rotation);
    const aa = m[0]; const ac = m[2]; const atx = m[4]; const ab = m[1]; const ad = m[3]; const aty = m[5];
    m[0] = aa * ct + ab * st;
    m[1] = -aa * st + ab * ct;
    m[2] = ac * ct + ad * st;
    m[3] = -ac * st + ct * ad;
    m[4] = ct * (atx - 0) + st * (aty - 0) + 0;
    m[5] = ct * (aty - 0) - st * (atx - 0) + 0;
  }
  m[4] += 0 + x;
  m[5] += 0 + y;
  return m;
}
function invert(a) {
  const aa = a[0]; const ac = a[2]; const atx = a[4]; const ab = a[1]; const ad = a[3]; const aty = a[5];
  let det = aa * ad - ab * ac;
  if (!det) return null;
  det = 1.0 / det;
  return [ad * det, -ab * det, -ac * det, aa * det, (ac * aty - ad * atx) * det, (ab * atx - aa * aty) * det];
}
// the panel ParallelAxisView._refreshBrushController builds
function panelRecipe(extent, areaWidth) {
  const len = extent[1] - extent[0];
  const extra = mut.noExtra ? 0 : Math.min(30, Math.abs(len) * 0.1);
  const norm = (x, y, w, h) => {
    if (w < 0) { x = x + w; w = -w; }
    if (h < 0) { y = y + h; h = -h; }
    return { x, y, width: w, height: h };
  };
  const r = norm(extent[0], -areaWidth / 2, len, areaWidth);
  r.x -= extra;
  r.width += 2 * extra;
  return norm(r.x, r.y, r.width, r.height);
}
function clipPts(points, panel) {
  return points.map(p => {
    let x = Math.max(p[0], panel.x);
    x = Math.min(x, panel.x + panel.width);
    let y = Math.max(p[1], panel.y);
    y = Math.min(y, panel.y + panel.height);
    return [x, y];
  });
}
function ptsToRect(pts) {
  const xmin = Math.min(pts[0][0], pts[1][0]);
  const ymin = Math.min(pts[0][1], pts[1][1]);
  const xmax = Math.max(pts[0][0], pts[1][0]);
  const ymax = Math.max(pts[0][1], pts[1][1]);
  return { x: xmin, y: ymin, width: xmax - xmin, height: ymax - ymin };
}
// P2: updateBaseRect of a lineX cover in its panel
function lineShapes(range, lw, panel) {
  const out = {};
  const rr = [range, [panel.y, panel.y + (panel.height || 0)]];
  lw = lw || 0;
  const hs = Math.max(lw, MIN_RESIZE);
  const x = rr[0][0]; const y = rr[1][0];
  const xa = x - lw / 2; const ya = y - lw / 2;
  const x2 = rr[0][1]; const y2 = rr[1][1];
  const x2a = x2 - hs + lw / 2;
  const w = x2 - x; const h = y2 - y;
  const ha = h + lw;
  const sh = (a, b, c, d) => ptsToRect(clipPts([[a, b], [a + c, b + d]], panel));
  out.main = sh(x, y, w, h);
  out.w = sh(xa, ya, hs, ha);
  out.e = sh(x2a, ya, hs, ha);
  return out;
}
// linearMap
function linearMap(val, domain, range, clamp) {
  const d0 = domain[0]; const d1 = domain[1]; const r0 = range[0]; const r1 = range[1];
  const subDomain = d1 - d0; const subRange = r1 - r0;
  if (subDomain === 0) return subRange === 0 ? r0 : (r0 + r1) / 2;
  if (clamp) {
    if (subDomain > 0) {
      if (val <= d0) return r0;
      else if (val >= d1) return r1;
    } else if (val >= d0) return r0;
    else if (val <= d1) return r1;
  } else {
    if (val === d0) return r0;
    if (val === d1) return r1;
  }
  return (val - d0) / subDomain * subRange + r0;
}
// a value axis: coordToData clamped through the scale's extent
function coordToValue(axis, c) {
  const t = linearMap(c, axis.getExtent(), [0, 1], !mut.noClamp);
  const se = axis.scale.getExtent();
  return t * (se[1] - se[0]) + se[0];
}
function valueToCoord(axis, v) {
  const se = axis.scale.getExtent();
  const t = (v - se[0]) / (se[1] - se[0]);
  return linearMap(t, [0, 1], axis.getExtent(), true);
}
// P7: transformDirection
function transformDirection(direction, t) {
  const hBase = (t[4] === 0 || t[5] === 0 || t[0] === 0) ? 1 : Math.abs(2 * t[4] / t[0]);
  const vBase = (t[4] === 0 || t[5] === 0 || t[2] === 0) ? 1 : Math.abs(2 * t[4] / t[2]);
  const v = [direction === 'left' ? -hBase : direction === 'right' ? hBase : 0, direction === 'top' ? -vBase : direction === 'bottom' ? vBase : 0];
  const g = [t[0] * v[0] + t[2] * v[1] + t[4], t[1] * v[0] + t[3] * v[1] + t[5]];
  return Math.abs(g[0]) > Math.abs(g[1]) ? (g[0] > 0 ? 'right' : 'left') : (g[1] > 0 ? 'bottom' : 'top');
}
function handleCursor(name, t) {
  if (mut.identityCursor) t = [1, 0, 0, 1, 0, 0];
  const map = { w: 'left', e: 'right' };
  const inv = { left: 'w', right: 'e', top: 'n', bottom: 's' };
  const d = inv[transformDirection(map[name], t)];
  return { w: 'ew', e: 'ew', n: 'ns', s: 'ns' }[d] + '-resize';
}
function activeRecipe(intervals, value) {
  if (!intervals.length) return 'normal';
  if (value == null || isNaN(+value)) return 'inactive';
  for (const iv of intervals) if (iv[0] <= value && value <= iv[1]) return 'active';
  return 'inactive';
}

function checkScenario(sc) {
  const diffs = [];
  const chart = sc._chart;
  const model = chart.getModel();
  const pm = model.getComponent('parallel', 0);
  const cs = pm.coordinateSystem;
  const axisOf = k => {
    const am = model.getComponent('parallelAxis', k);
    return am && am.axis;
  };
  const all = [sc.initial].concat(sc.steps.map(s => s.record));
  // P1 / P2 / P7 (the layout is the final chart's: no scenario moves an axis)
  all.forEach((rec, ri) => {
    rec.axes.forEach(a => {
      const c = a.ctl;
      if (!c) return;
      const axis = axisOf(a.k);
      const lay = cs.getAxisLayout(axis.dim);
      const tm = localTransform(lay.position[0], lay.position[1], lay.rotation);
      if (!sameDeep(tm, c._transform)) diffs.push(sc.id + ' rec ' + ri + ' axis ' + a.k + ' transform');
      if (!sameDeep(invert(tm), c._inv)) diffs.push(sc.id + ' rec ' + ri + ' axis ' + a.k + ' inv');
      const am = model.getComponent('parallelAxis', a.k);
      const pr = panelRecipe(axis.getExtent(), am.getAreaSelectStyle().width);
      const got = c.panel._r;
      if (!sameDeep([pr.x, pr.y, pr.x + pr.width, pr.y + pr.height], got)) diffs.push(sc.id + ' rec ' + ri + ' axis ' + a.k + ' panel');
      RECIPES.P1++;
      c.covers.forEach((cv, i) => {
        if (c.creating === i) return;
        const want = lineShapes(cv._range, cv._lineWidth, pr);
        for (const n of Object.keys(want)) {
          const g = cv._shapes[n];
          if (!g) continue;
          if (!['x', 'y', 'width', 'height'].every(f => same(want[n][f], g[f]))) diffs.push(sc.id + ' rec ' + ri + ' axis ' + a.k + ' cover ' + i + ' ' + n);
        }
        RECIPES.P2++;
        for (const n of ['w', 'e']) {
          if (cv._cursors[n] == null) continue;
          if (handleCursor(n, c._transform) !== cv._cursors[n]) diffs.push(sc.id + ' rec ' + ri + ' axis ' + a.k + ' cursor ' + n);
          RECIPES.P7++;
        }
      });
    });
  });
  // P3 / P4: the actions the views dispatched
  sc.steps.forEach((s, si) => {
    const st = s.step;
    const rec = s.record;
    rec.actions.forEach(act => {
      const am = act._axis;
      must(am, sc.id + ' step ' + si + ': an action for no axis');
      const rt = !!am.option.realtime;
      const rt2 = mut.realtimeInverted ? !rt : rt;
      const clearing = act._intervals.length === 0;
      let ok;
      if (st.type === 'mousemove') ok = rt2;
      else if (st.type === 'mouseup') ok = !rt2 || clearing;
      else ok = false;
      if (!ok) diffs.push(sc.id + ' step ' + si + ' realtime rule (' + st.type + ')');
      RECIPES.P4++;
      // the covers of that axis at the end of the step: not rendered again
      const ar = rec.axes.find(a => a.k === am.componentIndex);
      if (am.axis.type === 'value' && ar.ctl) {
        const want = ar.ctl.covers.map(cv => [coordToValue(am.axis, cv._range[0]), coordToValue(am.axis, cv._range[1])]);
        if (!sameDeep(want, act._intervals)) diffs.push(sc.id + ' step ' + si + ' intervals');
        RECIPES.P3++;
      }
    });
    // a move that drew or moved a cover on a realtime axis dispatched
    if (st.type === 'mousemove') {
      rec.axes.forEach((a, k) => {
        // a view rendered by another axis' action lays its covers again
        if (!a.ctl || rec.rendered.includes(a.k)) return;
        const am = model.getComponent('parallelAxis', a.k);
        const rt = mut.realtimeInverted ? !am.option.realtime : !!am.option.realtime;
        const now = a.ctl.covers.map(cv => JSON.stringify(cv._range));
        const was = rec._before[k] || [];
        const changed = now.length > 0 && JSON.stringify(now) !== JSON.stringify(was);
        if (changed && rt && !rec.actions.some(x => x._axis === am)) diffs.push(sc.id + ' step ' + si + ' a realtime move without an action');
      });
    }
  });
  // P5: the rows' opacity
  all.forEach((rec, ri) => {
    rec.rows.forEach(r => {
      const sm = model.getSeriesByIndex(r.seriesIndex);
      const data = sm.getData();
      const ivs = cs.dimensions.map(d => {
        const k = cs.getAxis(d).model.componentIndex;
        return rec.axes.find(a => a.k === k)._intervals;
      });
      const any = ivs.some(iv => iv.length > 0);
      r.items.forEach((it, i) => {
        let state = 'normal';
        if (any) {
          state = 'active';
          for (let q = 0; q < cs.dimensions.length; q++) {
            const v = data.get(data.mapDimension(cs.dimensions[q]), i);
            if (activeRecipe(ivs[q], v) === 'inactive') { state = 'inactive'; break; }
          }
        }
        const op = state === 'normal' ? sm.get(['lineStyle', 'opacity']) : state === 'active' ? sm.get('activeOpacity') : (mut.noInactive ? 1 : sm.get('inactiveOpacity'));
        if (hex(op) !== it.opacity || state !== it.active) diffs.push(sc.id + ' rec ' + ri + ' row ' + i + ' opacity');
        RECIPES.P5++;
      });
    });
  });
  // P6: a rendered value axis lays its covers from its intervals
  sc.steps.forEach((s, si) => {
    s.record.rendered.forEach(k => {
      const ar = s.record.axes.find(a => a.k === k);
      const axis = axisOf(k);
      if (!ar.ctl || axis.type !== 'value' || ar.ctl.dragging) return;
      // a later action in the same step can re-render: the intervals at the end
      const want = ar._intervals.map(iv => [valueToCoord(axis, iv[0]), valueToCoord(axis, iv[1])]);
      const got = ar.ctl.covers.map(cv => cv._range);
      if (!sameDeep(want, got)) diffs.push(sc.id + ' step ' + si + ' axis ' + k + ' covers from the intervals');
      RECIPES.P6++;
    });
  });
  return diffs;
}

const GUARDS = [
  { id: 'G1', mutation: 'the panel has no extra at its ends', set: { noExtra: true }, named: ['H-VALUE', 'V-VALUE', 'T-TYPES'] },
  { id: 'G2', mutation: "the handles' cursors ignore the group's turn", set: { identityCursor: true }, named: ['H-VALUE', 'D-DRAG'] },
  { id: 'G3', mutation: 'realtime read the other way round', set: { realtimeInverted: true }, named: ['H-VALUE', 'RT-OFF', 'D-DRAG'] },
  { id: 'G4', mutation: 'coordToData not clamped', set: { noClamp: true }, named: ['D-DRAG'] },
  { id: 'G5', mutation: 'an inactive row keeps the full opacity', set: { noInactive: true }, named: ['H-VALUE', 'M-MULTI', 'T-TYPES'] },
];

function generate() {
  for (const k of Object.keys(RECIPES)) RECIPES[k] = 0;
  const scenarios = [];
  for (const def of SCENARIOS) scenarios.push(runScenario(def));
  mut = {};
  for (const sc of scenarios) {
    const d = checkScenario(sc);
    must(d.length === 0, 'the transcription disagrees: ' + d.slice(0, 6).join('; '));
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
  const hv = byId('H-VALUE');
  must(hv.steps.some(s => s.step.type === 'mousemove' && s.record.actions.length > 0), 'H-VALUE never dispatches while moving');
  must(hv.steps.some(s => s.record.axes[1].ctl && s.record.axes[1].ctl.covers.length === 1), 'H-VALUE draws no cover');
  must(hv.steps.some(s => s.record.cursor === 'crosshair'), 'H-VALUE shows no crosshair');
  // resetCursor asks Path.contain with the LOCAL point, which contain turns
  // local again: over a turned axis' cover the crosshair stays
  must(hv.steps.some(s => s.hover === 'axis1.cover0.main' && s.record.cursor === 'crosshair'), 'H-VALUE: no crosshair over a cover');
  const ro = byId('RT-OFF');
  must(ro.steps.some(s => s.step.type === 'mouseup' && s.record.actions.length > 0 && s.record.actions[0].intervals.length > 0), 'RT-OFF never dispatches on release');
  must(!ro.steps.some(s => s.step.type === 'mousemove' && s.record.actions.some(a => a.parallelAxisId !== 'a3')), 'RT-OFF dispatched while moving');
  const mm = byId('M-MULTI');
  must(mm.steps.some(s => s.record.axes[1].ctl && s.record.axes[1].ctl.covers.length === 2), 'M-MULTI never shows two covers');
  const gp = byId('G-PAN');
  must(JSON.stringify(gp.steps[5].record.zoom) !== JSON.stringify(gp.initial.zoom), 'G-PAN never pans');
  must(gp.steps.some(s => s.record.panTaken), 'G-PAN never takes globalPan');
  // strip the private fields; an axis' state only when it changed
  for (const sc of scenarios) {
    for (const rec of [sc.initial].concat(sc.steps.map(s => s.record))) {
      rec.axes.forEach(a => {
        delete a._intervals;
        if (a.ctl) {
          delete a.ctl._transform;
          delete a.ctl._inv;
          if (a.ctl.panel) delete a.ctl.panel._r;
          a.ctl.covers.forEach(cv => { delete cv._range; delete cv._lineWidth; delete cv._shapes; delete cv._cursors; });
        }
      });
      rec.actions.forEach(x => { delete x._intervals; delete x._axis; });
      delete rec._before;
    }
    const prev = [];
    for (const rec of [sc.initial].concat(sc.steps.map(s => s.record))) {
      rec.axes = rec.axes.map((a, k) => {
        const j = JSON.stringify(a);
        if (prev[k] === j) return null;
        prev[k] = j;
        return a;
      });
    }
    sc._chart.dispose();
    delete sc._chart;
  }
  return {
    out: {
      source: 'ECharts 6.1 dist (' + path.basename(DIST) + '), node SSR, SVG renderer',
      W, H, clock: { start: CLOCK0, pointerDt: 200, clickDt: 0, idleDt: 1000 },
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
