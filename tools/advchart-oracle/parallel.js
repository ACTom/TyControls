// Upstream's own answers for the PARALLEL coordinate system (batch 128,
// roadmap C19): the parallel component (its box, layout 'horizontal' /
// 'vertical', the axes in their component order), every parallelAxis (its
// scale and extent, inverse, the position / rotation / transform the
// coordinate system gives it, the name's available width) and everything its
// AxisBuilder draws (line, arrows, ticks, minor ticks, labels, the name, the
// name cut to the width between two axes); the parallel series (each row's
// polyline through dataToPoint, a value that is empty dropping its point, the
// smooth curve's control points as zrender's smoothBezier makes them, the
// style the visual stages leave -- the palette, lineStyle, an item's own
// lineStyle, a visualMap's colour -- and the opacity parallelVisual writes:
// lineStyle.opacity, or activeOpacity / inactiveOpacity once an axis has
// active intervals); the axisAreaSelect action and its event; hover, emphasis,
// focus, the item tooltip and the legend; the enter animation (the data
// group's clip rect growing across the layout); containPixel and
// convertToPixel with parallel, parallelAxis and series finders (the parallel
// coordinate system has no convertToPixel at all).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist by default, or
// ECHARTS_DIST) in node: echarts.init(null, null, {renderer: 'svg', ssr:
// true}), right after init chart._ssr = false, echarts.env.node = false and
// the chart prototype's getDom answering an empty object so TooltipView runs
// (tooltip-finish.js' recipe). Text is measured with zrender's width table
// (the TZrSsrMeasurer of the Pascal tests). TZ=UTC.
//
// TIME. The global Date is replaced before the dist loads; every case starts
// at T0 = 1700000000000 (animation.js' clock). setOption's own flush steps
// every clip once at T0 (frame 0); a later frame is NOW = T0 + t,
// zr.animation.update(), the timers due by then (the clip's removal is a
// setTimeout), storage.getDisplayList(true).
//
//   node tools/advchart-oracle/parallel.js
//
// writes tests/fixtures/advchart-parallel.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex     a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//           lowercase (NaN 7ff8000000000000).
//   colour  [r, g, b, a] from echarts.color.parse, null when unset.
//
// Top level: source, W, H, T0, notes[], cases[], guards[], recipes{}
//   case: id, group ('layout' | 'interact' | 'enter' | 'convert'), note, W,
//     H, option, record, frames[] | null, steps[], convert[] | null
//   record: parallels[], series[], legend | null
//   parallel: index, rect [x, y, w, h] hex, layout, dims[], axes[]
//   axis: dim, axisIndex, type, extent [2] hex, inverse, scale [2] hex,
//     blank, position [2] hex, rotation hex, transform [6] hex, nameWidth hex
//     (axisNameAvailableWidth), labelShow, intervals [[a, b]] hex
//     (activeIntervals), view: {shown, line {x1, y1, x2, y2} | null,
//     arrows[] {type, x, y, rotation, w, h}, ticks[] {tick, x1, y1, x2, y2,
//     ignore}, minorTicks[] {x1, y1, x2, y2}, labels[] {tick, text, x, y,
//     rotation, align, va, ignore}, name {text (as drawn), full, x, y,
//     rotation, align, va} | null}
//   series: seriesIndex, parallelIndex, count, smooth hex, z, items[]
//   item: dataIndex, points (hex, flat), path [cmd, args hex ...] (the
//     element's buildPath: M, L, C), stroke colour, lineWidth hex, opacity
//     hex, lineDash (as the style holds it), z2 -- the element's look at
//     rest (its _normalState while in a state) --, active ('normal' |
//     'active' | 'inactive')
//   frame: t, clips [{seriesIndex, clip [x, y, w, h] hex | null}]
//   step: i, t ('move' | 'leave' | 'action' | 'merge'), x, y, payload |
//     option, hover {seriesIndex, dataIndex} | null, events [{type, ...}],
//     tooltip {shown, rows [{marker, name, value}] | null, text}, states
//     [{seriesIndex, dataIndex, states[], stroke, opacity hex, lineWidth hex,
//     z2}], record (after 'action' / 'merge': the record again), legend
//   convert: {op ('to' | 'from' | 'contain'), finder {in, text}, value {in,
//     text, textSafe}, out {k: 'none' | 'num' | 'arr' | 'bool' | 'throw', v}}
//
// Self-checks (recipes; each must run): R1 every parallel's rect from the
// box options (parsePercent of left / top / right / bottom / width / height)
// and every axis' position from the layout (step * index along, the axis
// length across, the rotation pi / 2 or 0); R2 every polyline point through
// the axis' dataToCoord and the transform (rotate, then translate --
// matrix.ts), a row's empty values dropped; R3 every smooth path's control
// points by smoothBezier transcribed; R4 every row's opacity from the active
// intervals (getActiveState) and the opacity map of parallelVisual; R5 every
// enter frame's clip width (or height) as the linear easing puts it. Guards:
// named facts. Two generations in one process give the same bytes; no
// \u0000; the JSON parses back. process.exit() ends the run.
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

// ---------- the fake clock (installed before the build loads) ----------
const RealDate = Date;
const T0 = 1700000000000;
let NOW = T0;
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
function settle(at) {
  for (;;) {
    TIMERS = TIMERS.filter(t => String(t.fn).indexOf('requestAnimationFrame') < 0);
    TIMERS.sort((a, b) => a.due - b.due || a.id - b.id);
    if (!TIMERS.length || TIMERS[0].due > at) break;
    const t = TIMERS.shift();
    if (t.due > NOW) NOW = t.due;
    t.fn();
  }
  if (at > NOW) NOW = at;
}

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-parallel.json');

const W = 600;
const H = 400;

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

// ---------- numbers ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hexOr = (v, d) => hex(v == null ? d : +v);
function colourOf(c) {
  if (c == null || c === 'none') return null;
  if (typeof c !== 'string') return null;
  const p = echarts.color.parse(c);
  return p ? [p[0], p[1], p[2], p[3]] : null;
}
const same = (a, b) => (Number.isNaN(a) && Number.isNaN(b)) || a === b;
const lineRec = s => ({ x1: hex(s.x1), y1: hex(s.y1), x2: hex(s.x2), y2: hex(s.y2) });

let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};

// ---------- charts ----------
function newChart(w, h) {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: w || W, height: h || H });
  chart._ssr = false;
  return chart;
}
(function enableTooltips() {
  const probe = newChart();
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });

let ecKey = null;
function ecData(el) {
  if (!el) return null;
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (k.indexOf('__ec_inner_') === 0 && v && typeof v === 'object' && 'seriesIndex' in v) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}
function walk(e, f) {
  f(e);
  if (e.childrenRef) e.childrenRef().forEach(x => walk(x, f));
}

// =====================================================================
// reading a chart
// =====================================================================
function axisViewRec(chart, axisModel) {
  const out = { shown: !!axisModel.get('show'), line: null, arrows: [], ticks: [], minorTicks: [], labels: [], name: null };
  const view = chart.getViewOfComponentModel(axisModel);
  must(view, 'no parallelAxis view');
  if (!out.shown) return out;
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
      out.labels.push({ tick: mm[1], text: String(e.style.text), x: hex(e.x), y: hex(e.y), rotation: hex(e.rotation),
        align: e.style.align, va: e.style.verticalAlign, ignore: !!e.ignore });
    }
    else if (e.anid === 'name' && e.style) {
      // the text as drawn: the tspans the truncation left
      e.update && e.update();
      const shown = (e.childrenRef ? e.childrenRef() : []).filter(k => k.type === 'tspan').map(k => String(k.style.text));
      out.name = { text: shown.join('\n'), full: String(e.style.text), x: hex(e.x), y: hex(e.y), rotation: hex(e.rotation),
        align: e.style.align, va: e.style.verticalAlign };
    }
  });
  return out;
}

