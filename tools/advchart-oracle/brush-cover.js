// Upstream's own answers for the BRUSH component's covers (C17, batch 126):
// how a drag in a target panel (a grid the brush's finder names, or the
// whole canvas when it names none) draws a rect, a polygon, a lineX or a
// lineY cover, how single and multiple modes keep them, how a cover moves
// when its main shape is dragged and resizes when one of its handles is,
// what a tiny drag does with removeOnClick, the cursor the pointer gets, the
// covers the `brush` action lays down from data ranges (coordRange) or pixel
// ranges, the areas the model keeps (range, coordRange, coordRanges and the
// __rangeOffset of the round trip), the `brush` / `brushEnd` actions and
// events with their areas, and when the throttled brushSelect dispatch runs
// (fixRate / debounce on a fake clock).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 600 x 400, and
// drives zrender's own Handler (mousemove / mousedown / mouseup / click with
// synthetic events, as datazoom-interact.js and toolbox.js do): the Handler
// finds the hovered element, sets the element's cursor, and its zr-level
// listeners -- zrender's Draggable (the covers' drift and dragend), then the
// BrushController's mousedown / mousemove / mouseup -- run as in a browser.
// Time is fake (Date and setTimeout replaced; the clock starts at
// 1700000000000 and moves 200 ms before every pointer event unless the step
// says otherwise, 0 before a click, 1000 for idle). Every option has
// `animation: false`.
//
//   node tools/advchart-oracle/brush-cover.js
//
// writes tests/fixtures/advchart-brush-cover.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (NaN 7ff8000000000000); a range or a point list keeps
//            its nesting with every number written so.
//   NUL      no string holds U+0000: a model id's NULs are written '<NUL>'.
//   piece    'brush<b>.cover<k>.<name>': cover k (its index in the
//            controller's _covers) of brush component b, its element named
//            main / w / e / n / s / se / sw / ne / nw.
//
// Top level
//   source, W, H, clock, notes[], scenarios[], guards[]
// A scenario
//   id, note, option, initial (a record), steps[] {i, step (the step as
//   run: x / y resolved for a step that names a piece), hover (the role
//   handler.findHover gives before the step: a piece, 'series<k>', 'other'
//   or null), record}
// A record
//   panels[] per brush component (null when unchanged): the target panels
//     the BrushTargetManager makes, [{panelId, rect [x, y, w, h] hex}]
//     (null: no panel, the global brush)
//   brushes[] per brush component (null when the same as the record before's):
//     enabled  the controller's _brushType (a type, or null when off)
//     option   the controller's _brushOption {brushType, brushMode,
//              transformable, removeOnClick, z, style {fill, stroke,
//              lineWidth}} | null
//     dragging the controller's _dragging; creating: the index of the cover
//              being drawn, or null
//     covers[] {id, brushType, panelId, range (hex), brushMode,
//              transformable, removeOnClick, z, order (its index among the
//              controller group's children), main {kind ('rect' | 'polyline'
//              | 'polygon'), rect [x, y, w, h] | points [[x, y]...] (hex),
//              silent, cursor, draggable, style {fill, stroke, lineWidth}},
//              handles null | {name: {rect, silent, invisible, cursor}}}
//     areas[]  the model's areas: {brushType, id, panelId, range,
//              coordRange, coordRanges, rangeOffset {offset, xyMinMax}}
//   cursor   the last proxy.setCursor of the step, or null
//   actions[] api.dispatchAction calls (brushSelect apart): {type, brushId,
//            areas (as the model's), key, brushOption}
//   events[] brush / brushend / globalcursortaken: {type, brushId, areas,
//            key, brushOption, from}
//   selects[] the brushSelect dispatches that ran: {t (ms since the clock's
//            start), batch [{brushIndex, areas [{brushType, range}]}]}
//   error    null | an exception's message
//
// Self-checks (any failure: nothing is written, exit 1). A transcription,
// recomputed and compared with the records:
//   T1 every cover's main shape and handles from its range, type, line width
//      and panel (updateBaseRect, clipPointsByRect, the line's other extent);
//   T2 a cover being drawn: its range from the track (the press and every
//      move since, clipped to the panel; the two ends for rect / lines);
//   T3 a dragged cover: the range before plus the pointer's delta on the
//      dragged piece's edges, formatRectRange after (driftRect / polygon);
//   T4 every brush / brushend event's areas: coordRange from range
//      (pointToData clamped, or the affine inverse; coordToData clamped for
//      a line) and the __rangeOffset of the round trip back;
//   T5 the model's areas after every step: range from coordRange back
//      through dataToPoint less the offset at the size ratio;
//   T6 brushSelect's execution times from the brush / takeGlobalCursor
//      dispatch times through util/throttle (fixRate / debounce).
// guards[] mutate the transcription one way each and name the scenarios
// that must notice; anchors (R-DRAW draws a cover, shows crosshair and the
// eight resize cursors; R-REMOVE clears by a tiny drag; TH-FIXRATE defers);
// no U+0000; the written JSON parses back; two generations give the same
// bytes.
// ---------------------------------------------------------------------------
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-brush-cover.json');
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
// numbers anywhere in a nesting of arrays written hex
function hexDeep(v) {
  if (v == null) return null;
  if (typeof v === 'number') return hex(v);
  if (Array.isArray(v)) return Array.from(v, x => (x === undefined ? null : hexDeep(x)));
  must(false, 'not a range: ' + JSON.stringify(v));
  return null;
}
const nul = s => (s == null ? null : String(s).split('\u0000').join('<NUL>'));
function clean(v) {
  if (v === undefined) return null;
  if (typeof v === 'string') return nul(v);
  if (typeof v === 'function') return '@fn';
  if (typeof v === 'number') return Number.isFinite(v) ? v : { $num: String(v) };
  if (v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return Array.from(v, x => clean(x));
  const o = {};
  for (const k of Object.keys(v)) {
    if (v[k] === undefined) continue;
    o[k] = clean(v[k]);
  }
  return o;
}
const rect4 = s => [hex(s.x), hex(s.y), hex(s.width), hex(s.height)];

// =====================================================================
// Recording
// =====================================================================
const PIECES = ['main', 'w', 'e', 'n', 's', 'se', 'sw', 'ne', 'nw'];
function brushViews(chart) {
  const out = [];
  chart.getModel().eachComponent('brush', m => {
    const v = chart.getViewOfComponentModel(m);
    out.push({ model: m, view: v, bc: v && v._brushController });
  });
  return out;
}
function styleRec(st) {
  return { fill: clean(st.fill), stroke: clean(st.stroke), lineWidth: st.lineWidth == null ? null : st.lineWidth };
}
function areaRec(a) {
  const o = { brushType: a.brushType, id: a.id == null ? null : clean(a.id), panelId: nul(a.panelId) };
  o.range = a.range == null ? null : hexDeep(a.range);
  o.coordRange = a.coordRange == null ? null : hexDeep(a.coordRange);
  o.coordRanges = a.coordRanges == null ? null : a.coordRanges.map(hexDeep);
  o.rangeOffset = a.__rangeOffset ? { offset: hexDeep(a.__rangeOffset.offset), xyMinMax: hexDeep(a.__rangeOffset.xyMinMax) } : null;
  // the finder an action's area names
  for (const k of ['xAxisIndex', 'yAxisIndex', 'gridIndex']) if (a[k] !== undefined) o[k] = clean(a[k]);
  return o;
}
function coverRec(bc, cover) {
  const opt = cover.__brushOption;
  const rec = {
    id: opt.id == null ? null : clean(opt.id), brushType: opt.brushType, panelId: nul(opt.panelId),
    range: hexDeep(opt.range), brushMode: opt.brushMode, transformable: !!opt.transformable,
    removeOnClick: !!opt.removeOnClick, z: opt.z == null ? null : opt.z,
    order: bc.group.children().indexOf(cover),
  };
  const main = cover.childOfName('main');
  rec.main = { kind: main.type, silent: !!main.silent, cursor: main.cursor == null ? null : main.cursor, draggable: !!main.draggable, style: styleRec(main.style) };
  if (main.type === 'rect') rec.main.rect = rect4(main.shape);
  else rec.main.points = hexDeep(main.shape.points || []);
  let handles = null;
  for (const n of PIECES.slice(1)) {
    const el = cover.childOfName(n);
    if (!el) continue;
    handles = handles || {};
    handles[n] = { rect: rect4(el.shape), silent: !!el.silent, invisible: !!el.invisible, cursor: el.cursor == null ? null : el.cursor };
  }
  rec.handles = handles;
  rec._range = JSON.parse(JSON.stringify(opt.range));
  rec._lineWidth = opt.brushStyle ? opt.brushStyle.lineWidth : undefined;
  rec._shapes = {};
  for (const n of PIECES) {
    const el = cover.childOfName(n);
    if (el) rec._shapes[n] = el.type === 'rect' ? Object.assign({}, el.shape) : { points: JSON.parse(JSON.stringify(el.shape.points || [])) };
  }
  return rec;
}
function brushRec(bv) {
  const bc = bv.bc;
  const rec = {
    enabled: bc._brushType ? bc._brushType : null,
    option: null,
    dragging: !!bc._dragging,
    creating: bc._creatingCover ? bc._covers.indexOf(bc._creatingCover) : null,
    covers: bc._covers.map(c => coverRec(bc, c)),
    areas: bv.model.areas.map(areaRec),
  };
  const o = bc._brushOption;
  if (o) {
    rec.option = { brushType: o.brushType, brushMode: o.brushMode, transformable: !!o.transformable, removeOnClick: !!o.removeOnClick, z: o.z == null ? null : o.z, style: styleRec(o.brushStyle || {}) };
  }
  rec._areas = bv.model.areas.map(a => JSON.parse(JSON.stringify(a)));
  return rec;
}
function panelsRec(bv) {
  const tm = bv.model.brushTargetManager;
  const list = tm ? tm._targetInfoList : [];
  if (!list.length) return null;
  return list.map(t => {
    const r = t.getPanelRect();
    return { panelId: nul(t.panelId), rect: rect4(r), _rect: { x: r.x, y: r.y, width: r.width, height: r.height }, _id: t.panelId };
  });
}

function makeCtx(chart) {
  const ctx = { chart, zr: chart.getZr(), h: chart.getZr().handler, cursor: null, actions: [], events: [], selects: [] };
  ctx.role = el => {
    if (!el) return null;
    const bvs = brushViews(chart);
    for (let b = 0; b < bvs.length; b++) {
      const bc = bvs[b].bc;
      for (let k = 0; k < bc._covers.length; k++) {
        const cv = bc._covers[k];
        if (el.parent === cv) return 'brush' + b + '.cover' + k + '.' + el.name;
      }
      let p = el;
      while (p) { if (p === bc.group) return 'brush' + b + '.other'; p = p.parent; }
    }
    let p = el;
    while (p) {
      if (p.__ecComponentInfo) return p.__ecComponentInfo.mainType + p.__ecComponentInfo.index;
      p = p.parent;
    }
    return 'other';
  };
  // a piece's centre, rounded: where a step that names it points
  ctx.pieceAt = (key, dx, dy) => {
    const mm = /^brush(\d+)\.cover(\d+)\.(\w+)$/.exec(key);
    must(mm, 'bad piece ' + key);
    const bc = brushViews(chart)[+mm[1]].bc;
    const cv = bc._covers[+mm[2]];
    must(cv, 'no cover ' + key);
    const el = cv.childOfName(mm[3]);
    must(el, 'no piece ' + key);
    let x;
    let y;
    if (el.type === 'rect') {
      x = el.shape.x + el.shape.width / 2;
      y = el.shape.y + el.shape.height / 2;
    } else {
      const pts = el.shape.points;
      x = pts.reduce((s, p) => s + p[0], 0) / pts.length;
      y = pts.reduce((s, p) => s + p[1], 0) / pts.length;
    }
    return [Math.round(x + (dx || 0)), Math.round(y + (dy || 0))];
  };
  return ctx;
}
function eventRaw(type, x, y) {
  return { type, zrX: x, zrY: y, which: 1, shiftKey: false, ctrlKey: false, altKey: false, cancelBubble: false, preventDefault() {}, stopPropagation() {} };
}
const EVENT_TYPES = ['brush', 'brushend', 'globalcursortaken'];

function payloadRec(p) {
  const o = { type: p.type };
  if (p.brushId !== undefined) o.brushId = nul(p.brushId);
  if (p.areas !== undefined) o.areas = p.areas == null ? null : p.areas.map(areaRec);
  if (p.key !== undefined) o.key = clean(p.key);
  if (p.brushOption !== undefined) o.brushOption = clean(p.brushOption);
  if (p.$from !== undefined) o.from = nul(p.$from);
  if (p.command !== undefined) o.command = clean(p.command);
  return o;
}

function snapshot(ctx, error) {
  ctx.zr.storage.getDisplayList(true);
  const bvs = brushViews(ctx.chart);
  return {
    panels: bvs.map(panelsRec),
    brushes: bvs.map(brushRec),
    cursor: ctx.cursor,
    actions: ctx.actions,
    events: ctx.events,
    selects: ctx.selects,
    error,
  };
}

function runScenario(def) {
  NOW = CLOCK0;
  TIMERS = [];
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    const ctx = makeCtx(chart);
    ctx.h.proxy.setCursor = c => { ctx.cursor = c; };
    const api = chart._api;
    const origDispatch = api.dispatchAction;
    api.dispatchAction = function (payload) {
      if (payload.type === 'brushSelect') {
        ctx.selects.push({ t: NOW - CLOCK0, batch: payload.batch.map(b => ({ brushIndex: b.brushIndex, areas: b.areas.map(a => ({ brushType: a.brushType, range: hexDeep(a.range) })) })) });
        ctx.calls.push({ kind: 'exec', t: NOW - CLOCK0 });
      } else if (payload.type !== 'hideTip') ctx.actions.push(payloadRec(payload));
      return origDispatch.apply(this, arguments);
    };
    ctx.calls = [];
    EVENT_TYPES.forEach(t => chart.on(t, p => ctx.events.push(Object.assign(payloadRec(p), { _raw: p.areas ? structuredClone(p.areas) : [] }))));
    chart.setOption(JSON.parse(JSON.stringify(def.option)));
    ctx.zr.storage.getDisplayList(true);
    const initial = snapshot(ctx, null);
    const recs = [];
    const steps = def.steps.concat([{ type: 'idle' }]);
    steps.forEach((st, i) => {
      ctx.cursor = null;
      ctx.actions = [];
      ctx.events = [];
      ctx.selects = [];
      let error = null;
      const dt = st.dt != null ? st.dt : st.type === 'click' ? 0 : st.type === 'idle' ? 1000 : 200;
      advanceClock(NOW + dt);
      ctx.zr.storage.getDisplayList(true);
      let hover = null;
      const out = { i, step: Object.assign({}, st, { dt }) };
      const coversBefore = brushViews(chart).map(bv => bv.bc._covers.slice());
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
          // outside the canvas the Handler finds nothing
          hover = (p[0] < 0 || p[1] < 0 || p[0] > W || p[1] > H) ? null : ctx.role(ctx.h.findHover(p[0], p[1]).target);
          ctx.h[st.type](eventRaw(st.type, p[0], p[1]));
        } else if (st.type === 'action') {
          // the API's own dispatch does not pass api.dispatchAction: T6's call
          if (st.payload.type === 'brush' || st.payload.type === 'takeGlobalCursor') ctx.calls.push({ kind: 'call', t: NOW - CLOCK0 });
          chart.dispatchAction(JSON.parse(JSON.stringify(st.payload)));
        } else if (st.type === 'set') {
          chart.setOption(JSON.parse(JSON.stringify(st.option)), !!st.notMerge);
        }
      } catch (e) {
        if (e instanceof OracleError) throw e;
        error = String(e.message);
      }
      // T6's input: when a brush / takeGlobalCursor dispatch ran
      for (const a of ctx.actions) if (a.type === 'brush' || a.type === 'takeGlobalCursor') ctx.calls.push({ kind: 'call', t: NOW - CLOCK0 });
      ctx.zr.storage.getDisplayList(true);
      out.hover = hover;
      out.record = snapshot(ctx, error);
      // what the transcription reads: the piece zrender's Draggable holds,
      // and the covers this step created
      const dm = ctx.h._draggingMgr;
      out.record._drag = dm && dm._draggingTarget ? ctx.role(dm._draggingTarget) : null;
      out.record._newCovers = brushViews(chart).map((bv, b) => bv.bc._covers.map((c, k) => (coversBefore[b] && coversBefore[b].indexOf(c) < 0 ? k : -1)).filter(k => k >= 0));
      recs.push(out);
    });
    return { id: def.id, note: def.note, option: def.option, initial, steps: recs, _calls: ctx.calls, _chart: chart, _layout: { grids: gridsOf(chart) } };
  } catch (e) {
    chart.dispose();
    throw e;
  }
}

