// Upstream's own answers for the BRUSH component's selection (C18, batch
// 127): which data items a cover selects on every series type that has a
// brushSelector (scatter, effectScatter, bar, candlestick -- point and rect
// selectors against rect, polygon, lineX and lineY areas), how brushLink
// ('all' or series indices) spreads a selection by data index, the
// inBrush / outOfBrush visuals that land on every item (colour, opacity,
// symbol, symbolSize, liftZ, colorAlpha) and what the views draw from them,
// the brushselected event's batch after every action that runs the visual
// stage (an empty batch without a brush component), the toolbox's brush
// buttons and the preprocessor that adds them, the globalPan mutex that
// stops an inside dataZoom and a graph's roam from panning while brushing,
// and onIrrelevantElement (a press on another coordinate system's element
// drawn over the panel starts no cover).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 600 x 400 and
// drives zrender's own Handler with synthetic events, as brush-cover.js
// does. Time is fake (Date and setTimeout replaced; the clock starts at
// 1700000000000 and moves 200 ms before every pointer event unless the step
// says otherwise, 0 before a click, 1000 for idle). Every option has
// `animation: false`.
//
//   node tools/advchart-oracle/brush-select.js
//
// writes tests/fixtures/advchart-brush-select.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (NaN 7ff8000000000000); a range keeps its nesting.
//   NUL      no string holds U+0000: a model id's NULs are written '<NUL>'.
//   colour   {css, r, g, b, a} -- css as upstream holds it, r g b integers and
//            a (hex) as zrender's color.parse reads it; null for none.
//
// Top level
//   source, W, H, clock, notes[], scenarios[], guards[]
// A scenario
//   id, note, option, initial (a record), steps[] {i, step (as run: x / y
//   resolved for a step that names a toolbox icon), record}
// A record
//   brushes[]  per brush component: {brushType (the model's, null when off),
//              brushMode (its brushOption's, null), areas [{brushType,
//              panelId, range}]}
//   series[]   per series (null when the same as the record before's):
//              {index, type, filtered, drawType, rows [{i (data index), raw,
//              fill, opacity, symbol, symbolSize, liftZ, drawn}]}; fill is
//              getItemVisual(i, 'style')[drawType]; drawn what the view drew:
//              a symbol {fill, opacity, scaleX, scaleY, symbolType}, a rect or
//              a candle {fill, stroke, opacity}, null for none, {states}
//              for an element in a state (not read)
//   toolbox    null when unchanged; else [{feature, name, title, status
//              (iconStatus), emph (in the emphasis state), rect [x, y, w, h]
//              (the icon's rect on the canvas, hex)}] for every icon
//   options    null when unchanged; else {toolbox: [{features [names],
//              brushType (the brush feature's type list | null)}]}
//   cursor     the last proxy.setCursor of the step, or null
//   zoom       null when unchanged; else [{start, end}] (hex) per dataZoom
//   events[]   in the order they fired: {type} plus, for brushselected,
//              batch [{brushId, brushIndex, brushName, areas [{brushType,
//              range}], selected [{seriesId, seriesIndex, seriesName,
//              dataIndex [...]}]}]; for brush / brushend: areas; for
//              globalcursortaken: key, brushOption
//   error      null | an exception's message
//
// Self-checks (any failure: nothing is written, exit 1). A transcription,
// recomputed and compared with the records:
//   S1 every brushselected batch from the areas (range), the items' layouts
//      (getItemLayout, read privately) through the point / rect selectors,
//      controlSeries, seriesIndex and brushLink;
//   S2 every item's visuals from its state (inBrush / outOfBrush through
//      the fixed mappings, prepareVisualTypes' order) over the visual it had
//      with no brush;
//   S3 the brush feature's icon statuses from the brush models;
//   S4 the preprocessor's toolbox type list from the option.
// guards[] mutate the transcription one way each and name the scenarios
// that must notice; anchors; no U+0000; the written JSON parses back; two
// generations give the same bytes.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-brush-select.json');
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
function colour(c) {
  if (c == null) return null;
  if (typeof c !== 'string') return { css: '@object', r: 0, g: 0, b: 0, a: hex(0) };
  if (c === 'none') return { css: 'none', r: 0, g: 0, b: 0, a: hex(0) };
  const p = echarts.color.parse(c);
  must(p, 'an unparsable colour ' + c);
  return { css: c, r: p[0], g: p[1], b: p[2], a: hex(p[3]) };
}
const numOrNull = v => (v == null ? null : hex(+v));