function parallelRecs(chart) {
  const out = [];
  chart.getModel().eachComponent('parallel', pm => {
    const cs = pm.coordinateSystem;
    if (!cs) return;
    const r = cs.getRect();
    const rec = { index: pm.componentIndex, rect: [r.x, r.y, r.width, r.height].map(hex), layout: pm.get('layout'),
      dims: cs.dimensions.slice(), axes: [] };
    cs.dimensions.forEach(dim => {
      const axis = cs.getAxis(dim);
      const lay = cs.getAxisLayout(dim);
      rec.axes.push({
        dim, axisIndex: axis.axisIndex, type: axis.type, extent: axis.getExtent().map(hex), inverse: !!axis.inverse,
        scale: axis.scale.getExtent().map(hex), blank: axis.scale.isBlank(),
        position: lay.position.map(hex), rotation: hex(lay.rotation), transform: Array.from(lay.transform).map(hex),
        nameWidth: hex(lay.axisNameAvailableWidth), labelShow: !!lay.axisLabelShow,
        intervals: (axis.model.activeIntervals || []).map(iv => iv.map(hex)),
        view: axisViewRec(chart, axis.model),
      });
    });
    out.push(rec);
  });
  return out;
}

// the element's path through a recording context
function pathOf(el) {
  const cmds = [];
  const ctx = {
    moveTo(x, y) { cmds.push('M', hex(x), hex(y)); },
    lineTo(x, y) { cmds.push('L', hex(x), hex(y)); },
    bezierCurveTo(a, b, c, d, e, f) { cmds.push('C', hex(a), hex(b), hex(c), hex(d), hex(e), hex(f)); },
    closePath() { cmds.push('Z'); },
  };
  el.buildPath(ctx, el.shape, false);
  return cmds;
}

function activeStates(sm) {
  const out = [];
  const cs = sm.coordinateSystem;
  cs.eachActiveState(sm.getData(), (st, i) => { out[i] = st; });
  return out;
}

function seriesRecs(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'parallel') return;
    const data = sm.getData();
    const act = activeStates(sm);
    const rec = { seriesIndex: sm.seriesIndex, parallelIndex: sm.coordinateSystem.model.componentIndex, count: data.count(),
      smooth: null, z: null, items: [] };
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) { rec.items.push({ dataIndex: i, el: false }); continue; }
      if (rec.smooth === null) { rec.smooth = hex(el.shape.smooth); rec.z = el.z; }
      const pts = [];
      el.shape.points.forEach(p => { pts.push(hex(p[0]), hex(p[1])); });
      // the look at rest: an element in a state holds its normal values
      // in _normalState
      const inState = (el.currentStates || []).length > 0 && el._normalState;
      const st = inState && el._normalState.style ? el._normalState.style : el.style;
      const z2 = inState && el._normalState.z2 != null ? el._normalState.z2 : el.z2;
      rec.items.push({ dataIndex: i, el: true, raw: data.getRawIndex(i), points: pts, path: pathOf(el),
        stroke: colourOf(st.stroke), lineWidth: hexOr(st.lineWidth, 1), opacity: hexOr(st.opacity, 1),
        lineDash: st.lineDash == null ? null : st.lineDash, z2, active: act[i] });
    }
    out.push(rec);
  });
  return out;
}

function legendRec(chart) {
  const m = chart.getModel().getComponent('legend', 0);
  if (!m) return null;
  const v = chart.getViewOfComponentModel(m);
  const out = [];
  v.group.traverse(el => {
    if (el.type === 'text' && el.parent) {
      const icon = el.parent.childAt(0);
      if (icon && icon.shape && icon.shape.symbolType) {
        out.push({ name: String(el.style.text), selected: m.isSelected(String(el.style.text)),
          icon: icon.shape.symbolType, fill: colourOf(icon.style.fill),
          stroke: colourOf(icon.style.stroke), opacity: hexOr(icon.style.opacity, 1), lineWidth: hexOr(icon.style.lineWidth, 1) });
      }
    }
  });
  return out;
}

function record(chart) {
  return { parallels: parallelRecs(chart), series: seriesRecs(chart), legend: legendRec(chart) };
}