// the coordinate systems the transcription converts through (kept alive
// until the checks are done: the chart's final state)
function gridsOf(chart) {
  const out = [];
  chart.getModel().eachComponent('grid', g => out.push(g));
  return out;
}

// ---------- the scenarios ----------
const CATS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const BARS = [120, 200, 150, 80, 70, 110, 130];
const catChart = extra => Object.assign({
  animation: false,
  xAxis: { type: 'category', data: CATS },
  yAxis: { type: 'value' },
  series: [{ type: 'bar', name: 'Bars', data: BARS }],
}, extra || {});
const valChart = extra => Object.assign({
  animation: false,
  xAxis: { type: 'value' },
  yAxis: { type: 'value' },
  series: [{ type: 'scatter', name: 'Pts', data: [[1.5, 2.25], [3.75, 8.125], [7.3, 4.4], [9.9, 0.5], [5.55, 6.66]] }],
}, extra || {});
const take = (brushType, brushMode, extra) => ({ type: 'action', payload: { type: 'takeGlobalCursor', key: 'brush', brushOption: Object.assign({ brushType, brushMode: brushMode || 'single' }, extra || {}) } });
// a press, two moves and the release, then the click a browser sends
const drag = (x0, y0, x1, y1) => [
  { type: 'mousemove', x: x0, y: y0 }, { type: 'mousedown', x: x0, y: y0 },
  { type: 'mousemove', x: Math.round((x0 + x1) / 2), y: Math.round((y0 + y1) / 2) },
  { type: 'mousemove', x: x1, y: y1 }, { type: 'mouseup', x: x1, y: y1 }, { type: 'click', x: x1, y: y1 },
];
// a drag that starts on a cover's piece and moves it by (dx, dy)
const dragPiece = (piece, dx, dy) => [
  { type: 'mousemove', piece }, { type: 'mousedown', piece },
  { type: 'mousemove', piece, dx: Math.round(dx / 2), dy: Math.round(dy / 2), relative: true },
  { type: 'mousemove', piece, dx, dy, relative: true }, { type: 'mouseup', piece, dx, dy, relative: true },
  { type: 'click', piece, dx, dy, relative: true },
];
const hoverPiece = piece => ({ type: 'mousemove', piece });
const HANDLES = ['w', 'e', 'n', 's', 'se', 'sw', 'ne', 'nw'];