// =====================================================================
// Recording
// =====================================================================
function brushModels(chart) {
  const out = [];
  chart.getModel().eachComponent('brush', m => out.push(m));
  return out;
}
function brushRec(m) {
  return {
    brushType: m.brushType ? m.brushType : null,
    brushMode: m.brushOption && m.brushOption.brushMode ? m.brushOption.brushMode : null,
    areas: m.areas.map(a => ({ brushType: a.brushType, panelId: nul(a.panelId), range: a.range == null ? null : hexDeep(a.range) })),
  };
}
function findSymbolPath(el) {
  if (!el) return null;
  if (el.shape && el.shape.symbolType != null) return el;
  if (el.childAt) {
    for (let k = 0; k < el.childCount(); k++) {
      const r = findSymbolPath(el.childAt(k));
      if (r) return r;
    }
  }
  return null;
}
// a style key in the element's normal state (a hovered element's style holds
// its emphasis; zrender keeps what the state replaced in _normalState)
function normalStyle(el, key) {
  const ns = el._normalState;
  if (el.currentStates && el.currentStates.length && ns && ns.style && Object.prototype.hasOwnProperty.call(ns.style, key)) return ns.style[key];
  return el.style[key];
}
function normalProp(el, key) {
  const ns = el._normalState;
  if (el.currentStates && el.currentStates.length && ns && Object.prototype.hasOwnProperty.call(ns, key)) return ns[key];
  return el[key];
}
// an element in a state (a hover's emphasis, a highlight) is not read: a
// re-render while it is in one writes the new visual into its style and
// leaves the old one in _normalState, which the leave restores
function drawnOf(type, el) {
  if (!el) return null;
  if (type === 'scatter' || type === 'effectScatter' || type === 'line' || type === 'graph') {
    const p = findSymbolPath(el);
    if (!p) return null;
    if ((p.currentStates && p.currentStates.length) || (el.currentStates && el.currentStates.length)) {
      return { states: (p.currentStates || []).concat(el.currentStates || []) };
    }
    return { fill: colour(normalStyle(p, 'fill')), opacity: numOrNull(normalStyle(p, 'opacity')), scaleX: hex(normalProp(p, 'scaleX')),
      scaleY: hex(normalProp(p, 'scaleY')), symbolType: p.shape.symbolType };
  }
  if (!el.style) return null;
  if (el.currentStates && el.currentStates.length) return { states: el.currentStates.slice() };
  return { fill: colour(normalStyle(el, 'fill')), stroke: colour(normalStyle(el, 'stroke')), opacity: numOrNull(normalStyle(el, 'opacity')) };
}
function layoutOf(type, data, i) {
  const l = data.getItemLayout(i);
  if (l == null) return null;
  if (type === 'candlestick') return l.brushRect ? { x: l.brushRect.x, y: l.brushRect.y, width: l.brushRect.width, height: l.brushRect.height } : null;
  if (Array.isArray(l)) return [l[0], l[1]];
  if (typeof l.x === 'number') return { x: l.x, y: l.y, width: l.width, height: l.height };
  return { other: true };
}
function seriesRec(chart, sm) {
  const type = sm.subType;
  const ecModel = chart.getModel();
  const rec = { index: sm.seriesIndex, type, filtered: ecModel.isSeriesFiltered(sm), drawType: null, rows: [] };
  if (rec.filtered) return rec;
  const data = sm.getData();
  const drawType = data.getVisual('drawType');
  rec.drawType = drawType;
  const ss = n => (n == null ? null : Array.isArray(n) ? n.map(x => hex(+x)) : hex(+n));
  for (let i = 0; i < data.count(); i++) {
    const st = data.getItemVisual(i, 'style') || {};
    rec.rows.push({
      i, raw: data.getRawIndex(i), fill: colour(st[drawType]), opacity: numOrNull(st.opacity),
      symbol: (() => { const s = data.getItemVisual(i, 'symbol'); return s == null ? null : String(s); })(),
      symbolSize: ss(data.getItemVisual(i, 'symbolSize')), liftZ: numOrNull(data.getItemVisual(i, 'liftZ')),
      drawn: drawnOf(type, data.getItemGraphicEl(i)),
      _layout: layoutOf(type, data, i),
    });
  }
  // the coordinate system the transcription asks controlSeries about
  const cs = sm.coordinateSystem;
  rec._grid = cs && cs.type === 'cartesian2d' ? cs.master.model.id : null;
  rec._large = !!(sm.pipelineContext && sm.pipelineContext.large);
  return rec;
}
function featureOf(view, p) {
  let f = null;
  view._features && view._features.each((feat, name) => {
    if (feat && feat.model && feat.model.iconPaths) {
      for (const k of Object.keys(feat.model.iconPaths)) if (feat.model.iconPaths[k] === p) f = { name, icon: k, feat };
    }
  });
  return f;
}
function toolboxRec(chart) {
  const out = [];
  chart.getModel().eachComponent('toolbox', m => {
    const v = chart.getViewOfComponentModel(m);
    if (!v || !m.get('show')) return;
    for (const c of v.group.children()) {
      if (c.type === 'rect' && c.silent) continue;
      const f = featureOf(v, c);
      if (!f) continue;
      const r = c.getBoundingRect();
      const st = (f.feat.model.option.iconStatus || {})[f.icon];
      out.push({
        toolbox: m.componentIndex, feature: f.name, name: f.icon, title: c.__title == null ? null : c.__title,
        status: st == null ? null : st, emph: c.currentStates.indexOf('emphasis') >= 0,
        rect: [hex(v.group.x + c.x + r.x), hex(v.group.y + c.y + r.y), hex(r.width), hex(r.height)],
      });
    }
  });
  return out;
}
function optionsRec(chart) {
  const o = chart.getOption();
  return {
    toolbox: (o.toolbox || []).map(t => ({
      features: Object.keys(t.feature || {}),
      brushType: t.feature && t.feature.brush && t.feature.brush.type ? t.feature.brush.type.map(String) : null,
    })),
  };
}
function zoomRec(chart) {
  const out = [];
  chart.getModel().eachComponent('dataZoom', m => {
    const p = m.getPercentRange();
    out.push({ start: hex(p[0]), end: hex(p[1]) });
  });
  return out;
}

function makeCtx(chart) {
  const ctx = { chart, zr: chart.getZr(), h: chart.getZr().handler, cursor: null, events: [] };
  ctx.iconCentre = (feature, icon) => {
    let found = null;
    chart.getModel().eachComponent('toolbox', m => {
      const v = chart.getViewOfComponentModel(m);
      for (const c of v.group.children()) {
        const f = featureOf(v, c);
        if (f && f.name === feature && f.icon === icon && !found) {
          const r = c.getBoundingRect();
          found = [Math.round(v.group.x + c.x + r.x + r.width / 2), Math.round(v.group.y + c.y + r.y + r.height / 2)];
        }
      }
    });
    must(found, 'no icon ' + feature + '.' + icon);
    return found;
  };
  // the centre of series s's data item i, rounded
  ctx.itemCentre = (s, i) => {
    const sm = chart.getModel().getSeriesByIndex(s);
    const l = sm.getData().getItemLayout(i);
    must(Array.isArray(l), 'no point layout');
    return [Math.round(l[0]), Math.round(l[1])];
  };
  return ctx;
}
function eventRaw(type, x, y, extra) {
  return Object.assign({ type, zrX: x, zrY: y, which: 1, shiftKey: false, ctrlKey: false, altKey: false, cancelBubble: false, preventDefault() {}, stopPropagation() {} }, extra || {});
}
const EVENT_TYPES = ['brush', 'brushend', 'brushselected', 'globalcursortaken', 'datazoom', 'legendselectchanged', 'restore',
  'axisareaselected', 'graphroam', 'selectchanged', 'highlight', 'downplay'];

function areaBrief(a) {
  return { brushType: a.brushType, range: a.range == null ? null : hexDeep(a.range) };
}
function eventRec(type, p) {
  const o = { type };
  if (type === 'brushselected') {
    o.batch = (p.batch || []).map(b => ({
      brushId: nul(b.brushId), brushIndex: b.brushIndex, brushName: nul(b.brushName),
      areas: (b.areas || []).map(areaBrief),
      // milestone D5-D8: the areas as the event holds them, every key in order
      areasFull: (b.areas || []).map(a => clean(a)),
      selected: (b.selected || []).map(s => ({ seriesId: nul(s.seriesId), seriesIndex: s.seriesIndex, seriesName: nul(s.seriesName), dataIndex: s.dataIndex.slice() })),
    }));
    o._raw = (p.batch || []).map(b => ({ areas: JSON.parse(JSON.stringify(b.areas || [])), brushIndex: b.brushIndex }));
  } else if (type === 'brush' || type === 'brushend') {
    o.areas = (p.areas || []).map(areaBrief);
    o.areasFull = (p.areas || []).map(a => clean(a));
  } else if (type === 'globalcursortaken') {
    o.key = clean(p.key);
    o.brushOption = p.brushOption === undefined ? null : clean(p.brushOption);
  }
  return o;
}

function snapshot(ctx, error) {
  const chart = ctx.chart;
  ctx.zr.storage.getDisplayList(true);
  const ecModel = chart.getModel();
  const series = [];
  ecModel.eachRawSeries(sm => series.push(seriesRec(chart, sm)));
  return {
    brushes: brushModels(chart).map(brushRec),
    series,
    toolbox: toolboxRec(chart),
    options: optionsRec(chart),
    cursor: ctx.cursor,
    zoom: zoomRec(chart),
    events: ctx.events,
    error,
    // what the transcription reads
    _brushOpts: brushModels(chart).map(m => ({
      id: m.id, option: JSON.parse(JSON.stringify(m.option, (k, v) => (k === 'brushTargetManager' ? undefined : v))),
      areas: m.areas.map(a => JSON.parse(JSON.stringify(a))), brushType: m.brushType || null,
      brushMode: (m.brushOption && m.brushOption.brushMode) || 'single',
    })),
  };
}