// =====================================================================
// the recipes
// =====================================================================
const RECIPES = { R1: 0, R2: 0, R3: 0, R4: 0, R5: 0 };
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
// layout.getLayoutRect with no margin, for the box keys as the model holds them
function boxRecipe(pm, w, h) {
  let left = parsePercent(pm.get('left'), w);
  let top = parsePercent(pm.get('top'), h);
  const right = parsePercent(pm.get('right'), w);
  const bottom = parsePercent(pm.get('bottom'), h);
  let width = parsePercent(pm.get('width'), w);
  let height = parsePercent(pm.get('height'), h);
  isNaN(width) && (width = w - right - 0 - left);
  isNaN(height) && (height = h - bottom - 0 - top);
  if (isNaN(left)) left = w - right - width - 0;
  if (isNaN(top)) top = h - bottom - height - 0;
  return [left + 0, top + 0, width, height];
}
// matrix.rotate then matrix.translate on the identity
function transformRecipe(rotation, position) {
  const st = Math.sin(rotation);
  const ct = Math.cos(rotation);
  const m = [1 * ct + 0 * st, -1 * st + 0 * ct, 0 * ct + 1 * st, -0 * st + ct * 1,
    ct * (0 - 0) + st * (0 - 0) + 0, ct * (0 - 0) - st * (0 - 0) + 0];
  m[4] = m[4] + position[0];
  m[5] = m[5] + position[1];
  return m;
}
function checkLayout(chart, where, w, h) {
  chart.getModel().eachComponent('parallel', pm => {
    const cs = pm.coordinateSystem;
    if (!cs) return;
    const r = cs.getRect();
    const want = boxRecipe(pm, w, h);
    must(same(want[0], r.x) && same(want[1], r.y) && same(want[2], r.width) && same(want[3], r.height),
      where + ': R1 rect ' + [r.x, r.y, r.width, r.height] + ', the recipe gives ' + want);
    const horiz = pm.get('layout') === 'horizontal';
    const layoutLength = horiz ? r.width : r.height;
    const axisLength = horiz ? r.height : r.width;
    const n = cs.dimensions.length;
    cs.dimensions.forEach((dim, idx) => {
      if (pm.get('axisExpandable')) return;
      const step = layoutLength / (n - 1);
      const pos = horiz ? [step * idx + r.x, axisLength + r.y] : [0 + r.x, step * idx + r.y];
      const rot = horiz ? Math.PI / 2 : 0;
      const lay = cs.getAxisLayout(dim);
      must(same(pos[0], lay.position[0]) && same(pos[1], lay.position[1]) && same(rot, lay.rotation), where + ': R1 axis ' + dim);
      const tm = transformRecipe(rot, pos);
      must(tm.every((v, k) => same(v, lay.transform[k])), where + ': R1 transform ' + dim + ' ' + Array.from(lay.transform) + ' / ' + tm);
      const axis = cs.getAxis(dim);
      const e = axis.getExtent();
      // the model's inverse: the extent is set before a backwards min / max
      // toggles axis.inverse
      const we = axis.model.get('inverse') ? [axisLength, 0] : [0, axisLength];
      must(same(e[0], we[0]) && same(e[1], we[1]), where + ': R1 extent ' + dim);
      RECIPES.R1++;
    });
  });
}
function emptyValue(v, type) {
  return type === 'category' ? v == null : (v == null || isNaN(v));
}
function checkPoints(chart, where) {
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'parallel') return;
    const cs = sm.coordinateSystem;
    const data = sm.getData();
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) continue;
      const want = [];
      cs.dimensions.forEach(dim => {
        const v = data.get(data.mapDimension(dim), i);
        const axis = cs.getAxis(dim);
        if (emptyValue(v, axis.type)) return;
        const c = axis.dataToCoord(v);
        const m = cs.getAxisLayout(dim).transform;
        want.push([m[0] * c + m[2] * 0 + m[4], m[1] * c + m[3] * 0 + m[5]]);
      });
      const got = el.shape.points;
      must(got.length === want.length, where + ': R2 point count ' + i);
      want.forEach((p, k) => must(same(p[0], got[k][0]) && same(p[1], got[k][1]), where + ': R2 point ' + i + '/' + k));
      RECIPES.R2++;
      if (el.shape.smooth && got.length >= 2) {
        const cps = smoothRecipe(got, el.shape.smooth);
        const cmds = pathOf(el);
        let k = 3;
        for (let s = 0; s < got.length - 1; s++) {
          must(cmds[k] === 'C', where + ': R3 a curve');
          const w6 = [cps[s * 2][0], cps[s * 2][1], cps[s * 2 + 1][0], cps[s * 2 + 1][1], got[s + 1][0], got[s + 1][1]];
          for (let q = 0; q < 6; q++) must(cmds[k + 1 + q] === hex(w6[q]), where + ': R3 control point ' + i + '/' + s + '/' + q);
          k += 7;
        }
        RECIPES.R3++;
      }
    }
  });
}
// zrender smoothBezier, not a loop, no constraint
function smoothRecipe(points, smooth) {
  const cps = [];
  const dist = (a, b) => Math.sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]));
  for (let i = 0, len = points.length; i < len; i++) {
    const point = points[i];
    if (i === 0 || i === len - 1) { cps.push([point[0], point[1]]); continue; }
    const prev = points[i - 1];
    const next = points[i + 1];
    const v = [(next[0] - prev[0]) * smooth, (next[1] - prev[1]) * smooth];
    let d0 = dist(point, prev);
    let d1 = dist(point, next);
    const sum = d0 + d1;
    if (sum !== 0) { d0 /= sum; d1 /= sum; }
    const v1 = [v[0] * -d0, v[1] * -d0];
    const v2 = [v[0] * d1, v[1] * d1];
    cps.push([point[0] + v1[0], point[1] + v1[1]]);
    cps.push([point[0] + v2[0], point[1] + v2[1]]);
  }
  return cps;
}
// parallelVisual and AxisModel.getActiveState
function activeRecipe(intervals, value) {
  if (!intervals.length) return 'normal';
  if (value == null || isNaN(+value)) return 'inactive';
  for (const iv of intervals) if (iv[0] <= value && value <= iv[1]) return 'active';
  return 'inactive';
}
function checkOpacity(chart, where) {
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'parallel') return;
    const cs = sm.coordinateSystem;
    const data = sm.getData();
    const any = cs.dimensions.some(d => cs.getAxis(d).model.activeIntervals.length > 0);
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) continue;
      let state = 'normal';
      if (any) {
        state = 'active';
        for (const d of cs.dimensions) {
          const s = activeRecipe(cs.getAxis(d).model.activeIntervals, data.get(data.mapDimension(d), i));
          if (s === 'inactive') { state = 'inactive'; break; }
        }
      }
      let op = state === 'normal' ? sm.get(['lineStyle', 'opacity']) : state === 'active' ? sm.get('activeOpacity') : sm.get('inactiveOpacity');
      if (state === 'normal' && data.hasItemOption) {
        const io = data.getItemModel(i).get(['lineStyle', 'opacity'], true);
        io != null && (op = io);
      }
      const ns = el._normalState && el._normalState.style;
      const shown = (el.currentStates || []).length && ns ? ns.opacity : el.style.opacity;
      must(same(op, shown), where + ': R4 opacity ' + i + ' ' + shown + ', the recipe gives ' + op);
      RECIPES.R4++;
    }
  });
}

// =====================================================================
// pointer positions
// =====================================================================
function hoverTarget(chart, x, y) {
  return chart.getZr().handler.findHover(x, y).target;
}
function segDist(p, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const l2 = dx * dx + dy * dy;
  let t = l2 ? ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2 : 0;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy));
}
function polyDist(el, p) {
  const pts = el.shape.points;
  let best = Infinity;
  for (let k = 1; k < pts.length; k++) best = Math.min(best, segDist(p, pts[k - 1], pts[k]));
  return best;
}
// a pixel on item k's segment j at t, on that line and at least 4 px from
// every other line of the chart
function resolveAt(chart, at, where) {
  if (Array.isArray(at)) return at;
  const [s, k, j, t] = at.on;
  const sm = chart.getModel().getSeriesByIndex(s);
  const el = sm.getData().getItemGraphicEl(k);
  const others = [];
  chart.getModel().eachSeries(o => {
    if (o.subType !== 'parallel') return;
    const d = o.getData();
    for (let i = 0; i < d.count(); i++) { const e = d.getItemGraphicEl(i); if (e && e !== el) others.push(e); }
  });
  const a = el.shape.points[j], b = el.shape.points[j + 1];
  const cx = a[0] + (b[0] - a[0]) * t, cy = a[1] + (b[1] - a[1]) * t;
  for (let rad = 0; rad <= 8; rad++) {
    for (let dx = -rad; dx <= rad; dx++) {
      for (let dy = -rad; dy <= rad; dy++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== rad) continue;
        const x = Math.round(cx) + dx, y = Math.round(cy) + dy;
        if (hoverTarget(chart, x, y) !== el) continue;
        if (polyDist(el, [x, y]) > 0.75) continue;
        if (others.some(o => polyDist(o, [x, y]) < 4)) continue;
        return [x, y];
      }
    }
  }
  throw new OracleError(where + ': no point on series ' + s + ' item ' + k);
}

const SEGMENT = /\{(__EC_aUTo_\d+)\|([^}]*)\}/g;
function tooltipRows(content) {
  const text = String(content.el.style.text);
  const rich = content.el.style.rich || {};
  return text.split('\n').map(line => {
    const row = { marker: null, name: null, value: null };
    SEGMENT.lastIndex = 0;
    let m;
    while ((m = SEGMENT.exec(line))) {
      const st = rich[m[1]] || {};
      if (st.width != null) row.marker = st.width === 10 ? 'item' : 'subItem';
      else if (st.fontWeight != null && +st.fontWeight >= 700 || st.fontWeight === 'bold') row.value = m[2];
      else if (row.name === null && st.align !== 'right') row.name = m[2];
      else row.value = m[2];
    }
    return row;
  });
}
function hoverRec(chart, x, y) {
  const t = hoverTarget(chart, x, y);
  if (!t) return null;
  let d = null;
  for (let e = t; e; e = e.__hostTarget || e.parent) {
    const q = ecData(e);
    if (q && q.seriesIndex != null) { d = q; break; }
  }
  if (!d) return { seriesIndex: null, dataIndex: null };
  return { seriesIndex: d.seriesIndex, dataIndex: d.dataIndex == null ? null : d.dataIndex };
}
function statesRec(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'parallel') return;
    const data = sm.getData();
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) continue;
      out.push({ seriesIndex: sm.seriesIndex, dataIndex: i, states: (el.currentStates || []).slice(),
        stroke: colourOf(el.style.stroke), opacity: hexOr(el.style.opacity, 1), lineWidth: hexOr(el.style.lineWidth, 1), z2: el.z2 });
    }
  });
  return out;
}
// an event's own keys, numbers as they are (hex is not needed: intervals are
// written by the case)
function eventRec(t, e) {
  if (t === 'mouseover' || t === 'mousemove' || t === 'mouseout') {
    return { type: t, seriesIndex: e.seriesIndex, dataIndex: e.dataIndex, name: e.name == null ? null : String(e.name) };
  }
  if (t === 'axisareaselected') {
    return { type: t, parallelAxisId: e.parallelAxisId == null ? null : e.parallelAxisId,
      parallelAxisIndex: e.parallelAxisIndex == null ? null : e.parallelAxisIndex, intervals: e.intervals };
  }
  if (t === 'brushselected') return { type: t, batch: e.batch };
  if (t === 'legendselectchanged') return { type: t, name: e.name, selected: e.selected };
  return { type: t };
}

