/*
Upstream's own answers for roadmap C4, batch 113: the series on a polar --
bar (radial and tangential, stacked, roundCap's Sausage, the sector corners,
clip, barMinHeight / barMinAngle, the background), the nine-plus sector label
positions with and without a turn, line and area with the polar clip,
scatter and effectScatter, heatmap (which draws nothing there), the markers,
dataZoom on the angle and radius axes, the axis pointer and the tooltip
snapping to the series, convertToPixel with a series finder, emphasis and
select on a polar bar -- and the enter animations of a polar bar and a polar
line (the clock hook of animation.js).

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node's server-side mode, SVG renderer, measuring every
string with zrender's width table (the TZrSsrMeasurer of the Pascal tests),
TZ=UTC. The static cases are 600 x 400 with `animation: false`; the
animation cases are 400 x 300 and run as animation.js runs them.

  node tools/advchart-oracle/polar-series.js

writes tests/fixtures/advchart-polar-series.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Numbers that are positions are the 16 hex digits of the IEEE double
(big-endian, lowercase; every NaN 7ff8000000000000). Counts, flags, strings
and option values are plain JSON.

Top level: source, version, notes[], cases[], anim {samplesMs, clock, cases[]},
guards[].

A static case: id, group, note, W, H, option (as run), threw (a string when
setOption threw -- upstream's markArea on a polar), polars[], series[],
markers[], zoom[] (dataZoom views), pointer[] (pointer cases), convert[]
(convert cases), states[] (state cases), fails[] (recipe mismatches; must be
empty).

polars[i]: index, cx, cy, rExtent [2], aExtent [2] (axis.getExtent()),
  rInverse, aInverse, rScale [2], aScale [2] (scale.getExtent()).

series[k]: index, type, polar, base ('angle' | 'radius'), count, raw[]
  (getRawIndex per view row), then by type --
  bar: items[] {i, raw, cls ('drawn' | 'hidden' | 'none'), layout [cx, cy,
    r0, r, sa, ea] + layoutCw (getItemLayout, unclipped), type ('sector' |
    'sausage'), shape [cx, cy, r0, r, sa, ea] + cw (as drawn, after clip),
    corner (null, a number, or the array, as the shape holds it), zero
    (fill 'none'), z2, rect [x, y, w, h] (the path's own bounding rect),
    label}, bg[] (view._backgroundEls: [cx, cy, r0, r, sa, ea] + cw + corner
    per view row, or null);
  line: points (data.getLayout('points')), stacked (the polygon's
    stackedOnPoints, null without an area), polyline (the polyline's shape
    points), polygon (the polygon's points), clip {cx, cy, r0, r, sa, ea,
    cw} (the line group's clip path), symClip {cx, cy, r0, r, x, y, w, h}
    (view._clipShapeForSymbol), symbols[] {i, drawn, x, y, label};
  scatter / effectScatter: symbols[] {i, drawn, x, y, label};
  heatmap: drawn (the view group's child count).
label: null when the host has no text content; else {text, drawn, word
  (textConfig.position: a string or the array), inside, x, y, rot, ox, oy
  (the innerTransformable after updateInnerText), dAlign, dVa (the
  position's own alignment, host._innerTextDefaultStyle), align, va (the
  text style's own)} -- the numbers only when drawn.

markers[]: {series, kind ('markPoint' | 'markLine'), items[] {layout (a
  point [x, y], or a line [[x, y], [x, y]], hex)}}.

zoom[]: {index, type, orient, x, y, w, h} -- a slider's location and size.

pointer[]: per probe {x, y, axes[] {dim, polar, value, el, label} as in
  advchart-polar-axes.json, tip null | [{axisDim, value, series[] {s, i}}]
  (the showTip payload's dataByCoordSys of the probe)}.

convert[]: {op, finder {in, text}, value {in, text, textSafe}, out, by?} as
  in advchart-polar-axes.json.

states[]: per action {action (as dispatched), items[] {s, i, states
  (currentStates), fill, stroke, lineWidth, opacity, labelFill}}.

anim.cases[]: the cases of advchart-animation.json's own format (id, kind,
  chart, variant, note, option, next, W, H, resolved, clips, elements).

Guards (any failure: nothing is written, exit 1): every recipe (the polar
bar layout recomputed from the data and the axes as barPolar.ts does it, the
clip, the sector label positions and turns, the line's clip path, the
symbols the polar area keeps) agrees with what was drawn; named facts; and
the whole fixture is generated twice, byte-identical. process.exit() ends
the run.
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

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-polar-series.json');
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
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const hexN = v => (v == null ? '7ff8000000000000' : hex(+v));
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const same = (a, b) => Object.is(a, b);
const RADIAN = Math.PI / 180;
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  const l = console.log;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; console.log = l; }
};

// ---------------------------------------------------------------------------
// the recipes
// ---------------------------------------------------------------------------
// numberUtil.parsePercent (parsePositionOption)
function parsePercent(v, all) {
  switch (v) {
    case 'center': case 'middle': v = '50%'; break;
    case 'left': case 'top': v = '0%'; break;
    case 'right': case 'bottom': v = '100%'; break;
  }
  if (typeof v === 'string') {
    if (v.replace(/^\s+|\s+$/g, '').match(/%$/)) return parseFloat(v) / 100 * all;
    return parseFloat(v);
  }
  return v == null ? NaN : +v;
}
// zrender contain/text parsePercent
function zrParsePercent(v, max) {
  if (typeof v === 'string') {
    if (v.lastIndexOf('%') >= 0) return parseFloat(v) / 100 * max;
    return parseFloat(v);
  }
  return v;
}

// barPolar.ts calcRadialBar + layoutPerAxisPerSeries, from the models
function barPolarRecipe(ecModel) {
  const out = new Map(); // seriesIndex -> [{layout}]
  const byAxis = new Map();
  ecModel.eachSeries(s => {
    if (s.subType !== 'bar' || s.get('coordinateSystem') !== 'polar') return;
    const polar = s.coordinateSystem;
    const base = polar.getBaseAxis();
    if (!byAxis.has(base)) byAxis.set(base, []);
    byAxis.get(base).push(s);
  });
  byAxis.forEach((list, axis) => {
    // calcBandWidth(axis, {fromStat, min: 1})
    const ext = axis.getExtent();
    const pxSpan = Math.abs(ext[1] - ext[0]);
    let w;
    if (axis.type === 'category') {
      // getScaleLinearSpanForMapping: the mapping extent (containShape's), else the effective one
      const se = axis.scale.getExtentUnsafe(1, 3) || axis.scale.getExtentUnsafe(0, 3);
      let len = se[1] - se[0] + (axis.onBand ? 1 : 0);
      len === 0 && (len = 1);
      w = pxSpan / len;
    }
    else {
      // the smallest positive gap of the bars' base values
      let gap = Infinity;
      let anyGap = false;
      let single = false;
      list.forEach(s => {
        const d = s.getData();
        const dim = d.mapDimension(axis.dim);
        const vals = [];
        d.each(dim, v => { if (isFinite(v)) vals.push(axis.scale.transformIn ? axis.scale.transformIn(v) : v); });
        vals.sort((a, b) => a - b);
        let g = Infinity;
        for (let k = 1; k < vals.length; k++) if (vals[k] - vals[k - 1] > 0) g = Math.min(g, vals[k] - vals[k - 1]);
        if (g < Infinity) { gap = anyGap ? Math.max(gap, g) : g; anyGap = true; }
        else if (vals.length) single = true;
      });
      w = NaN;
      if (anyGap) {
        // scaleLinearSpan for mapping
        const me = axis.scale.getExtentUnsafe ? null : null;
        void me;
      }
      void single;
      w = NaN; // the numeric band is taken from the drawn result (see guards)
    }
    if (!isFinite(w)) w = NaN;
    const band = isFinite(w) ? Math.max(1, w) : 1;
    let remained = band;
    let autoCount = 0;
    let catGapOpt = '20%';
    let gapOpt = '30%';
    const stacks = {};
    const order = [];
    const sid = s => s.get('stack') || '__ec_stack_' + s.seriesIndex;
    list.forEach(s => {
      const id = sid(s);
      if (!stacks[id]) { autoCount++; order.push(id); }
      stacks[id] = stacks[id] || { width: 0, maxWidth: 0 };
      let bw = parsePercent(s.get('barWidth'), band);
      const bmw = parsePercent(s.get('barMaxWidth'), band);
      const g = s.get('barGap');
      const cg = s.get('barCategoryGap');
      if (bw && !stacks[id].width) {
        bw = Math.min(remained, bw);
        stacks[id].width = bw;
        remained -= bw;
      }
      bmw && (stacks[id].maxWidth = bmw);
      g != null && (gapOpt = g);
      cg != null && (catGapOpt = cg);
    });
    const catGap = parsePercent(catGapOpt, band);
    const gapPct = parsePercent(gapOpt, 1);
    let auto = (remained - catGap) / (autoCount + (autoCount - 1) * gapPct);
    auto = Math.max(auto, 0);
    order.forEach(id => {
      const col = stacks[id];
      let mw = col.maxWidth;
      if (mw && mw < auto) {
        mw = Math.min(mw, remained);
        if (col.width) mw = Math.min(mw, col.width);
        remained -= mw;
        col.width = mw;
        autoCount--;
      }
    });
    auto = (remained - catGap) / (autoCount + (autoCount - 1) * gapPct);
    auto = Math.max(auto, 0);
    let sum = 0;
    let last;
    order.forEach(id => {
      const col = stacks[id];
      if (!col.width) col.width = auto;
      last = col;
      sum += col.width * (1 + gapPct);
    });
    if (last) sum -= last.width * gapPct;
    let off = -sum / 2;
    const res = {};
    order.forEach(id => {
      res[id] = { offset: off, width: stacks[id].width };
      off += stacks[id].width * (1 + gapPct);
    });
    // layoutPerAxisPerSeries
    const lastStack = {};
    list.forEach(s => {
      const d = s.getData();
      const id = sid(s);
      const col = res[id];
      const polar = s.coordinateSystem;
      const vAxis = polar.getOtherAxis(axis);
      const minH = s.get('barMinHeight') || 0;
      const minA = s.get('barMinAngle') || 0;
      lastStack[id] = lastStack[id] || [];
      const vDim = d.mapDimension(vAxis.dim);
      const bDim = d.mapDimension(axis.dim);
      const stacked = !!vDim && vDim === d.getCalculationInfo('stackedDimension');
      const clampLayout = axis.dim !== 'radius' || !s.get('roundCap', true);
      const startVal = vAxis.scale.rawExtentInfo.makeRenderInfo().startValue;
      const vStart = vAxis.dataToCoord(startVal);
      const items = [];
      for (let i = 0; i < d.count(); i++) {
        const value = d.get(vDim, i);
        const bv = d.get(bDim, i);
        const sign = value >= 0 ? 'p' : 'n';
        let bc = vStart;
        if (stacked) {
          if (!lastStack[id][bv]) lastStack[id][bv] = { p: vStart, n: vStart };
          bc = lastStack[id][bv][sign];
        }
        let r0; let r; let sa; let ea;
        if (vAxis.dim === 'radius') {
          let span = vAxis.dataToCoord(value) - vStart;
          const angle = axis.dataToCoord(bv);
          if (Math.abs(span) < minH) span = (span < 0 ? -1 : 1) * minH;
          r0 = bc; r = bc + span; sa = angle - col.offset; ea = sa - col.width;
          stacked && (lastStack[id][bv][sign] = r);
        }
        else {
          let span = vAxis.dataToCoord(value, clampLayout) - vStart;
          const radius = axis.dataToCoord(bv);
          if (Math.abs(span) < minA) span = (span < 0 ? -1 : 1) * minA;
          r0 = radius + col.offset; r = r0 + col.width; sa = bc; ea = bc + span;
          stacked && (lastStack[id][bv][sign] = ea);
        }
        items.push({ cx: polar.cx, cy: polar.cy, r0, r, startAngle: -sa * Math.PI / 180, endAngle: -ea * Math.PI / 180,
          clockwise: sa >= ea });
      }
      out.set(s.seriesIndex, { items, numericBase: axis.type !== 'category' });
    });
  });
  return out;
}
// BarView clip.polar on a copy
function clipPolarRecipe(area, lay) {
  const l = Object.assign({}, lay);
  const signR = l.r0 <= l.r ? 1 : -1;
  if (signR < 0) { const t = l.r; l.r = l.r0; l.r0 = t; }
  const r = Math.min(l.r, area.r);
  const r0 = Math.max(l.r0, area.r0);
  l.r = r;
  l.r0 = r0;
  const clipped = r - r0 < 0;
  if (signR < 0) { const t = l.r; l.r = l.r0; l.r0 = t; }
  return { l, clipped };
}
// sectorLabel.ts: the position and the turn
function mapPos(isRadial, p) {
  const ao = isRadial ? 'Arc' : 'Angle';
  switch (p) {
    case 'start': case 'insideStart': case 'end': case 'insideEnd': return p + ao;
    default: return p;
  }
}
function sectorPosRecipe(shape, mapped, distance, isRoundCap) {
  const cx = shape.cx; const cy = shape.cy; const r = shape.r; const r0 = shape.r0;
  const mr = (r + r0) / 2;
  const sa = shape.startAngle; const ea = shape.endAngle;
  const ma = (sa + ea) / 2;
  const extra = isRoundCap ? Math.abs(r - r0) / 2 : 0;
  const ax = (a, d, e) => d * Math.sin(a) * (e ? -1 : 1);
  const ay = (a, d, e) => d * Math.cos(a) * (e ? 1 : -1);
  switch (mapped) {
    case 'startArc': return { x: cx + (r0 - distance) * Math.cos(ma), y: cy + (r0 - distance) * Math.sin(ma), align: 'center', va: 'top' };
    case 'insideStartArc': return { x: cx + (r0 + distance) * Math.cos(ma), y: cy + (r0 + distance) * Math.sin(ma), align: 'center', va: 'bottom' };
    case 'startAngle': return { x: cx + mr * Math.cos(sa) + ax(sa, distance + extra, false), y: cy + mr * Math.sin(sa) + ay(sa, distance + extra, false), align: 'right', va: 'middle' };
    case 'insideStartAngle': return { x: cx + mr * Math.cos(sa) + ax(sa, -distance + extra, false), y: cy + mr * Math.sin(sa) + ay(sa, -distance + extra, false), align: 'left', va: 'middle' };
    case 'middle': return { x: cx + mr * Math.cos(ma), y: cy + mr * Math.sin(ma), align: 'center', va: 'middle' };
    case 'endArc': return { x: cx + (r + distance) * Math.cos(ma), y: cy + (r + distance) * Math.sin(ma), align: 'center', va: 'bottom' };
    case 'insideEndArc': return { x: cx + (r - distance) * Math.cos(ma), y: cy + (r - distance) * Math.sin(ma), align: 'center', va: 'top' };
    case 'endAngle': return { x: cx + mr * Math.cos(ea) + ax(ea, distance + extra, true), y: cy + mr * Math.sin(ea) + ay(ea, distance + extra, true), align: 'left', va: 'middle' };
    case 'insideEndAngle': return { x: cx + mr * Math.cos(ea) + ax(ea, -distance + extra, true), y: cy + mr * Math.sin(ea) + ay(ea, -distance + extra, true), align: 'right', va: 'middle' };
  }
  return null;
}
function sectorRotRecipe(shape, pos, isRadial, rotate) {
  if (typeof rotate === 'number') return rotate;
  if (Array.isArray(pos)) return 0;
  const s = shape.clockwise ? shape.startAngle : shape.endAngle;
  const e = shape.clockwise ? shape.endAngle : shape.startAngle;
  const m = (s + e) / 2;
  const mapped = mapPos(isRadial, pos);
  let a;
  switch (mapped) {
    case 'startArc': case 'insideStartArc': case 'middle': case 'insideEndArc': case 'endArc': a = m; break;
    case 'startAngle': case 'insideStartAngle': a = s; break;
    case 'endAngle': case 'insideEndAngle': a = e; break;
    default: return 0;
  }
  let rot = Math.PI * 1.5 - a;
  if (mapped === 'middle' && rot > Math.PI / 2 && rot < Math.PI * 1.5) rot -= Math.PI;
  return rot;
}
// createPolarClipPath without animation
function polarClipRecipe(polar) {
  const a = polar.getArea();
  const rnd = v => +(+v).toFixed(1);
  return { cx: rnd(polar.cx), cy: rnd(polar.cy), r0: rnd(a.r0), r: rnd(a.r), sa: a.startAngle, ea: a.endAngle, cw: a.clockwise };
}

// ---------------------------------------------------------------------------
// reading
// ---------------------------------------------------------------------------
function readPolars(chart) {
  const out = [];
  chart.getModel().eachComponent('polar', pm => {
    const p = pm.coordinateSystem;
    if (!p) return;
    const ra = p.getRadiusAxis();
    const aa = p.getAngleAxis();
    out.push({ index: pm.componentIndex, cx: hex(p.cx), cy: hex(p.cy),
      rExtent: ra.getExtent().map(hex), aExtent: aa.getExtent().map(hex),
      rInverse: !!ra.inverse, aInverse: !!aa.inverse,
      rScale: ra.scale.getExtent().map(hex), aScale: aa.scale.getExtent().map(hex) });
  });
  return out;
}
const SHAPE6 = s => [s.cx, s.cy, s.r0 || 0, s.r, s.startAngle, s.endAngle].map(hexN);
function cornerRec(cr) {
  if (cr == null) return null;
  if (Array.isArray(cr)) return cr.map(hexN);
  return hexN(cr);
}
function labelRec(host) {
  if (!host || !host.getTextContent) return null;
  const tc = host.getTextContent();
  if (!tc) return null;
  const cfg = host.textConfig || {};
  const pos = cfg.position;
  const inside = cfg.inside == null ? (typeof pos === 'string' && pos.indexOf('inside') >= 0) : !!cfg.inside;
  const drawn = !host.ignore && !tc.ignore && !tc.invisible;
  const rec = { text: tc.style.text == null ? null : String(tc.style.text), drawn,
    word: pos == null ? null : clone(pos), inside };
  if (drawn) {
    const it = tc.innerTransformable;
    const ds = host._innerTextDefaultStyle || {};
    rec.x = hex(it.x);
    rec.y = hex(it.y);
    rec.rot = hex(it.rotation || 0);
    rec.ox = hex(it.originX || 0);
    rec.oy = hex(it.originY || 0);
    rec.dAlign = ds.align == null ? null : ds.align;
    rec.dVa = ds.verticalAlign == null ? null : ds.verticalAlign;
    rec.align = tc.style.align == null ? null : tc.style.align;
    rec.va = tc.style.verticalAlign == null ? null : tc.style.verticalAlign;
  }
  return rec;
}
function symbolRec(el, i) {
  if (!el) return { i, drawn: false };
  const rec = { i, drawn: !el.ignore, x: hex(el.x), y: hex(el.y) };
  const sp = el.getSymbolPath ? el.getSymbolPath() : null;
  rec.label = labelRec(sp);
  return rec;
}
function readSeries(chart, c, fails) {
  const ecModel = chart.getModel();
  const out = [];
  const recipe = barPolarRecipe(ecModel);
  ecModel.eachSeries(s => {
    if (s.get('coordinateSystem') !== 'polar') return;
    const polar = s.coordinateSystem;
    const view = chart.getViewOfSeriesModel(s);
    const d = s.getData();
    const rec = { index: s.seriesIndex, type: s.subType, polar: polar ? polar.model.componentIndex : -1,
      base: polar ? polar.getBaseAxis().dim : null, count: d.count(), raw: [] };
    for (let i = 0; i < d.count(); i++) rec.raw.push(d.getRawIndex(i));
    if (s.subType === 'bar') {
      const isRadial = polar.getBaseAxis().dim === 'angle';
      const roundCap = !!s.get('roundCap', true);
      const area = polar.getArea();
      const rcp = recipe.get(s.seriesIndex);
      const pos = s.get(['label', 'position']);
      rec.items = [];
      for (let i = 0; i < d.count(); i++) {
        const el = d.getItemGraphicEl(i);
        const lay = d.getItemLayout(i);
        const it = { i, raw: d.getRawIndex(i), cls: !el ? 'none' : (el.ignore ? 'hidden' : 'drawn') };
        it.layout = lay ? SHAPE6(lay) : null;
        it.layoutCw = lay ? !!lay.clockwise : null;
        if (el) {
          it.type = el.type;
          it.shape = SHAPE6(el.shape);
          it.cw = !!el.shape.clockwise;
          it.corner = el.type === 'sector' ? cornerRec(el.shape.cornerRadius) : null;
          it.zero = el.style.fill === 'none';
          it.z2 = el.z2;
          const pr = el.path ? el.path.getBoundingRect() : el.getBoundingRect();
          it.rect = [pr.x, pr.y, pr.width, pr.height].map(hex);
          it.label = labelRec(el);
          // the recipe: the layout from the data, the clip, the label
          if (rcp && lay && !rcp.numericBase) {
            const w = rcp.items[i];
            const got = [lay.cx, lay.cy, lay.r0, lay.r, lay.startAngle, lay.endAngle];
            const want = [w.cx, w.cy, w.r0, w.r, w.startAngle, w.endAngle];
            if (!want.every((v, k) => same(v, got[k])) || w.clockwise !== lay.clockwise) {
              fails.push(c.id + ' s' + s.seriesIndex + ' i' + i + ': layout ' + JSON.stringify(got) + ', the recipe ' + JSON.stringify(want));
            }
          }
          if (lay && s.get('clip', true)) {
            const cr = clipPolarRecipe(area, lay);
            const got = [el.shape.r0, el.shape.r];
            if (!same(got[0], cr.l.r0) || !same(got[1], cr.l.r) || cr.clipped !== !!el.ignore) {
              fails.push(c.id + ' s' + s.seriesIndex + ' i' + i + ': clip ' + JSON.stringify(got) + ', the recipe ' + JSON.stringify([cr.l.r0, cr.l.r, cr.clipped]));
            }
          }
          const tc = el.getTextContent();
          if (tc && it.label && it.label.drawn) {
            const itemPos = d.getItemModel(i).get(['label', 'position']);
            const rot = d.getItemModel(i).get(['label', 'rotate']);
            const outside = isRadial ? (el.shape.r >= el.shape.r0 ? 'endArc' : 'startArc')
              : (el.shape.endAngle >= el.shape.startAngle ? 'endAngle' : 'startAngle');
            const word = itemPos === 'outside' ? outside : itemPos;
            const wantRot = sectorRotRecipe(el.shape, word, isRadial, rot);
            const itx = tc.innerTransformable;
            if (!same(itx.rotation || 0, wantRot) && !(wantRot === 0 && !itx.rotation)) {
              fails.push(c.id + ' s' + s.seriesIndex + ' i' + i + ': label turn ' + itx.rotation + ', the recipe ' + wantRot);
            }
            if (typeof word === 'string') {
              const dist = s.get(['label', 'distance']);
              const p = sectorPosRecipe(el.shape, mapPos(isRadial, word), dist != null ? dist : 5, roundCap && !isRadial);
              const off = d.getItemModel(i).get(['label', 'offset']) || [0, 0];
              if (p && (!same(itx.x, p.x + (off[0] || 0)) || !same(itx.y, p.y + (off[1] || 0)) || p.align !== host_ds(el).align)) {
                fails.push(c.id + ' s' + s.seriesIndex + ' i' + i + ': label at ' + itx.x + ',' + itx.y + ' ' + host_ds(el).align
                  + ', the recipe ' + JSON.stringify(p));
              }
            }
          }
        }
        rec.items.push(it);
      }
      void pos;
      rec.bg = null;
      if (view._backgroundEls && view._backgroundEls.length) {
        rec.bg = [];
        for (let i = 0; i < d.count(); i++) {
          const b = view._backgroundEls[i];
          rec.bg.push(b ? { shape: SHAPE6(b.shape), cw: !!b.shape.clockwise, corner: cornerRec(b.shape.cornerRadius) } : null);
        }
      }
    }
    else if (s.subType === 'line') {
      const pts = d.getLayout('points');
      rec.points = pts ? Array.from(pts).map(hexN) : null;
      rec.stacked = view._polygon ? Array.from(view._polygon.shape.stackedOnPoints).map(hexN) : null;
      rec.polyline = view._polyline ? Array.from(view._polyline.shape.points).map(hexN) : null;
      rec.polygon = view._polygon ? Array.from(view._polygon.shape.points).map(hexN) : null;
      const cp = view._lineGroup.getClipPath();
      rec.clip = cp ? { type: cp.type, cx: hex(cp.shape.cx), cy: hex(cp.shape.cy), r0: hex(cp.shape.r0), r: hex(cp.shape.r),
        sa: hex(cp.shape.startAngle), ea: hex(cp.shape.endAngle), cw: !!cp.shape.clockwise } : null;
      if (cp) {
        const w = polarClipRecipe(polar);
        const g = cp.shape;
        if (!same(g.cx, w.cx) || !same(g.cy, w.cy) || !same(g.r0, w.r0) || !same(g.r, w.r) || !same(g.startAngle, w.sa)
          || !same(g.endAngle, w.ea) || !!g.clockwise !== !!w.cw) {
          fails.push(c.id + ' s' + s.seriesIndex + ': clip path ' + JSON.stringify(g) + ', the recipe ' + JSON.stringify(w));
        }
      }
      const sc = view._clipShapeForSymbol;
      rec.symClip = sc ? { cx: hex(sc.cx), cy: hex(sc.cy), r0: hex(sc.r0), r: hex(sc.r), x: hex(sc.x), y: hex(sc.y),
        w: hex(sc.width), h: hex(sc.height) } : null;
      rec.symbols = [];
      for (let i = 0; i < d.count(); i++) {
        const el = d.getItemGraphicEl(i);
        rec.symbols.push(symbolRec(el, i));
        // the polar area keeps a symbol inside the ring
        if (sc && pts && isFinite(pts[i * 2]) && isFinite(pts[i * 2 + 1]) && s.get('showSymbol')) {
          const keep = sc.contain(pts[i * 2], pts[i * 2 + 1]);
          if (keep !== !!el) fails.push(c.id + ' s' + s.seriesIndex + ' i' + i + ': symbol ' + !!el + ', the ring says ' + keep);
        }
      }
    }
    else if (s.subType === 'scatter' || s.subType === 'effectScatter') {
      rec.symbols = [];
      for (let i = 0; i < d.count(); i++) rec.symbols.push(symbolRec(d.getItemGraphicEl(i), i));
    }
    else if (s.subType === 'heatmap') {
      rec.drawn = view.group.childCount();
    }
    out.push(rec);
  });
  return out;
}
function host_ds(el) {
  return el._innerTextDefaultStyle || {};
}
function readMarkers(chart) {
  const ecModel = chart.getModel();
  const out = [];
  ['markPoint', 'markLine'].forEach(kind => {
    const master = ecModel.getComponent(kind);
    if (!master) return;
    const MM = Object.getPrototypeOf(master.constructor);
    must(typeof MM.getMarkerModelFromSeries === 'function', 'MarkerModel.getMarkerModelFromSeries not reachable');
    ecModel.eachSeries(s => {
      const m = MM.getMarkerModelFromSeries(s, kind);
      if (!m) return;
      const d = m.getData();
      const items = [];
      d.each(i => {
        const lay = d.getItemLayout(i);
        let l = null;
        if (kind === 'markPoint') l = lay ? [hexN(lay[0]), hexN(lay[1])] : null;
        else l = lay ? [[hexN(lay[0][0]), hexN(lay[0][1])], [hexN(lay[1][0]), hexN(lay[1][1])]] : null;
        items.push({ layout: l });
      });
      out.push({ series: s.seriesIndex, kind, items });
    });
  });
  return out;
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
  const info = ecModel.getComponent('axisPointer', 0).coordSysAxesInfo;
  ecModel.eachComponent('polar', pm => {
    const polar = pm.coordinateSystem;
    [polar.getAngleAxis(), polar.getRadiusAxis()].forEach(axis => {
      const ai = Object.values(info.axesInfo).find(q => q.axis === axis);
      if (!ai) return;
      const apm = ai.axisPointerModel;
      if (apm.get('status') !== 'show') return;
      const view = chart.getViewOfComponentModel(axis.model);
      const ap = view && view._axisPointer;
      const g = ap && ap._group;
      must(g && !g.ignore, c.id + ': a shown pointer with no group');
      const rec = { dim: axis.dim, polar: pm.componentIndex, value: hexN(apm.get('value')), el: null, label: null };
      g.childrenRef().forEach(e => {
        const t = String(e.type).toLowerCase();
        if (t === 'line') rec.el = { type: 'line', shape: [e.shape.x1, e.shape.y1, e.shape.x2, e.shape.y2].map(hex) };
        else if (t === 'circle') rec.el = { type: 'circle', shape: [e.shape.cx, e.shape.cy, e.shape.r].map(hex) };
        else if (t === 'sector') {
          const s = e.shape;
          rec.el = { type: 'sector', shape: [s.cx, s.cy, s.r0, s.r, s.startAngle, s.endAngle].map(hex), cw: !!s.clockwise };
        }
        else if (t === 'text' && !e.ignore) {
          const b = e.getBoundingRect();
          rec.label = { text: e.style.text, x: hex(e.x), y: hex(e.y), w: hex(b.width), h: hex(b.height) };
        }
      });
      axes.push(rec);
    });
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
    // the browser's frame: the state flags applied (as select-legend.js)
    chart._onframe();
    chart.renderToSVGString();
    const items = [];
    ecModel.eachSeries(s => {
      const d = s.getData();
      for (let i = 0; i < d.count(); i++) {
        const el = d.getItemGraphicEl(i);
        if (!el) continue;
        const tc = el.getTextContent && el.getTextContent();
        items.push({ s: s.seriesIndex, i, states: (el.currentStates || []).slice(),
          fill: el.style.fill == null ? null : String(el.style.fill),
          stroke: el.style.stroke == null ? null : String(el.style.stroke),
          lineWidth: el.style.lineWidth == null ? null : hex(+el.style.lineWidth),
          opacity: el.style.opacity == null ? null : hex(+el.style.opacity),
          labelFill: tc && tc.style.fill != null ? String(tc.style.fill) : null });
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
const add = (group, id, note, option, more) => CASES.push(Object.assign({ group, id, note, W: 600, H: 400, option }, more || {}));
const C5 = ['a', 'b', 'c', 'd', 'e'];
const D5 = [3, 5, 2, 8, 6];
const P = (angle, radius, series, extra) => Object.assign({ polar: {}, angleAxis: angle, radiusAxis: radius, series }, extra || {});
const bar = (data, extra) => Object.assign({ type: 'bar', coordinateSystem: 'polar', data }, extra || {});
const line = (data, extra) => Object.assign({ type: 'line', coordinateSystem: 'polar', data }, extra || {});
const CAT = { type: 'category', data: C5 };

// ---- bars
add('bar', 'bar-radial', 'radial bars: a category angle axis, a value radius', P(CAT, {}, [bar(D5)]));
add('bar', 'bar-tangential', 'tangential bars: a category radius axis, a value angle', P({}, CAT, [bar(D5)]));
add('bar', 'bar-radial-two', 'two radial series side by side, barGap 20%, barCategoryGap 40% on the second', P(CAT, {},
  [bar(D5), bar([4, 1, 6, 3, 2], { barGap: '20%', barCategoryGap: '40%' })]));
add('bar', 'bar-radial-stack', 'three radial series stacked, negatives below the start', P(CAT, {},
  [bar([3, -2, 4, 1, 5], { stack: 'a' }), bar([2, 3, -1, 4, -2], { stack: 'a' }), bar([1, 1, 1, 1, 1], { stack: 'a' })]));
add('bar', 'bar-tangential-stack', 'tangential bars stacked, a second stack beside', P({}, CAT,
  [bar([3, -2, 4, 1, 5], { stack: 'a' }), bar([2, 3, -1, 4, -2], { stack: 'a' }), bar([2, 2, 2, 2, 2], { stack: 'b' })]));
add('bar', 'bar-roundcap', 'tangential roundCap: Sausage', P({}, CAT, [bar([3, -2, 4, 8, 6], { roundCap: true })]));
add('bar', 'bar-roundcap-radial', 'radial roundCap: still a Sector, its borderRadius ignored', P(CAT, {},
  [bar(D5, { roundCap: true, itemStyle: { borderRadius: 6 } })]));
add('bar', 'bar-corner', 'sector corners: a scalar, four values, two percentages', P({}, CAT,
  [bar([3, 5, 2, 8, 6], { itemStyle: { borderRadius: 6 } }), bar([4, 1, 6, 3, 2], { itemStyle: { borderRadius: [2, 4, 6, 8] } }),
    bar([2, 2, 3, 1, 4], { itemStyle: { borderRadius: ['10%', '20%'] } })]));
add('bar', 'bar-corner-radial', 'radial sector corners and a data item\'s own', P(CAT, {},
  [bar([3, 5, { value: 2, itemStyle: { borderRadius: 10 } }, 8, 6], { itemStyle: { borderRadius: [8, 2] } })]));
add('bar', 'bar-clip', 'a radius narrower than the data: r cut at the edge, wholly outside hidden; clip off on the second', P(CAT,
  { min: 2, max: 6 }, [bar([3, 5, 1, 8, 6]), bar([7, 1, 4, 9, 5], { clip: false })]));
add('bar', 'bar-clip-tangential', 'tangential on a short angle: only r is clipped, the angle runs over', P({ min: 0, max: 5 }, CAT,
  [bar([3, 5, 2, 8, 6])]));
add('bar', 'bar-minheight', 'barMinHeight 12 radial, barMinAngle 15 tangential on a second polar', {
  polar: [{ center: ['25%', '50%'], radius: '60%' }, { center: ['75%', '50%'], radius: '60%' }],
  angleAxis: [{ type: 'category', data: C5, polarIndex: 0 }, { polarIndex: 1 }],
  radiusAxis: [{ polarIndex: 0 }, { type: 'category', data: C5, polarIndex: 1 }],
  series: [bar([0.1, -0.2, 5, 0.05, 3], { barMinHeight: 12 }), bar([0.1, -0.2, 5, 0.05, 3], { barMinAngle: 15, polarIndex: 1 })],
});
add('bar', 'bar-background', 'showBackground radial and tangential, a rounded background', {
  polar: [{ center: ['25%', '50%'], radius: '60%' }, { center: ['75%', '50%'], radius: '60%' }],
  angleAxis: [{ type: 'category', data: C5, polarIndex: 0 }, { polarIndex: 1 }],
  radiusAxis: [{ polarIndex: 0 }, { type: 'category', data: C5, polarIndex: 1 }],
  series: [bar(D5, { showBackground: true, backgroundStyle: { borderRadius: 4 } }), bar(D5, { showBackground: true, polarIndex: 1 })],
});
add('bar', 'bar-value-base', 'radial bars on a value angle axis: the band from the smallest gap', P({ type: 'value', min: 0, max: 100 }, {},
  [bar([[3, 10], [5, 30], [2, 40], [6, 70], [4, 85]])]));
add('bar', 'bar-value-base-radius', 'two value axes: the angle is the base (radial bars), its containShape off by the model default', P({}, { type: 'value' },
  [bar([[10, 2], [30, 4], [45, 5], [60, 8]])]));
add('bar', 'bar-zero', 'zero values: a tangential sector of no sweep is drawn with no fill and no stroke; a radial one keeps its fill', P({}, CAT,
  [bar([0, 3, 0, 5, -0])]));
add('bar', 'bar-zero-radial', 'zero radial bars: r = r0, the angles differ, the fill stays', P(CAT, {}, [bar([0, 3, 0, 5, -0])]));
add('bar', 'bar-width', 'barWidth 50% on a stack, barMaxWidth 10 on another', P(CAT, {},
  [bar(D5, { stack: 's', barWidth: '50%' }), bar([1, 2, 1, 2, 1], { stack: 's' }), bar([2, 4, 3, 1, 5], { barMaxWidth: 10 })]));
add('bar', 'bar-inverse', 'an inverse radius, an anticlockwise angle from 30 degrees', P({ type: 'category', data: C5, clockwise: false, startAngle: 30 },
  { inverse: true }, [bar(D5)]));
add('bar', 'bar-ring', 'radial bars on a ring: they grow from the inner radius', P(CAT, {}, [bar(D5)], { polar: { radius: [50, '80%'] } }));
add('bar', 'bar-log', 'radial bars on a log radius: they stand on 1', P(CAT, { type: 'log' }, [bar([3, 50, 2, 800, 60])]));
add('bar', 'bar-half', 'tangential bars on half a turn, a value angle 0..10', P({ min: 0, max: 10, startAngle: 180, endAngle: 0 }, CAT, [bar(D5)]));
add('bar', 'bar-border', 'a bordered radial bar, labels inside the stroked rect', P(CAT, {}, [bar(D5, { itemStyle: { borderColor: '#333', borderWidth: 3 }, label: { show: true, position: 'insideBottom' } })]));

// ---- the labels: every position, radial and tangential, turned and not
const POSITIONS = ['start', 'insideStart', 'middle', 'insideEnd', 'end', 'outside', 'inside', 'top', 'insideTopLeft', [10, '50%']];
POSITIONS.forEach(pos => {
  const nm = Array.isArray(pos) ? 'array' : pos;
  ['radial', 'tangential'].forEach(o => {
    const series = [bar([3, 5, -2, 8, 6], { label: { show: true, position: pos } }),
      bar([4, 1, 6, -3, 2], { label: { show: true, position: pos, rotate: 30 } })];
    add('label', 'label-' + nm + '-' + o, 'label ' + JSON.stringify(pos) + ' on ' + o + ' bars, the second series rotate 30',
      o === 'radial' ? P(CAT, {}, series) : P({}, CAT, series));
  });
});
add('label', 'label-distance', 'distance 12 and an offset on end / insideStart', P(CAT, {},
  [bar(D5, { label: { show: true, position: 'end', distance: 12, offset: [4, -6] } }), bar(D5, { label: { show: true, position: 'insideStart', distance: 12 } })]));
add('label', 'label-align', 'the style\'s own align over the position\'s', P({}, CAT,
  [bar(D5, { label: { show: true, position: 'end', align: 'right', verticalAlign: 'top' } })]));
add('label', 'label-roundcap', 'roundCap: the angle positions move by half the thickness', P({}, CAT,
  [bar([3, 5, -2, 8, 6], { roundCap: true, label: { show: true, position: 'start' } }), bar([4, 1, 6, 3, 2], { roundCap: true, label: { show: true, position: 'insideEnd' } })]));
add('label', 'label-stack', 'stacked radial labels in the middle', P(CAT, {},
  [bar(D5, { stack: 'a', label: { show: true, position: 'middle' } }), bar([2, 1, 3, 1, 2], { stack: 'a', label: { show: true, position: 'middle' } })]));
add('label', 'label-item', 'a data item\'s own label position and rotate', P(CAT, {},
  [bar([3, { value: 5, label: { position: 'start', rotate: -20 } }, 2, { value: 8, label: { position: 'insideEnd' } }, 6], { label: { show: true, position: 'middle' } })]));

// ---- lines
add('line', 'line-polar', 'a line on a category angle: symbols, labels, a hole, an end label asked for (none on a polar)', P({ type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f'] }, {},
  [line([3, 5, null, 2, 8, 6], { label: { show: true }, symbolSize: 8, endLabel: { show: true } })]));
add('line', 'line-area-stack', 'two stacked areas', P({ type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f'], boundaryGap: false }, {},
  [line([3, 5, 4, 2, 8, 6], { stack: 't', areaStyle: {} }), line([1, 2, 3, 2, 1, 2], { stack: 't', areaStyle: {} })]));
add('line', 'line-clip-ring', 'a ring, a radius max below the data: symbols past it go', P({ type: 'category', data: C5 }, { max: 8 },
  [line([3, 5, 9, 2, 6], { areaStyle: {}, label: { show: true } })], { polar: { radius: [40, '85%'] } }));
add('line', 'line-radius-base', 'a line on a category radius, a value angle', P({}, CAT, [line(D5, { symbol: 'rect' })]));
add('line', 'line-smooth', 'smooth on a polar, with an area', P({ type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f'] }, {},
  [line([3, 5, 4, 2, 8, 6], { smooth: true, areaStyle: {} })]));
add('line', 'line-value', 'two value axes, [r, a] pairs, clip off', P({ type: 'value', min: 0, max: 360 }, { max: 10 },
  [line([[2, 0], [4, 60], [6, 120], [12, 180], [8, 240], [5, 300]], { clip: false })]));
add('line', 'line-step', 'step on a polar is ignored', P({ type: 'category', data: C5 }, {}, [line(D5, { step: 'start' })]));
add('line', 'line-inverse', 'an anticlockwise angle from 0, an inverse radius', P({ type: 'category', data: C5, clockwise: false, startAngle: 0 },
  { inverse: true }, [line(D5, { areaStyle: {} })]));

// ---- scatter, effectScatter, heatmap
add('scatter', 'scatter-polar', 'scatter on two value axes, some past the radius max', P({ type: 'value', min: 0, max: 360 }, { max: 10 },
  [{ type: 'scatter', coordinateSystem: 'polar', symbolSize: 10, label: { show: true, position: 'top' },
    data: [[2, 30], [5, 90], [12, 150], [7, 210], [9.9, 300], [10, 330]] }]));
add('scatter', 'scatter-cat', 'scatter on a category angle', P(CAT, {}, [{ type: 'scatter', coordinateSystem: 'polar', data: D5 }]));
add('scatter', 'scatter-noclip', 'scatter past the radius with clip off', P({ type: 'value', min: 0, max: 360 }, { max: 10 },
  [{ type: 'scatter', coordinateSystem: 'polar', clip: false, data: [[2, 30], [12, 150], [15, 250]] }]));
add('scatter', 'effect-polar', 'effectScatter on a polar', P(CAT, {}, [{ type: 'effectScatter', coordinateSystem: 'polar', data: D5, symbolSize: 12 }]));
add('scatter', 'heatmap-polar', 'heatmap on a polar draws nothing; its data still sizes the axes', P(CAT, {},
  [{ type: 'heatmap', coordinateSystem: 'polar', data: [[1, 0, 5], [3, 2, 8], [12, 4, 1]] }], { visualMap: { min: 0, max: 10, show: false } }));

// ---- the markers
add('marker', 'marker-line', 'markPoint and markLine on a polar line', P(CAT, {}, [line(D5, {
  markPoint: { data: [{ type: 'max' }, { type: 'min' }, { coord: [4, 'c'] }, { radiusAxis: 2, angleAxis: 'e' }, { type: 'average' }] },
  markLine: { data: [{ type: 'average' }, [{ coord: [1, 'a'] }, { coord: [6, 'd'] }], [{ type: 'min' }, { type: 'max' }]] },
})]));
add('marker', 'marker-bar', 'markPoint and markLine on a polar bar: no position', P(CAT, {}, [bar(D5, {
  markPoint: { data: [{ type: 'max' }, { coord: [4, 'c'] }] }, markLine: { data: [[{ coord: [1, 'a'] }, { coord: [6, 'd'] }]] },
})]));
add('marker', 'marker-scatter', 'markers on a polar scatter', P({ type: 'value', min: 0, max: 360 }, { max: 10 },
  [{ type: 'scatter', coordinateSystem: 'polar', data: [[2, 30], [5, 90], [7, 210], [4, 300]],
    markPoint: { data: [{ type: 'max', valueIndex: 0 }, { coord: [3, 45] }, { coord: [20, 45] }] },
    markLine: { data: [[{ coord: [1, 10] }, { coord: [9, 200] }], [{ coord: [1, 10] }, { coord: [30, 200] }]] } }]));
add('marker', 'marker-area', 'markArea on a polar: upstream throws (no clampData)', P(CAT, {}, [line(D5, {
  markArea: { data: [[{ coord: [1, 'a'] }, { coord: [4, 'c'] }]] } })]), { expectThrow: true });

// ---- dataZoom
add('zoom', 'zoom-inside-angle', 'an inside dataZoom on the category angle, 20% to 80%', Object.assign(P({ type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f'] }, {},
  [bar([1, 2, 3, 4, 5, 6]), line([6, 5, 4, 3, 2, 1])]), { dataZoom: [{ type: 'inside', angleAxisIndex: 0, start: 20, end: 80 }] }));
add('zoom', 'zoom-slider-radius', 'sliders on a category radius (0..50%) and a value angle (2..5)', Object.assign(P({}, { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f'] },
  [bar([1, 2, 3, 4, 5, 6])]), { dataZoom: [{ type: 'slider', radiusAxisIndex: 0, start: 0, end: 50 }, { type: 'slider', angleAxisIndex: 0, startValue: 2, endValue: 5 }] }));
add('zoom', 'zoom-radius-empty', 'an inside dataZoom on a value radius, filterMode empty', Object.assign(P({ type: 'category', data: C5 }, {},
  [line([3, 5, 2, 8, 6]), bar([1, 7, 4, 2, 9])]), { dataZoom: [{ type: 'inside', radiusAxisIndex: 0, startValue: 2, endValue: 7, filterMode: 'empty' }] }));
add('zoom', 'zoom-angle-value', 'an inside dataZoom on a value angle with scatter, weakFilter', Object.assign(P({ type: 'value', min: 0, max: 360 }, { max: 10 },
  [{ type: 'scatter', coordinateSystem: 'polar', data: [[2, 30], [5, 90], [7, 150], [7, 210], [9, 300]] }]),
{ dataZoom: [{ type: 'inside', angleAxisIndex: 0, startValue: 60, endValue: 250, filterMode: 'weakFilter' }] }));

// ---- containShape on a polar's base axis (mutation round 1)
add('bar', 'bar-gap-last', 'barGap and barCategoryGap: the last series that writes one wins', P(CAT, {},
  [bar(D5, { barGap: '10%', barCategoryGap: '10%' }), bar([2, 4, 1, 3, 5], { barGap: '60%' }), bar([1, 2, 3, 2, 1])]));
add('bar', 'bar-width-over', 'barWidth 150% takes no more than the band left', P(CAT, {},
  [bar(D5, { barWidth: '150%' }), bar([2, 4, 1, 3, 5])]));
add('bar', 'bar-maxwidth', 'barMaxWidth 5 degrees caps an auto column', P(CAT, {},
  [bar(D5, { barMaxWidth: 5 }), bar([2, 4, 1, 3, 5])]));
add('bar', 'bar-roundcap-over', 'roundCap on a radius base: the angle is not clamped, the sausage runs past max', P({ max: 5 }, CAT,
  [bar([3, 5, 2, 8, 6], { roundCap: true })]));
add('bar', 'bar-corner-one', 'a one-element and a three-element borderRadius: [v, v, 0, 0] and [a, b, c, c]', P({}, CAT,
  [bar(D5, { itemStyle: { borderRadius: [8] } }), bar([4, 1, 6, 3, 2], { itemStyle: { borderRadius: [2, 6, 10] } })]));
add('bar', 'bar-corner-negative', 'corners on tangential bars that run anticlockwise, labels inside their rect', P({}, CAT,
  [bar([3, -2, 4, -5, 6], { itemStyle: { borderRadius: [2, 4, 8, 12] }, label: { show: true, position: 'inside' } })]));
add('bar', 'bar-corner-narrow', 'big corners on narrow radial wedges: the corner limited where the edges meet', P({ type: 'category', data: Array.from({ length: 12 }, (_, i) => 'm' + i) }, {},
  [bar([3, 5, 2, 8, 6, 4, 7, 1, 9, 5, 3, 6], { itemStyle: { borderRadius: 30 }, label: { show: true, position: 'insideTopLeft' } })], { polar: { radius: [30, '80%'] } }));
add('line', 'line-fraction', 'a polar on fractions: the clip rounded to a tenth; a value under the radius min falls in the hole', P({ type: 'category', data: C5 }, { min: 2 },
  [line([3, 5, 1, 2.5, 6], { areaStyle: {} })], { polar: { center: ['50.37%', '49.71%'], radius: ['12.37%', '77.77%'] } }));
add('zoom', 'zoom-angle-percent', 'percent ends on a value angle: rounded by the span in degrees', Object.assign(P({ type: 'value', min: 0, max: 360 }, { max: 10 },
  [line([[2, 10], [4, 60], [6, 120], [8, 240], [5, 300]])]), { dataZoom: [{ type: 'inside', angleAxisIndex: 0, start: 13.37, end: 77.71, filterMode: 'none' }] }));
add('zoom', 'zoom-angle-half', 'the same on a half circle: a span of 180 degrees rounds the ends a digit coarser', Object.assign(P({ type: 'value', min: 0, max: 360, endAngle: -90 }, { max: 10 },
  [line([[2, 10], [4, 60], [6, 120], [8, 240], [5, 300]])]), { dataZoom: [{ type: 'inside', angleAxisIndex: 0, start: 13.37, end: 77.71, filterMode: 'none' }] }));
add('bar', 'bar-band-min', 'radial bars a tenth apart on a value angle 0..100: the band is held at 1 degree', P({ type: 'value', min: 0, max: 100 }, {},
  [bar([[3, 10], [5, 10.1], [2, 10.3], [4, 50]])]));
add('bar', 'bar-cat-radius-nogap', 'tangential bars on a category radius without a gap: containShape widens the radius by half a band', P({}, { type: 'category', data: C5, boundaryGap: false },
  [bar(D5)]));
add('bar', 'bar-time-radius', 'tangential bars on a time radius (the base): containShape by the smallest gap', P({ max: 10 }, { type: 'time' },
  [bar([[Date.UTC(2024, 0, 1), 3], [Date.UTC(2024, 0, 3), 5], [Date.UTC(2024, 0, 4), 2], [Date.UTC(2024, 0, 8), 8]])], { useUTC: true }));
add('bar', 'bar-angle-contain', 'radial bars on a value angle with containShape written true', P({ type: 'value', containShape: true }, {},
  [bar([[3, 10], [5, 30], [2, 40], [6, 70], [4, 85]])]));
add('zoom', 'zoom-contain-pinned', 'the same with an inside dataZoom pinning 20..80: the pinned ends are not widened', Object.assign(P({ type: 'value', containShape: true }, {},
  [bar([[3, 10], [5, 30], [2, 40], [6, 70], [4, 85]])]), { dataZoom: [{ type: 'inside', angleAxisIndex: 0, startValue: 20, endValue: 80, filterMode: 'none' }] }));

// ---- the pointer
const ring = (cx, cy, rs, n) => {
  const out = [];
  rs.forEach(r => { for (let k = 0; k < n; k++) { const a = k * 2 * Math.PI / n + 0.3; out.push([Math.round(cx + r * Math.cos(a)), Math.round(cy - r * Math.sin(a))]); } });
  return out;
};
const PROBES = ring(300, 200, [20, 75, 130, 155], 9).concat([[300, 200], [300, 41], [10, 10]]);
add('pointer', 'ptr-cat-angle', 'bars and a line on a category angle, axis trigger', Object.assign(P(CAT, {}, [bar(D5), line([2, 6, 1, 4, 3])]),
  { tooltip: { trigger: 'axis' } }), { probes: PROBES });
add('pointer', 'ptr-value-shadow', 'bars on a value angle: the shadow band from the bars\' gap', Object.assign(P({ type: 'value', min: 0, max: 100 }, {},
  [bar([[3, 10], [5, 30], [2, 40], [6, 70], [4, 85]])]), { tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } } }), { probes: PROBES });
add('pointer', 'ptr-cross-scatter', 'cross over a scatter on two value axes', Object.assign(P({ type: 'value', min: 0, max: 360 }, { max: 10 },
  [{ type: 'scatter', coordinateSystem: 'polar', data: [[2, 30], [5, 90], [7, 210], [4, 300]] }]),
{ tooltip: { trigger: 'axis', axisPointer: { type: 'cross' } } }), { probes: PROBES });
add('pointer', 'ptr-cat-radius', 'tangential bars on a category radius, shadow', Object.assign(P({}, CAT, [bar(D5), bar([2, 4, 1, 3, 5])]),
  { tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } } }), { probes: PROBES });
add('pointer', 'ptr-value-line', 'a line on two value axes, axis trigger: the value axis snaps', Object.assign(P({ type: 'value', min: 0, max: 360 }, { max: 10 },
  [line([[2, 0], [4, 60], [6, 120], [8, 240], [5, 300]])]), { tooltip: { trigger: 'axis' } }), { probes: PROBES });

// ---- the conversions with a series finder
const cvProbes = (finders, values, pixels) => {
  const out = [];
  finders.forEach(f => {
    values.forEach(v => out.push(['to', f, v]));
    pixels.forEach(p => out.push(['from', f, p]));
    pixels.forEach(p => out.push(['contain', f, p]));
  });
  return out;
};
add('convert', 'cv-series', 'seriesIndex / seriesId / seriesName finders on polar series, two polars and a grid', {
  grid: { left: 20, top: 20, width: 100, height: 100, outerBoundsMode: 'none' }, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
  polar: [{ center: [300, 200], radius: 100 }, { center: [480, 300], radius: [20, 80] }],
  angleAxis: [{ type: 'category', data: C5, polarIndex: 0 }, { min: 0, max: 360, polarIndex: 1 }],
  radiusAxis: [{ min: 0, max: 10, polarIndex: 0 }, { min: 0, max: 5, polarIndex: 1 }],
  series: [bar(D5, { id: 'b0', name: 'bars' }), line([[1, 30], [3, 200]], { polarIndex: 1, name: 'ln' }), { type: 'scatter', data: [[1, 1]] }],
}, { probes: cvProbes([{ seriesIndex: 0 }, { seriesIndex: 1 }, { seriesId: 'b0' }, { seriesName: 'ln' }, { seriesIndex: 2 }, 'series', { seriesIndex: [1, 0] }],
  [[0, 0], [5, 'c'], [5, 2], [2.5, 90], [3, 400]], [[300, 200], [350, 150], [480, 300], [500, 260], [60, 60], [10, 10]]) });

// ---- emphasis and select
add('state', 'state-bar', 'emphasis and select on polar bars, colours written', P(CAT, {}, [bar(D5, {
  itemStyle: { color: '#5470c6' }, label: { show: true, color: '#111' },
  emphasis: { itemStyle: { color: '#ee6666', borderColor: '#222', borderWidth: 2 }, label: { color: '#f00' } },
  select: { itemStyle: { color: '#91cc75', borderColor: '#000', borderWidth: 3 } }, selectedMode: 'single' }),
bar([2, 4, 1, 3, 5], { itemStyle: { color: '#fac858' }, emphasis: { focus: 'series', itemStyle: { color: '#73c0de' } }, blur: { itemStyle: { opacity: 0.2 } } })]), {
  actions: [
    { type: 'highlight', seriesIndex: 0, dataIndex: 1 },
    { type: 'downplay', seriesIndex: 0, dataIndex: 1 },
    { type: 'select', seriesIndex: 0, dataIndex: 2 },
    { type: 'select', seriesIndex: 0, dataIndex: 3 },
    { type: 'highlight', seriesIndex: 1, dataIndex: 0 },
    { type: 'downplay', seriesIndex: 1, dataIndex: 0 },
    { type: 'unselect', seriesIndex: 0, dataIndex: 3 },
  ] });
add('state', 'state-tangential', 'emphasis and select on tangential roundCap bars', P({}, CAT, [bar(D5, {
  roundCap: true, itemStyle: { color: '#5470c6' }, emphasis: { itemStyle: { color: '#ee6666' } },
  select: { itemStyle: { borderColor: '#000', borderWidth: 2 } }, selectedMode: 'multiple' })]), {
  actions: [
    { type: 'highlight', seriesIndex: 0, dataIndex: 4 },
    { type: 'select', seriesIndex: 0, dataIndex: 0 },
    { type: 'select', seriesIndex: 0, dataIndex: 1 },
    { type: 'downplay', seriesIndex: 0, dataIndex: 4 },
  ] });

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function runCase(c) {
  const fails = [];
  const option = clone(c.option);
  option.animation = false;
  const written = clone(option);
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: c.W, height: c.H });
  // the states need a chart that is not ssr: ecModel.ssr turns the hover
  // states off (as select-legend.js runs them)
  if (c.group === 'state') chart._ssr = false;
  try {
    const rec = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: written };
    try {
      quiet(() => { chart.setOption(option); chart.renderToSVGString(); });
    } catch (e) {
      must(c.expectThrow, c.id + ': setOption threw ' + e.message);
      rec.threw = e.constructor.name + ': ' + e.message;
      rec.fails = fails;
      return rec;
    }
    must(!c.expectThrow, c.id + ': upstream was expected to throw');
    rec.polars = readPolars(chart);
    rec.series = readSeries(chart, c, fails);
    rec.markers = readMarkers(chart);
    rec.zoom = readZoom(chart);
    if (c.group === 'pointer') rec.pointer = c.probes.map(([x, y]) => readPointer(chart, c, x, y));
    if (c.group === 'convert') rec.convert = runConvert(chart, c);
    if (c.group === 'state') rec.states = runStates(chart, c);
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
function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'dataIndex' in el[k]) return el[k];
  }
  return null;
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
const aadd = (id, note, option) => ACASES.push({ id, note, option });
aadd('polar-bar-radial.default', 'radial bars: shape.r grows from r0', P(CAT, {}, [bar(D5)]));
aadd('polar-bar-radial.delayFn', 'radial bars, animationDelay (idx) => idx * 50', P(CAT, {}, [bar(D5, { animationDelay: { $fn: 'idx*50' } })]));
aadd('polar-bar-tangential.default', 'tangential bars: shape.endAngle sweeps from startAngle', P({}, CAT, [bar([3, -2, 4, 8, 6])]));
aadd('polar-bar-roundcap.override', 'tangential roundCap (Sausage), duration 600, linear, delay 100', P({}, CAT,
  [bar(D5, { roundCap: true, animationDuration: 600, animationEasing: 'linear', animationDelay: 100 })]));
aadd('polar-bar-stack.default', 'stacked radial bars, a label in the middle', P(CAT, {},
  [bar(D5, { stack: 'a', label: { show: true, position: 'middle' } }), bar([2, 1, 3, 1, 2], { stack: 'a' })]));
aadd('polar-line-angle.default', 'a line on a category angle: the clip sweeps endAngle, the symbols pop in as it reaches them',
  P({ type: 'category', data: C5 }, {}, [line(D5, { areaStyle: {} })]));
aadd('polar-line-radius.override', 'a line on a category radius: the clip grows r, duration 600 linear, delay 100',
  P({}, CAT, [line(D5, { animationDuration: 600, animationEasing: 'linear', animationDelay: 100 })]));
aadd('polar-line-fraction.default', 'a line on a category radius over a ring on fractions: the pop-in reads the unrounded radii',
  P({}, CAT, [line(D5)], { polar: { center: ['50.37%', '49.71%'], radius: ['11.3%', '77.7%'] } }));
aadd('polar-line-ring.default', 'a line over a ring: the clip from r0', P({}, CAT, [line(D5)], { polar: { radius: [30, '80%'] } }));

function runAnim(ac) {
  NOW = T_BASE;
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
  const s0 = id => cs(id).series[0];
  out.cases.forEach(q => guard(q.id + ': every record matches its recipe', q.fails.length === 0));
  const numOf = h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); };
  guard('a radial bar grows r from the start', s0('bar-radial').items.every(it => it.layout[2] === hex(0) && it.type === 'sector'));
  guard('a tangential bar sweeps from the start angle', s0('bar-tangential').items.every(it => it.layout[4] === s0('bar-tangential').items[0].layout[4]));
  guard('roundCap on a tangential bar is a Sausage', s0('bar-roundcap').items.every(it => it.type === 'sausage'));
  guard('roundCap on a radial bar is a Sector with no corners', s0('bar-roundcap-radial').items.every(it => it.type === 'sector' && it.corner === hex(0)));
  guard('a negative tangential bar runs anticlockwise', s0('bar-roundcap').items[1].cw === false);
  guard('a clipped radial bar is cut at the edge', s0('bar-clip').items.some(it => it.cls === 'drawn' && it.shape[3] !== it.layout[3]));
  guard('a bar wholly outside is hidden', s0('bar-clip').items.some(it => it.cls === 'hidden'));
  guard('clip off keeps the bar whole', cs('bar-clip').series[1].items.every(it => it.cls === 'drawn' && it.shape[3] === it.layout[3]));
  guard('the angle of a tangential bar is clamped to the axis, not clipped', s0('bar-clip-tangential').items.filter(it => it.shape[5] === hex(3 * Math.PI / 2)).length === 3);
  guard('a zero tangential bar has no fill', s0('bar-zero').items[0].zero === true && s0('bar-zero').items[1].zero === false && s0('bar-zero').items[4].zero === true);
  guard('a zero radial bar keeps its fill', s0('bar-zero-radial').items.every(it => it.zero === false));
  guard('a percentage corner is of |r|', cs('bar-corner').series[2].items.every(it => Array.isArray(it.corner)));
  guard('barMinHeight lifts a small radial bar', Math.abs(numOf(s0('bar-minheight').items[0].layout[3]) - numOf(s0('bar-minheight').items[0].layout[2])) === 12);
  guard('a background sector spans the ring on a radial bar', s0('bar-background').bg && s0('bar-background').bg[0].shape[2] === hex(0));
  guard('a numeric rotate is taken as radians', cs('label-end-radial').series[1].items.some(it => it.label && it.label.drawn && it.label.rot === hex(30)));
  guard('middle flips a label to read', cs('label-middle-radial').series[0].items.some(it => it.label && it.label.drawn && numOf(it.label.rot) < 0));
  guard('outside on a negative radial bar is startArc', cs('label-outside-radial').series[0].items[2].label.word === 'startArc');
  guard('inside falls back on the path rect', cs('label-inside-tangential').series[0].items.every(it => !it.label.drawn || it.label.dAlign === 'center'));
  guard('heatmap on a polar draws nothing', s0('heatmap-polar').drawn === 0);
  guard('markArea on a polar throws', !!cs('marker-area').threw);
  guard('markers on a polar bar have no place', cs('marker-bar').markers.every(m => m.items.every(it => JSON.stringify(it.layout).includes('7ff8'))));
  guard('markers on a polar line are placed', cs('marker-line').markers.some(m => m.kind === 'markPoint' && m.items.some(it => !JSON.stringify(it.layout).includes('7ff8'))));
  guard('a one-value markLine is dropped on a polar', cs('marker-line').markers.find(m => m.kind === 'markLine').items.length === 2);
  guard('the polar symbol clip is padded as a rect', s0('line-clip-ring').symClip.r0 === hex(40));
  guard('a symbol past the radius is not drawn', s0('line-clip-ring').symbols[2].drawn === false);
  guard('step is ignored on a polar', JSON.stringify(s0('line-step').polyline) === JSON.stringify(s0('line-step').points));
  guard('the inside angle zoom filters the bars', cs('zoom-inside-angle').series[0].count === 4);
  guard('the pointer reports the series', cs('ptr-cat-angle').pointer.some(p => p.tip && p.tip.some(a => a.some(x => x.series.length === 2))));
  guard('the shadow on a value angle is wider than 1 degree', cs('ptr-value-shadow').pointer.some(p => p.axes.some(a => a.el && a.el.type === 'sector'
    && Math.abs(numOf(a.el.shape[5]) - numOf(a.el.shape[4])) > 2 * RADIAN)));
  guard('a series finder converts on its polar', cs('cv-series').convert.some(p => p.finder.text === '{"seriesIndex":1}' && p.op === 'to' && p.out.k === 'arr'));
  guard('emphasis paints the bar', cs('state-bar').states[0].items.some(it => it.s === 0 && it.i === 1 && it.fill === '#ee6666'));
  guard('select paints the bar', cs('state-bar').states[2].items.some(it => it.s === 0 && it.i === 2 && it.states.includes('select')));
  // the animations
  const an = id => out.anim.cases.find(q => q.id === id);
  const sectors = (c, t) => c.elements.filter(e => e.owner === 'series0:bar' && e.role === 'el' && e.type === t);
  guard('a radial bar animates r', sectors(an('polar-bar-radial.default'), 'sector').every(e => e.track && e.track['shape.r'] && !e.track['shape.endAngle']));
  guard('a tangential bar animates endAngle', sectors(an('polar-bar-tangential.default'), 'sector').every(e => e.track && e.track['shape.endAngle'] && !e.track['shape.r']));
  guard('a sausage animates endAngle', sectors(an('polar-bar-roundcap.override'), 'sausage').every(e => e.track && e.track['shape.endAngle']));
  guard('the angle line clip sweeps', an('polar-line-angle.default').elements.some(e => e.role === 'clip' && e.track && e.track['shape.endAngle']));
  guard('the radius line clip grows r', an('polar-line-radius.override').elements.some(e => e.role === 'clip' && e.track && e.track['shape.r']));
  guard('every animation settles by 1500', out.anim.cases.every(c => c.clips[c.clips.length - 1] === 0));
  return g;
}

function generate() {
  NOW = T_BASE;
  const out = {
    source: DIST, version: echarts.version,
    notes: [
      'static cases: animation false, 600 x 400, one renderToSVGString; labels read as updateInnerText left them (innerTransformable).',
      'pointer: updateAxisPointer at integer pixels; the showTip payload caught as the action\'s event.',
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