// upstream's default palette, written into every option: the port's own
// default is its skin's, and the colours the brush derives (colorAlpha,
// colorLightness) start from the series colour
const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
function withPalette(option) {
  return Object.assign({ color: PALETTE }, option);
}

function runScenario(def) {
  NOW = CLOCK0;
  TIMERS = [];
  def.option = withPalette(def.option);
  for (const st of def.steps) if (st.type === 'set' && st.notMerge) st.option = withPalette(st.option);
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    const ctx = makeCtx(chart);
    ctx.h.proxy.setCursor = c => { ctx.cursor = c; };
    EVENT_TYPES.forEach(t => chart.on(t, p => ctx.events.push(eventRec(t, p))));
    chart.setOption(JSON.parse(JSON.stringify(def.option)));
    ctx.zr.storage.getDisplayList(true);
    const initial = snapshot(ctx, null);
    const recs = [];
    const steps = def.steps.concat([{ type: 'idle' }]);
    steps.forEach((st, i) => {
      ctx.cursor = null;
      ctx.events = [];
      let error = null;
      const dt = st.dt != null ? st.dt : st.type === 'click' ? 0 : st.type === 'idle' ? 1000 : 200;
      advanceClock(NOW + dt);
      ctx.zr.storage.getDisplayList(true);
      const out = { i, step: Object.assign({}, st, { dt }) };
      try {
        if (['mousemove', 'mousedown', 'mouseup', 'click'].includes(st.type)) {
          let p;
          if (st.icon) p = ctx.iconCentre(st.icon[0], st.icon[1]);
          else if (st.item) p = ctx.itemCentre(st.item[0], st.item[1]);
          else p = [st.x, st.y];
          out.step.x = p[0];
          out.step.y = p[1];
          delete out.step.icon;
          delete out.step.item;
          ctx.h[st.type](eventRaw(st.type, p[0], p[1]));
        } else if (st.type === 'action') {
          if (st.payloadFn) {
            out.step.payload = st.payloadFn(chart);
            delete out.step.payloadFn;
          }
          chart.dispatchAction(JSON.parse(JSON.stringify(out.step.payload)));
        } else if (st.type === 'set') {
          chart.setOption(JSON.parse(JSON.stringify(st.option)), !!st.notMerge);
        }
      } catch (e) {
        if (e instanceof OracleError) throw e;
        error = String(e.message);
      }
      ctx.zr.storage.getDisplayList(true);
      out.record = snapshot(ctx, error);
      recs.push(out);
    });
    return { id: def.id, note: def.note, option: def.option, initial, steps: recs, _chart: chart };
  } catch (e) {
    chart.dispose();
    throw e;
  }
}

// ---------- the scenarios ----------
const CATS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const BARS = [120, 200, 150, 80, 70, 110, 130];
const PTS = [[1.5, 2.25], [3.75, 8.125], [7.3, 4.4], [9.9, 0.5], [5.55, 6.66], [2.2, 5.1], [6.1, 1.9], [8.4, 7.7], [4.05, 3.3], [0.6, 9.4]];
const take = (brushType, brushMode) => ({ type: 'action', payload: { type: 'takeGlobalCursor', key: 'brush', brushOption: { brushType, brushMode: brushMode || 'single' } } });
const drag = (x0, y0, x1, y1) => [
  { type: 'mousemove', x: x0, y: y0 }, { type: 'mousedown', x: x0, y: y0 },
  { type: 'mousemove', x: Math.round((x0 + x1) / 2), y: Math.round((y0 + y1) / 2) },
  { type: 'mousemove', x: x1, y: y1 }, { type: 'mouseup', x: x1, y: y1 }, { type: 'click', x: x1, y: y1 },
];
const poly = pts => [].concat([{ type: 'mousemove', x: pts[0][0], y: pts[0][1] }, { type: 'mousedown', x: pts[0][0], y: pts[0][1] }],
  pts.slice(1).map(p => ({ type: 'mousemove', x: p[0], y: p[1] })),
  [{ type: 'mouseup', x: pts[pts.length - 1][0], y: pts[pts.length - 1][1] }, { type: 'click', x: pts[pts.length - 1][0], y: pts[pts.length - 1][1] }]);
const icon = (feature, name) => [{ type: 'mousemove', icon: [feature, name] }, { type: 'mousedown', icon: [feature, name] },
  { type: 'mouseup', icon: [feature, name] }, { type: 'click', icon: [feature, name] }];
const valChart = extra => Object.assign({
  animation: false, xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: [{ type: 'scatter', name: 'Pts', data: PTS }],
}, extra || {});
const catChart = extra => Object.assign({
  animation: false, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
  series: [{ type: 'bar', name: 'Bars', data: BARS }],
}, extra || {});
const CANDLES = [[20, 34, 10, 38], [40, 35, 30, 50], [31, 38, 33, 44], [38, 15, 5, 42], [15, 25, 12, 30], [25, 22, 18, 36], [22, 30, 20, 33], [30, 28, 26, 40]];

// a global rect (a pixel range, no finder) whose right edge is exactly the
// left edge of series s's bar i: it touches the bar and overlaps nothing of it
const touchBar = (s, i) => chart => {
  const l = chart.getModel().getSeriesByIndex(s).getData().getItemLayout(i);
  const y0 = Math.min(l.y, l.y + l.height);
  const y1 = Math.max(l.y, l.y + l.height);
  return { type: 'brush', areas: [{ brushType: 'rect', range: [[l.x - 6, l.x], [y0 + 2, y1 - 2]] }] };
};