// =====================================================================
// the cases
// =====================================================================
const CASES = [];
function C(id, group, note, option, opts) {
  CASES.push(Object.assign({ id, group, note, option, steps: [], samples: null, probes: null, w: W, h: H }, opts || {}));
}
const COLORS = ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'];
const ROWS = [
  [12.99, 100, 82, 'Good', 7],
  [9.99, 80, 77, 'OK', 3],
  [20, 120, 60, 'Excellent', 9],
  [15.5, 95, 70, 'Bad', 5],
];
const AX4 = [
  { dim: 0, name: 'Price' },
  { dim: 1, name: 'Net Weight' },
  { dim: 2, name: 'Amount' },
  { dim: 3, name: 'Score', type: 'category', data: ['Excellent', 'Good', 'OK', 'Bad'] },
];
const base = extra => Object.assign({ animation: false, color: COLORS }, extra);
const PS = o => Object.assign({ type: 'parallel' }, o);

// ---- A. the layout and the axes ----
C('h-basic', 'layout', 'the defaults: horizontal, the box 80 / 60 / 80 / 60, four axes with names, one series of four rows',
  base({ parallelAxis: AX4, series: [PS({ data: ROWS })] }));
C('v-basic', 'layout', "layout 'vertical': the axes are rows, rotation 0, labels below each line",
  base({ parallel: { layout: 'vertical', left: 90, right: 60, top: 40, bottom: 50 }, parallelAxis: AX4, series: [PS({ data: ROWS })] }));
C('types', 'layout', 'every axis type: value, category with data, category collected from the data, time (zoned strings and a number), log',
  base({ useUTC: true, parallelAxis: [
    { dim: 0, type: 'value', name: 'v' },
    { dim: 1, type: 'category', data: ['a', 'b', 'c', 'd', 'e'], name: 'cat' },
    { dim: 2, type: 'category', name: 'collected' },
    { dim: 3, type: 'time', name: 'time' },
    { dim: 4, type: 'log', name: 'log' },
  ], series: [PS({ data: [
    [3, 'b', 'x', '2024-01-05T00:00:00Z', 10],
    [7, 'd', 'y', '2024-03-01T00:00:00Z', 1000],
    [-2, 'a', 'x', Date.UTC(2024, 1, 10), 2],
    [5, 'e', 'z', '2024-02-20T12:00:00Z', 50],
  ] })] }));
C('quirk-data-value', 'layout', 'a parallelAxis with data and no type is a VALUE axis (the parallel default type wins over the data)',
  base({ parallelAxis: [{ dim: 0 }, { dim: 1, data: ['a', 'b', 'c'] }, { dim: 2 }],
    series: [PS({ data: [[1, 2, 3], [4, 1, 2], [2, 0, 5]] })] }));
C('inverse', 'layout', 'inverse on a value and a category axis: the extent swapped, the name at the other end',
  base({ parallelAxis: [
    { dim: 0, name: 'up' },
    { dim: 1, inverse: true, name: 'down' },
    { dim: 2, type: 'category', data: ['p', 'q', 'r'], inverse: true, name: 'cat down' },
    { dim: 3, inverse: true, min: 0, max: 50, name: 'fixed' },
  ], series: [PS({ data: [[1, 10, 'p', 5], [3, 20, 'r', 40], [2, 15, 'q', 25]] })] }));
C('swapped', 'layout', 'min above max: the scale turns round and the axis inverts AFTER its extent was set -- only the name moves',
  base({ parallelAxis: [{ dim: 0, name: 'plain' }, { dim: 1, min: 50, max: 0, name: 'swapped' }, { dim: 2, min: 50, max: 0, inverse: true, name: 'both' }],
    series: [PS({ data: [[1, 10, 20], [2, 40, 5]] })] }));
C('many-categories', 'layout', 'forty categories on a horizontal and on a vertical parallel: the automatic label interval measures along the axis (a quarter turn on the horizontal layout)',
  base({ parallel: [{ right: '55%' }, { left: '55%', layout: 'vertical' }],
    parallelAxis: [
      { dim: 0, type: 'category', data: Array.from({ length: 40 }, (_, k) => 'category ' + k), parallelIndex: 0 },
      { dim: 1, parallelIndex: 0 },
      { dim: 0, type: 'category', data: Array.from({ length: 40 }, (_, k) => 'category ' + k), parallelIndex: 1 },
      { dim: 1, parallelIndex: 1 },
    ],
    series: [PS({ data: [['category 3', 1], ['category 30', 2]] }), PS({ parallelIndex: 1, data: [['category 7', 1]] })] }));
C('min-max', 'layout', 'min / max, scale: true, splitNumber, interval, dataMin / dataMax',
  base({ parallelAxis: [
    { dim: 0, min: -10, max: 30 },
    { dim: 1, scale: true },
    { dim: 2, splitNumber: 10 },
    { dim: 3, interval: 25, max: 100 },
    { dim: 4, min: 'dataMin', max: 'dataMax' },
  ], series: [PS({ data: [[1, 50, 3, 10, 7], [5, 70, 9, 60, 2], [12, 65, 4, 30, 9.5]] })] }));
C('names', 'layout', "names: start, middle (turned with the axis), end with a gap, nameRotate, one too long for the space between axes, nameTruncate's own maxWidth, a nameTextStyle colour and size",
  base({ parallelAxis: [
    { dim: 0, name: 'start name', nameLocation: 'start' },
    { dim: 1, name: 'middle name', nameLocation: 'middle', nameGap: 30 },
    { dim: 2, name: 'end name with a gap', nameGap: 25 },
    { dim: 3, name: 'rotated', nameRotate: 45 },
    { dim: 4, name: 'A name far too long to fit between two of these axes at all', nameTextStyle: { fontSize: 14 } },
    { dim: 5, name: 'truncated by its own width', nameTruncate: { maxWidth: 40, ellipsis: '..' } },
  ], series: [PS({ data: [[1, 2, 3, 4, 5, 6], [6, 5, 4, 3, 2, 1]] })] }));
C('names-vertical', 'layout', 'names on a vertical layout: end, start, middle; a long one cut to the row spacing',
  base({ parallel: { layout: 'vertical' }, parallelAxis: [
    { dim: 0, name: 'end' },
    { dim: 1, name: 'start', nameLocation: 'start' },
    { dim: 2, name: 'middle', nameLocation: 'middle' },
    { dim: 3, name: 'A long name on a vertical layout that the row spacing cuts short' },
  ], series: [PS({ data: [[1, 2, 3, 4], [4, 3, 2, 1]] })] }));
