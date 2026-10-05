/*
Upstream's own answers for roadmap C3, batch 111: the polar coordinate
system -- polar.center / polar.radius, the angle and radius axes of every
type, their extents (startAngle, endAngle, clockwise, inverse, the category
angle axis' fixed extent) and their scales -- every element the two axis
views draw, the polar axis pointer (line and shadow, with its label), and
convertToPixel / convertFromPixel / containPixel on a polar.

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node's server-side mode, SVG renderer, `animation: false`,
measuring every string with zrender's width table (the TZrSsrMeasurer of the
Pascal tests), TZ=UTC. Every case is 600 x 400 unless it says otherwise.

  node tools/advchart-oracle/polar-axes.js

writes tests/fixtures/advchart-polar-axes.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Numbers that are positions are the 16 hex digits of the IEEE double
(big-endian, lowercase). Counts, flags, strings and option values are plain
JSON.

THE MERGED PATHS. Both views batch their ticks, split lines and split areas
into one path per colour (graphic.mergePath), which keeps no shapes. The
oracle hooks Path.getUpdatedPathProxy (called on each piece as it is merged)
and Path.createPathProxy (called on the bundle) while a view renders, and
reads each piece's shape back out; which bundle is which follows the view's
builder order, and the counts are checked against the axis' own ticks.

Top level: source, version, notes[], cases[], guards[].

A case: id, group ('axes' | 'pointer' | 'convert'), note, W, H, option (as
  run), polars[], pointer[] (pointer cases), convert[] (convert cases), fails[]
  (recipe mismatches; must be empty).

polars[i]: index, cx, cy, rExtent [2], aExtent [2] (axis.getExtent()),
  rInverse, aInverse (axis.inverse after the scales), rType, aType,
  rScale [2], aScale [2] (scale.getExtent()), rBlank, aBlank,
  radius: the radius axis view --
    shown (the model's show),
    line null | {x1, y1, x2, y2} (AxisBuilder's line, sub-pixel optimised),
    arrows[] {end, type, x, y, rotation, w, h},
    ticks[] {tick (string, as the anid has it), x1, y1, x2, y2, ignore},
    minorTicks[] {x1, y1, x2, y2},
    labels[] {tick (string), text, x, y, rotation, align, va, ignore},
    name null | {text, x, y, rotation, align, va},
    splitLines[] {ci, kind ('circle' | 'arc'), cx, cy, r, sa, ea, cw},
    minorSplitLines[] {cx, cy, r},
    splitAreas[] {ci, cx, cy, r0, r, sa, ea, cw}
  angle: the angle axis view --
    shown,
    line null | {kind ('circle' | 'arc' | 'ring'), cx, cy, r, r0, sa, ea, cw},
    ticks[] {x1, y1, x2, y2}, minorTicks[] {x1, y1, x2, y2},
    labels[] {tick, text, x, y, align, va},
    splitLines[] {ci, x1, y1, x2, y2}, minorSplitLines[] {x1, y1, x2, y2},
    splitAreas[] {ci, cx, cy, r0, r, sa, ea, cw}
  (sa / ea / cw: startAngle, endAngle in radians, clockwise; ci: the index in
  the colour list -- the bundle the piece was merged into.)

pointer[]: per probe {x, y, axes[] {dim ('angle' | 'radius'), polar, value
  (hex, the axisPointer model's), el null | {type ('line' | 'circle' |
  'sector'), shape}, label null | {text, x, y, w, h}}} -- an axis appears when
  its pointer is shown; label x / y is the Text element's (after the align
  and the confinement), w / h its padded box.

convert[]: {op ('to' | 'from' | 'contain'), finder {in, text}, value {in, text,
  textSafe}, out, by?} as in advchart-convert-jitter.json: an input number is
  {"h": hex}; out {k: 'none' | 'num' | 'arr' | 'bool' | 'throw', v};
  by: the coordinate system that answered.

Guards (any failure: nothing is written, exit 1): every recipe (each record
transcribed again from upstream's code -- the centre and radius from the
option through parsePercent, the angle labels' place and alignment, the
axis line's kind, the tick and split line shapes from the ticks, the split
area sectors, the radius circles and arcs, the pointer shapes and the label
place) agrees with what was drawn; named facts; and the whole fixture is
generated twice, byte-identical. process.exit() ends the run.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-polar-axes.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  // one NaN: V8 does not keep a NaN's sign from one compiled run to the next
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const same = (a, b) => Object.is(a, b);
const RADIAN = Math.PI / 180;

// ---------------------------------------------------------------------------
// the merged-path capture
// ---------------------------------------------------------------------------
let CAP = null;
let IN_GUPP = 0;
{
  // zrender's Path: the prototype every shape class extends
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
// the bundles each axis view merged, by the view instance
const BUNDLES = new Map();
{
  const warm = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 200, height: 200 });
  warm.setOption({ animation: false, polar: {}, angleAxis: {}, radiusAxis: {} });
  warm.renderToSVGString();
  const views = warm._componentsViews.filter(v => v && v.__model
    && (v.__model.mainType === 'angleAxis' || v.__model.mainType === 'radiusAxis'));
  must(views.length === 2, 'the warm-up chart has no polar axis views');
  views.forEach(v => {
    let proto = Object.getPrototypeOf(v);
    while (proto && !Object.prototype.hasOwnProperty.call(proto, 'render')) proto = Object.getPrototypeOf(proto);
    must(proto, 'no render on the view prototype chain');
    if (proto.__c3Hooked) return;
    const render = proto.render;
    proto.render = function () {
      const prev = CAP;
      CAP = [];
      try {
        return render.apply(this, arguments);
      } finally {
        // pieces before the bundle that merges them
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
    proto.__c3Hooked = true;
  });
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
// numberUtil.parsePercent
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
function centreRecipe(polarModel, W, H) {
  const c = polarModel.get('center');
  const cx = parsePercent(c[0], W) + 0;
  const cy = parsePercent(c[1], H) + 0;
  const size = Math.min(W, H) / 2;
  let radius = polarModel.get('radius');
  if (radius == null) radius = [0, '100%'];
  else if (!Array.isArray(radius)) radius = [0, radius];
  return { cx, cy, r: [parsePercent(radius[0], size), parsePercent(radius[1], size)] };
}
function coordToPoint(polar, r, a) {
  const rad = a / 180 * Math.PI;
  return [Math.cos(rad) * r + polar.cx, -Math.sin(rad) * r + polar.cy];
}
function axisLineShape(polar, rExtent, angle) {
  rExtent[1] > rExtent[0] && (rExtent = rExtent.slice().reverse());
  const s = coordToPoint(polar, rExtent[0], angle);
  const e = coordToPoint(polar, rExtent[1], angle);
  return { x1: s[0], y1: s[1], x2: e[0], y2: e[1] };
}
function fixAngleOverlap(list) {
  const f = list[0];
  const l = list[list.length - 1];
  if (f && l && Math.abs(Math.abs(f.coord - l.coord) - 360) < 1e-4) list.pop();
}
const sameShape = (a, b, keys) => keys.every(k => same(a[k], b[k]));

// ---------------------------------------------------------------------------
// reading one polar
// ---------------------------------------------------------------------------
function readPolar(chart, c, polarModel, fails) {
  const polar = polarModel.coordinateSystem;
  const ra = polar.getRadiusAxis();
  const aa = polar.getAngleAxis();
  const W = c.W;
  const H = c.H;
  const key = 'polar' + polarModel.componentIndex;
  const want = centreRecipe(polarModel, W, H);
  if (!same(want.cx, polar.cx) || !same(want.cy, polar.cy)) fails.push(key + ': centre ' + [polar.cx, polar.cy] + ', the recipe gives ' + [want.cx, want.cy]);
  const re = ra.getExtent();
  const wr = ra.inverse !== !!ra.model.get('inverse') ? null : (ra.model.get('inverse') ? [want.r[1], want.r[0]] : want.r);
  if (wr && !(same(re[0], wr[0]) && same(re[1], wr[1]))) fails.push(key + ': radius extent ' + re + ', the recipe gives ' + wr);
  const rec = {
    index: polarModel.componentIndex, cx: hex(polar.cx), cy: hex(polar.cy),
    cxText: String(polar.cx), cyText: String(polar.cy),
    rExtent: re.map(hex), aExtent: aa.getExtent().map(hex),
    rInverse: !!ra.inverse, aInverse: !!aa.inverse, rType: ra.type, aType: aa.type,
    rScale: ra.scale.getExtent().map(hex), aScale: aa.scale.getExtent().map(hex),
    rBlank: ra.scale.isBlank(), aBlank: aa.scale.isBlank(),
    radius: readRadius(chart, polar, ra, fails, key),
    angle: readAngle(chart, polar, aa, fails, key),
  };
  return rec;
}

function readRadius(chart, polar, axis, fails, key) {
  const m = axis.model;
  const out = { shown: !!m.get('show'), line: null, arrows: [], ticks: [], minorTicks: [], labels: [], name: null,
    splitLines: [], minorSplitLines: [], splitAreas: [] };
  if (!out.shown) return out;
  const view = chart.getViewOfComponentModel(m);
  must(view && view._axisGroup, key + ': no radius axis group');
  const bg = view._axisGroup;
  walk(bg, e => {
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
  });
  // the view's own: splitLine, splitArea, minorSplitLine, in that order
  const bundles = BUNDLES.get(view) || [];
  const blank = axis.scale.isBlank();
  const ticks = axis.getTicksCoords();
  const minor = axis.getMinorTicksCoords();
  const aa = polar.getAngleAxis();
  const ae = aa.getExtent();
  let b = 0;
  const take = (n, what) => {
    must(b + n <= bundles.length, key + ': ' + what + ' wants bundle ' + (b + n - 1) + ' of ' + bundles.length);
    const r = bundles.slice(b, b + n);
    b += n;
    return r;
  };
  const colours = list => (Array.isArray(list) ? list : [list]);
  if (m.get(['splitLine', 'show']) && !blank) {
    const cols = colours(m.get(['splitLine', 'lineStyle', 'color']));
    const n = Math.min(ticks.length, cols.length);
    const bs = take(n, 'splitLine');
    const kind = Math.abs(ae[1] - ae[0]) === 360 ? 'circle' : 'arc';
    const total = bs.reduce((s, q) => s + q.pieces.length, 0);
    must(total === ticks.length, key + ': ' + total + ' split lines for ' + ticks.length + ' ticks');
    for (let i = 0; i < ticks.length; i++) {
      const ci = i % cols.length;
      const p = bs[ci].pieces[Math.floor(i / cols.length)];
      must(p.t === kind, key + ': a ' + p.t + ' split line, the recipe gives ' + kind);
      const s = p.s;
      const w = { cx: polar.cx, cy: polar.cy, r: Math.max(ticks[i].coord, 0), startAngle: -ae[0] * RADIAN, endAngle: -ae[1] * RADIAN, clockwise: aa.inverse };
      if (!sameShape(s, w, kind === 'arc' ? ['cx', 'cy', 'r', 'startAngle', 'endAngle', 'clockwise'] : ['cx', 'cy', 'r'])) {
        fails.push(key + ': split line ' + i + ' ' + JSON.stringify(s) + ', the recipe gives ' + JSON.stringify(w));
      }
      out.splitLines.push({ ci, kind, cx: hex(s.cx), cy: hex(s.cy), r: hex(s.r),
        sa: kind === 'arc' ? hex(s.startAngle) : null, ea: kind === 'arc' ? hex(s.endAngle) : null,
        cw: kind === 'arc' ? !!s.clockwise : null });
    }
  }
  if (m.get(['splitArea', 'show']) && !blank && ticks.length) {
    const cols = colours(m.get(['splitArea', 'areaStyle', 'color']));
    const count = ticks.length - 1;
    const n = Math.min(count, cols.length);
    const bs = take(n, 'splitArea');
    for (let i = 0; i < count; i++) {
      const ci = i % cols.length;
      const p = bs[ci].pieces[Math.floor(i / cols.length)];
      must(p && p.t === 'sector', key + ': split area ' + i + ' is no sector');
      const s = p.s;
      const w = { cx: polar.cx, cy: polar.cy, r0: ticks[i].coord, r: ticks[i + 1].coord, startAngle: 0, endAngle: Math.PI * 2 };
      if (!sameShape(s, w, ['cx', 'cy', 'r0', 'r', 'startAngle', 'endAngle'])) {
        fails.push(key + ': split area ' + i + ' ' + JSON.stringify(s) + ', the recipe gives ' + JSON.stringify(w));
      }
      out.splitAreas.push({ ci, cx: hex(s.cx), cy: hex(s.cy), r0: hex(s.r0), r: hex(s.r), sa: hex(s.startAngle),
        ea: hex(s.endAngle), cw: !!s.clockwise });
    }
  }
  if (m.get(['minorSplitLine', 'show']) && !blank && minor.length) {
    const bs = take(1, 'minorSplitLine');
    const flat = [];
    minor.forEach(g => g.forEach(t => flat.push(t)));
    must(bs[0].pieces.length === flat.length, key + ': minor split line count');
    bs[0].pieces.forEach((p, i) => {
      must(p.t === 'circle', key + ': a minor split line is no circle');
      if (!same(p.s.r, flat[i].coord) || !same(p.s.cx, polar.cx) || !same(p.s.cy, polar.cy)) fails.push(key + ': minor split line ' + i);
      out.minorSplitLines.push({ cx: hex(p.s.cx), cy: hex(p.s.cy), r: hex(p.s.r) });
    });
  }
  must(b === bundles.length, key + ': ' + (bundles.length - b) + ' radius bundles unread');
  return out;
}

function readAngle(chart, polar, axis, fails, key) {
  const m = axis.model;
  const out = { shown: !!m.get('show'), line: null, ticks: [], minorTicks: [], labels: [], splitLines: [],
    minorSplitLines: [], splitAreas: [] };
  if (!out.shown) return out;
  const view = chart.getViewOfComponentModel(m);
  must(view, key + ': no angle axis view');
  const ra = polar.getRadiusAxis();
  const radiusExtent = ra.getExtent();
  const ae = axis.getExtent();
  const blank = axis.scale.isBlank();
  const rId = ra.inverse ? 0 : 1;
  const r0Id = rId ? 0 : 1;
  const shows = name => m.get([name, 'show']) && (!blank || name === 'axisLine');
  // the recipe's ticks and labels
  const ticks = axis.getTicksCoords({ breakTicks: 'none' });
  const minor = axis.getMinorTicksCoords();
  const labels = [];
  axis.getViewLabels().forEach(l => {
    if (l.tick.offInterval) return;
    labels.push({ l, coord: axis.dataToCoord(l.tick.value) });
  });
  fixAngleOverlap(labels);
  fixAngleOverlap(ticks);
  // the elements: the line and the texts are the group's own children; the
  // rest are bundles
  const kids = view.group.childrenRef().slice();
  const texts = kids.filter(e => e.type === 'text');
  const bundles = BUNDLES.get(view) || [];
  if (shows('axisLine')) {
    const e = kids.find(x => x.type === 'circle' || x.type === 'arc' || x.type === 'ring');
    must(e, key + ': no angle axis line');
    const s = e.shape;
    const kind = e.type;
    let wantKind;
    if (radiusExtent[r0Id] === 0) wantKind = Math.abs(ae[1] - ae[0]) === 360 ? 'circle' : 'arc';
    else wantKind = 'ring';
    if (kind !== wantKind) fails.push(key + ': angle line ' + kind + ', the recipe gives ' + wantKind);
    const wr = radiusExtent[rId];
    if (!same(s.cx, polar.cx) || !same(s.cy, polar.cy) || !same(s.r, wr)) fails.push(key + ': angle line shape');
    if (kind === 'ring' && !same(s.r0, radiusExtent[r0Id])) fails.push(key + ': ring r0');
    if (kind !== 'ring' && (!same(s.startAngle, -ae[0] * RADIAN) || !same(s.endAngle, -ae[1] * RADIAN) || s.clockwise !== axis.inverse)) {
      fails.push(key + ': angle line angles');
    }
    out.line = { kind, cx: hex(s.cx), cy: hex(s.cy), r: hex(s.r), r0: kind === 'ring' ? hex(s.r0) : null,
      sa: kind === 'ring' ? null : hex(s.startAngle), ea: kind === 'ring' ? null : hex(s.endAngle),
      cw: kind === 'ring' ? null : !!s.clockwise };
  }
  if (shows('axisLabel')) {
    must(texts.length === labels.length, key + ': ' + texts.length + ' angle labels, the recipe gives ' + labels.length);
    const margin = m.get(['axisLabel', 'margin']);
    texts.forEach((t, i) => {
      const r = radiusExtent[rId];
      const p = coordToPoint(polar, r + margin, labels[i].coord);
      const align = Math.abs(p[0] - polar.cx) / r < 0.3 ? 'center' : (p[0] > polar.cx ? 'left' : 'right');
      const va = Math.abs(p[1] - polar.cy) / r < 0.3 ? 'middle' : (p[1] > polar.cy ? 'top' : 'bottom');
      const st = t.style;
      if (!same(st.x, p[0]) || !same(st.y, p[1]) || st.align !== align || st.verticalAlign !== va
        || st.text !== labels[i].l.formattedLabel) {
        fails.push(key + ': angle label ' + i + ' ' + JSON.stringify([st.x, st.y, st.align, st.verticalAlign, st.text])
          + ', the recipe gives ' + JSON.stringify([p[0], p[1], align, va, labels[i].l.formattedLabel]));
      }
      out.labels.push({ tick: String(labels[i].l.tick.value), text: st.text, x: hex(st.x), y: hex(st.y), align: st.align, va: st.verticalAlign });
    });
  } else must(texts.length === 0, key + ': angle labels drawn while hidden');
  let b = 0;
  const take = (n, what) => {
    must(b + n <= bundles.length, key + ': ' + what + ' wants bundle ' + (b + n - 1) + ' of ' + bundles.length);
    const r = bundles.slice(b, b + n);
    b += n;
    return r;
  };
  const colours = list => (Array.isArray(list) ? list : [list]);
  const lineAt = (rExt, a) => axisLineShape(polar, rExt, a);
  const checkLines = (pieces, wants, what) => {
    must(pieces.length === wants.length, key + ': ' + pieces.length + ' ' + what + ', the recipe gives ' + wants.length);
    return pieces.map((p, i) => {
      must(p.t === 'line', key + ': a ' + what + ' is a ' + p.t);
      if (!sameShape(p.s, wants[i], ['x1', 'y1', 'x2', 'y2'])) fails.push(key + ': ' + what + ' ' + i + ' ' + JSON.stringify(p.s) + ', the recipe gives ' + JSON.stringify(wants[i]));
      return lineRec(p.s);
    });
  };
  const flatMinor = [];
  minor.forEach(g => g.forEach(t => flatMinor.push(t)));
  if (shows('axisTick')) {
    const bs = take(1, 'axisTick');
    const len = (m.get(['axisTick', 'inside']) ? -1 : 1) * m.get(['axisTick', 'length']);
    const r = radiusExtent[rId];
    out.ticks = checkLines(bs[0].pieces, ticks.map(t => lineAt([r, r + len], t.coord)), 'tick');
  }
  if (shows('minorTick') && minor.length) {
    const bs = take(1, 'minorTick');
    const len = (m.get(['axisTick', 'inside']) ? -1 : 1) * m.get(['minorTick', 'length']);
    const r = radiusExtent[rId];
    out.minorTicks = checkLines(bs[0].pieces, flatMinor.map(t => lineAt([r, r + len], t.coord)), 'minor tick');
  }
  if (shows('splitLine')) {
    const cols = colours(m.get(['splitLine', 'lineStyle', 'color']));
    const n = Math.min(ticks.length, cols.length);
    const bs = take(n, 'splitLine');
    for (let i = 0; i < ticks.length; i++) {
      const ci = i % cols.length;
      const p = bs[ci].pieces[Math.floor(i / cols.length)];
      const rec = checkLines([p], [lineAt(radiusExtent, ticks[i].coord)], 'split line')[0];
      out.splitLines.push(Object.assign({ ci }, rec));
    }
    must(bs.reduce((s, q) => s + q.pieces.length, 0) === ticks.length, key + ': split line count');
  }
  if (shows('minorSplitLine') && minor.length) {
    const bs = take(1, 'minorSplitLine');
    out.minorSplitLines = checkLines(bs[0].pieces, flatMinor.map(t => lineAt(radiusExtent, t.coord)), 'minor split line');
  }
  if (shows('splitArea') && ticks.length) {
    const cols = colours(m.get(['splitArea', 'areaStyle', 'color']));
    const len = ticks.length;
    const n = Math.min(len, cols.length);
    const bs = take(n, 'splitArea');
    const r0 = Math.min(radiusExtent[0], radiusExtent[1]);
    const r1 = Math.max(radiusExtent[0], radiusExtent[1]);
    const cw = m.get('clockwise');
    let prev = -ticks[0].coord * RADIAN;
    for (let i = 1; i <= len; i++) {
      const coord = i === len ? ticks[0].coord : ticks[i].coord;
      const ci = (i - 1) % cols.length;
      const p = bs[ci].pieces[Math.floor((i - 1) / cols.length)];
      must(p && p.t === 'sector', key + ': split area ' + i + ' is no sector');
      const w = { cx: polar.cx, cy: polar.cy, r0, r: r1, startAngle: prev, endAngle: -coord * RADIAN, clockwise: cw };
      if (!sameShape(p.s, w, ['cx', 'cy', 'r0', 'r', 'startAngle', 'endAngle', 'clockwise'])) {
        fails.push(key + ': angle split area ' + i + ' ' + JSON.stringify(p.s) + ', the recipe gives ' + JSON.stringify(w));
      }
      out.splitAreas.push({ ci, cx: hex(p.s.cx), cy: hex(p.s.cy), r0: hex(p.s.r0), r: hex(p.s.r), sa: hex(p.s.startAngle),
        ea: hex(p.s.endAngle), cw: !!p.s.clockwise });
      prev = -coord * RADIAN;
    }
  }
  must(b === bundles.length, key + ': ' + (bundles.length - b) + ' angle bundles unread');
  return out;
}

// ---------------------------------------------------------------------------
// the pointer
// ---------------------------------------------------------------------------
function readPointer(chart, c, x, y, fails) {
  const ecModel = chart.getModel();
  const zr = chart.getZr();
  chart.dispatchAction({ type: 'updateAxisPointer', currTrigger: 'mousemove', x, y });
  zr.refreshImmediately();
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
      const value = apm.get('value');
      const rec = { dim: axis.dim, polar: pm.componentIndex, value: hex(value), el: null, label: null };
      const els = g.childrenRef();
      const ptype = apm.get('type');
      const coord = axis.dataToCoord(value);
      const thisExt = axis.getExtent();
      const otherExt = polar.getOtherAxis(axis).getExtent();
      els.forEach(e => {
        const t = String(e.type).toLowerCase();
        if (t === 'line') {
          rec.el = { type: 'line', shape: [e.shape.x1, e.shape.y1, e.shape.x2, e.shape.y2].map(hex) };
          const p1 = coordToPoint(polar, otherExt[0], coord);
          const p2 = coordToPoint(polar, otherExt[1], coord);
          if (!(axis.dim === 'angle' && same(e.shape.x1, p1[0]) && same(e.shape.y1, p1[1]) && same(e.shape.x2, p2[0]) && same(e.shape.y2, p2[1]))) {
            fails.push(c.id + ' ' + x + ',' + y + ': pointer line ' + JSON.stringify(e.shape));
          }
        } else if (t === 'circle') {
          rec.el = { type: 'circle', shape: [e.shape.cx, e.shape.cy, e.shape.r].map(hex) };
          if (!(axis.dim === 'radius' && same(e.shape.r, coord) && same(e.shape.cx, polar.cx) && same(e.shape.cy, polar.cy))) {
            fails.push(c.id + ' ' + x + ',' + y + ': pointer circle ' + JSON.stringify(e.shape));
          }
        } else if (t === 'sector') {
          const s = e.shape;
          rec.el = { type: 'sector', shape: [s.cx, s.cy, s.r0, s.r, s.startAngle, s.endAngle].map(hex), cw: !!s.clockwise };
          // calcAxisPointerShadowBandWidth: a category's band, else 1
          let bw = 1;
          if (axis.type === 'category') {
            const se = axis.scale.getExtent();
            let len = se[1] - se[0] + (axis.onBand ? 1 : 0);
            if (len === 0) len = 1;
            bw = Math.max(1, Math.abs(thisExt[1] - thisExt[0]) / len);
          }
          let w;
          if (axis.dim === 'angle') {
            w = [polar.cx, polar.cy, otherExt[0], otherExt[1], (-coord - bw / 2) * RADIAN, (-coord + bw / 2) * RADIAN];
          } else {
            const lo = Math.max(Math.min(thisExt[0], thisExt[1]), coord - bw / 2);
            const hi = Math.min(coord + bw / 2, Math.max(thisExt[0], thisExt[1]));
            w = [polar.cx, polar.cy, lo, hi, 0, Math.PI * 2];
          }
          const got = [s.cx, s.cy, s.r0, s.r, s.startAngle, s.endAngle];
          if (!w.every((v, i) => same(v, got[i])) || s.clockwise !== true) {
            fails.push(c.id + ' ' + x + ',' + y + ': pointer sector ' + JSON.stringify(got) + ', the recipe gives ' + JSON.stringify(w));
          }
        } else if (t === 'text') {
          if (e.ignore) return;
          const st = e.style;
          const b = e.getBoundingRect();
          rec.label = { text: st.text, x: hex(e.x), y: hex(e.y), w: hex(b.width), h: hex(b.height),
            xText: String(e.x), yText: String(e.y), wText: String(b.width), hText: String(b.height) };
          // the label's place: getLabelPosition, then the align and the
          // container
          const margin = apm.get(['label', 'margin']);
          let pos;
          let align;
          let va;
          const axisAngle = polar.getAngleAxis().getExtent()[0] * Math.PI / 180;
          if (axis.dim === 'radius') {
            const ct = Math.cos(axisAngle);
            const st2 = Math.sin(axisAngle);
            // matrix.rotate(identity, a) then translate(cx, cy)
            const mm = [ct, -st2, st2, ct, 0, 0];
            mm[4] += polar.cx;
            mm[5] += polar.cy;
            pos = [mm[0] * coord + mm[2] * -margin + mm[4], mm[1] * coord + mm[3] * -margin + mm[5]];
            const lr = (axis.model.getModel('axisLabel').get('rotate') || 0) * Math.PI / 180;
            const lay = echarts.innerTextLayoutForOracle(axisAngle, lr, -1);
            align = lay.textAlign;
            va = lay.textVerticalAlign;
          } else {
            const r = polar.getRadiusAxis().getExtent()[1];
            pos = coordToPoint(polar, r + margin, coord);
            align = Math.abs(pos[0] - polar.cx) / r < 0.3 ? 'center' : (pos[0] > polar.cx ? 'left' : 'right');
            va = Math.abs(pos[1] - polar.cy) / r < 0.3 ? 'middle' : (pos[1] > polar.cy ? 'top' : 'bottom');
          }
          const wd = b.width;
          const ht = b.height;
          align === 'right' && (pos[0] -= wd);
          align === 'center' && (pos[0] -= wd / 2);
          va === 'bottom' && (pos[1] -= ht);
          va === 'middle' && (pos[1] -= ht / 2);
          pos[0] = Math.min(pos[0] + wd, c.W) - wd;
          pos[1] = Math.min(pos[1] + ht, c.H) - ht;
          pos[0] = Math.max(pos[0], 0);
          pos[1] = Math.max(pos[1], 0);
          if (!same(pos[0], e.x) || !same(pos[1], e.y)) fails.push(c.id + ' ' + x + ',' + y + ': pointer label at ' + [e.x, e.y] + ', the recipe gives ' + pos);
        }
      });
      if ((ptype === 'line' || ptype === 'shadow') && !rec.el) fails.push(c.id + ': no pointer element for a ' + ptype);
      axes.push(rec);
    });
  });
  return { x, y, axes };
}
// AxisBuilder.innerTextLayout, transcribed for the recipe
echarts.innerTextLayoutForOracle = function (axisRotation, textRotation, direction) {
  const PI2 = Math.PI * 2;
  let d = textRotation - axisRotation;
  d = ((d % PI2) + PI2) % PI2;
  const around = v => v > -1e-4 && v < 1e-4;
  let textAlign;
  let textVerticalAlign;
  if (around(d)) { textVerticalAlign = direction > 0 ? 'top' : 'bottom'; textAlign = 'center'; }
  else if (around(d - Math.PI)) { textVerticalAlign = direction > 0 ? 'bottom' : 'top'; textAlign = 'center'; }
  else {
    textVerticalAlign = 'middle';
    if (d > 0 && d < Math.PI) textAlign = direction > 0 ? 'right' : 'left';
    else textAlign = direction > 0 ? 'left' : 'right';
  }
  return { textAlign, textVerticalAlign };
};

// ---------------------------------------------------------------------------
// the conversions
// ---------------------------------------------------------------------------
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
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};
// util/model.ts parseFinder with no options, transcribed for the bookkeeping
// (as the C2 oracle has it)
function PARSE_FINDER(ecModel, finderInput) {
  let finder = finderInput;
  if (typeof finderInput === 'string') { finder = {}; finder[finderInput + 'Index'] = 0; }
  const result = {};
  const qmap = new Map();
  if (finder && typeof finder === 'object') {
    Object.keys(finder).forEach(key => {
      const value = finder[key];
      if (key === 'dataIndex' || key === 'dataIndexInside') { result[key] = value; return; }
      const m = key.match(/^(\w+)(Index|Id|Name)$/) || [];
      if (!m[1] || !m[2]) return;
      if (!qmap.has(m[1])) qmap.set(m[1], {});
      qmap.get(m[1])[m[2].toLowerCase()] = value;
    });
  }
  qmap.forEach((q, mainType) => {
    let index = q.index;
    let id = q.id;
    let name = q.name;
    let models;
    if (index == null && id == null && name == null) models = [];
    else if (index === 'none' || index === false) models = [];
    else {
      if (index === 'all') index = id = name = null;
      models = ecModel.queryComponents({ mainType, index, id, name });
    }
    result[mainType + 'Models'] = models;
    result[mainType + 'Model'] = models[0];
  });
  return result;
}
function runConvert(chart, c, fails) {
  return c.probes(chart).map(([op, finder, value]) => {
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
    const rec = { op, finder: input(finder), value: input(value), out };
    if (op !== 'contain' && out.k !== 'none' && out.k !== 'throw') {
      const list = chart._coordSysMgr.getCoordinateSystems();
      const pf = chart.__c3Finder(finder);
      const method = op === 'to' ? 'convertToPixel' : 'convertFromPixel';
      for (const cs of list) {
        let r = null;
        try { r = cs[method] ? quiet(() => cs[method](chart.getModel(), pf, value)) : null; } catch (e) { r = null; }
        if (r != null) { rec.by = cs.type; break; }
      }
      must(rec.by, c.id + ': no coordinate system answered a probe that has an answer');
      // the recipe on a polar: dataToPoint / pointToData
      if (rec.by === 'polar' && Array.isArray(value) && value.every(v => typeof v === 'number')) {
        const pm = pf.polarModel;
        const polar = pm && pm.coordinateSystem;
        if (polar) {
          const got = Array.from(op === 'to' ? chart.convertToPixel(finder, value) : chart.convertFromPixel(finder, value));
          let want;
          if (op === 'to') {
            want = coordToPoint(polar, polar.getRadiusAxis().dataToCoord(value[0]), polar.getAngleAxis().dataToCoord(value[1]));
          } else {
            const pc = polar.pointToCoord(value);
            want = [polar.getRadiusAxis().coordToData(pc[0]), polar.getAngleAxis().coordToData(pc[1])];
          }
          if (!want.every((v, i) => same(v, got[i]))) fails.push(c.id + ': ' + op + ' ' + JSON.stringify(value) + ' ' + got + ', the recipe gives ' + want);
        }
      }
    }
    return rec;
  });
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
const add = (group, id, note, option, more) => CASES.push(Object.assign({ group, id, note, W: 600, H: 400, option }, more || {}));
const P = (angle, radius, extra) => Object.assign({ polar: {}, angleAxis: angle, radiusAxis: radius }, extra || {});
const cats = (n, p) => Array.from({ length: n }, (_, i) => (p || 'c') + i);
const C5 = ['a', 'b', 'c', 'd', 'e'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const R10 = { min: 0, max: 10 };
const A100 = { min: 0, max: 100 };

// ---- the angle axis
add('axes', 'cat-angle-basic', 'a category angle axis of five against a value radius 0..10', P({ type: 'category', data: C5 }, R10));
add('axes', 'cat-angle-months', 'twelve months, split lines and split areas shown', P({ type: 'category', data: MONTHS, splitLine: { show: true }, splitArea: { show: true } }, { min: 0, max: 100 }));
add('axes', 'cat-angle-nogap', 'boundaryGap false: the extent loses one band', P({ type: 'category', data: ['a', 'b', 'c', 'd'], boundaryGap: false, splitLine: { show: true }, splitArea: { show: true } }, R10));
add('axes', 'cat-angle-many', 'sixty categories: the angle axis measures its interval by line height', P({ type: 'category', data: cats(60) }, R10));
add('axes', 'cat-angle-interval', 'axisLabel.interval 3, axisTick.interval 1', P({ type: 'category', data: cats(24), axisLabel: { interval: 3 }, axisTick: { interval: 1 }, splitLine: { show: true } }, R10));
add('axes', 'cat-angle-align', 'alignWithLabel on the ticks', P({ type: 'category', data: cats(6), axisTick: { alignWithLabel: true }, splitLine: { show: true }, splitArea: { show: true } }, R10));
add('axes', 'cat-angle-anticlockwise', 'clockwise false from 0 degrees', P({ type: 'category', data: cats(6), clockwise: false, startAngle: 0, splitArea: { show: true }, splitLine: { show: true } }, R10));
add('axes', 'cat-angle-inverse', 'an inverse category angle axis', P({ type: 'category', data: cats(6), inverse: true, splitArea: { show: true } }, R10));
add('axes', 'cat-angle-inverse-anticlockwise', 'inverse and clockwise false: inverse !== clockwise is true', P({ type: 'category', data: cats(7), inverse: true, clockwise: false, startAngle: 45, splitLine: { show: true } }, R10));
add('axes', 'value-angle', 'a value angle axis 0..360, twelve splits', P({ type: 'value', min: 0, max: 360 }, { min: 0, max: 5 }));
add('axes', 'value-angle-blank', 'no data and no bounds: both axes blank, only the angle line', P({ type: 'value' }, { type: 'value' }));
add('axes', 'value-angle-half', 'endAngle 180 from 0: an arc', P({ type: 'value', min: 0, max: 100, startAngle: 0, endAngle: 180 }, R10));
add('axes', 'value-angle-half-ring', 'a half angle range over a ring radius: the line is a ring', P({ type: 'value', min: 0, max: 100, startAngle: 0, endAngle: 180 }, R10, { polar: { radius: [40, '80%'] } }));
add('axes', 'value-angle-start', 'startAngle 30, clockwise false, -50..50', P({ type: 'value', min: -50, max: 50, startAngle: 30, clockwise: false }, R10));
add('axes', 'value-angle-minor', 'minor ticks and minor split lines', P({ type: 'value', min: 0, max: 100, splitNumber: 5, minorTick: { show: true, splitNumber: 4 }, minorSplitLine: { show: true } }, R10));
add('axes', 'value-angle-margin', 'label margin 20, ticks inside and 10 long, minor ticks 4 long', P({ type: 'value', min: 0, max: 100, axisLabel: { margin: 20 }, axisTick: { inside: true, length: 10 }, minorTick: { show: true, length: 4 } }, R10));
add('axes', 'value-angle-swapped', 'min above max: the scale turns round, the axis inverts, the extent stays', P({ type: 'value', min: 5, max: 1 }, R10));
add('axes', 'value-angle-nice', 'a nice step on an unround range', P({ type: 'value', min: 3, max: 97, splitNumber: 7 }, R10));
add('axes', 'time-angle', 'a time angle axis over 2024 (UTC)', P({ type: 'time', min: Date.UTC(2024, 0, 1), max: Date.UTC(2024, 11, 31) }, { min: 0, max: 5 }, { useUTC: true }));
add('axes', 'time-angle-days', 'a time angle axis over ten days', P({ type: 'time', min: Date.UTC(2024, 2, 1), max: Date.UTC(2024, 2, 11), splitLine: { show: true } }, { min: 0, max: 5 }, { useUTC: true }));
add('axes', 'log-angle', 'a log angle axis 1..10000', P({ type: 'log', min: 1, max: 10000 }, R10));
// ---- the radius axis
add('axes', 'cat-radius', 'a category radius axis of five', P({ type: 'value', min: 0, max: 100 }, { type: 'category', data: C5 }));
add('axes', 'cat-radius-nogap', 'boundaryGap false, split lines and split areas', P(A100, { type: 'category', data: C5, boundaryGap: false, splitLine: { show: true }, splitArea: { show: true } }));
add('axes', 'cat-radius-many', 'thirty categories on the radius: the generic interval thins them', P(A100, { type: 'category', data: cats(30, 'item ') }));
add('axes', 'cat-radius-all', 'interval 0: every label, overlapping', P(A100, { type: 'category', data: cats(30, 'item '), axisLabel: { interval: 0 } }));
add('axes', 'cat-radius-align', 'ticks aligned with the labels', P(A100, { type: 'category', data: C5, axisTick: { alignWithLabel: true } }));
add('axes', 'value-radius-nice', 'min 3 max 97 in four', P(A100, { min: 3, max: 97, splitNumber: 4 }));
add('axes', 'value-radius-hide', 'twenty steps to a million, hideOverlap', P(A100, { min: 0, max: 1000000, splitNumber: 20, axisLabel: { hideOverlap: true } }));
add('axes', 'value-radius-crowd', 'twenty steps to a million, no hideOverlap: the max label gives way', P(A100, { min: 0, max: 1000000, splitNumber: 20 }));
add('axes', 'value-radius-minmax', 'showMinLabel false, showMaxLabel true', P(A100, { min: 0.5, max: 9.3, axisLabel: { showMinLabel: false, showMaxLabel: true } }));
add('axes', 'time-radius', 'a time radius axis', P(A100, { type: 'time', min: Date.UTC(2024, 0, 1), max: Date.UTC(2024, 0, 8) }, { useUTC: true }));
add('axes', 'time-radius-20d', 'a time radius over twenty days: its five splits are not the time axis\' six', P(A100, { type: 'time', min: Date.UTC(2024, 0, 1), max: Date.UTC(2024, 0, 21) }, { useUTC: true }));
add('axes', 'cat-radius-hide-min', 'showMinLabel false on a banded category radius: the tick on the band edge stays', P(A100, { type: 'category', data: C5, axisLabel: { showMinLabel: false } }));
add('axes', 'radius-subpixel-half', 'a radius line a tenth of a degree off level with its centre on a quarter pixel: Math.round decides the snap', P({ min: 0, max: 100, startAngle: 0.1 }, R10, { polar: { center: [300, 200.25] } }));
add('axes', 'radius-name-collide', 'an end name with no gap runs into the last label and is moved off it', P(A100, { min: 0, max: 10, name: 'Radius name', nameGap: 0 }));
add('axes', 'log-radius', 'a log radius axis 1..100000', P(A100, { type: 'log', min: 1, max: 100000, splitLine: { show: true } }));
add('axes', 'radius-inverse', 'an inverse radius with split areas and minor ticks', P(A100, { min: 0, max: 10, inverse: true, splitArea: { show: true }, minorTick: { show: true }, minorSplitLine: { show: true } }));
add('axes', 'radius-start-0', 'startAngle 0: the radius axis lies flat', P({ min: 0, max: 100, startAngle: 0 }, R10));
add('axes', 'radius-start-45', 'startAngle 45', P({ min: 0, max: 100, startAngle: 45 }, R10));
add('axes', 'radius-start-200', 'startAngle 200, labels turned 30', P({ min: 0, max: 100, startAngle: 200 }, { min: 0, max: 10, axisLabel: { rotate: 30 } }));
add('axes', 'radius-rotate-90', 'labels turned 90 on a vertical radius', P(A100, { min: 0, max: 10, axisLabel: { rotate: 90 } }));
add('axes', 'radius-rotate-neg', 'labels turned -45, startAngle 120', P({ min: 0, max: 100, startAngle: 120 }, { min: 0, max: 10, axisLabel: { rotate: -45 } }));
add('axes', 'radius-name-end', 'a name at the end, nameGap 20', P(A100, { min: 0, max: 10, name: 'Radius', nameGap: 20 }));
add('axes', 'radius-name-start', 'a name at the start turned 30', P({ min: 0, max: 100, startAngle: 30 }, { min: 0, max: 10, name: 'From here', nameLocation: 'start', nameRotate: 30 }));
add('axes', 'radius-name-middle', 'a middle name, moved off the labels', P(A100, { min: 0, max: 1000, name: 'A middle name', nameLocation: 'middle' }));
add('axes', 'radius-name-inverse', 'an end name on an inverse radius', P(A100, { min: 0, max: 10, inverse: true, name: 'Inv', nameGap: 10 }));
add('axes', 'radius-arrows', 'arrows on the radius line', P(A100, { min: 0, max: 10, axisLine: { symbol: ['none', 'arrow'], symbolSize: [8, 12] } }));
add('axes', 'radius-margin', 'radius label margin 14, tick length 8 inside (AxisBuilder ignores inside)', P(A100, { min: 0, max: 10, axisLabel: { margin: 14 }, axisTick: { length: 8, inside: true } }));
add('axes', 'split-colours', 'split lines and split areas in colour lists',
  P({ min: 0, max: 100, splitLine: { lineStyle: { color: ['#a00', '#0a0', '#00a'] } }, splitArea: { show: true, areaStyle: { color: ['#eee', '#ddd', '#ccc'] } } },
    { min: 0, max: 10, splitLine: { lineStyle: { color: ['#111', '#222'] } }, splitArea: { show: true, areaStyle: { color: ['#f0f', '#ff0', '#0ff'] } } }));
// ---- centre and radius
add('axes', 'radius-px', 'radius [20, 150] px, centre [250, 180] px', P(A100, R10, { polar: { radius: [20, 150], center: [250, 180] } }));
add('axes', 'radius-pct', "radius ['20%', '70%'], centre ['40%', '60%']", P(A100, R10, { polar: { radius: ['20%', '70%'], center: ['40%', '60%'] } }));
add('axes', 'radius-scalar', 'radius 120: the hole is nothing', P(A100, R10, { polar: { radius: 120 } }));
add('axes', 'radius-null', "radius null: [0, '100%']", P(A100, R10, { polar: { radius: null } }));
add('axes', 'radius-words', "centre ['left', 'bottom'], radius '50%'", P(A100, R10, { polar: { center: ['left', 'bottom'], radius: '50%' } }), { W: 500, H: 300 });
add('axes', 'radius-mixed', "radius ['10%', 130], centre [' 30% ', 210]", P(A100, R10, { polar: { center: [' 30% ', 210], radius: ['10%', 130] } }));
add('axes', 'multi-polar', 'two polars side by side, axes by polarIndex and polarId', {
  polar: [{ center: ['25%', '50%'], radius: '40%' }, { id: 'right', center: ['75%', '50%'], radius: ['10%', '40%'] }],
  angleAxis: [{ type: 'category', data: C5, polarIndex: 0 }, { min: 0, max: 360, polarId: 'right', startAngle: 0, splitArea: { show: true } }],
  radiusAxis: [{ min: 0, max: 10, polarIndex: 0 }, { type: 'category', data: ['x', 'y', 'z'], polarIndex: 1 }],
});
add('axes', 'hidden-parts', 'the radius hidden; the angle without line, ticks or labels but with split lines',
  P({ min: 0, max: 100, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { show: false } }, { min: 0, max: 10, show: false }));
add('axes', 'radius-parts-off', 'the radius line, ticks and labels off', P(A100, { min: 0, max: 10, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { show: false }, splitLine: { show: false } }));

// ---- the pointer
const tipAxis = (type, extra) => ({ tooltip: Object.assign({ trigger: 'axis', axisPointer: { type } }, extra || {}) });
const ring = (cx, cy, rs, n) => {
  const out = [];
  rs.forEach(r => { for (let k = 0; k < n; k++) { const a = k * 2 * Math.PI / n + 0.3; out.push([Math.round(cx + r * Math.cos(a)), Math.round(cy - r * Math.sin(a))]); } });
  return out;
};
const PROBES = ring(300, 200, [20, 75, 130, 159, 175], 7).concat([[300, 200], [301, 200], [300, 41], [459, 200], [10, 10]]);
add('pointer', 'ptr-angle-line', 'a category angle axis, line pointer', Object.assign(P({ type: 'category', data: cats(8) }, R10), tipAxis('line')), { probes: PROBES });
add('pointer', 'ptr-angle-shadow', 'a category angle axis, shadow pointer', Object.assign(P({ type: 'category', data: cats(8) }, R10), tipAxis('shadow')), { probes: PROBES });
add('pointer', 'ptr-cross', 'cross: both axes, labels shown', Object.assign(P({ type: 'category', data: cats(8) }, R10), tipAxis('cross')), { probes: PROBES });
add('pointer', 'ptr-radius-base', "axisPointer.axis 'radius' on a category radius, shadow", Object.assign(P(A100, { type: 'category', data: C5 }), tipAxis('shadow', { axisPointer: { type: 'shadow', axis: 'radius' } })), { probes: PROBES });
add('pointer', 'ptr-value-shadow', 'two value axes: the angle is the base, its shadow 1 degree', Object.assign(P({ min: 0, max: 360 }, R10), tipAxis('shadow')), { probes: PROBES });
add('pointer', 'ptr-value-cross', 'two value axes, cross, label formatter and precision', Object.assign(P({ min: 0, max: 360 }, { min: 0, max: 10 }),
  { tooltip: { trigger: 'axis', axisPointer: { type: 'cross', label: { formatter: '{value} u', precision: 1 } } } }), { probes: PROBES });
add('pointer', 'ptr-half', 'a half angle range: off the arc is no pointer', Object.assign(P({ min: 0, max: 100, startAngle: 0, endAngle: 180 }, R10), tipAxis('cross')), { probes: PROBES });
add('pointer', 'ptr-inverse', 'an inverse radius over a ring, cross', Object.assign(P({ type: 'category', data: cats(6) }, { min: 0, max: 10, inverse: true }, { polar: { radius: [40, '80%'] } }), tipAxis('cross')), { probes: PROBES });
add('pointer', 'ptr-own-label', "the angle axis' own pointer: shadow with its label shown", Object.assign(P({ type: 'category', data: cats(8), axisPointer: { type: 'shadow', label: { show: true } } }, R10), tipAxis('line')), { probes: PROBES });
add('pointer', 'ptr-start', 'startAngle 0: the radius label turns with the axis', Object.assign(P({ min: 0, max: 100, startAngle: 0 }, { min: 0, max: 10, axisLabel: { rotate: 30 } }), tipAxis('cross')), { probes: PROBES });
add('pointer', 'ptr-nogap', 'boundaryGap false: the last band takes no pointer', Object.assign(P({ type: 'category', data: cats(6), boundaryGap: false }, R10), tipAxis('shadow')), { probes: PROBES });
add('pointer', 'ptr-time-radius', 'a time radius against a value angle: the time axis is the base', Object.assign(P({ min: 0, max: 360 }, { type: 'time', min: Date.UTC(2024, 0, 1), max: Date.UTC(2024, 0, 11) }, { useUTC: true }), tipAxis('shadow')), { probes: PROBES });
add('pointer', 'ptr-radius-nogap', "a category radius without a gap, shadow: the first band is clamped to the centre", Object.assign(P(A100, { type: 'category', data: C5, boundaryGap: false }), tipAxis('shadow', { axisPointer: { type: 'shadow', axis: 'radius' } })), { probes: PROBES });
add('pointer', 'ptr-want-radius', "axis 'radius' where the base would be the angle", Object.assign(P({ type: 'category', data: C5 }, R10), tipAxis('shadow', { axisPointer: { type: 'shadow', axis: 'radius' } })), { probes: PROBES });
add('pointer', 'ptr-radius-auto', 'a category radius against a value angle: the radius is the base axis', Object.assign(P({ min: 0, max: 360 }, { type: 'category', data: C5 }), tipAxis('shadow')), { probes: PROBES });
add('pointer', 'ptr-edge', "radius '100%': a label past the top is pushed back into the chart", Object.assign(P({ type: 'category', data: cats(8) }, R10, { polar: { radius: '100%' } }), tipAxis('cross')),
  { probes: ring(300, 200, [120, 190, 199], 9).concat([[300, 2], [300, 10], [120, 200], [480, 200]]) });
add('pointer', 'ptr-multi', 'two polars: each takes its own points', Object.assign({
  polar: [{ center: ['25%', '50%'], radius: '40%' }, { center: ['75%', '50%'], radius: '40%' }],
  angleAxis: [{ type: 'category', data: C5, polarIndex: 0 }, { min: 0, max: 360, polarIndex: 1 }],
  radiusAxis: [{ min: 0, max: 10, polarIndex: 0 }, { min: 0, max: 5, polarIndex: 1 }],
}, tipAxis('cross')), { probes: ring(150, 200, [30, 70], 5).concat(ring(450, 200, [30, 70], 5)).concat([[300, 200]]) });

// ---- the conversions
const VALUES_TO = [null, [0, 0], [5, 0], [10, 50], [2.5, 25], [7, 99.5], [12, -10], [3, 400], [0, 100], ['4', '20'], [null, 3], [4, null], [], [4], 'abc', [[3], [30]]];
const PIXELS = [null, [300, 200], [300, 40], [460, 200], [380, 120], [200, 300], [301, 199], [300, 360], [459, 201], [0, 0], [300, 41], ['300', '100'], [null, 3], [], [5]];
const convertProbes = (finders, values, pixels) => chart => {
  const out = [];
  finders.forEach(f => {
    values.forEach(v => out.push(['to', f, v]));
    pixels.forEach(p => out.push(['from', f, p]));
    pixels.forEach(p => out.push(['contain', f, p]));
  });
  return out;
};
add('convert', 'cv-basic', 'a value radius 0..10 and a value angle 0..100: every finder form', P(A100, R10),
  { probes: convertProbes([{ polarIndex: 0 }, 'polar', { polarId: 'p0' }, { polarName: 'main' }, { polarIndex: 1 }, { seriesIndex: 0 }, { angleAxisIndex: 0 }, { radiusAxisIndex: 0 }],
    VALUES_TO, PIXELS) });
CASES[CASES.length - 1].option.polar = { id: 'p0', name: 'main' };
add('convert', 'cv-category', 'a category angle and a category radius: names and ordinals', P({ type: 'category', data: cats(8) }, { type: 'category', data: C5 }),
  { probes: convertProbes([{ polarIndex: 0 }], [[0, 0], ['c', 'c3'], [2, 5], ['z', 'c1'], [4.4, 7.6], [1.5, 2.5], ['a', 7]], PIXELS) });
add('convert', 'cv-time', 'a time angle axis', P({ type: 'time', min: '2024-01-01T00:00:00Z', max: '2024-12-31T00:00:00Z' }, R10, { useUTC: true }),
  { probes: convertProbes([{ polarIndex: 0 }], [[5, '2024-06-01T00:00:00Z'], [5, Date.UTC(2024, 3, 1)], [5, Date.UTC(2024, 3, 1) + 0.6], [5, '2024-02-30']], PIXELS) });
add('convert', 'cv-log', 'a log radius 1..1000', P(A100, { type: 'log', min: 1, max: 1000 }),
  { probes: convertProbes([{ polarIndex: 0 }], [[1, 0], [10, 20], [0, 30], [-5, 40], [1000, 100], [5000, 50]], PIXELS) });
add('convert', 'cv-inverse-half', 'an inverse radius over a ring and a half angle range', P({ min: 0, max: 100, startAngle: 0, endAngle: 180 }, { min: 0, max: 10, inverse: true }, { polar: { radius: [40, '80%'] } }),
  { probes: convertProbes([{ polarIndex: 0 }], VALUES_TO, PIXELS.concat([[300, 160], [300, 159], [300, 361], [140, 200], [460, 200], [380, 280], [300, 240]])) });
add('convert', 'cv-swapped', 'min above max on the angle: the inverse toggled, pointToCoord follows it', P({ min: 100, max: 0 }, R10),
  { probes: convertProbes([{ polarIndex: 0 }], [[5, 0], [5, 25], [5, 75]], PIXELS) });
add('convert', 'cv-nogap', 'a category angle without a gap: the last band is outside the extent', P({ type: 'category', data: cats(6), boundaryGap: false }, R10),
  { probes: convertProbes([{ polarIndex: 0 }], [[5, 0], [5, 5]], ring(300, 200, [50, 100], 12)) });
add('convert', 'cv-with-grid', 'a grid and two polars: the grid answers first, each polar for itself', {
  grid: { left: 20, top: 20, width: 100, height: 100, outerBoundsMode: 'none' }, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
  polar: [{ center: [300, 200], radius: 100 }, { center: [480, 300], radius: [20, 80] }],
  angleAxis: [{ min: 0, max: 360, polarIndex: 0 }, { type: 'category', data: C5, polarIndex: 1 }],
  radiusAxis: [{ min: 0, max: 10, polarIndex: 0 }, { min: 0, max: 5, polarIndex: 1 }],
}, { probes: convertProbes([{ polarIndex: 0 }, { polarIndex: 1 }, { gridIndex: 0, polarIndex: 1 }, { polarIndex: 'all' }, { polarIndex: [1, 0] }],
  [[0, 0], [5, 90], [3, 2]], [[300, 200], [480, 300], [350, 150], [500, 260], [60, 60]]) });

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function runCase(c) {
  const fails = [];
  const option = clone(c.option);
  option.animation = false;
  const written = clone(option);
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: c.W, height: c.H });
  chart.__c3Finder = finder => PARSE_FINDER(chart.getModel(), finder);
  try {
    quiet(() => chart.setOption(option));
    chart.renderToSVGString();
    const polars = [];
    chart.getModel().eachComponent('polar', pm => {
      if (!pm.coordinateSystem) return;
      polars.push(readPolar(chart, c, pm, fails));
    });
    const rec = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: written, polars };
    if (c.group === 'pointer') rec.pointer = c.probes.map(([x, y]) => readPointer(chart, c, x, y, fails));
    if (c.group === 'convert') rec.convert = runConvert(chart, c, fails);
    rec.fails = fails;
    return rec;
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
  const p0 = id => cs(id).polars[0];
  out.cases.forEach(q => guard(q.id + ': every record matches its recipe', q.fails.length === 0));
  guard('a full turn is a circle', p0('cat-angle-basic').angle.line.kind === 'circle');
  guard('a half turn is an arc', p0('value-angle-half').angle.line.kind === 'arc');
  guard('a hole makes a ring even on half a turn', p0('value-angle-half-ring').angle.line.kind === 'ring');
  guard('clockwise is the default: the angle axis is inverse', p0('cat-angle-basic').aInverse === true);
  guard('inverse and the clockwise default cancel', p0('cat-angle-inverse').aInverse === false);
  guard('inverse and anticlockwise make an inverse axis', p0('cat-angle-inverse-anticlockwise').aInverse === true);
  guard('a category angle axis without a gap loses one band of its extent', cs('cat-angle-nogap').polars[0].aExtent[1] === hex(-180));
  guard('a value angle axis 0..360 drops its overlapping last tick', p0('value-angle').angle.ticks.length === 12);
  guard('a blank axis draws only its line', p0('value-angle-blank').angle.ticks.length === 0 && p0('value-angle-blank').angle.line !== null
    && p0('value-angle-blank').radius.labels.length === 0);
  guard('min above max toggles the inverse, not the extent', p0('value-angle-swapped').aInverse === false && p0('value-angle-swapped').aExtent[1] === hex(-270));
  guard('sixty categories thin to every third', p0('cat-angle-many').angle.labels.length === 20);
  guard('the angle labels skip the off-interval end', !p0('cat-angle-many').angle.labels.some(l => l.tick === '59'));
  guard('a radius split area is a full ring', p0('radius-inverse').radius.splitAreas.every(a => a.sa === hex(0) && a.ea === hex(Math.PI * 2)));
  guard('the radius line is sub-pixel optimised', p0('cat-angle-basic').radius.line.x1 === hex(300.5));
  guard('hideOverlap hides radius labels', p0('value-radius-hide').radius.labels.some(l => l.ignore));
  guard('showMinLabel false hides the first', p0('value-radius-minmax').radius.labels[0].ignore === true);
  guard('a hidden label takes its tick', p0('value-radius-minmax').radius.ticks[0].ignore === true);
  guard('the second polar takes the axes that name it', cs('multi-polar').polars[1].aType === 'value' && cs('multi-polar').polars[1].rType === 'category');
  guard('a hidden radius axis draws nothing', p0('hidden-parts').radius.line === null && p0('hidden-parts').radius.labels.length === 0);
  const ptr = cs('ptr-angle-line').pointer;
  guard('a line pointer on the angle axis', ptr.some(p => p.axes.some(a => a.dim === 'angle' && a.el && a.el.type === 'line')));
  guard('no pointer outside the polar', ptr.find(p => p.x === 10 && p.y === 10).axes.length === 0);
  guard('a shadow on the angle axis is a sector', cs('ptr-angle-shadow').pointer.some(p => p.axes.some(a => a.el && a.el.type === 'sector')));
  guard('cross puts a circle on the radius', cs('ptr-cross').pointer.some(p => p.axes.some(a => a.dim === 'radius' && a.el && a.el.type === 'circle')));
  guard('cross shows the labels', cs('ptr-cross').pointer.some(p => p.axes.some(a => a.label)));
  guard('a plain tooltip pointer shows no label', !ptr.some(p => p.axes.some(a => a.label)));
  guard('the axis\' own label shows under a line tooltip', cs('ptr-own-label').pointer.some(p => p.axes.some(a => a.label)));
  guard('off the half arc: nothing', cs('ptr-half').pointer.some(p => p.axes.length === 0 && Math.hypot(p.x - 300, p.y - 200) < 150));
  guard('a time radius is the base axis', cs('ptr-time-radius').pointer.some(p => p.axes.some(a => a.dim === 'radius')));
  guard('the radius shadow is clamped to the centre', cs('ptr-radius-nogap').pointer.some(p => p.axes.some(a => a.el && a.el.shape[2] === hex(0))));
  guard("axis 'radius' overrides the angle base", cs('ptr-want-radius').pointer.every(p => p.axes.every(a => a.dim === 'radius')));
  guard('a banded tick outlives its hidden label', p0('cat-radius-hide-min').radius.labels[0].ignore === true && p0('cat-radius-hide-min').radius.ticks.every(q => !q.ignore));
  guard('a colliding end name is moved', p0('radius-name-collide').radius.name.y !== hex(40));
  guard('a category radius is the base axis', cs('ptr-radius-auto').pointer.some(p => p.axes.some(a => a.dim === 'radius' && a.el && a.el.type === 'sector')));
  guard('a label past the top is held at 0', cs('ptr-edge').pointer.some(p => p.axes.some(a => a.label && a.label.y === hex(0))));
  guard('polar answers a conversion', cs('cv-basic').convert.some(p => p.by === 'polar'));
  guard('a series finder on no polar series answers nothing', cs('cv-basic').convert.filter(p => p.finder.text === '{"seriesIndex":0}').every(p => p.out.k === 'none' || p.out.k === 'bool'));
  guard('a null radius throws', cs('cv-basic').convert.some(p => p.op === 'to' && p.out.k === 'throw'));
  guard('the grid answers before a polar', cs('cv-with-grid').convert.some(p => p.finder.text === '{"gridIndex":0,"polarIndex":1}' && p.by === 'grid'));
  return g;
}

function generate() {
  const out = {
    source: DIST, version: echarts.version,
    notes: [
      'merged paths: each piece read as mergePath merged it (Path.getUpdatedPathProxy), the bundles in the view\'s builder order.',
      'radius axis: the AxisBuilder elements by anid (line, ticks_<v>, minorticks_<i>_<v>, label_<v>, name).',
      'angle labels: the Text style x / y / align / verticalAlign.',
      'pointer: updateAxisPointer at integer pixels; the axis view\'s pointer group.',
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
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
out1.cases.forEach(q => q.fails.slice(0, 8).forEach(f => console.log('  ' + q.id + ': ' + f)));
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