const SCENARIOS = [
  {
    id: 'S-SCATTER', note: 'a scatter on value axes: rect, a moved rect, polygon, lineX and lineY select by the point selector; the default visuals (out of brush the disabled colour, in it liftZ 5)',
    option: valChart({ brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('rect')], drag(150, 90, 330, 250), [take('polygon')], poly([[120, 300], [300, 80], [480, 200], [400, 320]]),
      [take('lineX')], drag(250, 200, 420, 210), [take('lineY')], drag(300, 120, 310, 260)),
  },
  {
    id: 'S-BAR', note: 'vertical bars: a rect touching some bars, a polygon crossing them (its edges against the bars), lineX, lineY over the bars\' lengths',
    option: catChart({ series: [{ type: 'bar', name: 'Bars', data: BARS }, { type: 'bar', name: 'More', data: [60, 90, 40, 130, 100, 50, 75] }], brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('rect')], drag(130, 100, 280, 230), [take('polygon')], poly([[300, 120], [420, 140], [380, 260], [320, 300]]),
      [take('lineX')], drag(420, 150, 520, 150), [take('lineY')], drag(100, 140, 100, 180),
      [take('polygon')], poly([[120, 200], [210, 205], [120, 210]]),
      [{ type: 'action', payloadFn: touchBar(0, 2) }]),
  },
  {
    id: 'S-HBAR', note: 'horizontal bars on a category y axis: lineY and rect',
    option: {
      animation: false, xAxis: { type: 'value' }, yAxis: { type: 'category', data: CATS },
      series: [{ type: 'bar', data: BARS }], brush: { yAxisIndex: 0 },
    },
    steps: [].concat([take('lineY')], drag(200, 100, 260, 200), [take('rect')], drag(330, 150, 500, 320)),
  },
  {
    id: 'S-CANDLE', note: 'a candlestick: lineX, rect, polygon against its brushRect (lowest to highest, a candle wide)',
    option: {
      animation: false, xAxis: { type: 'category', data: CATS.concat(['Mon2']) }, yAxis: { type: 'value', scale: true },
      series: [{ type: 'candlestick', data: CANDLES, itemStyle: { color: '#eb5454', color0: '#47b262', borderColor: '#eb5454', borderColor0: '#47b262' } }],
      brush: { xAxisIndex: 0 },
    },
    steps: [].concat([take('lineX')], drag(160, 200, 300, 200), [take('rect')], drag(320, 80, 470, 160),
      [take('polygon')], poly([[80, 300], [200, 100], [260, 310]])),
  },
  {
    id: 'S-MIXED', note: 'no finder (the global panel): an effectScatter selected, a line (no brushSelector) and a pie (no coordinate system) not',
    option: {
      animation: false, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [
        { type: 'effectScatter', name: 'Fx', data: PTS.slice(0, 6), rippleEffect: { number: 1 } },
        { type: 'line', name: 'Ln', data: [[1, 1], [3, 4], [5, 2], [7, 6], [9, 3]] },
        { type: 'pie', name: 'Pie', center: [500, 90], radius: 40, data: [{ name: 'a', value: 3 }, { name: 'b', value: 5 }] },
      ],
      brush: {},
    },
    steps: [].concat([take('rect')], drag(60, 60, 400, 330), drag(380, 30, 560, 150)),
  },
  {
    id: 'S-VISUALS', note: 'inBrush / outOfBrush written: colour, opacity, symbol, symbolSize, colorAlpha; a merge that writes outOfBrush drops inBrush (replaceVisualOption); seriesIndex',
    option: {
      animation: false, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'scatter', name: 'A', symbolSize: 10, data: PTS }, { type: 'scatter', name: 'B', data: PTS.map(p => [p[0] + 0.3, p[1] - 0.4]) }],
      brush: {
        xAxisIndex: 0,
        inBrush: { color: '#ff0000', symbolSize: 20, opacity: 0.9, symbol: 'diamond' },
        outOfBrush: { colorAlpha: 0.2, symbolSize: [6, 30] },
      },
    },
    steps: [].concat([take('rect')], drag(150, 90, 380, 260),
      [{ type: 'set', option: { brush: { outOfBrush: { color: ['#00ff00', '#0000ff'], opacity: 0.5 } } } }],
      [{ type: 'set', option: { brush: { seriesIndex: [1] } } }],
      [{ type: 'set', option: { brush: { seriesIndex: 'all', inBrush: { colorLightness: 0.3, liftZ: 9 } } } }]),
  },
  {
    id: 'S-TWOGRIDS', note: "two grids, xAxisIndex 'all': a cover in the left grid controls only the series on it",
    option: {
      animation: false,
      grid: [{ left: 50, right: 330, top: 60, bottom: 60 }, { left: 330, right: 40, top: 60, bottom: 60 }],
      xAxis: [{ type: 'value', gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
      yAxis: [{ type: 'value', gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
      series: [{ type: 'scatter', name: 'L', data: PTS }, { type: 'scatter', name: 'R', xAxisIndex: 1, yAxisIndex: 1, data: PTS }],
      brush: { xAxisIndex: 'all' },
    },
    steps: [].concat([take('lineY')], drag(100, 100, 120, 300), drag(400, 120, 420, 250)),
  },
  {
    id: 'S-FILTERED', note: 'a slider dataZoom filters the scatter: the selected indices are the raw ones of the items left',
    option: valChart({ dataZoom: [{ type: 'slider', xAxisIndex: 0, start: 20, end: 85 }], brush: { xAxisIndex: 0 } }),
    steps: [].concat([take('rect')], drag(70, 70, 530, 320)),
  },
  {
    id: 'L-ALL', note: "brushLink 'all': a scatter's selection spreads by data index to a bar and a line (whose symbols take the visuals)",
    option: catChart({
      series: [
        { type: 'bar', name: 'Bars', data: BARS },
        { type: 'scatter', name: 'Dots', data: [90, 40, 170, 60, 140, 30, 100] },
        { type: 'line', name: 'Line', data: [50, 70, 60, 90, 80, 100, 95] },
      ],
      brush: { xAxisIndex: 0, brushLink: 'all', inBrush: { opacity: 1 }, outOfBrush: { opacity: 0.25 } },
    }),
    steps: [].concat([take('rect')], drag(200, 80, 380, 200), drag(380, 290, 540, 320)),
  },
  {
    id: 'L-INDICES', note: 'brushLink [0, 2]: series 1 checks its own items; two brush components (the batch has both; the first one\'s throttle)',
    option: {
      animation: false,
      grid: [{ left: 50, right: 330, top: 60, bottom: 60 }, { left: 330, right: 40, top: 60, bottom: 60 }],
      xAxis: [{ type: 'category', data: CATS, gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
      yAxis: [{ type: 'value', gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
      series: [
        { type: 'bar', name: 'B0', data: BARS },
        { type: 'bar', name: 'B1', data: [60, 90, 40, 130, 100, 50, 75] },
        { type: 'scatter', name: 'S2', xAxisIndex: 1, yAxisIndex: 1, data: PTS.slice(0, 7) },
      ],
      brush: [{ xAxisIndex: 0, brushLink: [0, 2] }, { xAxisIndex: 1, throttleType: 'debounce', throttleDelay: 500 }],
    },
    steps: [].concat([take('lineX')], drag(100, 150, 190, 150), drag(400, 150, 480, 150)),
  },
  {
    id: 'E-ACTIONS', note: 'no brush component: every action that runs the visual stage fires brushselected with an empty batch; setOption, highlight and select do not',
    option: catChart({ legend: {}, series: [{ type: 'bar', name: 'Bars', data: BARS }, { type: 'line', name: 'Line', data: [50, 70, 60, 90, 80, 100, 95] }], toolbox: { feature: { restore: {} } } }),
    steps: [
      { type: 'action', payload: { type: 'legendToggleSelect', name: 'Line' } },
      { type: 'action', payload: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } },
      { type: 'action', payload: { type: 'select', seriesIndex: 0, dataIndex: 2 } },
      { type: 'set', option: { yAxis: { max: 300 } } },
      { type: 'action', payload: { type: 'takeGlobalCursor', key: 'dataZoomSelect', dataZoomSelectActive: false } },
      { type: 'action', payload: { type: 'restore' } },
      { type: 'action', payload: { type: 'brushEnd', areas: [] } },
    ],
  },
  {
    id: 'E-SEQUENCE', note: 'debounce 300: the batch is the latest call\'s; a brush action from coordRange; a legend toggle hides a series, which leaves the batch',
    option: catChart({
      legend: {},
      series: [{ type: 'bar', name: 'Bars', data: BARS }, { type: 'bar', name: 'More', data: [60, 90, 40, 130, 100, 50, 75] }],
      brush: { xAxisIndex: 0, throttleType: 'debounce', throttleDelay: 300 },
    }),
    steps: [].concat([take('rect')], drag(130, 100, 380, 300), [{ type: 'idle' }],
      [{ type: 'action', payload: { type: 'brush', areas: [{ brushType: 'lineX', xAxisIndex: 0, coordRange: [2, 4] }] } }, { type: 'idle' }],
      [{ type: 'action', payload: { type: 'legendToggleSelect', name: 'More' } }, { type: 'idle' }],
      [{ type: 'action', payload: { type: 'brush', areas: [] } }]),
  },
  {
    id: 'T-BUTTONS', note: 'the preprocessor adds a toolbox with rect, polygon, keep and clear: rect on, a cover, keep (multiple), a second cover, polygon, clear, rect off',
    option: catChart({ brush: { xAxisIndex: 0 } }),
    steps: [].concat(icon('brush', 'rect'), drag(130, 100, 260, 220), icon('brush', 'keep'), drag(300, 150, 420, 300),
      icon('brush', 'polygon'), poly([[440, 120], [520, 160], [470, 300]]), icon('brush', 'clear'), icon('brush', 'polygon'), icon('brush', 'polygon')),
  },
  {
    id: 'T-OWN', note: "a brush's own toolbox list added to the author's toolbox: lineX, lineY, clear beside saveAsImage",
    option: catChart({ toolbox: { feature: { saveAsImage: {} } }, brush: { xAxisIndex: 0, toolbox: ['lineX', 'lineY', 'clear'] } }),
    steps: [].concat(icon('brush', 'lineX'), drag(150, 200, 330, 200), icon('brush', 'lineY'), drag(200, 120, 200, 200), icon('brush', 'clear')),
  },
  {
    id: 'T-MERGE', note: 'a merge that brings a brush: the toolbox it adds has no buttons (not new); a notMerge does; a written type list deduplicated',
    option: catChart(),
    steps: [
      { type: 'set', option: { brush: { xAxisIndex: 0 } } },
      { type: 'set', notMerge: true, option: catChart({ brush: { xAxisIndex: 0, toolbox: [] } }) },
      { type: 'set', notMerge: true, option: catChart({ toolbox: { feature: { brush: { type: ['rect', 'clear', 'rect'] } } }, brush: [{ toolbox: ['lineY'] }, { toolbox: ['clear', 'lineX'] }] }) },
    ],
  },
  {
    id: 'G-INSIDE', note: 'an inside dataZoom pans until the brush takes globalPan; brushing draws a cover and pans nothing; off again, it pans',
    option: valChart({ dataZoom: [{ type: 'inside', xAxisIndex: 0, start: 20, end: 60 }], brush: { xAxisIndex: 0 } }),
    steps: [].concat(drag(300, 200, 360, 200), [take('rect')], drag(200, 120, 330, 260),
      [{ type: 'action', payload: { type: 'takeGlobalCursor', key: 'brush', brushOption: { brushType: false } } }], drag(450, 300, 390, 310)),
  },
  {
    id: 'G-ROAM', note: "a graph's roam pans until the brush takes globalPan",
    option: {
      animation: false,
      series: [{
        type: 'graph', layout: 'none', roam: true, symbolSize: 20,
        data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 50 }, { name: 'c', x: 50, y: 120 }],
        links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }],
      }],
      brush: {},
    },
    steps: [].concat(drag(300, 210, 330, 230), [take('rect')], drag(300, 210, 360, 190),
      [{ type: 'action', payload: { type: 'takeGlobalCursor', key: 'brush', brushOption: { brushType: false } } }], drag(250, 150, 200, 140)),
  },
  {
    id: 'I-IRRELEVANT', note: "a scatter on another grid drawn over the brush's panel: a press on its symbol starts no cover and gets no crosshair; once the panel's grid is higher it does",
    option: {
      animation: false,
      grid: [{}, { left: 380, top: 80, width: 140, height: 100 }],
      xAxis: [{ type: 'category', data: CATS }, { type: 'value', gridIndex: 1, show: false }],
      yAxis: [{ type: 'value' }, { type: 'value', gridIndex: 1, show: false }],
      series: [{ type: 'bar', data: BARS }, { type: 'scatter', xAxisIndex: 1, yAxisIndex: 1, symbolSize: 24, data: [[1, 1], [3, 4], [5, 2]] }],
      brush: { xAxisIndex: 0 },
    },
    steps: [].concat([take('rect')],
      [{ type: 'mousemove', item: [1, 1] }, { type: 'mousedown', item: [1, 1] }, { type: 'mousemove', x: 300, y: 250 }, { type: 'mouseup', x: 300, y: 250 }],
      drag(400, 170, 250, 250),
      [{ type: 'set', option: { grid: [{ z: 5 }] } }],
      [{ type: 'mousemove', item: [1, 1] }, { type: 'mousedown', item: [1, 1] }, { type: 'mousemove', x: 300, y: 250 }, { type: 'mouseup', x: 300, y: 250 }]),
  },
];

const NOTES = [
  'Every option has animation false; the clock is fake.',
  'A step naming a toolbox icon points at its rect centre (rounded); one naming an item at its layout point (rounded).',
  'The rows are the data the series holds after its filter (data index i, raw index raw).',
  "Every option is given upstream's default palette (color), so the port, whose default is its skin's, starts from the same series colours.",
  'brushselected comes after the event of the action whose update ran the visual stage (the pending brushSelect is flushed after it).',
];

// =====================================================================
// The transcription (mutations as switches in `mut`)
// =====================================================================
let mut = {};
function rectOfMinMax(mm) {
  let x = mm[0][0];
  let y = mm[1][0];
  let w = mm[0][1] - mm[0][0];
  let h = mm[1][1] - mm[1][0];
  if (w < 0) { x += w; w = -w; }
  if (h < 0) { y += h; h = -h; }
  return { x, y, width: w, height: h };
}
function boundingOf(area) {
  if (area.brushType === 'rect') return rectOfMinMax(area.range);
  if (area.brushType === 'polygon') {
    let mm = null;
    for (const rg of area.range) {
      mm = mm || [[Infinity, -Infinity], [Infinity, -Infinity]];
      rg[0] < mm[0][0] && (mm[0][0] = rg[0]);
      rg[0] > mm[0][1] && (mm[0][1] = rg[0]);
      rg[1] < mm[1][0] && (mm[1][0] = rg[1]);
      rg[1] > mm[1][1] && (mm[1][1] = rg[1]);
    }
    return mm && rectOfMinMax(mm);
  }
  return undefined;
}
const rcontain = (r, x, y) => x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height;
function rintersect(a, b) {
  const n = r => {
    let { x, y, width: w, height: h } = r;
    if (w < 0) { x += w; w = -w; }
    if (h < 0) { y += h; h = -h; }
    return { x, y, width: w, height: h };
  };
  a = n(a);
  b = n(b);
  const ax0 = a.x; const ax1 = a.x + a.width; const ay0 = a.y; const ay1 = a.y + a.height;
  const bx0 = b.x; const bx1 = b.x + b.width; const by0 = b.y; const by1 = b.y + b.height;
  if (ax0 > ax1 || ay0 > ay1 || bx0 > bx1 || by0 > by1) return false;
  if (mut.strictIntersect) return !(ax1 <= bx0 || bx1 <= ax0 || ay1 <= by0 || by1 <= ay0);
  return !(ax1 < bx0 || bx1 < ax0 || ay1 < by0 || by1 < ay0);
}
function windingLine(x0, y0, x1, y1, x, y) {
  if ((y > y0 && y > y1) || (y < y0 && y < y1)) return 0;
  if (y1 === y0) return 0;
  const t = (y - y0) / (y1 - y0);
  let dir = y1 < y0 ? 1 : -1;
  if (t === 1 || t === 0) dir = y1 < y0 ? 0.5 : -0.5;
  const x_ = t * (x1 - x0) + x0;
  return x_ === x ? Infinity : x_ > x ? dir : 0;
}
function polyContain(points, x, y) {
  let w = 0;
  let p = points[0];
  if (!p) return false;
  for (let i = 1; i < points.length; i++) {
    const p2 = points[i];
    w += windingLine(p[0], p[1], p2[0], p2[1], x, y);
    p = p2;
  }
  const p0 = points[0];
  if (!(Math.abs(p[0] - p0[0]) < 1e-8) || !(Math.abs(p[1] - p0[1]) < 1e-8)) w += windingLine(p[0], p[1], p0[0], p0[1], x, y);
  return w !== 0;
}
function lineLine(a1x, a1y, a2x, a2y, b1x, b1y, b2x, b2y) {
  const mx = a2x - a1x; const my = a2y - a1y; const nx = b2x - b1x; const ny = b2y - b1y;
  const cross = (x1, y1, x2, y2) => x1 * y2 - x2 * y1;
  const nm = cross(nx, ny, mx, my);
  if (nm <= 1e-6 && nm >= -1e-6) return false;
  const bx = a1x - b1x; const by = a1y - b1y;
  const q = cross(bx, by, mx, my) / nm;
  if (q < 0 || q > 1) return false;
  const p = cross(bx, by, nx, ny) / nm;
  if (p < 0 || p > 1) return false;
  return true;
}
function linePoly(a1x, a1y, a2x, a2y, pts) {
  for (let i = 0, p2 = pts[pts.length - 1]; i < pts.length; i++) {
    const p = pts[i];
    if (lineLine(a1x, a1y, a2x, a2y, p[0], p[1], p2[0], p2[1])) return true;
    p2 = p;
  }
  return false;
}
const inLine = (p, r) => r[0] <= p && p <= r[1];
function selectPoint(area, l) {
  if (!l) return false;
  switch (area.brushType) {
    case 'rect': return rcontain(area._br, l[0], l[1]);
    case 'polygon': return rcontain(area._br, l[0], l[1]) && (mut.polyNoWinding ? true : polyContain(area.range, l[0], l[1]));
    case 'lineX': return inLine(l[0], area.range);
    case 'lineY': return inLine(l[1], area.range);
  }
  return false;
}
function selectRect(area, l) {
  if (!l) return false;
  if (area.brushType === 'rect') return rintersect(area._br, l);
  if (area.brushType === 'polygon') {
    const pts = area.range;
    if (pts.length <= 1) return false;
    const { x, y, width, height } = l;
    const p = pts[0];
    return polyContain(pts, x, y) || polyContain(pts, x + width, y) || polyContain(pts, x, y + height) || polyContain(pts, x + width, y + height)
      || rcontain(rectOfMinMax([[x, x + width], [y, y + height]]), p[0], p[1])
      || (!mut.noEdges && (linePoly(x, y, x + width, y, pts) || linePoly(x, y, x, y + height, pts)
        || linePoly(x + width, y, x + width, y + height, pts) || linePoly(x, y + height, x + width, y + height, pts)));
  }
  const xy = area.brushType === 'lineX' ? 0 : 1;
  const lr = xy === 0 ? [l.x, l.x + l.width] : [l.y, l.y + l.height];
  if (!mut.noReverse) lr[1] < lr[0] && lr.reverse();
  const r = area.range;
  return inLine(lr[0], r) || inLine(lr[1], r) || inLine(r[0], lr) || inLine(r[1], lr);
}
const SELECTOR_KIND = { scatter: 'point', effectScatter: 'point', bar: 'rect', candlestick: 'rect' };

// brushselected's batch for one record
function transcribeSelect(rec) {
  return rec._brushOpts.map((bo, bi) => {
    const opt = bo.option;
    const link = opt.brushLink;
    const linkOthers = s => link === 'all' || (Array.isArray(link) && link.indexOf(s) >= 0 && !mut.linkIgnored);
    const areas = bo.areas.map(a => Object.assign({}, a, { _br: boundingOf(a) }));
    const sidx = opt.seriesIndex;
    const notControl = s => sidx != null && sidx !== 'all' && (Array.isArray(sidx) ? sidx.indexOf(s) < 0 : s !== sidx);
    const live = rec.series.filter(s => !s.filtered);
    const linkSel = {};
    let hasBrush = false;
    const ranges = {};
    for (const s of live) {
      const list = ranges[s.index] = [];
      const kind = SELECTOR_KIND[s.type];
      if (!kind || notControl(s.index)) continue;
      for (const a of areas) {
        // controlSeries: the area's target grid, or every series
        const tgt = a.panelId && rec._targets[bi].includes(a.panelId);
        const ctrl = mut.noControl || !tgt || (s._grid != null && a.panelId === 'grid--' + s._grid);
        if (ctrl) list.push(a);
        hasBrush = hasBrush || list.length > 0;
      }
      if (linkOthers(s.index) && list.length) {
        for (const row of s.rows) if (checkIn(kind, list, row)) linkSel[row.i] = 1;
      }
    }
    const selected = live.map(s => {
      const kind = SELECTOR_KIND[s.type];
      const list = ranges[s.index];
      const dataIndex = [];
      const states = s.rows.map(row => {
        const inb = linkOthers(s.index) ? !!linkSel[row.i] : checkIn(kind, list, row);
        if (inb) dataIndex.push(row.raw);
        return inb;
      });
      const applies = linkOthers(s.index) ? hasBrush : list.length > 0;
      return { seriesIndex: s.index, dataIndex, states, applies };
    });
    return { brushIndex: bi, selected };
  });
}
function checkIn(kind, list, row) {
  if (!kind) return false;
  for (const a of list) {
    if (kind === 'point' ? selectPoint(a, row._layout) : selectRect(a, row._layout)) return true;
  }
  return false;
}

// S2: the visuals of a record's rows from the state and the base (the rows
// of the scenario with no area -- the initial record's)
function prepareTypes(obj) {
  const types = Object.keys(obj || {}).filter(k => ['color', 'colorHue', 'colorSaturation', 'colorLightness', 'colorAlpha', 'opacity', 'liftZ', 'symbol', 'symbolSize', 'decal'].includes(k));
  types.sort((t1, t2) => (t2 === 'color' && t1 !== 'color' && t1.indexOf('color') === 0 ? 1 : -1));
  return types;
}
function fixedOf(v) {
  return Array.isArray(v) ? v[0] : v;
}
function applyFixed(state, row, opt) {
  const vis = state ? opt.inBrush : opt.outOfBrush;
  const out = { fill: row.fill && row.fill.css, opacity: row.opacity, symbol: row.symbol, symbolSize: row.symbolSize, liftZ: row.liftZ };
  for (const t of prepareTypes(vis)) {
    const v = fixedOf(vis[t]);
    if (t === 'color') out.fill = v;
    else if (t === 'opacity') out.opacity = v == null ? null : hex(+v);
    else if (t === 'symbol') out.symbol = v == null ? null : String(v);
    else if (t === 'symbolSize') out.symbolSize = v == null ? null : hex(+v);
    else if (t === 'liftZ') out.liftZ = v == null ? null : hex(+v);
    else if (t === 'colorAlpha') out.fill = echarts.color.modifyAlpha(out.fill, v);
    else if (t === 'colorLightness') out.fill = echarts.color.modifyHSL(out.fill, null, null, v);
    else if (t === 'colorHue') out.fill = echarts.color.modifyHSL(out.fill, v);
    else if (t === 'colorSaturation') out.fill = echarts.color.modifyHSL(out.fill, null, v);
  }
  return out;
}

// S3: the brush feature's icon statuses
function transcribeStatus(rec) {
  let brushType;
  let brushMode;
  let isBrushed = false;
  for (const bo of rec._brushOpts) {
    brushType = bo.brushType || undefined;
    brushMode = bo.brushMode;
    isBrushed = isBrushed || bo.areas.length > 0;
  }
  const out = {};
  for (const t of ['rect', 'polygon', 'lineX', 'lineY', 'keep', 'clear']) {
    const on = t === 'keep' ? brushMode === 'multiple' : t === 'clear' ? (mut.clearAlwaysOff ? false : isBrushed) : t === brushType;
    out[t] = on ? 'emphasis' : 'normal';
  }
  return out;
}

// S4: the preprocessor's type list
function transcribePre(option, isNew, existing) {
  const brushes = option.brush == null ? [] : Array.isArray(option.brush) ? option.brush : [option.brush];
  if (!brushes.length) return existing;
  let spec = [];
  for (const b of brushes) {
    const tbs = Object.prototype.hasOwnProperty.call(b, 'toolbox') ? b.toolbox : [];
    if (Array.isArray(tbs)) spec = spec.concat(tbs);
  }
  let tb = option.toolbox;
  if (Array.isArray(tb)) tb = tb[0];
  const types = ((tb && tb.feature && tb.feature.brush && tb.feature.brush.type) || []).slice();
  types.push(...spec);
  const seen = {};
  let ded = types.filter(t => (seen[t + ''] ? false : (seen[t + ''] = 1)));
  if (mut.noDedupe) ded = types;
  if (isNew && !ded.length) ded = ['rect', 'polygon', 'keep', 'clear'];
  return ded;
}

function checkScenario(sc, def) {
  const diffs = [];
  const recs = [sc.initial].concat(sc.steps.map(s => s.record));
  const base = {};
  for (const s of sc.initial.series) base[s.index] = s;
  recs.forEach((rec, ri) => {
    const batch = transcribeSelect(rec);
    // S1 against the record's last brushselected (the state after the step)
    const evs = rec.events.filter(e => e.type === 'brushselected');
    const last = evs[evs.length - 1];
    if (last && last.batch.length && !rec._throttled) {
      last.batch.forEach((b, bi) => {
        const want = batch[bi];
        if (!want) return diffs.push(sc.id + ' @' + ri + ' a batch item too many');
        const got = b.selected.map(s => ({ seriesIndex: s.seriesIndex, dataIndex: s.dataIndex }));
        const exp = want.selected.map(s => ({ seriesIndex: s.seriesIndex, dataIndex: s.dataIndex }));
        if (JSON.stringify(got) !== JSON.stringify(exp)) diffs.push(sc.id + ' @' + ri + ' selected ' + JSON.stringify(got) + ' vs ' + JSON.stringify(exp));
      });
    }
    // S2: the rows of every series a brush applies to
    if (!def.noVisualCheck) {
      // every brush in component order over what the one before wrote
      for (const sr of rec.series) {
        if (sr.filtered) continue;
        const br = base[sr.index];
        let touched = false;
        sr.rows.forEach((row, k) => {
          const b0 = br.rows.find(q => q.raw === row.raw) || row;
          let cur = { fill: b0.fill, opacity: b0.opacity, symbol: b0.symbol, symbolSize: b0.symbolSize, liftZ: b0.liftZ };
          batch.forEach((b, bi) => {
            const s = b.selected.find(q => q.seriesIndex === sr.index);
            if (!s || !s.applies) return;
            touched = true;
            const w = applyFixed(s.states[k], cur, rec._brushOpts[bi].option);
            cur = { fill: w.fill == null ? null : { css: w.fill }, opacity: w.opacity, symbol: w.symbol, symbolSize: w.symbolSize, liftZ: w.liftZ };
          });
          if (!touched) return;
          const want = { fill: cur.fill && cur.fill.css, opacity: cur.opacity, symbol: cur.symbol, symbolSize: cur.symbolSize, liftZ: cur.liftZ };
          const got = { fill: row.fill && row.fill.css, opacity: row.opacity, symbol: row.symbol, symbolSize: row.symbolSize, liftZ: row.liftZ };
          for (const key of Object.keys(want)) {
            const gw = JSON.stringify(got[key]);
            const ww = JSON.stringify(want[key]);
            if (key === 'symbolSize' && Array.isArray(got[key]) && got[key][0] === want[key]) continue;
            if (gw !== ww) diffs.push(sc.id + ' @' + ri + ' s' + sr.index + ' row ' + row.i + ' ' + key + ' ' + gw + ' vs ' + ww);
          }
        });
      }
    }
    // S3
    const st = transcribeStatus(rec);
    for (const ic of rec.toolbox) {
      if (ic.feature !== 'brush') continue;
      const want = st[ic.name];
      if (ri > 0 && ic.status !== want && !rec._staleToolbox) diffs.push(sc.id + ' @' + ri + ' status ' + ic.name + ' ' + ic.status + ' vs ' + want);
    }
  });
  // S4
  if (def.preCheck) {
    for (const pc of def.preCheck) {
      const rec = recs[pc.rec];
      const want = transcribePre(pc.option, pc.isNew, null);
      const got = rec.options.toolbox[0] ? rec.options.toolbox[0].brushType : null;
      if (JSON.stringify(want) !== JSON.stringify(got)) diffs.push(sc.id + ' pre ' + JSON.stringify(got) + ' vs ' + JSON.stringify(want));
    }
  }
  return diffs;
}

const GUARDS = [
  { id: 'G1', mutation: 'a rect touching a bar does not intersect it', set: { strictIntersect: true }, named: ['S-BAR'] },
  { id: 'G2', mutation: "a polygon's bars tested by corners only, not by its edges", set: { noEdges: true }, named: ['S-BAR'] },
  { id: 'G3', mutation: 'every area controls every series (no controlSeries)', set: { noControl: true }, named: ['S-TWOGRIDS'] },
  { id: 'G4', mutation: 'a brushLink index list links nothing', set: { linkIgnored: true }, named: ['L-INDICES'] },
  { id: 'G5', mutation: "a bar's layout range is not put in order (negative heights)", set: { noReverse: true }, named: ['S-BAR'] },
  { id: 'G6', mutation: 'the clear button is never emphasised', set: { clearAlwaysOff: true }, named: ['T-BUTTONS'] },
  { id: 'G7', mutation: 'the preprocessor keeps duplicates', set: { noDedupe: true }, named: ['T-MERGE'] },
];

function generate() {
  const scenarios = [];
  const checks = {};
  for (const def of SCENARIOS) {
    const sc = runScenario(def);
    checks[def.id] = { sc, def };
    scenarios.push(sc);
  }
  // the targets each brush's model has (panel ids), for controlSeries
  for (const sc of scenarios) {
    for (const rec of [sc.initial].concat(sc.steps.map(s => s.record))) {
      rec._targets = brushModels(sc._chart).map(m => (m.brushTargetManager ? m.brushTargetManager._targetInfoList.map(t => t.panelId) : []));
      // a throttled brushselected carries an earlier state; the toolbox renders
      // on a full update only
      rec._throttled = false;
      rec._staleToolbox = false;
    }
    // the debounced case: S1 is compared where the batch's areas are the record's
    for (const st of sc.steps) {
      const rec = st.record;
      const evs = rec.events.filter(e => e.type === 'brushselected');
      const last = evs[evs.length - 1];
      if (last) {
        const areasNow = JSON.stringify(rec._brushOpts.map(b => b.areas.map(a => a.range)));
        const areasEv = JSON.stringify(last._raw.map(b => b.areas.map(a => a.range)));
        rec._throttled = areasNow !== areasEv;
      }
      // a brush action (updateVisual) does not render the toolbox
      rec._staleToolbox = !rec.events.some(e => e.type === 'globalcursortaken') && st.step.type !== 'set';
    }
  }
  // the preprocessor checks
  checks['T-MERGE'].def.preCheck = [
    { rec: 1, option: { brush: { xAxisIndex: 0 } }, isNew: false },
    { rec: 2, option: catChart({ brush: { xAxisIndex: 0, toolbox: [] } }), isNew: true },
    { rec: 3, option: catChart({ toolbox: { feature: { brush: { type: ['rect', 'clear', 'rect'] } } }, brush: [{ toolbox: ['lineY'] }, { toolbox: ['clear', 'lineX'] }] }), isNew: true },
  ];
  checks['T-OWN'].def.preCheck = [{ rec: 0, option: catChart({ toolbox: { feature: { saveAsImage: {} } }, brush: { xAxisIndex: 0, toolbox: ['lineX', 'lineY', 'clear'] } }), isNew: true }];
  checks['T-BUTTONS'].def.preCheck = [{ rec: 0, option: catChart({ brush: { xAxisIndex: 0 } }), isNew: true }];
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
  const allRecs = sc => [sc.initial].concat(sc.steps.map(s => s.record));
  const sel = (sc, f) => allRecs(sc).some(r => r.events.some(e => e.type === 'brushselected' && f(e)));
  must(sel(byId('S-SCATTER'), e => e.batch[0].selected[0].dataIndex.length > 0), 'S-SCATTER selects nothing');
  must(sel(byId('E-ACTIONS'), e => e.batch.length === 0), 'E-ACTIONS fires no empty batch');
  must(sel(byId('L-ALL'), e => e.batch[0].selected[2].dataIndex.length > 0), 'L-ALL links nothing to the line');
  const gi = byId('G-INSIDE');
  const zooms = allRecs(gi).map(r => JSON.stringify(r.zoom));
  must(new Set(zooms).size >= 3, 'G-INSIDE pans too little');
  must(allRecs(byId('T-BUTTONS')).some(r => r.toolbox.some(t => t.feature === 'brush' && t.name === 'keep' && t.status === 'emphasis')), 'T-BUTTONS never keeps');
  const ir = byId('I-IRRELEVANT');
  must(ir.steps[4].record.brushes[0].areas.length === 0, 'I-IRRELEVANT draws over the other grid');
  // strip the private fields; write what changed
  for (const sc of scenarios) {
    let prevS = [];
    let prevT = null;
    let prevO = null;
    let prevZ = null;
    for (const rec of allRecs(sc)) {
      rec.series = rec.series.map((s, k) => {
        delete s._grid;
        delete s._large;
        s.rows.forEach(r => { delete r._layout; });
        const j = JSON.stringify(s);
        if (prevS[k] === j) return null;
        prevS[k] = j;
        return s;
      });
      const tj = JSON.stringify(rec.toolbox);
      rec.toolbox = tj === prevT ? null : rec.toolbox;
      prevT = tj;
      const oj = JSON.stringify(rec.options);
      rec.options = oj === prevO ? null : rec.options;
      prevO = oj;
      const zj = JSON.stringify(rec.zoom);
      rec.zoom = zj === prevZ ? null : rec.zoom;
      prevZ = zj;
      rec.events.forEach(ev => { delete ev._raw; });
      delete rec._brushOpts;
      delete rec._targets;
      delete rec._throttled;
      delete rec._staleToolbox;
    }
    sc._chart.dispose();
    delete sc._chart;
  }
  return {
    out: {
      source: 'ECharts 6.1 dist (' + path.basename(DIST) + '), node SSR, SVG renderer',
      W, H, clock: { start: CLOCK0, pointerDt: 200, clickDt: 0, idleDt: 1000 },
      outOfBrushDefault: '#cfd2d7',
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
const nEvents = out.scenarios.reduce((n, s) => n + s.steps.reduce((m, st) => m + st.record.events.length, 0), 0);
const nSel = out.scenarios.reduce((n, s) => n + s.steps.reduce((m, st) => m + st.record.events.filter(e => e.type === 'brushselected').length, 0), 0);
console.log(out.scenarios.length + ' scenarios, ' + nSteps + ' steps, ' + nEvents + ' events, ' + nSel + ' brushselected; '
  + (out.guards.length - bad.length) + '/' + out.guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT')
  + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