C('labels', 'layout', 'axis labels: rotate 30 and -45, margin 14, a formatter template, showMinLabel false, axisLabel.show false (the coordinate system shows them anyway), an interval on a category axis, inside (ignored)',
  base({ parallelAxis: [
    { dim: 0, axisLabel: { rotate: 30 } },
    { dim: 1, axisLabel: { rotate: -45, margin: 14 } },
    { dim: 2, axisLabel: { formatter: '{value} kg' } },
    { dim: 3, axisLabel: { showMinLabel: false } },
    { dim: 4, axisLabel: { show: false } },
    { dim: 5, type: 'category', data: ['c0', 'c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7'], axisLabel: { interval: 1, inside: true } },
  ], series: [PS({ data: [[1, 2, 3, 4, 5, 'c2'], [9, 8, 7, 6, 5, 'c7'], [4, 4, 4, 4, 4, 'c0']] })] }));
C('furniture', 'layout', 'ticks 9 long and inside (ignored), minor ticks, a hidden axis line, a hidden axis, arrows on the line, a hidden tick',
  base({ parallelAxis: [
    { dim: 0, axisTick: { length: 9, inside: true } },
    { dim: 1, minorTick: { show: true, splitNumber: 4 } },
    { dim: 2, axisLine: { show: false } },
    { dim: 3, show: false },
    { dim: 4, axisLine: { symbol: ['none', 'arrow'], symbolSize: [8, 12] } },
    { dim: 5, axisTick: { show: false } },
  ], series: [PS({ data: [[1, 2, 3, 4, 5, 6], [6, 5, 4, 3, 2, 1]] })] }));
C('box', 'layout', 'the box as percents, width and height, and a right-and-bottom-only box',
  base({ parallel: [{ left: '10%', top: '15%', width: '50%', height: '30%' }, { right: 20, bottom: 10, width: 200, height: 120 }],
    parallelAxis: [{ dim: 0, parallelIndex: 0 }, { dim: 1, parallelIndex: 0 }, { dim: 2, parallelIndex: 0 },
      { dim: 0, parallelIndex: 1 }, { dim: 1, parallelIndex: 1 }],
    series: [PS({ data: [[1, 2, 3], [3, 1, 2]] }), PS({ parallelIndex: 1, data: [[5, 6], [7, 2]] })] }));
C('axis-default', 'layout', "parallel.parallelAxisDefault merged under every axis of it (the preprocessor; an axis' own key wins)",
  base({ parallel: { parallelAxisDefault: { type: 'value', nameLocation: 'start', nameGap: 8, axisLabel: { margin: 3 }, axisTick: { length: 3 } } },
    parallelAxis: [{ dim: 0, name: 'a' }, { dim: 1, name: 'b', nameLocation: 'end' }, { dim: 2, name: 'c', axisTick: { length: 7 } }],
    series: [PS({ data: [[1, 2, 3], [3, 1, 2]] })] }));
C('dim-order', 'layout', 'the axes in component order, not dim order: dims 3, 0, 2 -- the series maps each row element by its dim',
  base({ parallelAxis: [{ dim: 3, name: 'd3' }, { dim: 0, name: 'd0' }, { dim: 2, name: 'd2' }],
    series: [PS({ data: [[1, 2, 3, 4], [4, 3, 2, 1], [2, 2, 2, 2]] })] }));
C('no-parallel', 'layout', 'no parallel component: the preprocessor creates one',
  base({ parallelAxis: [{ dim: 0 }, { dim: 1 }], series: [PS({ data: [[1, 2], [2, 1]] })] }));
C('expand', 'layout', 'axisExpandable: eight axes, axisExpandCount 4 about axisExpandCenter 3, axisExpandWidth 60 -- the collapsed axes stand axisCollapseWidth apart, their labels hidden and their names cut to that width',
  base({ parallel: { axisExpandable: true, axisExpandCount: 4, axisExpandCenter: 3, axisExpandWidth: 60 },
    parallelAxis: [0, 1, 2, 3, 4, 5, 6, 7].map(k => ({ dim: k, name: 'axis number ' + k })),
    series: [PS({ data: [[1, 2, 3, 4, 5, 6, 7, 8], [8, 7, 6, 5, 4, 3, 2, 1]] })] }));
C('smooth', 'layout', 'smooth true (0.3), a number, a numeric string, 0 and false; and an empty value dropping its point',
  base({ parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }, { dim: 3 }, { dim: 4 }],
    series: [
      PS({ smooth: true, data: [[1, 5, 2, 8, 3], [6, 2, 7, 1, 4]] }),
      PS({ smooth: 0.6, data: [[3, 3, 9, 2, 6]] }),
      PS({ smooth: '0.15', data: [[2, 8, 1, 6, 5]] }),
      PS({ smooth: 0, data: [[5, 1, 5, 1, 5]] }),
      PS({ smooth: false, data: [[4, null, 3, '-', 2], [7, 7, NaN, 7, 7]] }),
    ] }));
C('empty-values', 'layout', 'empty values: null and NaN on value axes are dropped, a null on a category axis too, an unknown category is not',
  base({ parallelAxis: [{ dim: 0 }, { dim: 1, type: 'category', data: ['a', 'b'] }, { dim: 2 }],
    series: [PS({ data: [[1, 'a', 3], [null, 'b', 2], [2, null, 1], [3, 'zz', 2], [4, 'b', '']] })] }));
C('styles', 'layout', 'the palette over three series; lineStyle width 2 dashed and its own colour; item lineStyle colour, width, opacity, type; series color',
  base({ parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }],
    series: [
      PS({ lineStyle: { width: 2, type: 'dashed' }, data: [[1, 2, 3], { value: [3, 1, 2], lineStyle: { color: '#123456', width: 3, opacity: 0.9, type: 'dotted' } }] }),
      PS({ data: [[2, 2, 2]] }),
      PS({ color: '#aa3300', lineStyle: { opacity: 0.8 }, data: [[1, 3, 1]] }),
      PS({ lineStyle: { color: '#008800', width: 0.5 }, data: [[3, 3, 3]] }),
    ] }));
C('multi', 'layout', 'two parallels side by side, axes and series by parallelIndex (one series names parallelId)',
  base({ parallel: [{ id: 'left', left: 40, right: '55%' }, { id: 'right', left: '55%', right: 40, layout: 'vertical' }],
    parallelAxis: [
      { dim: 0, parallelIndex: 0, name: 'L0' }, { dim: 1, parallelIndex: 0, name: 'L1' },
      { dim: 0, parallelIndex: 1, name: 'R0' }, { dim: 1, parallelIndex: 1, name: 'R1' }, { dim: 2, parallelIndex: 1, name: 'R2' },
    ],
    series: [PS({ data: [[1, 9], [5, 3]] }), PS({ parallelIndex: 1, data: [[1, 2, 3], [3, 2, 1]] }), PS({ parallelId: 'right', data: [[2, 2, 2]] })] }));
C('visualmap', 'layout', 'a continuous visualMap on dimension 2 colouring the lines; its opacity channel is overwritten by parallelVisual',
  base({ visualMap: { type: 'continuous', dimension: 2, min: 0, max: 10, inRange: { color: ['#0000ff', '#ff0000'], opacity: [0.2, 1] }, show: false },
    parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }],
    series: [PS({ data: [[1, 2, 0], [2, 3, 2.5], [3, 1, 5], [4, 4, 7.5], [5, 5, 10], [6, 0, 12]] })] }));
C('visualmap-pieces', 'layout', 'a piecewise visualMap on the default dimension (the last), outOfRange grey, seriesIndex picking one series',
  base({ visualMap: { type: 'piecewise', seriesIndex: 0, pieces: [{ min: 0, max: 3, color: '#00aa00' }, { min: 3, max: 6, color: '#aa0000' }], outOfRange: { color: '#999999' }, show: false },
    parallelAxis: [{ dim: 0 }, { dim: 1 }],
    series: [PS({ data: [[1, 2, 1], [2, 3, 4], [3, 1, 9]] }), PS({ data: [[2, 2, 2]] })] }));