const SCENARIOS = [
  {
    id: 'R-DRAW', note: 'a rect on a category grid: the crosshair, the cover, its cursors over the main shape and the eight handles',
    option: catChart({ brush: { xAxisIndex: 0 } }),
    steps: [].concat([{ type: 'mousemove', x: 300, y: 200 }, take('rect'), { type: 'mousemove', x: 301, y: 200 }],
      drag(150, 100, 260, 210), [hoverPiece('brush0.cover0.main')], HANDLES.map(h => hoverPiece('brush0.cover0.' + h)),
      [{ type: 'mousemove', x: 400, y: 250 }, { type: 'mousemove', x: 50, y: 40 }]),
  },
  {
    id: 'R-MOVE', note: 'the main shape dragged inside the grid, then past its right and bottom edges: the range leaves the panel, the shapes are clipped',
    option: catChart({ brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('rect')], drag(150, 100, 260, 210), dragPiece('brush0.cover0.main', 30, 20), dragPiece('brush0.cover0.main', 330, 140),
      [hoverPiece('brush0.cover0.main')]),
  },
  {
    id: 'R-HANDLES', note: 'each of the eight handles dragged in turn; the west handle past the east edge swaps them',
    option: catChart({ brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('rect')], drag(200, 120, 330, 240),
      dragPiece('brush0.cover0.w', -15, 7), dragPiece('brush0.cover0.e', 21, -3), dragPiece('brush0.cover0.n', 4, -12),
      dragPiece('brush0.cover0.s', -6, 18), dragPiece('brush0.cover0.se', 9, 11), dragPiece('brush0.cover0.sw', -8, 5),
      dragPiece('brush0.cover0.ne', 12, -9), dragPiece('brush0.cover0.nw', -7, -6), dragPiece('brush0.cover0.w', 200, 0)),
  },
  {
    id: 'R-REMOVE', note: 'single mode: a second rect replaces the first; a tiny drag clears (removeOnClick); a click on a cover ends a brush',
    option: catChart({ brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('rect')], drag(120, 90, 200, 160), drag(300, 150, 420, 260), drag(450, 100, 452, 101), drag(450, 100, 452, 101),
      drag(200, 120, 330, 230), [{ type: 'mousemove', piece: 'brush0.cover0.main' }, { type: 'mousedown', piece: 'brush0.cover0.main' },
        { type: 'mouseup', piece: 'brush0.cover0.main' }, { type: 'click', piece: 'brush0.cover0.main' }]),
  },
  {
    id: 'R-THRESHOLD', note: 'a drag of exactly 6 px draws nothing, 7 px does; a press outside the grid draws nothing; a drag leaving the canvas',
    option: catChart({ brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('rect')], drag(200, 150, 206, 150), drag(200, 150, 207, 150), drag(40, 30, 200, 200),
      [{ type: 'mousemove', x: 300, y: 200 }, { type: 'mousedown', x: 300, y: 200 }, { type: 'mousemove', x: 650, y: 380 },
        { type: 'mousemove', x: 620, y: -30 }, { type: 'mouseup', x: 620, y: -30 }]),
  },
  {
    id: 'M-MULTI', note: 'multiple mode: three rects, the later on top; a tiny drag removes nothing; switching to single keeps the covers until a new one',
    option: catChart({ brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('rect', 'multiple')], drag(120, 90, 250, 200), drag(200, 150, 330, 260), drag(400, 80, 500, 140),
      [{ type: 'mousemove', x: 225, y: 175 }], drag(470, 290, 472, 292), dragPiece('brush0.cover0.nw', 10, 10),
      [take('rect', 'single')], drag(150, 270, 260, 300)),
  },
  {
    id: 'P-POLYGON', note: 'a polygon: every move a vertex, clipped to the grid; dragged; replaced in single mode; cleared by a tiny drag',
    option: catChart({ brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('polygon')],
      [{ type: 'mousemove', x: 150, y: 100 }, { type: 'mousedown', x: 150, y: 100 }, { type: 'mousemove', x: 200, y: 90 },
        { type: 'mousemove', x: 260, y: 130 }, { type: 'mousemove', x: 600, y: 250 }, { type: 'mousemove', x: 280, y: 300 },
        { type: 'mousemove', x: 180, y: 230 }, { type: 'mouseup', x: 175, y: 225 }, { type: 'click', x: 175, y: 225 }],
      [{ type: 'mousemove', x: 230, y: 180 }], dragPiece('brush0.cover0.main', 20, -10), drag(400, 120, 480, 200),
      drag(300, 280, 301, 281)),
  },
  {
    id: 'L-LINEX', note: 'lineX on a value x axis: the cover spans the grid height; its two handles; dragged',
    option: Object.assign(valChart(), { brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('lineX')], drag(150, 200, 300, 150), [hoverPiece('brush0.cover0.w'), hoverPiece('brush0.cover0.e'), hoverPiece('brush0.cover0.main')],
      dragPiece('brush0.cover0.e', 40, 30), dragPiece('brush0.cover0.main', -100, 50), dragPiece('brush0.cover0.w', -30, 0)),
  },
  {
    id: 'L-LINEY', note: 'lineY on a category y axis (horizontal bars): the cover spans the grid width',
    option: {
      animation: false, xAxis: { type: 'value' }, yAxis: { type: 'category', data: CATS },
      series: [{ type: 'bar', data: BARS }], brush: { yAxisIndex: 0 },
    },
    steps: [].concat([take('lineY')], drag(200, 100, 260, 230), [hoverPiece('brush0.cover0.n'), hoverPiece('brush0.cover0.s')],
      dragPiece('brush0.cover0.s', 0, 40), dragPiece('brush0.cover0.n', 0, -50), dragPiece('brush0.cover0.main', 30, 25)),
  },
  {
    id: 'G-GLOBAL', note: 'no finder: the global panel -- not clipped, no coordRange; a global lineX spans the canvas; a tiny drag clears',
    option: catChart({ brush: {} }),
    steps: [].concat([take('rect')], drag(30, 30, 250, 200), dragPiece('brush0.cover0.main', 15, -10), drag(500, 300, 501, 300), [take('lineX')],
      drag(100, 300, 50, 200), [hoverPiece('brush0.cover0.e')], dragPiece('brush0.cover0.e', 30, 0)),
  },
  {
    id: 'T-TWOGRIDS', note: "two grids, xAxisIndex 'all': a drag in the right grid clipped to it; then one in the left grid replaces it",
    option: {
      animation: false,
      grid: [{ left: 50, right: 330, top: 60, bottom: 60 }, { left: 330, right: 40, top: 60, bottom: 60 }],
      xAxis: [{ type: 'category', data: CATS, gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
      yAxis: [{ type: 'value', gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
      series: [{ type: 'bar', data: BARS }, { type: 'scatter', xAxisIndex: 1, yAxisIndex: 1, data: [[1, 2], [3, 9], [6, 4]] }],
      brush: { xAxisIndex: 'all' },
    },
    steps: [].concat([take('rect')], [{ type: 'mousemove', x: 300, y: 200 }], drag(400, 100, 200, 300), dragPiece('brush0.cover0.main', 40, 20),
      drag(90, 120, 250, 280)),
  },
  {
    id: 'A-API', note: 'the brush action lays covers from coordRange (rect, lineX, polygon) and from a pixel range (global); dragged while the brush is off; fewer areas; none',
    option: valChart({ brush: { xAxisIndex: 0, yAxisIndex: 0 } }),
    steps: [].concat([{
      type: 'action', payload: {
        type: 'brush', areas: [
          { brushType: 'rect', xAxisIndex: 0, coordRange: [[1, 3], [2, 5]] },
          { brushType: 'lineX', xAxisIndex: 0, coordRange: [6, 8.5] },
          { brushType: 'polygon', yAxisIndex: 0, coordRange: [[2, 7], [4, 9], [5, 6.5]] },
          { brushType: 'rect', range: [[10, 50], [10, 40]] },
          { brushType: 'rect', id: 'named', xAxisIndex: 0, coordRange: [[7, 9], [1, 3]] },
        ],
      },
    }], [{ type: 'mousemove', x: 300, y: 200 }], dragPiece('brush0.cover4.main', -20, 15), dragPiece('brush0.cover1.e', 10, 0),
    [{ type: 'action', payload: { type: 'brush', areas: [{ brushType: 'rect', id: 'named', xAxisIndex: 0, coordRange: [[6, 9.5], [0.5, 3]] }, { brushType: 'lineX', xAxisIndex: 0, coordRange: [1, 2] }] } },
      { type: 'action', payload: { type: 'brush', areas: [] } }]),
  },
  {
    id: 'Q-RESCALE', stableAxes: false, rescaleStep: 7, note: "a cover kept by the model: a merge that rescales the y axis lays it again at the size ratio; a release away from the last move leaves the model at the move's range",
    option: catChart({ brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('rect')], drag(160, 120, 300, 250), [{ type: 'set', option: { yAxis: { max: 400 } } }],
      [{ type: 'mousemove', x: 350, y: 100 }, { type: 'mousedown', x: 350, y: 100 }, { type: 'mousemove', x: 420, y: 160 },
        { type: 'mouseup', x: 460, y: 190 }, { type: 'click', x: 460, y: 190 }], [take('rect')]),
  },
  {
    id: 'S-STYLE', note: 'brushStyle, transformable false, removeOnClick false: no handles, no move cursor, a press on the cover draws anew, a tiny drag keeps',
    option: catChart({ brush: { xAxisIndex: 0, transformable: false, removeOnClick: false, brushStyle: { borderWidth: 8, color: 'rgba(255,0,0,0.2)', borderColor: '#0000ff' } } }),
    steps: [].concat([take('rect')], drag(150, 100, 260, 210), [{ type: 'mousemove', x: 200, y: 150 }], drag(200, 150, 330, 250),
      drag(450, 100, 452, 101)),
  },
  {
    id: 'S-WIDE', note: 'a 10 px border: the handles take the line width; a brushOption of its own (transformable kept, mode multiple)',
    option: catChart({ brush: { xAxisIndex: 0, brushStyle: { borderWidth: 10 } } }),
    steps: [].concat([take('rect', 'multiple', { removeOnClick: false })], drag(150, 100, 260, 210), [hoverPiece('brush0.cover0.e'), hoverPiece('brush0.cover0.nw')],
      dragPiece('brush0.cover0.s', 0, 20)),
  },
  {
    id: 'D-DISABLE', note: 'the brush switched off (brushType false, then another key): the covers stay and still move; no crosshair, no drawing',
    option: catChart({ brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('rect')], drag(150, 100, 260, 210), [take(false)], [{ type: 'mousemove', x: 400, y: 250 }], drag(380, 120, 480, 220),
      dragPiece('brush0.cover0.main', 40, 30), [{ type: 'action', payload: { type: 'takeGlobalCursor', key: 'other' } }], [{ type: 'mousemove', x: 300, y: 250 }]),
  },
  {
    id: 'TH-FIXRATE', note: 'throttleType fixRate, 300 ms: brushSelect runs at once, then at lastExec + 300 with the latest areas',
    option: catChart({ brush: { xAxisIndex: 0, throttleType: 'fixRate', throttleDelay: 300 } }),
    steps: [].concat([take('rect')], [{ type: 'mousemove', x: 150, y: 100 }, { type: 'mousedown', x: 150, y: 100 }],
      [160, 175, 190, 205, 220, 235, 250, 265].map((x, k) => ({ type: 'mousemove', x, y: 110 + 10 * k, dt: 100 })),
      [{ type: 'mouseup', x: 265, y: 180, dt: 100 }, { type: 'click', x: 265, y: 180 }]),
  },
  {
    id: 'TH-DEBOUNCE', note: 'throttleType debounce, 250 ms: brushSelect only after the moves stop',
    option: catChart({ brush: { xAxisIndex: 0, throttleType: 'debounce', throttleDelay: 250 } }),
    steps: [].concat([take('rect')], [{ type: 'mousemove', x: 150, y: 100 }, { type: 'mousedown', x: 150, y: 100 }],
      [160, 175, 190, 205, 220].map((x, k) => ({ type: 'mousemove', x, y: 110 + 10 * k, dt: 100 })),
      [{ type: 'mousemove', x: 240, y: 170, dt: 300 }, { type: 'mouseup', x: 240, y: 170, dt: 100 }, { type: 'click', x: 240, y: 170 }]),
  },
];

const NOTES = [
  'Every option has animation false; the clock is fake.',
  "The brush preprocessor adds a toolbox with the brush feature (C18): no step points at it.",
  'brushSelect is recorded apart (selects): when it ran and the areas it carried; its selected data is C18.',
  'A step naming a piece points at its shape centre (rounded) plus dx / dy, read just before the step.',
];

// =====================================================================
// The transcription (mutations as switches in `mut`)
// =====================================================================
let mut = {};
const MIN_RESIZE = 6;
function clipPts(points, panel) {
  if (!panel || mut.noClip) return points.map(p => p.slice());
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
// T1: the shapes updateBaseRect gives
function transcribeShapes(cv, panel) {
  const out = {};
  const t = cv.brushType;
  if (t === 'polygon') {
    out.main = { points: clipPts(cv._range, panel) };
    return out;
  }
  let rr;
  if (t === 'rect') rr = cv._range;
  else {
    const other = panel ? (t === 'lineX' ? [panel.y, panel.y + (panel.height || 0)] : [panel.x, panel.x + (panel.width || 0)])
      : [0, t === 'lineX' ? H : W];
    // the mutation: a global line's other extent across the wrong side
    const o2 = mut.lineWrongSide && !panel ? [0, t === 'lineX' ? W : H] : other;
    rr = t === 'lineX' ? [cv._range, o2] : [o2, cv._range];
  }
  const lw = cv._lineWidth || 0;
  const hs = mut.noMinHandle ? lw : Math.max(lw, MIN_RESIZE);
  const x = rr[0][0];
  const y = rr[1][0];
  const xa = x - lw / 2;
  const ya = y - lw / 2;
  const x2 = rr[0][1];
  const y2 = rr[1][1];
  const x2a = x2 - hs + lw / 2;
  const y2a = y2 - hs + lw / 2;
  const w = x2 - x;
  const h = y2 - y;
  const wa = w + lw;
  const ha = h + lw;
  const sh = (a, b, c, d) => ptsToRect(clipPts([[a, b], [a + c, b + d]], panel));
  out.main = sh(x, y, w, h);
  if (cv.transformable) {
    out.w = sh(xa, ya, hs, ha);
    out.e = sh(x2a, ya, hs, ha);
    out.n = sh(xa, ya, wa, hs);
    out.s = sh(xa, y2a, wa, hs);
    out.nw = sh(xa, ya, hs, hs);
    out.ne = sh(x2a, ya, hs, hs);
    out.sw = sh(xa, y2a, hs, hs);
    out.se = sh(x2a, y2a, hs, hs);
  }
  return out;
}
// T2: getCreatingRange of a track
function creatingRange(type, track, panel) {
  const tr = clipPts(track, panel);
  if (type === 'polygon') return tr;
  const a = tr[0];
  const b = tr[tr.length - 1];
  if (type === 'rect') return [[Math.min(b[0], a[0]), Math.max(b[0], a[0])], [Math.min(b[1], a[1]), Math.max(b[1], a[1])]];
  const i = type === 'lineX' ? 0 : 1;
  return [Math.min(a[i], b[i]), Math.max(a[i], b[i])];
}
const DIR = { w: [0, 0], e: [0, 1], n: [1, 0], s: [1, 1] };
// T3: driftRect / driftPolygon
function drifted(type, range, piece, dx, dy) {
  if (type === 'polygon') return range.map(p => [p[0] + dx, p[1] + dy]);
  let rr = type === 'rect' ? range.map(r => r.slice()) : (type === 'lineX' ? [range.slice(), [0, 100]] : [[0, 100], range.slice()]);
  const seq = piece === 'main' ? ['n', 's', 'w', 'e'] : piece.split('');
  for (const d of seq) {
    const ind = DIR[d];
    const delta = mut.nWithDx && d === 'n' ? dx : [dx, dy][ind[0]];
    rr[ind[0]][ind[1]] += delta;
  }
  rr = [[Math.min(rr[0][0], rr[0][1]), Math.max(rr[0][0], rr[0][1])], [Math.min(rr[1][0], rr[1][1]), Math.max(rr[1][0], rr[1][1])]];
  if (type === 'rect') return rr;
  return type === 'lineX' ? rr[0] : rr[1];
}
// T4 / T5: the coordinate conversions (BrushTargetManager)
function cartOf(chart, panelId) {
  let found = null;
  chart.getModel().eachComponent('grid', g => { if ('grid--' + g.id === panelId) found = g.coordinateSystem.getCartesians()[0]; });
  return found;
}
const fmm = mm => (mm[0] > mm[1] ? [mm[1], mm[0]] : mm);
function convert(type, to, cs, r, clamp) {
  if (type === 'lineX' || type === 'lineY') {
    const i = type === 'lineX' ? 0 : 1;
    const axis = cs.getAxis(['x', 'y'][i]);
    const values = fmm([0, 1].map(k => (to ? axis.coordToData(axis.toLocalCoord(r[k]), true) : axis.toGlobalCoord(axis.dataToCoord(r[k])))));
    const xy = [];
    xy[i] = values;
    xy[1 - i] = [NaN, NaN];
    return { values, xyMinMax: xy };
  }
  if (type === 'rect') {
    const a = to ? cs.pointToData([r[0][0], r[1][0]], clamp) : cs.dataToPoint([r[0][0], r[1][0]], clamp);
    const b = to ? cs.pointToData([r[0][1], r[1][1]], clamp) : cs.dataToPoint([r[0][1], r[1][1]], clamp);
    const values = [fmm([a[0], b[0]]), fmm([a[1], b[1]])];
    return { values, xyMinMax: values };
  }
  const xy = [[Infinity, -Infinity], [Infinity, -Infinity]];
  const values = r.map(item => {
    const p = to ? cs.pointToData(item, clamp) : cs.dataToPoint(item, clamp);
    xy[0][0] = Math.min(xy[0][0], p[0]);
    xy[1][0] = Math.min(xy[1][0], p[1]);
    xy[0][1] = Math.max(xy[0][1], p[0]);
    xy[1][1] = Math.max(xy[1][1], p[1]);
    return p;
  });
  return { values, xyMinMax: xy };
}
function diff(type, values, refer, scales) {
  if (type === 'lineX' || type === 'lineY') {
    const s = scales[type === 'lineX' ? 0 : 1];
    return [values[0] - s * refer[0], values[1] - s * refer[1]];
  }
  if (type === 'rect') return [[values[0][0] - scales[0] * refer[0][0], values[0][1] - scales[0] * refer[0][1]], [values[1][0] - scales[1] * refer[1][0], values[1][1] - scales[1] * refer[1][1]]];
  return values.map((it, k) => [it[0] - scales[0] * refer[k][0], it[1] - scales[1] * refer[k][1]]);
}
function scalesOf(cur, orig) {
  if (mut.noScales) return [1, 1];
  const sz = m => (m ? [m[0][1] - m[0][0], m[1][1] - m[1][0]] : [NaN, NaN]);
  const a = sz(cur);
  const b = sz(orig);
  const s = [a[0] / b[0], a[1] / b[1]];
  if (isNaN(s[0])) s[0] = 1;
  if (isNaN(s[1])) s[1] = 1;
  return s;
}
// T6: util/throttle over the dispatch times
function transcribeThrottle(calls, type, delay) {
  // calls: dispatch times; answers the times the function ran
  if (delay == null || !type) return calls.slice();
  const runs = [];
  // the throttle starts at the epoch: the times here count from the clock's start
  let lastCall = -CLOCK0;
  let lastExec = -CLOCK0;
  let timer = null;
  const debounce = type === 'debounce';
  const events = calls.map(t => ({ t }));
  for (let i = 0; i < events.length; i++) {
    const now = events[i].t;
    // a timer due before this call has run
    if (timer != null && timer <= now) {
      runs.push(timer);
      lastExec = timer;
      timer = null;
    }
    const diffT = now - ((debounce || mut.fromLastCall) ? lastCall : lastExec) - delay;
    timer = null;
    if (debounce) timer = now + delay;
    else if (diffT >= 0) {
      runs.push(now);
      lastExec = now;
    } else timer = now + -diffT;
    lastCall = now;
  }
  if (timer != null) runs.push(timer);
  return runs;
}

function sameNum(a, b) {
  return (Number.isNaN(a) && Number.isNaN(b)) || a === b;
}
function sameDeep(a, b) {
  if (typeof a === 'number' || typeof b === 'number') return typeof a === 'number' && typeof b === 'number' && sameNum(a, b);
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => sameDeep(x, b[i]));
  return a == b; // eslint-disable-line eqeqeq
}

function latestPanels(sc, si) {
  let p = sc.initial.panels;
  for (let i = 0; i <= si; i++) if (sc.steps[i].record.panels) p = sc.steps[i].record.panels;
  return p;
}
function checkScenario(sc, def) {
  const diffs = [];
  const all = [sc.initial].concat(sc.steps.map(s => s.record));
  let panels = sc.initial.panels;
  // T1: the shapes
  all.forEach((rec, ri) => {
    if (rec.panels) panels = rec.panels;
    rec.brushes.forEach((b, bi) => {
      b.covers.forEach((cv, k) => {
        const pl = panels[bi] ? panels[bi].find(p => p._id === cv._panelRaw) : null;
        const want = transcribeShapes(cv, pl ? pl._rect : null);
        for (const n of Object.keys(want)) {
          const got = cv._shapes[n];
          if (!got) continue;
          // a cover being drawn keeps its handles as created (empty)
          if (n !== 'main' && b.creating === k) continue;
          if (want[n].points) {
            if (!sameDeep(want[n].points, got.points)) diffs.push(sc.id + ' rec ' + ri + ' cover ' + k + ' ' + n);
          } else if (!['x', 'y', 'width', 'height'].every(f => sameNum(want[n][f], got[f]))) diffs.push(sc.id + ' rec ' + ri + ' cover ' + k + ' ' + n);
        }
      });
    });
  });
  // T2 / T3: the ranges a gesture gives
  let track = null;
  let lastXY = null;
  let prevRec = sc.initial;
  sc.steps.forEach((s, si) => {
    const st = s.step;
    const rec = s.record;
    const b = rec.brushes[0];
    const pb = prevRec.brushes[0];
    const isPointer = ['mousemove', 'mousedown', 'mouseup'].includes(st.type);
    if (st.type === 'mousedown') track = b.dragging ? [[st.x, st.y]] : null;
    else if ((st.type === 'mousemove' || st.type === 'mouseup') && track) {
      track.push([st.x, st.y]);
      let k = st.type === 'mousemove' ? b.creating : null;
      if (st.type === 'mouseup') {
        // the cover drawn by this gesture: shown since a move, or at the release
        if (pb.creating != null) k = pb.creating;
        else if (rec._newCovers[0].length) k = rec._newCovers[0][0];
        // single mode clears the others: the drawn cover is the last
        if (k != null && k >= b.covers.length) k = b.covers.length - 1;
      }
      if (k != null && b.covers[k]) {
        const cv = b.covers[k];
        const pl = latestPanels(sc, si);
        const pr = pl && pl[0] ? pl[0].find(p => p._id === cv._panelRaw) : null;
        const want = creatingRange(cv.brushType, track, pr ? pr._rect : null);
        if (!sameDeep(want, cv._range)) diffs.push(sc.id + ' step ' + si + ' creating range');
      }
      if (st.type === 'mouseup') track = null;
    }
    // a piece under zrender's Draggable: the move drifts it by the delta since the last pointer event
    if (st.type === 'mousemove' && prevRec._drag && /^brush0\.cover\d+\./.test(prevRec._drag)) {
      const k = +/cover(\d+)/.exec(prevRec._drag)[1];
      const piece = prevRec._drag.split('.')[2];
      const before = pb.covers[k];
      const after = b.covers[k];
      if (before && after) {
        const want = drifted(before.brushType, before._range, piece, st.x - lastXY[0], st.y - lastXY[1]);
        if (!sameDeep(want, after._range)) diffs.push(sc.id + ' step ' + si + ' drift ' + piece);
      }
    }
    if (isPointer) lastXY = [st.x, st.y];
    prevRec = rec;
  });
  // T4: the events' coordRange and offset
  const chart = sc._chart;
  sc.steps.forEach((s, si) => {
    s.record.events.forEach(ev => {
      if ((ev.type !== 'brush' && ev.type !== 'brushend') || !ev.from) return;
      ev._areas.forEach((a, k) => {
        if (!a.panelId) return;
        const cs = cartOf(chart, a.panelId);
        if (!cs || def.stableAxes === false) return;
        const out = convert(a.brushType, 1, cs, a.range, true);
        if (!sameDeep(out.values, a.coordRange)) diffs.push(sc.id + ' step ' + si + ' area ' + k + ' coordRange');
        const back = convert(a.brushType, 0, cs, out.values);
        const off = diff(a.brushType, back.values, a.range, [1, 1]);
        if (!sameDeep(off, a.__rangeOffset.offset)) diffs.push(sc.id + ' step ' + si + ' area ' + k + ' offset');
      });
    });
  });
  // T5: the model's areas laid back (stable axes: the final chart converts)
  if (def.stableAxes !== false) {
    sc.steps.forEach((s, si) => {
      s.record.brushes[0]._areas.forEach((a, k) => {
        if (!a.panelId || !a.coordRange) return;
        const cs = cartOf(chart, a.panelId);
        const res = convert(a.brushType, 0, cs, a.coordRange);
        const want = a.__rangeOffset ? diff(a.brushType, res.values, a.__rangeOffset.offset, scalesOf(res.xyMinMax, a.__rangeOffset.xyMinMax)) : res.values;
        if (!sameDeep(want, a.range)) diffs.push(sc.id + ' step ' + si + ' model area ' + k);
      });
    });
  }
  // T5b: a rescale (Q-RESCALE): the area after the merge from the one before
  if (def.rescaleStep != null) {
    const before = sc.steps[def.rescaleStep - 1].record.brushes[0]._areas[0];
    const after = sc.steps[def.rescaleStep].record.brushes[0]._areas[0];
    const cs = cartOf(chart, after.panelId);
    const res = convert(after.brushType, 0, cs, before.coordRange);
    const want = diff(after.brushType, res.values, before.__rangeOffset.offset, scalesOf(res.xyMinMax, before.__rangeOffset.xyMinMax));
    if (!sameDeep(want, after.range)) diffs.push(sc.id + ' rescale');
  }
  // T6: brushSelect's times
  const opt = (def.option.brush || {});
  const calls = sc._calls.filter(c => c.kind === 'call').map(c => c.t);
  const runs = sc._calls.filter(c => c.kind === 'exec').map(c => c.t);
  const want = transcribeThrottle(calls, opt.throttleType === undefined ? 'fixRate' : opt.throttleType, opt.throttleDelay === undefined ? 0 : opt.throttleDelay);
  if (!sameDeep(want, runs)) diffs.push(sc.id + ' throttle ' + JSON.stringify(want) + ' vs ' + JSON.stringify(runs));
  return diffs;
}

const GUARDS = [
  { id: 'G1', mutation: 'the handle size is the line width, not at least 6', set: { noMinHandle: true }, named: ['R-DRAW', 'R-HANDLES'] },
  { id: 'G2', mutation: "the drift of the 'n' edge adds dx", set: { nWithDx: true }, named: ['R-HANDLES', 'R-MOVE'] },
  { id: 'G3', mutation: "a global line cover's other extent is the canvas' other side", set: { lineWrongSide: true }, named: ['G-GLOBAL'] },
  { id: 'G4', mutation: 'nothing clipped to the panel', set: { noClip: true }, named: ['R-MOVE', 'P-POLYGON', 'T-TWOGRIDS'] },
  { id: 'G5', mutation: 'the round trip ignores the size ratio', set: { noScales: true }, named: ['Q-RESCALE'] },
  { id: 'G6', mutation: 'fixRate measured from the last call, not the last run', set: { fromLastCall: true }, named: ['TH-FIXRATE'] },
];

function generate() {
  const scenarios = [];
  const checks = {};
  for (const def of SCENARIOS) {
    const sc = runScenario(def);
    // the private fields the transcription reads
    for (const rec of [sc.initial].concat(sc.steps.map(s => s.record))) {
      rec.brushes.forEach(b => b.covers.forEach((cv, k) => { void k; }));
    }
    checks[def.id] = { sc, def };
    scenarios.push(sc);
  }
  // panel ids of the covers (raw, NULs kept) for the transcription
  for (const sc of scenarios) {
    for (const rec of [sc.initial].concat(sc.steps.map(s => s.record))) {
      rec.brushes.forEach(b => b.covers.forEach(cv => { cv._panelRaw = cv.panelId == null ? null : cv.panelId.split('<NUL>').join('\u0000'); }));
      rec.events.forEach(ev => { ev._areas = ev._raw || []; });
      void rec;
    }
  }
  const base = {};
  for (const id of Object.keys(checks)) {
    mut = {};
    base[id] = checkScenario(checks[id].sc, checks[id].def);
    must(base[id].length === 0, 'the transcription disagrees: ' + base[id].slice(0, 5).join('; '));
  }
  const guards = GUARDS.map(g => {
    mut = g.set;
    const changed = [];
    for (const id of Object.keys(checks)) if (checkScenario(checks[id].sc, checks[id].def).length) changed.push(id);
    mut = {};
    return { id: g.id, mutation: g.mutation, named: g.named, changed, ok: g.named.every(n => changed.includes(n)) };
  });
  // the anchors
  const byId = id => scenarios.find(s => s.id === id);
  const rd = byId('R-DRAW');
  must(rd.steps.some(s => s.record.brushes[0].covers.length === 1), 'R-DRAW draws no cover');
  must(rd.steps.some(s => s.record.cursor === 'crosshair'), 'R-DRAW shows no crosshair');
  for (const c of ['move', 'ew-resize', 'ns-resize', 'nwse-resize', 'nesw-resize']) must(rd.steps.some(s => s.record.cursor === c), 'R-DRAW never shows ' + c);
  const rr = byId('R-REMOVE');
  must(rr.steps.some(s => s.record.events.some(e => e.type === 'brush' && e.areas.length === 0)), 'R-REMOVE never clears');
  const tf = byId('TH-FIXRATE');
  must(tf._calls.filter(c => c.kind === 'exec').length < tf._calls.filter(c => c.kind === 'call').length, 'TH-FIXRATE defers nothing');
  // strip the private fields; the panels only when they changed
  for (const sc of scenarios) {
    let last = null;
    for (const rec of [sc.initial].concat(sc.steps.map(s => s.record))) {
      const pj = JSON.stringify(rec.panels.map(p => (p ? p.map(q => ({ panelId: q.panelId, rect: q.rect })) : null)));
      rec.panels = pj === last ? null : JSON.parse(pj);
      last = pj;
      rec.brushes.forEach(b => {
        delete b._areas;
        b.covers.forEach(cv => { delete cv._range; delete cv._lineWidth; delete cv._shapes; delete cv._panelRaw; });
      });
      rec.events.forEach(ev => { delete ev._areas; delete ev._raw; });
      delete rec._drag;
      delete rec._newCovers;
    }
    // a brush's state: written when it changed
    let prevB = [];
    for (const rec of [sc.initial].concat(sc.steps.map(s => s.record))) {
      rec.brushes = rec.brushes.map((b, bi) => {
        const j = JSON.stringify(b);
        if (prevB[bi] === j) return null;
        prevB[bi] = j;
        return b;
      });
    }
    sc._chart.dispose();
    delete sc._chart;
    delete sc._calls;
    delete sc._layout;
  }
  return {
    out: {
      source: 'ECharts 6.1 dist (' + path.basename(DIST) + '), node SSR, SVG renderer',
      W, H, clock: { start: CLOCK0, pointerDt: 200, clickDt: 0, idleDt: 1000 },
      notes: NOTES, scenarios, guards,
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
const nSelects = out.scenarios.reduce((n, s) => n + s.steps.reduce((m, st) => m + st.record.selects.length, 0), 0);
console.log(out.scenarios.length + ' scenarios, ' + nSteps + ' steps, ' + nActions + ' actions, ' + nEvents + ' events, ' + nSelects + ' brushSelects; '
  + (out.guards.length - bad.length) + '/' + out.guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT')
  + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
