/*
Upstream's own answers for roadmap C10, batch 118: the single axis
coordinate system (singleAxis: its box, orient and position, every axis
type, several of them), the axis view (AxisBuilder's line, ticks, labels,
name and arrows, the view's own split lines and split areas), scatter and
effectScatter on a single axis (the punch card, per-item sizes, jitter),
themeRiver (fixData's zeros, the layers, the wiggle baseline, the polygons,
their labels, emphasis and focus, the legend's filter), the axis pointer and
the tooltip's axis trigger on a single axis (themeRiver's own nearest rows),
dataZoom on a single axis, convertToPixel / convertFromPixel / containPixel
with single-axis finders, and the enter animations of a themeRiver (its clip
rect) and of a scatter on a single axis (the clock hook of animation.js).

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node's server-side mode, SVG renderer, measuring every
string with zrender's width table (the TZrSsrMeasurer of the Pascal tests),
TZ=UTC. The static cases are 600 x 400 with `animation: false`; the
animation cases are 400 x 300 and run as animation.js runs them.
Math.random is the port's xorshift32 from 2463534242, reset before every
chart (as convert-jitter.js), so a jittered scatter is reproducible.

  node tools/advchart-oracle/single-themeriver.js

writes tests/fixtures/advchart-single-themeriver.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Numbers that are positions are the 16 hex digits of the IEEE double
(big-endian, lowercase; every NaN 7ff8000000000000). Counts, flags, strings
and option values are plain JSON.

Top level: source, version, seed, notes[], cases[], anim {samplesMs, clock,
cases[]}, guards[].

A static case: id, group, note, W, H, option (as run), actions? (dispatched
after the first render), singles[], series[], pointer[] (pointer cases),
convert[] (convert cases), states[] (state cases), after[] (action cases:
singles and series again after each action), zoom[], fails[] (recipe
mismatches; must be empty).

singles[i]: index, rect [x, y, w, h], orient, position, horizontal
  (isHorizontal(): the position's), inverse (axis.inverse), type, extent [2]
  (axis.getExtent()), scale [2], blank, view --
    shown,
    line null | {x1, y1, x2, y2} (sub-pixel optimised),
    arrows[] {type, x, y, rotation, w, h},
    ticks[] {tick, x1, y1, x2, y2, ignore}, minorTicks[] {x1, y1, x2, y2},
    labels[] {tick, text, x, y, rotation, align, va, ignore},
    name null | {text, x, y, rotation, align, va},
    splitLines[] {ci, x1, y1, x2, y2} (each piece as mergePath merged it),
    splitAreas[] {anid, x, y, w, h, fill}.

series[k]: index, type, single, count, raw[] (getRawIndex per view row) --
  scatter / effectScatter: symbols[] {i, drawn, x, y, size, lx, ly (the
    layout), label};
  themeRiver: gap [2] (the boundaryGap the layout left, px), groupY,
    rows[] {i, name, time, value, x, y0, y} (per view row: data and layout),
    layers[] {name, indices[], points[] (flat, hex), stacked[], dataIndex
    (the polygon's ECData), fill, stroke, lineWidth, opacity, rect [4] (the
    polygon's own bounding rect), label null | {text, drawn, x, y, align,
    va, fill, stroke, lineWidth}}.

pointer[]: per probe {x, y, axes[] {single, value, el null | {type ('line' |
  'rect'), shape [4]}, label null | {text, x, y, w, h}}, tip null |
  [[{axisDim, value, series[] {s, i}}]] (the showTip payload)}.

convert[]: {op, finder {in, text, textSafe}, value {in, text, textSafe},
  out {k: 'none' | 'bool' | 'num' | 'arr' | 'throw', v}}.

states[]: per action {action, items[] {s, i, states, fill, stroke,
  lineWidth, opacity, labelFill}} -- every element getItemGraphicEl finds
  (a themeRiver's layer i is dataIndex i's).

anim.cases[]: the cases of advchart-animation.json's own format (id, kind,
  chart, variant, note, option, next, W, H, resolved, clips, elements).

Guards (any failure: nothing is written, exit 1): the recipes (the single's
dataToPoint, the themeRiver layout recomputed from the data -- fixData, the
layers, computeBaseline -- and the label place) agree with what was drawn;
named facts; and the whole fixture is generated twice, byte-identical.
process.exit() ends the run.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

// ---------- the controlled clock (must precede loading the dist) ----------
const RealDate = Date;
const T_BASE = 1700000000000;
let NOW = T_BASE;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;

// ---------- the random numbers: the port's xorshift32 (convert-jitter.js) ----------
const SEED = 2463534242;
let rngState = SEED;
let draws = 0;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  draws++;
  return x / 4294967296;
};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-single-themeriver.json');
const ENV_NODE = echarts.env.node;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function numOf(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const hexN = v => (v == null ? '7ff8000000000000' : hex(+v));
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const same = (a, b) => Object.is(a, b);
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  const l = console.log;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; console.log = l; }
};
const colourText = v => (v == null ? null : (typeof v === 'string' ? v : JSON.stringify(v)));

// ---------------------------------------------------------------------------
// the merged-path capture (as polar-axes.js): SingleAxisView merges its
// split lines into one path per colour
// ---------------------------------------------------------------------------
let CAP = null;
let IN_GUPP = 0;
{
  const proto = Object.getPrototypeOf(echarts.graphic.Line.prototype);
  must(proto && Object.prototype.hasOwnProperty.call(proto, 'getUpdatedPathProxy'), 'no Path prototype');
  const gupp = proto.getUpdatedPathProxy;
  proto.getUpdatedPathProxy = function (inBatch) {
    if (CAP && inBatch) CAP.push({ t: String(this.type).toLowerCase(), s: Object.assign({}, this.shape) });
    IN_GUPP++;
    try { return gupp.apply(this, arguments); } finally { IN_GUPP--; }
  };
  const cpp = proto.createPathProxy;
  proto.createPathProxy = function () {
    if (CAP && !IN_GUPP) CAP.push({ b: this });
    return cpp.apply(this, arguments);
  };
}
const BUNDLES = new Map();
{
  const warm = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 200, height: 200 });
  warm.setOption({ animation: false, singleAxis: {} });
  warm.renderToSVGString();
  const views = warm._componentsViews.filter(v => v && v.__model && v.__model.mainType === 'singleAxis');
  must(views.length === 1, 'the warm-up chart has no single axis view');
  let proto = Object.getPrototypeOf(views[0]);
  while (proto && !Object.prototype.hasOwnProperty.call(proto, 'render')) proto = Object.getPrototypeOf(proto);
  must(proto, 'no render on the view prototype chain');
  const render = proto.render;
  proto.render = function () {
    const prev = CAP;
    CAP = [];
    try {
      return render.apply(this, arguments);
    } finally {
      const list = [];
      let cur = [];
      CAP.forEach(e => {
        if (e.b) { list.push({ bundle: e.b, pieces: cur }); cur = []; }
        else cur.push(e);
      });
      must(cur.length === 0, 'pieces merged into no bundle');
      BUNDLES.set(this, list);
      CAP = prev;
    }
  };
  warm.dispose();
}

function walk(e, f) {
  f(e);
  if (e.childrenRef) e.childrenRef().forEach(x => walk(x, f));
}
const lineRec = s => ({ x1: hex(s.x1), y1: hex(s.y1), x2: hex(s.x2), y2: hex(s.y2) });

// ---------------------------------------------------------------------------
// the recipes
// ---------------------------------------------------------------------------
// Single.dataToPoint
function dataToPointRecipe(single, val) {
  const axis = single.getAxis();
  const rect = single.getRect();
  const out = [];
  const idx = axis.orient === 'horizontal' ? 0 : 1;
  if (val instanceof Array) val = val[0];
  out[idx] = axis.toGlobalCoord(axis.dataToCoord(+val));
  out[1 - idx] = idx === 0 ? rect.y + rect.height / 2 : rect.x + rect.width / 2;
  return out;
}
// themeRiverLayout + computeBaseline, from the data as the series holds it
function riverRecipe(series) {
  const data = series.getData();
  const single = series.coordinateSystem;
  const rect = single.getRect();
  const gap = data.getLayout('layoutInfo').boundaryGap;
  const len = single.getAxis().orient === 'horizontal' ? rect.height : rect.width;
  const height = len - gap[0] - gap[1];
  const layers = series.getLayerSeries();
  const out = new Map();
  if (!data.count()) return out;
  const timeDim = data.mapDimension('single');
  const valueDim = data.mapDimension('value');
  const pts = layers.map(l => l.indices.map(idx => {
    const p = dataToPointRecipe(single, data.get(timeDim, idx));
    p[1] = data.get(valueDim, idx);
    return p;
  }));
  const n = pts.length;
  const m = pts[0].length;
  const sums = [];
  const y0 = [];
  let max = 0;
  for (let i = 0; i < m; ++i) {
    let t = 0;
    for (let j = 0; j < n; ++j) t += pts[j][i][1];
    if (t > max) max = t;
    sums.push(t);
  }
  for (let k = 0; k < m; ++k) y0[k] = (max - sums[k]) / 2;
  max = 0;
  for (let l = 0; l < m; ++l) {
    const s = sums[l] + y0[l];
    if (s > max) max = s;
  }
  const ky = height / max;
  for (let j = 0; j < m; ++j) {
    let b = y0[j] * ky;
    out.set(layers[0].indices[j], { x: pts[0][j][0], y0: b, y: pts[0][j][1] * ky });
    for (let i = 1; i < n; ++i) {
      b += pts[i - 1][j][1] * ky;
      out.set(layers[i].indices[j], { x: pts[i][j][0], y0: b, y: pts[i][j][1] * ky });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// reading
// ---------------------------------------------------------------------------
function readSingles(chart, c, fails) {
  const out = [];
  chart.getModel().eachComponent('singleAxis', sm => {
    const single = sm.coordinateSystem;
    if (!single) return;
    const axis = single.getAxis();
    const r = single.getRect();
    const rec = { index: sm.componentIndex, rect: [r.x, r.y, r.width, r.height].map(hex),
      orient: axis.orient, position: axis.position, horizontal: axis.isHorizontal(), inverse: !!axis.inverse,
      type: axis.type, extent: axis.getExtent().map(hex), scale: axis.scale.getExtent().map(hex),
      blank: axis.scale.isBlank(), view: readView(chart, sm, axis, fails, c.id + ' single' + sm.componentIndex) };
    out.push(rec);
  });
  return out;
}
function readView(chart, sm, axis, fails, key) {
  const out = { shown: !!sm.get('show'), line: null, arrows: [], ticks: [], minorTicks: [], labels: [], name: null,
    splitLines: [], splitAreas: [] };
  if (!out.shown) return out;
  const view = chart.getViewOfComponentModel(sm);
  must(view && view.group, key + ': no single axis view');
  walk(view.group, e => {
    let mm;
    if (e.anid === 'line' && e.shape) out.line = lineRec(e.shape);
    else if (e.shape && e.shape.symbolType != null) {
      out.arrows.push({ type: e.shape.symbolType, x: hex(e.x), y: hex(e.y), rotation: hex(e.rotation),
        w: hex(e.shape.width), h: hex(e.shape.height) });
    }
    else if (e.anid && (mm = /^ticks_(.*)$/.exec(e.anid))) out.ticks.push(Object.assign({ tick: mm[1] }, lineRec(e.shape), { ignore: !!e.ignore }));
    else if (e.anid && /^minorticks_/.test(e.anid)) out.minorTicks.push(lineRec(e.shape));
    else if (e.anid && (mm = /^label_(.*)$/.exec(e.anid)) && e.style) {
      out.labels.push({ tick: mm[1], text: e.style.text, x: hex(e.x), y: hex(e.y), rotation: hex(e.rotation),
        align: e.style.align, va: e.style.verticalAlign, ignore: !!e.ignore });
    }
    else if (e.anid === 'name' && e.style) {
      out.name = { text: e.style.text, x: hex(e.x), y: hex(e.y), rotation: hex(e.rotation), align: e.style.align, va: e.style.verticalAlign };
    }
    else if (e.anid && /^area_/.test(e.anid) && e.shape) {
      let cols = sm.get(['splitArea', 'areaStyle', 'color']);
      cols = Array.isArray(cols) ? cols : [cols];
      out.splitAreas.push({ anid: e.anid, x: hex(e.shape.x), y: hex(e.shape.y), w: hex(e.shape.width), h: hex(e.shape.height),
        fill: colourText(e.style.fill), ci: cols.indexOf(e.style.fill) });
    }
  });
  // the split lines: one bundle per colour, pieces in turn
  const bundles = BUNDLES.get(view) || [];
  if (sm.get(['splitLine', 'show']) && !axis.scale.isBlank()) {
    let cols = sm.get(['splitLine', 'lineStyle', 'color']);
    cols = cols instanceof Array ? cols : [cols];
    const ticks = axis.getTicksCoords({ tickModel: sm.getModel('splitLine'), breakTicks: 'none', pruneByBreak: 'preserve_extent_bound' });
    const total = bundles.reduce((s, q) => s + q.pieces.length, 0);
    must(total === ticks.length, key + ': ' + total + ' split lines for ' + ticks.length + ' ticks');
    for (let i = 0; i < ticks.length; i++) {
      const ci = i % cols.length;
      const p = bundles[ci].pieces[Math.floor(i / cols.length)];
      must(p.t === 'line', key + ': a ' + p.t + ' split line');
      out.splitLines.push(Object.assign({ ci }, lineRec(p.s)));
    }
  }
  return out;
}
function labelRec(host) {
  if (!host || !host.getTextContent) return null;
  const tc = host.getTextContent();
  if (!tc) return null;
  const drawn = !host.ignore && !tc.ignore && !tc.invisible;
  const rec = { text: tc.style.text == null ? null : String(tc.style.text), drawn };
  if (drawn) {
    const it = tc.innerTransformable;
    const ds = host._innerTextDefaultStyle || {};
    rec.x = hex(it.x);
    rec.y = hex(it.y);
    rec.dAlign = ds.align == null ? null : ds.align;
    rec.dVa = ds.verticalAlign == null ? null : ds.verticalAlign;
    rec.align = tc.style.align == null ? null : tc.style.align;
    rec.va = tc.style.verticalAlign == null ? null : tc.style.verticalAlign;
    rec.fill = colourText(tc.style.fill);
    rec.stroke = colourText(tc.style.stroke);
    rec.lineWidth = tc.style.lineWidth == null ? null : hex(+tc.style.lineWidth);
  }
  return rec;
}
function symbolRec(d, i) {
  const el = d.getItemGraphicEl(i);
  const lay = d.getItemLayout(i);
  const size = d.getItemVisual(i, 'symbolSize');
  const rec = { i, drawn: !!el && !el.ignore, lx: lay ? hexN(lay[0]) : null, ly: lay ? hexN(lay[1]) : null,
    size: Array.isArray(size) ? size.map(hexN) : hexN(size) };
  if (el) {
    rec.x = hex(el.x);
    rec.y = hex(el.y);
    const sp = el.getSymbolPath ? el.getSymbolPath() : null;
    rec.label = labelRec(sp);
  }
  return rec;
}
function readSeries(chart, c, fails) {
  const ecModel = chart.getModel();
  const out = [];
  ecModel.eachSeries(s => {
    if (s.get('coordinateSystem') !== 'singleAxis') return;
    const single = s.coordinateSystem;
    const view = chart.getViewOfSeriesModel(s);
    const d = s.getData();
    const rec = { index: s.seriesIndex, type: s.subType, single: single ? single.model.componentIndex : -1,
      count: d.count(), raw: [] };
    for (let i = 0; i < d.count(); i++) rec.raw.push(d.getRawIndex(i));
    if (s.subType === 'scatter' || s.subType === 'effectScatter') {
      rec.symbols = [];
      for (let i = 0; i < d.count(); i++) {
        rec.symbols.push(symbolRec(d, i));
        // the layout is dataToPoint of the single dimension (unless jittered)
        const lay = d.getItemLayout(i);
        const jit = single.getAxis().model.get('jitter') > 0 && s.subType === 'scatter';
        if (lay && !jit) {
          const w = dataToPointRecipe(single, d.get(d.mapDimension('single'), i));
          if (!same(w[0], lay[0]) || !same(w[1], lay[1])) fails.push(c.id + ' s' + s.seriesIndex + ' i' + i + ': layout ' + lay + ', the recipe ' + w);
        }
      }
    }
    else if (s.subType === 'themeRiver') {
      const info = d.getLayout('layoutInfo');
      rec.gap = info ? info.boundaryGap.map(v => hexN(v)) : null;
      rec.groupY = hex(view.group.y);
      const recipe = riverRecipe(s);
      rec.rows = [];
      for (let i = 0; i < d.count(); i++) {
        const lay = d.getItemLayout(i);
        rec.rows.push({ i, name: d.getName(i), time: hexN(d.get('time', i)), value: hexN(d.get('value', i)),
          x: lay ? hexN(lay.x) : null, y0: lay ? hexN(lay.y0) : null, y: lay ? hexN(lay.y) : null });
        const w = recipe.get(i);
        if (lay && w && !(same(w.x, lay.x) && same(w.y0, lay.y0) && same(w.y, lay.y))) {
          fails.push(c.id + ' s' + s.seriesIndex + ' i' + i + ': layout ' + JSON.stringify(lay) + ', the recipe ' + JSON.stringify(w));
        }
      }
      const layers = s.getLayerSeries();
      rec.layers = [];
      const groups = view._layers || [];
      layers.forEach((l, k) => {
        const g = groups[k];
        must(g, c.id + ': no group for layer ' + k);
        const p = g.childAt(0);
        const ecd = ecDataOf(p);
        // the PATH's own rect: what the enter clip is made from (taken before the style, no stroke)
        const br = p.path.getBoundingRect();
        const lab = labelRec(p);
        rec.layers.push({ name: l.name, indices: l.indices.slice(), points: Array.from(p.shape.points).map(hexN),
          stacked: Array.from(p.shape.stackedOnPoints).map(hexN), dataIndex: ecd ? ecd.dataIndex : null,
          fill: colourText(p.style.fill), stroke: colourText(p.style.stroke),
          lineWidth: p.style.lineWidth == null ? null : hex(+p.style.lineWidth),
          opacity: p.style.opacity == null ? null : hex(+p.style.opacity),
          rect: [br.x, br.y, br.width, br.height].map(hex), label: lab });
        // the label sits at the first point, margin to its left, halfway up
        if (lab && lab.drawn) {
          const first = d.getItemLayout(l.indices[0]);
          const margin = s.get(['label', 'margin']);
          if (!same(numOf(lab.x), first.x - margin) || !same(numOf(lab.y), first.y0 + first.y / 2)) {
            fails.push(c.id + ' s' + s.seriesIndex + ' layer ' + k + ': label at ' + numOf(lab.x) + ',' + numOf(lab.y));
          }
        }
      });
    }
    out.push(rec);
  });
  return out;
}
function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'dataIndex' in el[k]) return el[k];
  }
  return null;
}
function readZoom(chart) {
  const out = [];
  (chart._componentsViews || []).forEach(v => {
    const m = v.__model;
    if (!m || m.mainType !== 'dataZoom' || m.subType !== 'slider') return;
    if (!v._location || !v._size) return;
    out.push({ index: m.componentIndex, type: m.subType, orient: v._orient,
      x: hex(v._location.x), y: hex(v._location.y), w: hex(v._size[0]), h: hex(v._size[1]) });
  });
  return out;
}

// ---- the pointer
function readPointer(chart, c, x, y) {
  const ecModel = chart.getModel();
  const zr = chart.getZr();
  let tip = null;
  const onTip = p => {
    tip = (p.dataByCoordSys || []).map(cs => (cs.dataByAxis || []).map(a => ({
      axisDim: a.axisDim, value: hexN(a.value),
      series: (a.seriesDataIndices || []).map(q => ({ s: q.seriesIndex, i: q.dataIndexInside })),
    })));
  };
  chart.on('showTip', onTip);
  chart.dispatchAction({ type: 'updateAxisPointer', currTrigger: 'mousemove', x, y });
  zr.refreshImmediately();
  chart.off('showTip', onTip);
  const axes = [];
  const apComp = ecModel.getComponent('axisPointer', 0);
  const info = apComp ? apComp.coordSysAxesInfo : null;
  ecModel.eachComponent('singleAxis', sm => {
    const axis = sm.axis;
    if (!info) return;
    const ai = Object.values(info.axesInfo).find(q => q.axis === axis);
    if (!ai) return;
    const apm = ai.axisPointerModel;
    if (apm.get('status') !== 'show') return;
    const view = chart.getViewOfComponentModel(sm);
    const ap = view && view._axisPointer;
    const g = ap && ap._group;
    must(g && !g.ignore, c.id + ': a shown pointer with no group');
    const rec = { single: sm.componentIndex, value: hexN(apm.get('value')), el: null, label: null };
    g.childrenRef().forEach(e => {
      const t = String(e.type).toLowerCase();
      if (t === 'line') rec.el = { type: 'line', shape: [e.shape.x1, e.shape.y1, e.shape.x2, e.shape.y2].map(hex) };
      else if (t === 'rect') rec.el = { type: 'rect', shape: [e.shape.x, e.shape.y, e.shape.width, e.shape.height].map(hex) };
      else if (t === 'text' && !e.ignore) {
        const b = e.getBoundingRect();
        rec.label = { text: e.style.text, x: hex(e.x), y: hex(e.y), w: hex(b.width), h: hex(b.height) };
      }
    });
    axes.push(rec);
  });
  return { x, y, axes, tip };
}

// ---- the conversions (as advchart-polar-axes.json)
function encIn(v) {
  if (typeof v === 'number') return { h: hex(v) };
  if (Array.isArray(v)) return v.map(encIn);
  if (v && typeof v === 'object') {
    const o = {};
    Object.keys(v).forEach(k => { o[k] = encIn(v[k]); });
    return o;
  }
  return v;
}
function textSafe(v) {
  if (typeof v === 'number') return Number.isFinite(v) && Number(v.toPrecision(15)) === v;
  if (Array.isArray(v)) return v.every(textSafe);
  if (v && typeof v === 'object') return Object.keys(v).every(k => textSafe(v[k]));
  return true;
}
function input(v) {
  must(v !== undefined, 'an undefined input cannot be recorded');
  return { in: encIn(v), text: JSON.stringify(v), textSafe: textSafe(v) };
}
function outOf(r) {
  if (r === undefined) return { k: 'none' };
  if (typeof r === 'boolean') return { k: 'bool', v: r };
  if (typeof r === 'number') return { k: 'num', v: hex(r) };
  if (Array.isArray(r) || ArrayBuffer.isView(r)) {
    const a = Array.from(r);
    must(a.every(x => typeof x === 'number'), 'a result array holds a non-number: ' + JSON.stringify(a));
    return { k: 'arr', v: a.map(hex) };
  }
  throw new OracleError('an unexpected result ' + JSON.stringify(r));
}
function runConvert(chart, c) {
  return c.probes.map(([op, finder, value]) => {
    let out;
    try {
      out = outOf(quiet(() => {
        if (op === 'to') return chart.convertToPixel(finder, value);
        if (op === 'from') return chart.convertFromPixel(finder, value);
        return chart.containPixel(finder, value);
      }));
    } catch (e) {
      if (!(e instanceof TypeError)) throw e;
      out = { k: 'throw' };
    }
    return { op, finder: input(finder), value: input(value), out };
  });
}

// ---- the states
function runStates(chart, c) {
  const ecModel = chart.getModel();
  const out = [];
  c.actions.forEach(a => {
    chart.dispatchAction(clone(a));
    chart._onframe();
    chart.renderToSVGString();
    const items = [];
    ecModel.eachSeries(s => {
      const d = s.getData();
      for (let i = 0; i < d.count(); i++) {
        const el = d.getItemGraphicEl(i);
        if (!el) continue;
        const host = el.getSymbolPath ? el.getSymbolPath() : el;
        const tc = host.getTextContent && host.getTextContent();
        items.push({ s: s.seriesIndex, i, states: (host.currentStates || []).slice(),
          fill: host.style.fill == null ? null : colourText(host.style.fill),
          stroke: host.style.stroke == null ? null : colourText(host.style.stroke),
          lineWidth: host.style.lineWidth == null ? null : hex(+host.style.lineWidth),
          opacity: host.style.opacity == null ? null : hex(+host.style.opacity),
          labelFill: tc && tc.style.fill != null ? colourText(tc.style.fill) : null,
          labelShown: tc ? !tc.ignore && !tc.invisible : null });
      }
    });
    out.push({ action: clone(a), items });
  });
  return out;
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
// every case in UTC: the oracle runs at TZ=UTC, the port's dates then do not depend on the machine's zone
// and a palette written at the root: the port's default palette is its skin's, upstream's its theme's
const PALETTE = ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de', '#3ba272', '#fc8452', '#9a60b4', '#ea7ccc'];
const add = (group, id, note, option, more) => CASES.push(Object.assign({ group, id, note, W: 600, H: 400,
  option: Object.assign({ useUTC: true, color: PALETTE }, option) }, more || {}));
const DAYS = ['Saturday', 'Friday', 'Thursday', 'Wednesday', 'Tuesday', 'Monday', 'Sunday'];
const HOURS = ['12a', '1a', '2a', '3a', '4a', '5a', '6a', '7a', '8a', '9a', '10a', '11a',
  '12p', '1p', '2p', '3p', '4p', '5p', '6p', '7p', '8p', '9p', '10p', '11p'];
const sc = (data, extra) => Object.assign({ type: 'scatter', coordinateSystem: 'singleAxis', data }, extra || {});
const river = (data, extra) => Object.assign({ type: 'themeRiver', data }, extra || {});
// a day of November 2015 at UTC midnight, written with its zone
const day = d => '2015-11-' + String(d).padStart(2, '0') + 'T00:00:00Z';
const D = (d, v, n) => [day(d), v, n];
// a river of several layers, some points missing
const RIVER3 = [D(8, 10, 'DQ'), D(9, 15, 'DQ'), D(10, 35, 'DQ'), D(11, 38, 'DQ'), D(12, 22, 'DQ'), D(13, 16, 'DQ'),
  D(8, 35, 'TY'), D(9, 36, 'TY'), D(10, 37, 'TY'), D(12, 22, 'TY'), D(13, 24, 'TY'),
  D(9, 21, 'SS'), D(10, 25, 'SS'), D(11, 27, 'SS'), D(12, 23, 'SS'), D(13, 24, 'SS')];
const RIVER6 = (() => {
  const names = ['DQ', 'TY', 'SS', 'QG', 'SY', 'DD'];
  const out = [];
  names.forEach((n, k) => {
    for (let d = 8; d <= 19; d++) {
      if ((d * 7 + k * 3) % 11 === 0) continue;
      out.push(D(d, ((d * 13 + k * 29) % 37) + 3, n));
    }
  });
  return out;
})();
const RIVER_V = [[1, 5, 'a'], [2, 8, 'a'], [3, 4, 'a'], [4, 9, 'a'], [1, 3, 'b'], [2, 6, 'b'], [4, 2, 'b'],
  [2, 7, 'c'], [3, 3, 'c'], [5, 6, 'c'], [1, 2, 'd'], [5, 4, 'd']];

// ---- the axes
add('axis', 'axis-value-h', 'a value axis, horizontal at the bottom (the defaults)', { singleAxis: { type: 'value', min: 0, max: 100 } });
add('axis', 'axis-value-top', 'a value axis on top, labels turned 30 (negated on top), a name at the end',
  { singleAxis: { type: 'value', min: -50, max: 50, position: 'top', axisLabel: { rotate: 30 }, name: 'Value', top: 60, bottom: 200 } });
add('axis', 'axis-category-h', 'a category axis, seven days, banded: ticks and split lines on the band edges',
  { singleAxis: { type: 'category', data: DAYS, top: 100, height: 80 } });
add('axis', 'axis-category-nogap', 'a category axis of 24 hours, boundaryGap false, interval 2, ticks aligned',
  { singleAxis: { type: 'category', data: HOURS, boundaryGap: false, axisLabel: { interval: 2 }, axisTick: { alignWithLabel: true }, left: 80 } });
add('axis', 'axis-time-h', 'a time axis over ten days',
  { singleAxis: { type: 'time', min: day(8), max: day(18), top: 50, bottom: 50 } });
add('axis', 'axis-log-h', 'a log axis 1..10000',
  { singleAxis: { type: 'log', min: 1, max: 10000, bottom: 40, height: 60 } });
add('axis', 'axis-value-v-left', 'a vertical value axis on the left',
  { singleAxis: { type: 'value', min: 0, max: 50, orient: 'vertical', position: 'left', left: 100, right: 300 } });
add('axis', 'axis-value-v-right', 'a vertical value axis on the right, inverse, a name',
  { singleAxis: { type: 'value', min: 0, max: 1000, orient: 'vertical', position: 'right', inverse: true, name: 'Count', right: 80, left: 400 } });
add('axis', 'axis-category-v', 'a vertical category axis on the left',
  { singleAxis: { type: 'category', data: DAYS, orient: 'vertical', position: 'left', left: 120, width: 100 } });
add('axis', 'axis-time-v', 'a vertical time axis on the right',
  { singleAxis: { type: 'time', min: day(8), max: day(12), orient: 'vertical', position: 'right', right: 120, width: 200 } });
add('axis', 'axis-inside', 'ticks and labels inside, a 12 px margin, ten-pixel ticks',
  { singleAxis: { type: 'value', min: 0, max: 10, axisTick: { inside: true, length: 10 }, axisLabel: { inside: true, margin: 12 }, top: 100, bottom: 150 } });
add('axis', 'axis-split', 'split areas with colours, split lines in two colours',
  { singleAxis: { type: 'value', min: 0, max: 60, splitArea: { show: true, areaStyle: { color: ['#eef', '#fee', '#efe'] } },
    splitLine: { lineStyle: { color: ['#aaa', '#555'] } } } });
add('axis', 'axis-multi', 'seven single axes stacked, the punch card\'s frames',
  { singleAxis: DAYS.map((day, idx) => ({ left: 150, type: 'category', boundaryGap: false, data: HOURS,
    top: (idx * 100) / 7 + 5 + '%', height: 100 / 7 - 10 + '%', axisLabel: { interval: 2 }, name: day, nameLocation: 'start', nameGap: 20 })) });
add('axis', 'axis-box', 'the box: left and width, bottom and height, merged as mergeLayoutParam merges them',
  { singleAxis: [{ type: 'value', min: 0, max: 10, left: 150, width: 300, bottom: 20, height: 60 },
    { type: 'value', min: 0, max: 5, right: '10%', width: '40%', top: '10%', height: 40 }] });
add('axis', 'axis-name-middle', 'a centred name with a gap, arrows on the line',
  { singleAxis: { type: 'value', min: 0, max: 20, name: 'Middle name', nameLocation: 'middle', nameGap: 25,
    axisLine: { symbol: ['none', 'arrow'], symbolSize: [8, 12] }, top: 120, bottom: 120 } });
add('axis', 'axis-minor', 'minor ticks on a value axis, splitNumber 4',
  { singleAxis: { type: 'value', min: 0, max: 100, splitNumber: 4, minorTick: { show: true, splitNumber: 5 }, top: 150, bottom: 150 } });
add('axis', 'axis-hide-overlap', 'crowded labels hidden by hideOverlap, their ticks with them',
  { singleAxis: { type: 'value', min: 0, max: 1000000, splitNumber: 20, axisLabel: { hideOverlap: true }, top: 150, bottom: 150 } });
add('axis', 'axis-vertical-bottom', "orient vertical with the default position bottom: the frame's x is not a number (upstream's layout has no vertical bottom)",
  { singleAxis: { type: 'value', min: 0, max: 10, orient: 'vertical', left: 100, width: 200 }, series: [sc([[2, 1], [5, 1]])] });
add('axis', 'axis-hidden', 'a hidden axis draws nothing, a series still maps',
  { singleAxis: { type: 'value', min: 0, max: 10, show: false }, series: [sc([[2, 1], [5, 1], [8, 1]])] });
add('axis', 'axis-data-extent', 'a value axis sized by its series (no min / max), splitLine off',
  { singleAxis: { type: 'value', splitLine: { show: false }, top: 100, bottom: 200 }, series: [sc([[3.2, 1], [17.9, 1], [41.5, 1], [26, 1]])] });

// ---- scatter on a single axis
const punch = (() => {
  const singleAxis = [];
  const series = [];
  DAYS.forEach((day, idx) => {
    singleAxis.push({ left: 150, type: 'category', boundaryGap: false, data: HOURS, top: (idx * 100) / 7 + 5 + '%',
      height: 100 / 7 - 10 + '%', axisLabel: { interval: 2 } });
    const data = [];
    for (let h = 0; h < 24; h++) {
      const v = (idx * 5 + h * 3) % 11;
      if (v === 0) continue;
      data.push({ value: [h, v], symbolSize: v * 4 });
    }
    series.push(sc(data, { singleAxisIndex: idx }));
  });
  return { tooltip: { position: 'top' }, title: [], singleAxis, series };
})();
add('scatter', 'scatter-punch', 'the punch card: seven axes, a scatter on each, the sizes data-driven', punch);
add('scatter', 'scatter-value', 'a scatter on a value axis with labels',
  { singleAxis: { type: 'value', top: 150, bottom: 150 }, series: [sc([[3, 'a'], [12, 'b'], [25, 'c'], [7, 'd']].map(p => p[0]), { symbolSize: 16, label: { show: true, position: 'top' } })] });
add('scatter', 'scatter-vertical', 'a scatter on a vertical axis',
  { singleAxis: { type: 'value', orient: 'vertical', position: 'left', min: 0, max: 40, left: 200, width: 100 }, series: [sc([[5], [18], [33]], { symbolSize: 20 })] });
add('scatter', 'scatter-outside', 'points past the axis\' ends are drawn: a single axis has no clip area',
  { singleAxis: { type: 'value', min: 10, max: 20, top: 150, bottom: 150 }, series: [sc([[5, 1], [15, 1], [25, 1], [null, 1]])] });
add('scatter', 'effect-scatter', 'an effectScatter on a single axis',
  { singleAxis: { type: 'category', data: ['a', 'b', 'c', 'd'], top: 150, bottom: 150 },
    series: [{ type: 'effectScatter', coordinateSystem: 'singleAxis', data: [[0, 4], [2, 9], [3, 1]], symbolSize: 18 }] });
add('scatter', 'scatter-jitter', 'jitter 30 on a value axis (no band): every point moves across the axis at random',
  { singleAxis: { type: 'value', min: 0, max: 10, jitter: 30, top: 150, bottom: 150 }, series: [sc([[2, 1], [2, 1], [5, 1], [5, 1], [5, 1], [8, 1]], { symbolSize: 10 })] });
add('scatter', 'scatter-jitter-avoid', 'jitter 60, jitterOverlap false on a value axis: placed beside each other',
  { singleAxis: { type: 'value', min: 0, max: 10, jitter: 60, jitterOverlap: false, top: 150, bottom: 150 },
    series: [sc([[5, 1], [5, 1], [5, 1], [5.2, 1], [9, 1]], { symbolSize: 12 })] });
add('scatter', 'scatter-jitter-cat', 'jitter 20 on a category axis: along the axis inside the band',
  { singleAxis: { type: 'category', data: ['a', 'b', 'c'], jitter: 20, top: 150, bottom: 150 }, series: [sc([[0, 1], [0, 1], [1, 1], [2, 1], [2, 1]], { symbolSize: 8 })] });

add('scatter', 'scatter-jitter-vcat', 'jitter 20 on a vertical category axis: along the axis inside the band (isSingleY)',
  { singleAxis: { type: 'category', data: ['a', 'b', 'c'], orient: 'vertical', position: 'left', jitter: 20, left: 150, width: 200 },
    series: [sc([[0, 1], [0, 1], [1, 1], [2, 1]], { symbolSize: 8 })] });
add('scatter', 'scatter-jitter-vvalue', 'jitter 40 on a vertical value axis: across it',
  { singleAxis: { type: 'value', min: 0, max: 10, orient: 'vertical', position: 'right', jitter: 40, left: 150, width: 200 },
    series: [sc([[2, 1], [2, 1], [7, 1]], { symbolSize: 8 })] });

// ---- themeRiver
add('river', 'river-basic', 'three layers over a time axis, points missing (fixData\'s zeros)',
  { singleAxis: { type: 'time', top: 50, bottom: 50 }, series: [river(RIVER3)] });
add('river', 'river-value', 'four layers over a value axis',
  { singleAxis: { type: 'value', top: 60, bottom: 60 }, series: [river(RIVER_V)] });
add('river', 'river-category', 'a river over a category axis',
  { singleAxis: { type: 'category', data: ['p', 'q', 'r', 's'], top: 60, bottom: 60 },
    series: [river([['p', 4, 'x'], ['q', 6, 'x'], ['r', 2, 'x'], ['s', 5, 'x'], ['q', 3, 'y'], ['s', 7, 'y'], ['p', 1, 'y']])] });
add('river', 'river-gap', 'boundaryGap 20% and 30 px, label margin 10 and size 14',
  { singleAxis: { type: 'time', top: 40, bottom: 40 }, series: [river(RIVER3, { boundaryGap: ['20%', 30], label: { margin: 10, fontSize: 14 } })] });
add('river', 'river-many', 'six layers over twelve days',
  { singleAxis: { type: 'time', top: 50, bottom: 50, left: 60, right: 30 }, series: [river(RIVER6)] });
add('river', 'river-style', 'the series\' colours, an item style with border and opacity',
  { singleAxis: { type: 'time', top: 50, bottom: 50 },
    series: [river(RIVER3, { color: ['#c23531', '#2f4554', '#61a0a8'], itemStyle: { borderColor: '#333', borderWidth: 1, opacity: 0.8 } })] });
add('river', 'river-unnamed', 'an item without a name is dropped; a repeated time in a layer is kept',
  { singleAxis: { type: 'value', top: 80, bottom: 80 },
    series: [river([[1, 3, 'a'], [2, 5, 'a'], [3, 2], [3, 4, 'a'], [1, 2, 'b'], [2, 2, 'b'], [3, 6, 'b']])] });
add('river', 'river-two', 'two single axes, a river on each',
  { singleAxis: [{ type: 'time', top: 30, height: 140 }, { type: 'value', top: 220, height: 140 }],
    series: [river(RIVER3), river(RIVER_V, { singleAxisIndex: 1 })] });
add('river', 'river-label-formatter', "a label template over the layer's last row: its name and its value",
  { singleAxis: { type: 'value', top: 60, bottom: 60 }, series: [river(RIVER_V, { label: { formatter: '{b}: {c}', align: 'right' } })] });
add('river', 'river-time-numbers', "timestamps on a time axis: fixData's zero rows come back from their keys as no time",
  { singleAxis: { type: 'time', top: 60, bottom: 60 },
    series: [river([[1446940800000, 5, 'a'], [1447027200000, 8, 'a'], [1447113600000, 3, 'a'], [1446940800000, 2, 'b'], [1447113600000, 6, 'b']])] });
add('river', 'river-label-off', 'labels off',
  { singleAxis: { type: 'time', top: 50, bottom: 50 }, series: [river(RIVER3, { label: { show: false } })] });
add('river', 'river-inverse', 'an inverse time axis',
  { singleAxis: { type: 'time', inverse: true, top: 50, bottom: 50 }, series: [river(RIVER3)] });
add('river', 'river-vertical', 'a vertical axis: the layout still lays out across (upstream\'s), the x from the rect\'s centre',
  { singleAxis: { type: 'value', orient: 'vertical', position: 'left', left: 80, right: 80 }, series: [river(RIVER_V)] });
add('river', 'river-scatter', 'a river and a scatter on one axis',
  { singleAxis: { type: 'value', top: 60, bottom: 60 }, series: [river(RIVER_V), sc([[1.5, 1], [3.5, 1]], { symbolSize: 14 })] });

// ---- the legend
add('legend', 'legend-river', 'a legend of the layers, one switched off: its rows are filtered out',
  { legend: { data: ['DQ', 'TY', 'SS'], selected: { TY: false } }, singleAxis: { type: 'time', top: 50, bottom: 50 }, series: [river(RIVER3)] });
add('action', 'legend-toggle', 'legend actions: a layer off, another off, the first back',
  { legend: {}, singleAxis: { type: 'value', top: 60, bottom: 60 }, series: [river(RIVER_V)] }, {
    actions: [
      { type: 'legendUnSelect', name: 'b' },
      { type: 'legendToggleSelect', name: 'd' },
      { type: 'legendSelect', name: 'b' },
    ] });

// ---- the states
add('state', 'state-river', 'emphasis on a layer: focus self, an emphasis colour',
  { singleAxis: { type: 'value', top: 60, bottom: 60 },
    series: [river(RIVER_V, { emphasis: { focus: 'self', itemStyle: { color: '#ff0000' } }, blur: { itemStyle: { opacity: 0.3 } } })] }, {
    actions: [
      { type: 'highlight', seriesIndex: 0, dataIndex: 1 },
      { type: 'downplay', seriesIndex: 0, dataIndex: 1 },
      { type: 'highlight', seriesIndex: 0, dataIndex: 3 },
      { type: 'downplay', seriesIndex: 0, dataIndex: 3 },
      { type: 'highlight', seriesIndex: 0, dataIndex: 7 },
    ] });
add('state', 'state-river-series', 'two rivers, focus series with blurScope global: the other river blurs; the default lift',
  { singleAxis: [{ type: 'value', top: 30, height: 140 }, { type: 'value', top: 220, height: 140 }],
    series: [river(RIVER_V, { emphasis: { focus: 'series', blurScope: 'global' } }), river(RIVER_V, { singleAxisIndex: 1 })] }, {
    actions: [
      { type: 'highlight', seriesIndex: 0, dataIndex: 0 },
      { type: 'downplay', seriesIndex: 0, dataIndex: 0 },
      { type: 'highlight', seriesIndex: 1, dataIndex: 2 },
    ] });
add('state', 'state-river-label', "labels off: the emphasis label shows by the series' default",
  { singleAxis: { type: 'value', top: 60, bottom: 60 }, series: [river(RIVER_V, { label: { show: false } })] }, {
    actions: [
      { type: 'highlight', seriesIndex: 0, dataIndex: 1 },
      { type: 'downplay', seriesIndex: 0, dataIndex: 1 },
    ] });
add('state', 'state-scatter', 'a scatter on a single axis: emphasis and select',
  { singleAxis: { type: 'value', top: 150, bottom: 150 },
    series: [sc([[2, 1], [5, 1], [9, 1]], { symbolSize: 14, itemStyle: { color: '#5470c6' }, selectedMode: 'single',
      emphasis: { itemStyle: { color: '#ee6666' } }, select: { itemStyle: { color: '#91cc75' } } })] }, {
    actions: [
      { type: 'highlight', seriesIndex: 0, dataIndex: 1 },
      { type: 'select', seriesIndex: 0, dataIndex: 2 },
      { type: 'downplay', seriesIndex: 0, dataIndex: 1 },
    ] });

// ---- the pointer and the tooltip
const probesAlong = (y, xs) => xs.map(x => [x, y]);
add('pointer', 'ptr-river', 'the gallery\'s pointer: a line with its label, the tooltip lists every layer',
  { tooltip: { trigger: 'axis', axisPointer: { type: 'line', label: { show: true } } },
    singleAxis: { type: 'time', top: 50, bottom: 50, axisPointer: { label: { show: true } } }, series: [river(RIVER3)] }, {
    probes: probesAlong(200, [20, 30, 31, 84, 100, 165, 200, 251, 300, 389, 450, 520, 570, 580]).concat([[300, 40], [300, 51], [300, 349], [300, 360]]) });
add('pointer', 'ptr-river-shadow', 'a shadow pointer over a river on a value axis',
  { tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } }, singleAxis: { type: 'value', top: 60, bottom: 60 }, series: [river(RIVER_V)] }, {
    probes: probesAlong(200, [30, 31, 99, 150, 260, 301, 420, 569, 570]) });
// [milestone C6-C13] the axis starting at the first value: the shadow's low
// end is clamped to the axis start (calcAxisPointerShadowEnds' max), which a
// category band or a value axis from 0 never reaches
add('pointer', 'ptr-river-shadow-min', 'a shadow pointer on a value axis whose min is the first value: the band is cut at the axis start',
  { tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } }, singleAxis: { type: 'value', min: 1, top: 60, bottom: 60 }, series: [river(RIVER_V)] }, {
    probes: probesAlong(200, [30, 31, 60, 569, 570]) });
add('pointer', 'ptr-scatter-cat', 'a category axis with a scatter: shadow a band wide, the nearest row',
  { tooltip: { trigger: 'axis', axisPointer: { type: 'shadow', label: { show: true } } },
    singleAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e'], top: 150, bottom: 150 }, series: [sc([[0, 1], [1, 1], [3, 1]], { symbolSize: 10 })] }, {
    probes: probesAlong(200, [30, 60, 140, 141, 250, 300, 360, 470, 569, 571]) });
add('pointer', 'ptr-scatter-value', 'a value axis with a scatter: the line snaps to the nearest value',
  { tooltip: { trigger: 'axis', axisPointer: { label: { show: true, precision: 1 } } },
    singleAxis: { type: 'value', min: 0, max: 20, top: 150, bottom: 150 }, series: [sc([[3, 1], [11, 1], [17, 1]], { symbolSize: 10 })] }, {
    probes: probesAlong(200, [30, 100, 200, 300, 400, 500, 570]).concat([[300, 100], [300, 250]]) });
add('pointer', 'ptr-vertical', 'a vertical axis: the pointer line sits at the rect\'s centre (upstream\'s), its label moves',
  { tooltip: { trigger: 'axis', axisPointer: { label: { show: true } } },
    singleAxis: { type: 'value', orient: 'vertical', position: 'left', min: 0, max: 40, left: 200, width: 200 }, series: [sc([[5], [18], [33]], { symbolSize: 12 })] }, {
    probes: [[300, 30], [300, 100], [300, 200], [300, 300], [300, 370], [250, 250]] });
add('pointer', 'ptr-two', 'two single axes, each takes the pointer over its own rect',
  { tooltip: { trigger: 'axis', axisPointer: { label: { show: true } } },
    singleAxis: [{ type: 'value', min: 0, max: 10, top: 40, height: 100 }, { type: 'category', data: ['x', 'y', 'z'], top: 220, height: 100 }],
    series: [sc([[2, 1], [7, 1]], { symbolSize: 10 }), sc([[0, 1], [2, 1]], { singleAxisIndex: 1, symbolSize: 10 })] }, {
    probes: [[100, 90], [300, 90], [100, 270], [300, 270], [500, 270], [300, 180]] });

// ---- dataZoom
add('zoom', 'zoom-slider-river', 'a slider on the river\'s time axis, 20% .. 80%',
  { dataZoom: [{ type: 'slider', singleAxisIndex: 0, start: 20, end: 80 }], singleAxis: { type: 'time', top: 50, bottom: 80 }, series: [river(RIVER3)] });
add('zoom', 'zoom-inside-scatter', 'an inside zoom on a value axis, startValue / endValue: rows filtered',
  { dataZoom: [{ type: 'inside', singleAxisIndex: [0], startValue: 4, endValue: 12 }], singleAxis: { type: 'value', top: 150, bottom: 150 },
    series: [sc([[1, 1], [3, 1], [5, 1], [9, 1], [12, 1], [15, 1]], { symbolSize: 10 })] });
add('zoom', 'zoom-auto', 'a dataZoom with no target: the first horizontal single axis',
  { dataZoom: [{ type: 'slider', start: 10, end: 60 }], singleAxis: [{ type: 'value', orient: 'vertical', position: 'left', left: 40, width: 100 },
    { type: 'value', top: 100, bottom: 200 }], series: [sc([[1, 1], [5, 1], [9, 1]]), sc([[2, 1], [4, 1], [8, 1], [10, 1]], { singleAxisIndex: 1 })] });
add('zoom', 'zoom-empty', 'filterMode empty on a category axis',
  { dataZoom: [{ type: 'inside', singleAxisIndex: 0, start: 25, end: 75, filterMode: 'empty' }],
    singleAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e'], top: 150, bottom: 150 }, series: [sc([[0, 1], [1, 1], [2, 1], [3, 1], [4, 1]], { symbolSize: 10 })] });

// ---- the conversions
const cvAll = (finders, values, pixels) => {
  const out = [];
  finders.forEach(f => {
    values.forEach(v => out.push(['to', f, v]));
    pixels.forEach(p => out.push(['from', f, p]));
    pixels.forEach(p => out.push(['contain', f, p]));
  });
  return out;
};
add('convert', 'cv-single', 'single-axis finders on two singles beside a grid',
  { grid: { left: 20, right: 320, top: 20, bottom: 300 }, xAxis: { type: 'value' }, yAxis: { type: 'value' },
    singleAxis: [{ type: 'value', min: 0, max: 100, id: 'sa', name: 'first', left: 320, right: 20, top: 40, height: 60 },
      { type: 'category', data: ['a', 'b', 'c', 'd'], id: 'sb', left: 320, right: 20, top: 200, height: 60 }],
    series: [{ type: 'scatter', data: [[1, 2]] }, sc([[10, 1], [50, 1]]), sc([[1, 1]], { singleAxisIndex: 1 })] }, {
    probes: cvAll(['singleAxis', { singleAxisIndex: 0 }, { singleAxisIndex: 1 }, { singleAxisId: 'sb' }, { singleAxisName: 'first' },
      { seriesIndex: 1 }, { seriesIndex: 2 }, { seriesIndex: 0 }, { singleAxisIndex: 'all' }, { singleAxisIndex: 5 }],
    [50, [25], [[75]], '12', null, 'b', 1.4, [], true, -10],
    [[470, 70], [320, 40], [580, 100], [580, 101], [319, 70], [470, 230], ['500', '230'], [null, 70], [470]]) });
add('convert', 'cv-vertical', 'a vertical single: the x is the rect\'s centre; containPoint compares x with the rect\'s y (upstream\'s)',
  { singleAxis: { type: 'value', min: 0, max: 50, orient: 'vertical', position: 'left', left: 100, width: 200, top: 20, bottom: 30 } }, {
    probes: cvAll(['singleAxis'], [0, 25, 50, [10]], [[200, 100], [150, 100], [30, 100], [350, 100], [200, 10], [301, 200], [21, 200]]) });

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function runCase(c) {
  const fails = [];
  const option = clone(c.option);
  option.animation = false;
  const written = clone(option);
  rngState = SEED;
  draws = 0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: c.W, height: c.H });
  if (c.group === 'state' || c.group === 'action') chart._ssr = false;
  try {
    const rec = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: written };
    quiet(() => { chart.setOption(option); chart.renderToSVGString(); });
    rec.draws = draws;
    rec.singles = readSingles(chart, c, fails);
    rec.series = readSeries(chart, c, fails);
    rec.zoom = readZoom(chart);
    if (c.group === 'pointer') rec.pointer = c.probes.map(([x, y]) => readPointer(chart, c, x, y));
    if (c.group === 'convert') rec.convert = runConvert(chart, c);
    if (c.group === 'state') rec.states = runStates(chart, c);
    if (c.group === 'action') {
      rec.after = c.actions.map(a => {
        quiet(() => { chart.dispatchAction(clone(a)); chart._onframe(); chart.renderToSVGString(); });
        return { action: clone(a), singles: readSingles(chart, c, fails), series: readSeries(chart, c, fails) };
      });
    }
    rec.fails = fails;
    return rec;
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// the animations (animation.js' harness: its clock, samples and records)
// ---------------------------------------------------------------------------
const AW = 400;
const AH = 300;
const SAMPLES = [0, 1, 16, 50, 100, 250, 500, 750, 999, 1000, 1001, 1500];
const FNS = { 'idx*50': idx => idx * 50, 'idx*30': idx => idx * 30, 'dur:600+idx*100': idx => 600 + idx * 100 };
function materialize(v) {
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    if (typeof v.$fn === 'string') {
      must(FNS[v.$fn], 'unknown $fn ' + v.$fn);
      return FNS[v.$fn];
    }
    const o = {};
    for (const k of Object.keys(v)) o[k] = materialize(v[k]);
    return o;
  }
  return v;
}
function fnName(f) {
  for (const k of Object.keys(FNS)) if (FNS[k] === f) return { $fn: k };
  return { $fn: '?' };
}
const optVal = v => (typeof v === 'function' ? fnName(v) : v === undefined ? null : v);
const TRANSFORM_KEYS = ['x', 'y', 'scaleX', 'scaleY', 'rotation', 'originX', 'originY', 'skewX', 'skewY'];
const STYLE_KEYS = ['opacity', 'fill', 'stroke', 'lineWidth', 'text', 'x', 'y', 'fillOpacity', 'strokeOpacity'];
function flatNums(v, out) {
  for (let i = 0; i < v.length; i++) {
    const e = v[i];
    if (e != null && typeof e === 'object' && e.length != null) flatNums(e, out);
    else out.push(typeof e === 'number' ? e : NaN);
  }
  return out;
}
function encA(v) {
  if (typeof v === 'number') return [hex(v), text(v)];
  if (typeof v === 'string' || typeof v === 'boolean') return [v, v];
  if (v && typeof v === 'object' && v.length != null && typeof v !== 'string') {
    const f = flatNums(v, []);
    return [f.map(hex), f.map(text)];
  }
  if (v && typeof v === 'object' && v.colorStops) {
    const s = JSON.stringify(v);
    return [s, s];
  }
  return undefined;
}
function snap(el) {
  const o = {};
  const put = (k, v) => {
    const e = encA(v);
    if (e !== undefined) o[k] = e;
  };
  for (const k of TRANSFORM_KEYS) if (typeof el[k] === 'number') put(k, el[k]);
  put('ignore', !!el.ignore);
  if (el.invisible != null) put('invisible', !!el.invisible);
  if (el.style) for (const k of STYLE_KEYS) if (el.style[k] != null) put('style.' + k, el.style[k]);
  if (el.shape) for (const k of Object.keys(el.shape)) if (el.shape[k] != null) put('shape.' + k, el.shape[k]);
  return o;
}
const sameJ = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function walkView(root) {
  const out = [];
  const visit = (el, p) => {
    out.push({ el, role: 'el', path: p });
    const cl = el.getClipPath && el.getClipPath();
    if (cl) out.push({ el: cl, role: 'clip', path: p + '#clip' });
    const label = el.getTextContent && el.getTextContent();
    if (label) out.push({ el: label, role: 'label', path: p + '#label' });
    const guide = el.getTextGuideLine && el.getTextGuideLine();
    if (guide) out.push({ el: guide, role: 'guide', path: p + '#guide' });
    if (el.isGroup) el.childrenRef().forEach((ch, i) => visit(ch, p === '' ? String(i) : p + '.' + i));
  };
  visit(root, '');
  return out;
}
function views(chart) {
  const out = [];
  chart.getModel().eachSeries(s => {
    const v = chart.getViewOfSeriesModel(s);
    if (v) out.push({ owner: 'series' + s.seriesIndex + ':' + s.subType, series: true, group: v.group });
  });
  (chart._componentsViews || []).forEach(v => {
    const m = v.__model;
    if (m && v.group) out.push({ owner: m.mainType + m.componentIndex, series: false, group: v.group });
  });
  return out;
}
function clipCount(zr) {
  let n = 0;
  for (let cl = zr.animation._head; cl; cl = cl.next) n++;
  return n;
}
function recordTimeline(chart, start) {
  const zr = chart.getZr();
  const ids = new Map();
  const recs = [];
  const clips = [];
  SAMPLES.forEach((t, si) => {
    NOW = start + t;
    if (si === 0) {
      for (let cl = zr.animation._head; cl; cl = cl.next) must(cl._inited, 'a clip was not stepped by the setOption flush');
    }
    else zr.animation.update();
    zr.storage.getDisplayList(true);
    clips.push(clipCount(zr));
    for (const v of views(chart)) {
      for (const it of walkView(v.group)) {
        let rec = ids.get(it.el);
        if (!rec) {
          const ecd = ecDataOf(it.el);
          rec = { id: v.owner + '/' + (it.path === '' ? 'root' : it.path), owner: v.owner, series: v.series, role: it.role,
            type: it.el.type, dataIndex: ecd && ecd.dataIndex != null ? ecd.dataIndex : null,
            snaps: new Array(SAMPLES.length).fill(null), anim: new Array(SAMPLES.length).fill(0), scopes: new Set() };
          ids.set(it.el, rec);
          recs.push(rec);
        }
        rec.snaps[si] = snap(it.el);
        rec.anim[si] = it.el.animators ? it.el.animators.length : 0;
        (it.el.animators || []).forEach(a => rec.scopes.add(a.scope == null ? '' : a.scope));
      }
    }
  });
  const seen = new Map();
  const elements = [];
  for (const rec of recs) {
    const presentIdx = [];
    rec.snaps.forEach((s, i) => { if (s) presentIdx.push(i); });
    const keys = new Set();
    presentIdx.forEach(i => Object.keys(rec.snaps[i]).forEach(k => keys.add(k)));
    const lastI = presentIdx[presentIdx.length - 1];
    const final = {};
    const finalText = {};
    const track = {};
    const trackText = {};
    for (const k of [...keys].sort()) {
      const vals = presentIdx.map(i => rec.snaps[i][k]);
      const constant = vals.every(v => v !== undefined && sameJ(v[0], vals[0][0]));
      const last = rec.snaps[lastI][k];
      if (last !== undefined) {
        final[k] = last[0];
        finalText[k] = last[1];
      }
      if (!constant) {
        track[k] = rec.snaps.map(s => (s && s[k] !== undefined ? s[k][0] : null));
        trackText[k] = rec.snaps.map(s => (s && s[k] !== undefined ? s[k][1] : null));
      }
    }
    const everAnim = rec.anim.some(n => n > 0);
    if (!rec.series && !everAnim && Object.keys(track).length === 0) continue;
    let id = rec.id + (rec.role !== 'el' && !rec.id.includes('#') ? '#' + rec.role : '');
    const n = seen.get(id) || 0;
    seen.set(id, n + 1);
    if (n) id += '~' + n;
    elements.push({ id, owner: rec.owner, role: rec.role, type: rec.type, dataIndex: rec.dataIndex,
      present: presentIdx.length === SAMPLES.length ? null : presentIdx, final, finalText,
      track: Object.keys(track).length ? track : null, trackText: Object.keys(track).length ? trackText : null,
      animators: everAnim ? rec.anim : null, scopes: [...rec.scopes].sort() });
  }
  return { clips, elements };
}
function resolvedOf(chart) {
  const out = [];
  chart.getModel().eachSeries(s => {
    const g = k => optVal(s.getShallow(k));
    out.push({ seriesIndex: s.seriesIndex, type: s.subType, dataCount: s.getData().count(),
      animationOption: g('animation'), threshold: g('animationThreshold'), enabled: !!s.isAnimationEnabled(),
      duration: g('animationDuration'), easing: g('animationEasing'), delay: g('animationDelay'),
      durationUpdate: g('animationDurationUpdate'), easingUpdate: g('animationEasingUpdate'), delayUpdate: g('animationDelayUpdate') });
  });
  return out;
}
const ACASES = [];
const aadd = (id, note, option) => ACASES.push({ id, note, option: Object.assign({ useUTC: true, color: PALETTE }, option) });
const AR = [D(8, 10, 'A'), D(9, 15, 'A'), D(10, 35, 'A'), D(11, 20, 'A'), D(8, 35, 'B'), D(10, 10, 'B'), D(11, 12, 'B'), D(9, 20, 'C'), D(10, 8, 'C')];
aadd('river.default', 'a themeRiver\'s enter: each layer\'s clip rect widens from nothing, linear (the series\' default easing)',
  { singleAxis: { type: 'time', top: 30, bottom: 30 }, series: [river(AR)] });
aadd('river.override', 'the same, duration 600, cubicOut, delay 100, labels off',
  { singleAxis: { type: 'time', top: 30, bottom: 30 }, series: [river(AR, { animationDuration: 600, animationEasing: 'cubicOut', animationDelay: 100, label: { show: false } })] });
aadd('river-value.delayFn', 'a river on a value axis, animationDelay (idx) => idx * 50 -- the clip has no row',
  { singleAxis: { type: 'value', top: 30, bottom: 30 }, series: [river(RIVER_V, { animationDelay: { $fn: 'idx*50' } })] });
aadd('single-scatter.default', 'a scatter on a single axis: the symbols pop in',
  { singleAxis: { type: 'value', top: 100, bottom: 100 }, series: [sc([[2, 1], [5, 1], [9, 1]], { symbolSize: 14 })] });

function runAnim(ac) {
  NOW = T_BASE;
  rngState = SEED;
  echarts.env.node = false;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: AW, height: AH });
  chart._ssr = false;
  try {
    chart.setOption(materialize(ac.option));
    const tl = recordTimeline(chart, T_BASE);
    const parts = ac.id.split('.');
    return { id: ac.id, kind: 'enter', chart: parts[0], variant: parts[1], note: ac.note, option: ac.option, next: null,
      W: AW, H: AH, resolved: resolvedOf(chart), clips: tl.clips, elements: tl.elements };
  } finally {
    chart.dispose();
    echarts.env.node = ENV_NODE;
  }
}

// ---------------------------------------------------------------------------
// named guards
// ---------------------------------------------------------------------------
function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => out.cases.find(q => q.id === id);
  out.cases.forEach(q => guard(q.id + ': every record matches its recipe', q.fails.length === 0));
  const s0 = id => cs(id).singles[0];
  const r0 = id => cs(id).series[0];
  // the single
  guard('the default box is 5% on every side', s0('axis-value-h').rect.map(numOf).join() === [30, 20, 540, 360].join());
  guard('a horizontal axis spans the rect\'s width', numOf(s0('axis-value-h').extent[1]) === 540);
  guard('a vertical axis spans the rect\'s height', numOf(s0('axis-value-v-left').extent[1]) === numOf(s0('axis-value-v-left').rect[3]));
  guard('an inverse axis runs from the far end', numOf(s0('axis-value-v-right').extent[0]) > 0 && numOf(s0('axis-value-v-right').extent[1]) === 0);
  guard('the split lines are drawn on a category axis (the single\'s own default)', s0('axis-category-h').view.splitLines.length === 5);
  guard('the ticks are drawn on a category axis, on every other band edge', s0('axis-category-h').view.ticks.length === 5);
  guard('a top axis\' label rotation is negated', s0('axis-value-top').view.labels.every(l => numOf(l.rotation) < 0));
  guard('a vertical left axis\' labels are right-aligned', s0('axis-value-v-left').view.labels.every(l => l.align === 'right'));
  guard('inside labels flip their side', s0('axis-inside').view.labels.every(l => l.va === 'bottom'));
  guard('two split-line colours alternate', s0('axis-split').view.splitLines.some(l => l.ci === 1));
  guard('split areas cycle three colours', new Set(s0('axis-split').view.splitAreas.map(a => a.fill)).size === 3);
  guard('seven punch-card frames', cs('axis-multi').singles.length === 7);
  guard('hideOverlap hides some labels', s0('axis-hide-overlap').view.labels.some(l => l.ignore));
  guard('a hidden axis draws nothing', !s0('axis-hidden').view.shown && cs('axis-hidden').series[0].symbols.every(p => p.drawn));
  guard('the axis is sized by its series', numOf(s0('axis-data-extent').scale[1]) >= 41.5 && numOf(s0('axis-data-extent').scale[0]) <= 3.2);
  // scatter
  guard('the punch card sizes come from the data', cs('scatter-punch').series[0].symbols.some(p => numOf(p.size) === 8));
  guard('a scatter sits on the rect\'s middle line', r0('scatter-value').symbols.every(p => numOf(p.ly) === 200));
  guard('a vertical scatter sits on the rect\'s middle column', r0('scatter-vertical').symbols.every(p => numOf(p.lx) === 250));
  guard('a point past the axis is still drawn', r0('scatter-outside').symbols[0].drawn && r0('scatter-outside').symbols[2].drawn);
  guard('a point with no value is not drawn', !r0('scatter-outside').symbols[3].drawn);
  guard('jitter draws a number per point', cs('scatter-jitter').draws === 6);
  guard('jitter moves across a value axis', r0('scatter-jitter').symbols.every(p => numOf(p.ly) !== 200 && numOf(p.lx) === numOf(p.x)));
  guard('jitter moves along a category axis', r0('scatter-jitter-cat').symbols.some(p => numOf(p.ly) === 200 && (numOf(p.lx) - 30) % 1 !== 0));
  guard('jitterOverlap false places the first point without a draw', cs('scatter-jitter-avoid').draws < 5);
  // the river
  guard('fixData fills the missing points with zeros', r0('river-basic').count === 18 && r0('river-basic').rows.filter(r => numOf(r.value) === 0).length === 2);
  guard('the layers keep their first-seen order', r0('river-basic').layers.map(l => l.name).join() === 'DQ,TY,SS');
  guard('the default gap is 10% of the rect\'s height', numOf(r0('river-basic').gap[0]) === 30);
  guard('the polygon group sits at the rect\'s top plus the gap', numOf(r0('river-basic').groupY) === 80);
  guard('the layer\'s ECData is its index', r0('river-basic').layers.every((l, k) => l.dataIndex === k));
  guard('a label hangs left-aligned at the first point less the margin', r0('river-basic').layers.every(l => l.label && l.label.drawn && l.label.align == null && l.label.va === 'middle'));
  guard('a named gap in px stays px', numOf(r0('river-gap').gap[1]) === 30);
  guard('an unnamed item is dropped', r0('river-unnamed').rows.every(r => r.name !== '' && r.name != null));
  guard('labels off draw no label', r0('river-label-off').layers.every(l => !l.label || !l.label.drawn));
  guard('a vertical river puts every x at the rect\'s centre', r0('river-vertical').rows.every(r => numOf(r.x) === 300));
  guard('the series\' colours paint the layers', r0('river-style').layers.map(l => l.fill).join() === '#c23531,#2f4554,#61a0a8');
  // the legend
  guard('a legend-hidden layer is gone', r0('legend-river').layers.length === 2 && !r0('legend-river').layers.some(l => l.name === 'TY'));
  guard('legend actions filter the layers', cs('legend-toggle').after[0].series[0].layers.length === 3
    && cs('legend-toggle').after[1].series[0].layers.length === 2 && cs('legend-toggle').after[2].series[0].layers.length === 3);
  guard('the hidden layers keep their colours', cs('legend-toggle').after[1].series[0].layers.every(l =>
    l.fill === cs('legend-toggle').series[0].layers.find(q => q.name === l.name).fill));
  // states
  const st = cs('state-river').states;
  guard('highlight paints layer 1 in the emphasis colour', st[0].items.some(it => it.i === 1 && it.fill === '#ff0000' && it.states.includes('emphasis')));
  guard('focus self blurs the other layers', st[0].items.some(it => it.i !== 1 && it.states.includes('blur')));
  guard('the emphasis label shows by default', cs('state-river-label').states[0].items.some(it => it.i === 1 && it.labelShown === true)
    && cs('state-river-label').states[1].items.every(it => it.labelShown === false));
  guard('a data index past the layers highlights nothing', st[4].items.every(it => !it.states.includes('emphasis')));
  guard('focus series blurs the other river', cs('state-river-series').states[0].items.some(it => it.s === 1 && it.states.includes('blur')));
  // pointer
  const pr = cs('ptr-river').pointer;
  guard('the river pointer lists every layer', pr.some(p => p.tip && p.tip[0] && p.tip[0][0].series.length === 3));
  guard('the river pointer draws a line with a label', pr.some(p => p.axes.length && p.axes[0].el && p.axes[0].el.type === 'line' && p.axes[0].label));
  guard('outside the rect there is no pointer', pr.find(p => p.x === 300 && p.y === 40).axes.length === 0);
  guard('the shadow is a rect', cs('ptr-river-shadow').pointer.some(p => p.axes.length && p.axes[0].el.type === 'rect'));
  guard('the vertical pointer line stays at the rect\'s centre', cs('ptr-vertical').pointer.filter(p => p.axes.length).every(p => numOf(p.axes[0].el.shape[1]) === 300));
  guard('two singles each take their own pointer', cs('ptr-two').pointer.filter(p => p.axes.length && p.axes[0].single === 1).length >= 2);
  // zoom
  guard('the slider sits under the single\'s rect', cs('zoom-slider-river').zoom.length === 1);
  guard('the inside zoom filters the rows', r0('zoom-inside-scatter').count === 3);
  guard('the auto target is the horizontal single', cs('zoom-auto').series[1].count < 4 && cs('zoom-auto').series[0].count === 3);
  // convert
  const cv = cs('cv-single').convert;
  guard('a bare singleAxis finder converts', cv.some(p => p.finder.text === '"singleAxis"' && p.op === 'to' && p.out.k === 'arr'));
  guard('a single-axis series finder converts on its axis', cv.some(p => p.finder.text === '{"seriesIndex":2}' && p.op === 'to' && p.out.k === 'arr'));
  guard('from pixel is one number in an array', cv.some(p => p.finder.text === '"singleAxis"' && p.op === 'from' && p.out.k === 'arr' && p.out.v.length === 1));
  guard('a string category is not a number to dataToPoint', cv.some(p => p.finder.text === '{"singleAxisIndex":1}' && p.value.text === '"b"' && p.out.k === 'arr' && p.out.v[0] === '7ff8000000000000'));
  guard('null converts as 0', cv.some(p => p.finder.text === '"singleAxis"' && p.op === 'to' && p.value.text === 'null' && p.out.k === 'arr'));
  guard('containPixel on a single', cv.some(p => p.op === 'contain' && p.out.k === 'bool' && p.out.v === true));
  // animations
  const an = id => out.anim.cases.find(q => q.id === id);
  guard('a river layer\'s clip widens', an('river.default').elements.some(e => e.role === 'clip' && e.track && e.track['shape.width'] && e.track['shape.x']));
  guard('the river\'s easing is linear by default', an('river.default').resolved[0].easing === 'linear');
  guard('every animation settles by 1500', out.anim.cases.every(c => c.clips[c.clips.length - 1] === 0));
  return g;
}

function generate() {
  NOW = T_BASE;
  const out = {
    source: DIST, version: echarts.version, seed: SEED,
    notes: [
      'static cases: animation false, 600 x 400, one renderToSVGString; labels read as updateInnerText left them (innerTransformable).',
      'Math.random is the port\'s xorshift32 from ' + SEED + ', reset before every chart.',
      'merged paths: each split line read as mergePath merged it (Path.getUpdatedPathProxy), the bundles in colour order.',
      'pointer: updateAxisPointer at integer pixels; the showTip payload caught as the action\'s event.',
      'state and action cases: chart._ssr false, each action followed by a frame (_onframe) and a render.',
      'anim: animation.js\' harness -- the Date hook, chart._ssr false before setOption, env.node false while a case runs, 400 x 300.',
    ],
    cases: CASES.map(runCase),
    anim: { samplesMs: SAMPLES, clock: { T0: T_BASE }, cases: ACASES.map(runAnim) },
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
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
out1.cases.forEach(q => q.fails.slice(0, 8).forEach(f => console.log('  ' + q.id + ': ' + f)));
const deterministic = json1 === json2;
console.log(out1.cases.length + ' cases, ' + out1.anim.cases.length + ' animation cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