C('legend', 'layout', 'two named series and a legend: the icons; toggling one off rescales the axes',
  base({ legend: {}, parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }],
    series: [PS({ name: 'alpha', data: [[1, 2, 3], [2, 3, 1]] }), PS({ name: 'beta', data: [[10, 20, 30]] })] }),
  { steps: [['action', { type: 'legendToggleSelect', name: 'beta' }], ['action', { type: 'legendToggleSelect', name: 'beta' }]] });

// ---- B. interaction ----
const IX = extra => Object.assign({ animation: false, color: COLORS, tooltip: {} }, extra);
C('hover', 'interact', 'hovering a line: emphasis (the stroke lifted, z2 +10), the item tooltip (the whole row inline), the events; then another line, then leave',
  IX({ parallelAxis: AX4, series: [PS({ name: 'goods', data: ROWS.map((r, i) => (i === 1 ? { name: 'second', value: r } : r)) })] }),
  { steps: [['move', { on: [0, 0, 0, 0.5] }], ['move', { on: [0, 1, 1, 0.5] }], ['move', { on: [0, 2, 2, 0.4] }], ['leave']] });
C('hover-focus', 'interact', "emphasis.focus 'series' and its own emphasis / blur lineStyle: the other series blurs",
  IX({ parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }],
    series: [
      PS({ emphasis: { focus: 'series', lineStyle: { width: 4, color: '#ff00ff' } }, blur: { lineStyle: { opacity: 0.1 } }, data: [[1, 9, 1], [2, 8, 3]] }),
      PS({ data: [[9, 1, 9], [8, 2, 7]] }),
    ] }),
  { steps: [['move', { on: [0, 0, 0, 0.2] }], ['leave'], ['action', { type: 'highlight', seriesIndex: 1, dataIndex: 0 }], ['action', { type: 'downplay', seriesIndex: 1, dataIndex: 0 }]] });
C('area-select', 'interact', 'axisAreaSelect: one interval on an axis by id (active 1, inactive 0.05), two intervals, a second axis by index, a reversed interval, clear; an item lineStyle.opacity shows only while nothing is selected',
  IX({ parallelAxis: [{ dim: 0, id: 'price' }, { dim: 1 }, { dim: 2, type: 'category', data: ['a', 'b', 'c'] }],
    series: [PS({ data: [[1, 10, 'a'], [2, 20, 'b'], { value: [3, 30, 'c'], lineStyle: { opacity: 0.7 } }, [4, 40, 'a'], [5, null, 'b']] })] }),
  { steps: [
    ['action', { type: 'axisAreaSelect', parallelAxisId: 'price', intervals: [[1.5, 3.5]] }],
    ['action', { type: 'axisAreaSelect', parallelAxisId: 'price', intervals: [[0, 1], [3.5, 5]] }],
    ['action', { type: 'axisAreaSelect', parallelAxisIndex: 1, intervals: [[45, 5]] }],
    ['action', { type: 'axisAreaSelect', parallelAxisIndex: 2, intervals: [[0.5, 2]] }],
    ['action', { type: 'axisAreaSelect', parallelAxisIndex: [0, 1, 2], intervals: [] }],
  ] });
C('area-select-opacity', 'interact', 'activeOpacity / inactiveOpacity of the series; a selection kept across a setOption merge; the axis named by name',
  IX({ parallelAxis: [{ dim: 0, name: 'first' }, { dim: 1 }],
    series: [PS({ activeOpacity: 0.8, inactiveOpacity: 0.3, lineStyle: { opacity: 0.6 }, data: [[1, 1], [2, 2], [3, 3]] })] }),
  { steps: [
    ['action', { type: 'axisAreaSelect', parallelAxisName: 'first', intervals: [[1.5, 3]] }],
    ['merge', { series: [{ data: [[1, 1], [2, 2], [3, 3], [2.5, 1]] }] }],
  ] });
C('area-select-legend', 'interact', 'a legend click after a selection keeps the active intervals (they live on the axis model)',
  IX({ legend: {}, parallelAxis: [{ dim: 0 }, { dim: 1 }],
    series: [PS({ name: 'a', data: [[1, 1], [2, 2]] }), PS({ name: 'b', data: [[3, 3]] })] }),
  { steps: [
    ['action', { type: 'axisAreaSelect', parallelAxisIndex: 0, intervals: [[0, 1.5]] }],
    ['action', { type: 'legendToggleSelect', name: 'b' }],
  ] });

// ---- C. the enter animation ----
const ENTER = [0, 16, 100, 250, 500, 750, 999, 1000, 1001, 1100];
C('enter-h', 'enter', 'the enter animation: the data group clip grows in width over 1000 ms, linear; removed after',
  { color: COLORS, parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }], series: [PS({ data: [[1, 2, 3], [3, 1, 2]] })] },
  { samples: ENTER });
C('enter-v', 'enter', 'vertical: the clip grows in height; animationDuration 600, a delay of 100, two series',
  { color: COLORS, parallel: { layout: 'vertical' }, parallelAxis: [{ dim: 0 }, { dim: 1 }],
    series: [PS({ animationDuration: 600, animationDelay: 100, data: [[1, 2], [2, 1]] }), PS({ data: [[1.5, 1.5]] })] },
  { samples: [0, 16, 100, 101, 300, 500, 699, 700, 701, 1000, 1001, 1100] });
C('enter-easing', 'enter', "an easing of the series' own (cubicOut) and animation off on the second series",
  { color: COLORS, parallelAxis: [{ dim: 0 }, { dim: 1 }],
    series: [PS({ animationEasing: 'cubicOut', data: [[1, 2], [2, 1]] }), PS({ animation: false, data: [[1.5, 1.5]] })] },
  { samples: [0, 100, 400, 999, 1000, 1001] });

// ---- D. the conversions ----
const PIXELS = [[300, 200], [80, 60], [520, 340], [79, 200], [521, 200], [300, 59], [300, 341], [600, 0], [80.5, 340]];
C('convert', 'convert', 'containPixel answers on a parallel (its rect), on a parallelAxis (its coordinate system) and on a parallel series; convertToPixel / convertFromPixel answer nothing',
  base({ parallelAxis: [{ dim: 0, id: 'a0' }, { dim: 1 }, { dim: 2 }], series: [PS({ data: [[1, 2, 3], [3, 1, 2]] })] }),
  { probes: () => {
    const out = [];
    const finders = [{ parallelIndex: 0 }, 'parallel', { parallelAxisIndex: 1 }, { parallelAxisId: 'a0' }, { seriesIndex: 0 }, { parallelIndex: 1 }, { parallelAxisIndex: 5 }];
    finders.forEach(f => {
      out.push(['to', f, [1, 2, 3]]);
      out.push(['to', f, 2]);
      out.push(['from', f, [300, 200]]);
      PIXELS.forEach(p => out.push(['contain', f, p]));
    });
    return out;
  } });
C('convert-vertical', 'convert', 'containPixel on a vertical parallel with a box of its own, beside a grid',
  base({ grid: { left: 20, right: 420, top: 20, bottom: 20 }, xAxis: { type: 'value' }, yAxis: { type: 'value' },
    parallel: { layout: 'vertical', left: 250, right: 30, top: 50, bottom: 70 },
    parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }],
    series: [{ type: 'scatter', data: [[1, 1]] }, PS({ data: [[1, 2, 3]] })] }),
  { probes: () => {
    const out = [];
    [{ parallelIndex: 0 }, { seriesIndex: 1 }, { seriesIndex: 0 }, { gridIndex: 0 }].forEach(f => {
      out.push(['to', f, [1, 1]]);
      [[250, 50], [570, 330], [249, 100], [571, 100], [400, 49], [400, 331], [100, 200], [400, 200]].forEach(p => out.push(['contain', f, p]));
    });
    return out;
  } });

// =====================================================================
// the conversions
// =====================================================================
function enc(v) {
  if (typeof v === 'number') return { h: hex(v) };
  if (Array.isArray(v)) return v.map(enc);
  if (v && typeof v === 'object') {
    const o = {};
    Object.keys(v).forEach(k => { o[k] = enc(v[k]); });
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
  return { in: enc(v), text: JSON.stringify(v), textSafe: textSafe(v) };
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
  return c.probes().map(([op, finder, value]) => {
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

// =====================================================================
// one case
// =====================================================================
let LOG = null;
const EVENTS = ['mouseover', 'mousemove', 'mouseout', 'axisareaselected', 'brushselected', 'legendselectchanged', 'highlight', 'downplay'];
function clipsRec(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'parallel') return;
    const view = chart.getViewOfSeriesModel(sm);
    const cp = view._dataGroup.getClipPath();
    out.push({ seriesIndex: sm.seriesIndex, clip: cp ? [cp.shape.x, cp.shape.y, cp.shape.width, cp.shape.height].map(hex) : null });
  });
  return out;
}
// R5: the clip at t (initProps on the series: duration, delay, easing)
function checkClip(chart, t, where) {
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'parallel') return;
    const view = chart.getViewOfSeriesModel(sm);
    const cp = view._dataGroup.getClipPath();
    const rect = sm.coordinateSystem.getRect();
    const horiz = sm.coordinateSystem.model.get('layout') === 'horizontal';
    const full = horiz ? rect.width : rect.height;
    const on = sm.isAnimationEnabled();
    const dur = sm.get('animationDuration');
    const delay = sm.get('animationDelay') || 0;
    const easing = sm.get('animationEasing');
    if (!on) {
      must(cp === null || (horiz ? cp.shape.width : cp.shape.height) === full, where + ': R5 no animation, the clip is whole or gone');
      RECIPES.R5++;
      return;
    }
    if (!cp) { must(t >= dur + delay, where + ': R5 the clip went before its end'); RECIPES.R5++; return; }
    const p = Math.min(Math.max((t - delay) / dur, 0), 1);
    let want;
    if (easing === 'linear') want = (full - 0) * p + 0;
    else if (easing === 'cubicOut') { const k = p - 1; want = (full - 0) * (k * k * k + 1) + 0; }
    if (t <= delay) want = 0;
    if (p >= 1) want = full;
    const got = horiz ? cp.shape.width : cp.shape.height;
    must(same(want, got), where + ': R5 clip at ' + t + ' ' + got + ', the recipe gives ' + want);
    RECIPES.R5++;
  });
}

function recordCase(c) {
  NOW = T0;
  TIMERS = [];
  const chart = newChart(c.w, c.h);
  try {
    const where = c.id;
    for (const t of EVENTS) {
      chart.on(t, e => {
        if (!LOG) return;
        LOG.push(eventRec(t, e));
      });
    }
    const opt = JSON.parse(JSON.stringify(c.option));
    quiet(() => chart.setOption(JSON.parse(JSON.stringify(c.option))));
    const zr = chart.getZr();
    zr.storage.getDisplayList(true);
    checkLayout(chart, where, c.w, c.h);
    checkPoints(chart, where);
    checkOpacity(chart, where);
    const rec = record(chart);
    let frames = null;
    if (c.samples) {
      frames = [];
      for (const t of c.samples) {
        if (t > 0) {
          NOW = T0 + t;
          zr.animation.update();
          settle(NOW);
        }
        zr.storage.getDisplayList(true);
        checkClip(chart, t, where);
        frames.push({ t, clips: clipsRec(chart) });
      }
    }
    const steps = [];
    if (c.steps.length) {
      const tm = chart.getModel().getComponent('tooltip', 0);
      const tv = tm ? chart.getViewOfComponentModel(tm) : null;
      const content = () => tv && tv._tooltipContent;
      const visible = () => { const ct = content(); return !!(ct && ct.el && !ct.el.ignore && !ct.el.invisible); };
      if (tv) {
        const show = tv._showTooltipContent;
        tv._showTooltipContent = function () {
          const r = show.apply(this, arguments);
          const ct = tv._tooltipContent;
          if (ct && ct.el) ct.el.silent = true;
          return r;
        };
      }
      chart._onframe();
      c.steps.forEach((s, i) => {
        settle(NOW + 500);
        const st = { i, t: s[0], x: null, y: null };
        LOG = [];
        if (s[0] === 'move') {
          const at = resolveAt(chart, s[1], where + ' step ' + i);
          st.x = at[0];
          st.y = at[1];
          zr.handler.mousemove(raw(at[0], at[1]));
        }
        else if (s[0] === 'leave') {
          zr.handler.mouseout(raw(-1, -1));
        }
        else if (s[0] === 'action') {
          st.payload = s[1];
          quiet(() => chart.dispatchAction(JSON.parse(JSON.stringify(s[1]))));
        }
        else if (s[0] === 'merge') {
          st.option = s[1];
          quiet(() => chart.setOption(JSON.parse(JSON.stringify(s[1]))));
        }
        chart._onframe();
        zr.storage.getDisplayList(true);
        settle(NOW + 500);
        chart._onframe();
        zr.storage.getDisplayList(true);
        st.events = LOG;
        LOG = null;
        st.hover = st.x == null ? null : hoverRec(chart, st.x, st.y);
        const vis = visible();
        st.tooltip = { shown: vis, rows: vis ? tooltipRows(content()) : null,
          text: vis ? String(content().el.style.text).replace(SEGMENT, '$2') : null };
        st.states = statesRec(chart);
        if (s[0] === 'action' || s[0] === 'merge') {
          checkPoints(chart, where + ' step ' + i);
          checkOpacity(chart, where + ' step ' + i);
          st.record = record(chart);
        }
        steps.push(st);
      });
    }
    const convert = c.probes ? runConvert(chart, c) : null;
    return { id: c.id, group: c.group, note: c.note, W: c.w, H: c.h, option: opt, record: rec, frames, steps, convert };
  }
  finally {
    chart.dispose();
  }
}

// =====================================================================
// guards
// =====================================================================
function guards(cases) {
  const g = [];
  const get = id => { const c = cases.find(k => k.id === id); must(c, 'no case ' + id); return c; };
  const num = h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); };
  const G = (name, cond) => { must(cond, 'guard: ' + name); g.push(name); };
  const p0 = id => get(id).record.parallels[0];
  const ax = (id, k, p) => get(id).record.parallels[p || 0].axes[k];
  const item = (id, s, k) => get(id).record.series[s].items[k];
  G('the default box is 80 / 60 / 80 / 60', p0('h-basic').rect.map(num).join() === '80,60,440,280');
  G('a horizontal axis is turned a quarter, a vertical one not at all', num(ax('h-basic', 0).rotation) === Math.PI / 2 && num(ax('v-basic', 0).rotation) === 0);
  G('the horizontal transform carries cos(pi/2) into x', num(ax('h-basic', 1).transform[0]) !== 0);
  G('the labels sit on the +1 side: left-aligned beside a horizontal layout\'s axis', ax('h-basic', 0).view.labels.every(l => l.align === 'left'));
  G('a parallelAxis with data and no type is a value axis', ax('quirk-data-value', 1).type === 'value');
  G('a category axis collects its categories from the data', ax('types', 2).type === 'category' && num(ax('types', 2).scale[1]) === 2);
  G('a backwards min and max inverts the axis after its extent was set', ax('swapped', 1).inverse && num(ax('swapped', 1).extent[0]) === 0
    && !ax('swapped', 2).inverse && num(ax('swapped', 2).extent[0]) > 0);
  G('the category interval thins forty labels on both layouts', ax('many-categories', 0).view.labels.length < 40
    && get('many-categories').record.parallels[1].axes[0].view.labels.length < 40
    && ax('many-categories', 0).view.labels.length !== get('many-categories').record.parallels[1].axes[0].view.labels.length);
  G('inverse swaps the extent', num(ax('inverse', 1).extent[0]) > num(ax('inverse', 1).extent[1]) && ax('inverse', 1).inverse);
  G('the end name of an inverse axis is at the other end', num(ax('inverse', 1).view.name.y) !== num(ax('inverse', 0).view.name.y));
  G('a name longer than the space between axes is cut', (() => { const n = ax('names', 4).view.name; return n.text !== n.full && n.text.length < n.full.length; })());
  G("nameTruncate's own maxWidth cuts with its ellipsis", ax('names', 5).view.name.text.endsWith('..'));
  G('axisLabel.show false is overruled by the coordinate system', ax('labels', 4).view.labels.length > 0 && ax('labels', 4).labelShow);
  G('a hidden axis draws nothing', ax('furniture', 3).view.shown === false);
  G('the preprocessor creates a parallel', get('no-parallel').record.parallels.length === 1);
  G('parallelAxisDefault reaches every axis, the axis wins', ax('axis-default', 0).view.name.va !== ax('axis-default', 1).view.name.va);
  G('the axes follow component order', p0('dim-order').dims.join() === 'dim3,dim0,dim2');
  G("an expandable layout hides a collapsed axis' labels and cuts its name", !ax('expand', 0).labelShow && ax('expand', 0).view.labels.length === 0
    && ax('expand', 3).labelShow && ax('expand', 0).view.name.text !== ax('expand', 0).view.name.full);
  G('smooth true is 0.3', num(get('smooth').record.series[0].smooth) === 0.3);
  G('a numeric string smooths', num(get('smooth').record.series[2].smooth) === 0.15);
  G('smooth false and 0 draw straight', num(get('smooth').record.series[3].smooth) === 0 && num(get('smooth').record.series[4].smooth) === 0);
  G('an empty value drops its point', item('smooth', 4, 0).points.length === 6 && item('smooth', 4, 1).points.length === 8);
  G('a null category drops its point, an unknown one not', item('empty-values', 0, 2).points.length === 4 && item('empty-values', 0, 3).points.length === 6);
  G('the default opacity is 0.45', num(item('h-basic', 0, 0).opacity) === 0.45);
  G('the polyline sits at z2 10', item('h-basic', 0, 0).z2 === 10);
  G("an item's lineStyle opacity wins while nothing is selected", num(item('styles', 0, 1).opacity) === 0.9);
  G('the visualMap colours the stroke', JSON.stringify(item('visualmap', 0, 0).stroke) !== JSON.stringify(item('visualmap', 0, 4).stroke));
  G("the visualMap's opacity is overwritten", get('visualmap').record.series[0].items.every(i => num(i.opacity) === 0.45));
  G('outOfRange greys a row', JSON.stringify(item('visualmap-pieces', 0, 2).stroke) === '[153,153,153,1]');
  G('the legend toggle rescales an axis', num(get('legend').steps[0].record.parallels[0].axes[0].scale[1]) < num(get('legend').record.parallels[0].axes[0].scale[1]));
  G('a hover lifts the stroke and z2', (() => { const s = get('hover').steps[0].states.find(r => r.dataIndex === 0); return s.states.indexOf('emphasis') >= 0 && s.z2 === 20; })());
  G('the item tooltip names the row by its first category and shows the last numeric coordinate', (() => { const t = get('hover').steps[0].tooltip;
    return t.shown && t.rows.length === 2 && t.rows[0].name === 'goods' && t.rows[1].name === 'Good' && t.rows[1].value === '82'; })());
  G('focus series blurs the other series', get('hover-focus').steps[0].states.filter(r => r.seriesIndex === 1).every(r => r.states.indexOf('blur') >= 0));
  G('axisAreaSelect fires axisareaselected then brushselected', (() => { const e = get('area-select').steps[0].events.map(x => x.type); return e[0] === 'axisareaselected' && e.indexOf('brushselected') > 0; })());
  G('active rows are opaque, inactive ones 0.05', (() => { const its = get('area-select').steps[0].record.series[0].items; return num(its[1].opacity) === 1 && num(its[0].opacity) === 0.05; })());
  G("an item's own opacity loses to an active state", num(get('area-select').steps[0].record.series[0].items[2].opacity) === 1);
  G('a reversed interval is sorted', get('area-select').steps[2].record.parallels[0].axes[1].intervals[0].map(num).join() === '5,45');
  G('a null value is inactive', get('area-select').steps[2].record.series[0].items[4].active === 'inactive');
  G('an empty list clears', get('area-select').steps[4].record.series[0].items.every(i => i.active === 'normal'));
  G('the selection survives a merge', get('area-select-opacity').steps[1].record.series[0].items[3].active === 'active');
  G('the selection survives a legend toggle', get('area-select-legend').steps[1].record.parallels[0].axes[0].intervals.length === 1);
  G('the enter clip starts at 0 width', num(get('enter-h').frames[0].clips[0].clip[2]) === 0);
  G('the enter clip is removed after its end', get('enter-h').frames[get('enter-h').frames.length - 1].clips[0].clip === null);
  G('a vertical clip grows in height', num(get('enter-v').frames[0].clips[0].clip[3]) === 0 && num(get('enter-v').frames[0].clips[0].clip[2]) > 0);
  G('the parallel coordinate system converts nothing', get('convert').convert.filter(p => p.op !== 'contain').every(p => p.out.k === 'none'));
  G('containPixel answers on an axis finder', get('convert').convert.some(p => p.op === 'contain' && p.finder.text === '{"parallelAxisIndex":1}' && p.out.v === true));
  G('containPixel answers on a series finder', get('convert').convert.some(p => p.op === 'contain' && p.finder.text === '{"seriesIndex":0}' && p.out.v === true));
  return g;
}

function generate() {
  const cases = CASES.map(recordCase);
  if (process.env.C19_DUMP) fs.writeFileSync(process.env.C19_DUMP, JSON.stringify(cases, null, 1));
  const gs = guards(cases);
  for (const k of Object.keys(RECIPES)) must(RECIPES[k] > 0, 'recipe ' + k + ' never ran');
  const out = {
    source: 'ECharts ' + echarts.version + ' dist (' + path.basename(DIST) + ') under node, svg painter, ssr init then _ssr = false, env.node = false, TZ=UTC',
    W, H, T0, seed: SEED,
    notes: [
      'The clock is reset to T0 per case; setOption steps every clip once at T0 (frame 0); a later frame is T0 + t, one zr.animation.update(), the timers due, getDisplayList(true).',
      'hover is handler.findHover after the event.',
      'name.text is the name as drawn (the tspans after the truncation); name.full the text the element holds.',
      'convert: the parallel coordinate system has no convertToPixel / convertFromPixel; containPixel asks its containPoint.',
    ],
    cases, guards: gs, recipes: Object.assign({}, RECIPES),
  };
  for (const k of Object.keys(RECIPES)) RECIPES[k] = 0;
  return JSON.stringify(out);
}

try {
  const a = generate();
  const b = generate();
  must(a === b, 'two generations differ');
  must(!a.includes('\\u0000'), 'a NUL in the output');
  JSON.parse(a);
  fs.writeFileSync(OUT, a);
  console.log('wrote ' + OUT + ' (' + CASES.length + ' cases, ' + a.length + ' bytes)');
  process.exit(0);
}
catch (e) {
  console.error(e && e.stack || e);
  process.exit(1);
}
