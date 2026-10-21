/*
Upstream's own answers for roadmap D12 part one (MX1), batch 145: the MATRIX
coordinate system -- the model (MatrixModel.ts: the defaults, the box merged
by mergeLayoutParam at init, the x / y dimension models with no parent),
the header trees (MatrixDim.ts: _initByDimModelData's traversal and spans,
the leaves-first ordinal order, createUniqueValueGenerator's renaming of
duplicates and nulls, `length`, _initBySeriesData's collecting dimension),
the layout (Matrix.ts _resize: getLayoutRect on the canvas,
layOutUnitsOnDimension -- levelSize / levels[i].levelSize / a leaf's size,
px or a percentage of the matrix, confineSize, the equal share, the last
unit aligned to the far edge unless everything was specified --,
layOutDimCellsRestInfoByUnit), the single-value positioning
(matrixCoordHelper.ts coordDataToAllCellLevelLayout + parseCoordRangeOption
for one value per dimension + xyLocatorRangeToRectOneDim; dataToLayout /
dataToPoint), the view (MatrixView.ts: the dimension cells, the body and
corner cells, the background and the outer border, the two divider lines,
z2, createMatrixRect / createMatrixLine's subPixelOptimize, the cell label
with its default overflow 'break' / lineOverflow 'truncate' / padding,
labelStyle's createTextConfig, zrender Element.updateInnerText's
autoOverflowArea, Text._updatePlainTexts' calcInnerTextOverflowArea,
parsePlainText, the clip path), and the two series MX1 draws on it: a
heatmap's cell (HeatmapView's matrix branch: dataToLayout(...).rect, z2 1)
and a scatter's symbol (layout/points.ts: dataToPoint).

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr) with
Math.random the port's xorshift32 (seed 2463534242, reset before every chart)
and zrender's width table measuring every string (the TZrSsrMeasurer of the
Pascal tests, checked here character by character). Every option is run with
animation off; after setOption, zr.storage.getDisplayList(true) updates
every element (the labels are placed, the Texts lay out their TSpans).

  node tools/advchart-oracle/matrix.js

writes tests/fixtures/advchart-matrix.json (ORACLE_OUT overrides). Ends with
process.exit().

-----------------------------------------------------------------------------
Numbers that are positions are the 16 lowercase hex digits of the IEEE double
(big-endian; NaN 7ff8000000000000); counts, flags, strings and option values
are plain JSON.

Top level: source, version, seed, W, H, measure {firstCode, ratio[] (hex)},
notes[], cases[], guards[].

A case: id, note, gallery (the file name under examples/advchart/gallery,
fed VERBATIM; option is then null) or option (as fed, before animation:false
was added), matrices[], series[], fails[] (recipe mismatches; must be empty).

A matrix record:
  index, id (option id or null), z, rect {x, y, width, height} (hex),
  box {left, right, top, bottom, width, height}: the layout params after the
    init merge, as JSON (null where undefined),
  dims[2] (x then y): {show, collect (the dimension takes its leaves from
    the series), leaves (count), levels[] {xy, wh (hex), size (the
    levelSize option as read: JSON or null)}, cells[] in ORDINAL order
    {kind ('leaf' | 'nonLeaf'), ordinal, level, firstLeaf, id [x, y],
    span [x, y], xy, wh (hex: a leaf's unit, a non-leaf's span), rect {x, y,
    width, height} (hex), value (the cell's option.value after the unique
    renaming)}}
  els[]: the matrix view group's children in order -- each {k ('rect' |
    'line'), role ('cell' | 'bg' | 'border' | 'divider'), target ('x' | 'y'
    | 'body' | 'corner' for a cell, the divider's dimension, null), loc
    [x, y] (a cell's locator pair: a dimension cell's id, a body or corner
    cell's), dl (its index in the display list), shape (rect: x, y, width,
    height; line: x1, y1, x2, y2; hex), style {fill, stroke (strings as set,
    null when undefined), lineWidth (hex), opacity (number or null), lineDash
    (array or null)}, z, z2, silent, label null | {text (style.text), t (the
    Text's transform, 6 hex), align, va (the Text's style align / verticalAlign
    or its default style's), fill, font, z2, dl, lines[] {text, x, y (hex):
    each TSpan}, clip null | {x, y, width, height} (hex, in the Text's own
    frame)}}
  probes[] {input [a, b] (as passed: numbers, strings, null), rect {x, y,
    width, height}, point [x, y] (hex)}

A series record (heatmap, scatter or effectScatter on a matrix):
  seriesIndex, type, matrixIndex, count, rows[] by data index {index, x, y,
  value (data.get of the three dimensions: a number in hex, null for NaN;
  an ordinal dimension holds an index or the raw number), drawn, heatmap: shape
  {x, y, width, height} (hex), fill (the style's own fill, null when the
  style has none); scatter: point [x, y] (hex, the item layout), size
  ([w, h] the symbolSize visual), fill (the symbol path's); label null |
  {text, t (6 hex), lines[] {text, x, y}} -- a scatter's label on a matrix
  has no default words (its defaulted label dimension is an ordinal one)}

Guards (any failure: nothing is written, exit 1): R1 every dimension cell's
rect is the span of its units; R2 every heatmap rect is dataToLayout of its
row's x / y, every scatter point dataToPoint; R3 every cell label's anchor is
calculateTextPosition('inside') on the cell's (sub-pixel) shape when no
position was written; R4 the display list order of a matrix's elements is
the group order stably sorted by z2; R5 a one-line label's TSpan is where
parsePlainText puts it; named discriminating facts; and the whole fixture
generated twice, byte-identical.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

// ---------- the random numbers: the port's xorshift32 ----------
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
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-matrix.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');
// [R2-J2] the gallery as it was before every function got a name
const { withoutFunctions } = require('./gallery-functions.js');
const W = 800;
const H = 600;

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
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const hexN = v => (typeof v === 'number' ? hex(v) : null);
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const jsonOf = v => (v === undefined ? null : clone(v));
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};
const rectRec = r => ({ x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) });

// ---------- zrender's width table ----------
const FIRST_CODE = 32;
const LAST_CODE = 126;
function decodeTable(literal, where) {
  const s = Function('"use strict"; return (' + literal + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, where + ': the width table is not 95 characters');
  return s;
}
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = decodeTable(line.slice(line.indexOf('=') + 1).trim().replace(/;$/, ''), DIST);
  if (fs.existsSync(ZRENDER_SRC)) {
    const m = /const defaultWidthMapStr = (`[^`]*`)/.exec(fs.readFileSync(ZRENDER_SRC, 'utf8'));
    must(m && decodeTable(m[1], ZRENDER_SRC) === s, 'the dist and the zrender source disagree on the width table');
  }
  return s;
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);
function measure(text, font) {
  font = font || '12px sans-serif';
  const r = /((?:\d+)?\.?\d*)px/.exec(font);
  const px = (r && +r[1]) || 12;
  if (font.indexOf('mono') >= 0) return px * text.length;
  let w = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    w += c >= FIRST_CODE && c <= LAST_CODE ? RATIO[c - FIRST_CODE] * px : px;
  }
  return w;
}
(function checkMeasurer() {
  RATIO.forEach((r, i) => {
    const w = new echarts.graphic.Text({ style: { text: String.fromCharCode(FIRST_CODE + i), font: '1px sans-serif' } }).getBoundingRect().width;
    must(Object.is(w, r), 'char code ' + (FIRST_CODE + i) + ': the table says ' + r + ', a 1px Text measures ' + w);
  });
})();

// ---------------------------------------------------------------------------
// the chart
// ---------------------------------------------------------------------------
function run(option, isGallery) {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  const opt = clone(option);
  opt.animation = false;
  // A GALLERY CUSTOM SERIES lost its renderItem to JSON, and the development
  // build asserts on that: it is given one that draws nothing -- the matrix
  // under it is what is compared (a custom series on a matrix is MX2)
  if (isGallery) {
    [].concat(opt.series || []).forEach(s => {
      if (s && s.type === 'custom' && typeof s.renderItem !== 'function') s.renderItem = function () { return null; };
    });
  }
  quiet(() => chart.setOption(opt));
  chart.getZr().storage.getDisplayList(true);
  return chart;
}

// the elements a Text lays out (its TSpans), in order
function tspans(text) {
  const out = [];
  const ch = text.childrenRef ? text.childrenRef() : text._children;
  for (let i = 0; i < (text._childCursor != null ? text._childCursor : ch.length); i++) {
    const c = ch[i];
    if (c && c.type === 'tspan') out.push({ text: c.style.text, x: hex(c.style.x), y: hex(c.style.y) });
  }
  return out;
}
function labelRec(host, dlIndex) {
  const t = host.getTextContent();
  if (!t || t.ignore || t.invisible) return null;
  const m = t.transform || [1, 0, 0, 1, 0, 0];
  const cp = t.getClipPath();
  const ds = t._defaultStyle || {};
  return {
    text: t.style.text == null ? null : String(t.style.text),
    t: Array.from(m).map(hex),
    align: t.style.align || ds.align || null,
    va: t.style.verticalAlign || ds.verticalAlign || null,
    fill: t.style.fill == null ? (ds.fill == null ? null : String(ds.fill)) : String(t.style.fill),
    font: t.style.font || null,
    z2: t.z2,
    dl: dlIndex.has(t) ? dlIndex.get(t) : -1,
    lines: tspans(t),
    clip: cp ? rectRec(cp.shape) : null,
  };
}
function styleRec(s) {
  return {
    fill: s.fill == null ? null : String(s.fill),
    stroke: s.stroke == null ? null : String(s.stroke),
    lineWidth: hex(s.lineWidth == null ? 1 : s.lineWidth),
    opacity: s.opacity == null ? null : s.opacity,
    lineDash: s.lineDash == null ? null : (Array.isArray(s.lineDash) ? s.lineDash.slice() : String(s.lineDash)),
  };
}

// The cell order of MatrixView: the dimension cells (x then y, in ordinal
// order, a hidden dimension none), the body cells (y leaves, then x leaves),
// the corner cells when both dimensions show (x levels, then y levels).
function viewPlan(xDim, yDim) {
  const plan = [];
  [xDim, yDim].forEach((d, di) => {
    if (!d.shouldShow()) return;
    d._cells.forEach(c => plan.push({ target: di === 0 ? 'x' : 'y', loc: [c.id.x, c.id.y] }));
  });
  for (let iy = 0; iy < yDim._leavesCount; iy++)
    for (let ix = 0; ix < xDim._leavesCount; ix++) plan.push({ target: 'body', loc: [ix, iy] });
  if (xDim.shouldShow() && yDim.shouldShow()) {
    const nx = xDim._levels.length;
    const ny = yDim._levels.length;
    for (let ly = 0; ly < nx; ly++)
      for (let lx = 0; lx < ny; lx++) plan.push({ target: 'corner', loc: [lx - ny, ly - nx] });
  }
  return plan;
}

function dimRec(d) {
  return {
    show: d.shouldShow(),
    collect: !!(d._ordinalMeta && d._ordinalMeta._needCollect),
    leaves: d._leavesCount,
    levels: d._levels.map(l => ({ xy: hex(l.xy), wh: hex(l.wh), size: l.option ? jsonOf(l.option.levelSize) : null })),
    cells: d._cells.map(c => ({
      kind: c.type === 2 ? 'leaf' : 'nonLeaf',
      ordinal: c.ordinal, level: c.level, firstLeaf: c.firstLeafLocator,
      id: [c.id.x, c.id.y], span: [c.span.x, c.span.y],
      xy: hex(c.xy), wh: hex(c.wh), rect: rectRec(c.rect),
      value: c.option.value == null ? null : String(c.option.value),
    })),
  };
}

function probeInputs(xDim, yDim) {
  const ins = [[0, 0], [1, 0], [0, 1], [-1, 0], [0, -1], [-1, -1], [1.5, 0.4], [-0.4, 0], [-0.6, 0],
    [-2, 0], [0, -2], [-99, 0], [99, 0], [null, 0], [0, null], ['__none__', 0]];
  const nx = xDim._leavesCount;
  const ny = yDim._leavesCount;
  ins.push([nx - 1, ny - 1], [nx, 0], [0, ny], [xDim._cells.length - 1, 0], [0, yDim._cells.length - 1]);
  // every cell by its value (the first of each name), and a pair of them
  xDim._cells.forEach(c => ins.push([String(c.option.value), 0]));
  yDim._cells.forEach(c => ins.push([0, String(c.option.value)]));
  if (xDim._cells.length && yDim._cells.length)
    ins.push([String(xDim._cells[xDim._cells.length - 1].option.value), String(yDim._cells[yDim._cells.length - 1].option.value)]);
  return ins;
}

function matrixRec(chart, mm, dlIndex, fails) {
  const cs = mm.coordinateSystem;
  const xDim = mm.getDimensionModel('x').dim;
  const yDim = mm.getDimensionModel('y').dim;
  const view = chart.getViewOfComponentModel(mm);
  const plan = viewPlan(xDim, yDim);
  const kids = view.group.children();
  const els = [];
  let pi = 0;
  kids.forEach((el, k) => {
    const rec = { k: el.type, role: null, target: null, loc: null, dl: dlIndex.has(el) ? dlIndex.get(el) : -1 };
    if (pi < plan.length) {
      rec.role = 'cell';
      rec.target = plan[pi].target;
      rec.loc = plan[pi].loc;
      pi++;
    }
    else if (el.type === 'rect') {
      rec.role = els.some(e => e.role === 'bg') ? 'border' : 'bg';
    }
    else {
      rec.role = 'divider';
      rec.target = el.shape.y1 === el.shape.y2 && el.shape.x1 !== el.shape.x2 ? 'x' : 'y';
    }
    if (el.type === 'rect') rec.shape = rectRec(el.shape);
    else rec.shape = { x1: hex(el.shape.x1), y1: hex(el.shape.y1), x2: hex(el.shape.x2), y2: hex(el.shape.y2) };
    rec.style = styleRec(el.style);
    rec.z = el.z;
    rec.z2 = el.z2;
    rec.silent = !!el.silent;
    rec.label = el.type === 'rect' ? labelRec(el, dlIndex) : null;
    els.push(rec);
  });
  if (pi !== plan.length) fails.push('matrix ' + mm.componentIndex + ': ' + plan.length + ' cells planned, ' + pi + ' drawn');
  const probes = probeInputs(xDim, yDim).map(input => {
    const lay = cs.dataToLayout(input);
    const pt = cs.dataToPoint(input);
    return { input, rect: rectRec(lay.rect), point: [hex(pt[0]), hex(pt[1])] };
  });
  const box = {};
  ['left', 'right', 'top', 'bottom', 'width', 'height'].forEach(k => { box[k] = jsonOf(mm.option[k]); });
  return {
    index: mm.componentIndex, id: mm.option.id == null ? null : String(mm.option.id), z: mm.get('z'),
    rect: rectRec(cs.getRect()), box,
    dims: [dimRec(xDim), dimRec(yDim)],
    els, probes,
  };
}

function seriesRecs(chart, dlIndex) {
  const out = [];
  chart.getModel().eachSeries(s => {
    if (s.get('coordinateSystem') !== 'matrix') return;
    const type = s.subType;
    if (type !== 'heatmap' && type !== 'scatter' && type !== 'effectScatter') return;
    const data = s.getData();
    const mm = s.getReferringComponents('matrix', { useDefault: true, enableAll: false, enableNone: false }).models[0];
    const rows = [];
    const g = v => (typeof v === 'number' ? (Number.isNaN(v) ? null : hex(v)) : (v == null ? null : String(v)));
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      const row = { index: i, raw: data.getRawIndex(i), x: g(data.get('x', i)), y: g(data.get('y', i)), value: g(data.get('value', i)), drawn: !!el };
      if (type === 'heatmap') {
        row.shape = el ? rectRec(el.shape) : null;
        row.fill = el ? (el.style.fill == null ? null : String(el.style.fill)) : null;
        row.label = el ? labelRec(el, dlIndex) : null;
      }
      else {
        const lay = data.getItemLayout(i);
        row.point = lay ? [hex(lay[0]), hex(lay[1])] : null;
        const sz = data.getItemVisual(i, 'symbolSize');
        row.size = Array.isArray(sz) ? sz.slice() : [sz, sz];
        const path = el && el.childAt ? el.childAt(0) : null;
        row.fill = path ? (path.style.fill == null ? null : String(path.style.fill)) : null;
        row.label = path ? labelRec(path, dlIndex) : null;
      }
      rows.push(row);
    }
    out.push({ seriesIndex: s.seriesIndex, type, matrixIndex: mm ? mm.componentIndex : null, count: data.count(), rows });
  });
  return out;
}

// ---------------------------------------------------------------------------
// recipes
// ---------------------------------------------------------------------------
function subPixel(p, lw) {
  if (!lw) return p;
  const d = Math.round(p * 2);
  return (d + Math.round(lw)) % 2 === 0 ? d / 2 : (d + 1) / 2;
}
function checkMatrix(chart, mm, rec, fails) {
  const cs = mm.coordinateSystem;
  const where = 'matrix ' + rec.index;
  const dims = [mm.getDimensionModel('x').dim, mm.getDimensionModel('y').dim];
  // R1: a dimension cell's rect from its units
  const unit = (dimIdx, loc) => (loc < 0 ? dims[1 - dimIdx] : dims[dimIdx]).getUnitLayoutInfo(dimIdx, loc);
  dims.forEach((d, di) => d._cells.forEach(c => {
    for (const k of [0, 1]) {
      const id = k === 0 ? c.id.x : c.id.y;
      const sp = k === 0 ? c.span.x : c.span.y;
      const u0 = unit(k, id);
      const u1 = unit(k, id + sp - 1);
      const xy = u0.xy;
      const wh = sp > 1 ? u1.xy + u1.wh - u0.xy : u0.wh;
      const rx = k === 0 ? c.rect.x : c.rect.y;
      const rw = k === 0 ? c.rect.width : c.rect.height;
      if (!Object.is(xy, rx) || !Object.is(wh, rw)) fails.push(where + ' dim ' + di + ' cell ' + c.ordinal + ': R1 axis ' + k);
    }
  }));
  // R3 / R5: the cell labels
  rec.els.forEach((e, i) => {
    if (!e.label || e.role !== 'cell') return;
    const sh = { x: num(e.shape.x), y: num(e.shape.y), w: num(e.shape.width), h: num(e.shape.height) };
    const tx = sh.x + sh.w / 2;
    const ty = sh.y + sh.h / 2;
    if (e.label.align === 'center' && e.label.va === 'middle'
      && !(Object.is(num(e.label.t[4]), tx) && Object.is(num(e.label.t[5]), ty)))
      fails.push(where + ' el ' + i + ': R3 the label is not at the cell centre');
    if (e.label.lines.length === 1 && e.label.align === 'center' && e.label.va === 'middle' && e.label.font) {
      // the overflow area of an inside label and parsePlainText's one line
      const ox = sh.x + -tx;
      const ow = sh.w;
      const bx0 = -ow;
      const ix = Math.max(ox, bx0);
      const iw = Math.min(ox + ow, bx0 + ow * 2) - ix;
      const baseX = ix + iw / 2;
      const oy = sh.y + -ty;
      const oh = sh.h;
      const by0 = -oh;
      const iy = Math.max(oy, by0);
      const ih = Math.min(oy + oh, by0 + oh * 2) - iy;
      const baseY = iy + ih / 2;
      const r = /((?:\d+)?\.?\d*)px/.exec(e.label.font);
      const lh = (r && +r[1]) || 12;
      const y = baseY - lh / 2 + lh / 2;
      if (!(Object.is(num(e.label.lines[0].y), y))) fails.push(where + ' el ' + i + ': R5 the line y ' + num(e.label.lines[0].y) + ' recipe ' + y);
      if (!(Object.is(num(e.label.lines[0].x), baseX))) fails.push(where + ' el ' + i + ': R5 the line x ' + num(e.label.lines[0].x) + ' recipe ' + baseX);
    }
  });
  // sub-pixel: a cell's shape from its raw rect
  rec.els.forEach((e, i) => {
    if (e.k !== 'rect' || e.role !== 'cell') return;
    const lw = num(e.style.lineWidth);
    if (!lw) return;
    const lay = cs.dataToLayout(e.loc, { ignoreMergeCells: true }).rect;
    if (Number.isNaN(lay.x) || Number.isNaN(lay.y)) return;
    if (e.target === 'x' || e.target === 'y') return;
    const x = subPixel(lay.x, lw);
    const y = subPixel(lay.y, lw);
    const w = subPixel(lay.x + lay.width, lw) - x;
    const h = subPixel(lay.y + lay.height, lw) - y;
    if (!(Object.is(num(e.shape.x), x) && Object.is(num(e.shape.y), y) && Object.is(num(e.shape.width), w) && Object.is(num(e.shape.height), h)))
      fails.push(where + ' el ' + i + ': the sub-pixel shape');
  });
  // R4: the display order
  const withDl = [];
  rec.els.forEach((e, i) => {
    withDl.push({ i, z2: e.z2, dl: e.dl, lab: false });
    if (e.label) withDl.push({ i: i + 0.5, z2: e.label.z2, dl: e.label.dl, lab: true });
  });
  const sorted = withDl.filter(q => q.dl >= 0).slice().sort((a, b) => a.z2 - b.z2 || a.i - b.i);
  const byDl = withDl.filter(q => q.dl >= 0).slice().sort((a, b) => a.dl - b.dl);
  if (sorted.map(q => q.i).join() !== byDl.map(q => q.i).join()) fails.push(where + ': R4 the display order is not the z2 order');
}
function checkSeries(chart, srecs, fails) {
  srecs.forEach(sr => {
    const mm = chart.getModel().getComponent('matrix', sr.matrixIndex);
    const cs = mm.coordinateSystem;
    sr.rows.forEach(r => {
      const xv = r.x == null ? NaN : (typeof r.x === 'string' && /^[0-9a-f]{16}$/.test(r.x) ? num(r.x) : r.x);
      const yv = r.y == null ? NaN : (typeof r.y === 'string' && /^[0-9a-f]{16}$/.test(r.y) ? num(r.y) : r.y);
      if (sr.type === 'heatmap') {
        if (!r.drawn) return;
        const lay = cs.dataToLayout([xv, yv]).rect;
        const sh = r.shape;
        if (!(Object.is(num(sh.x), lay.x) && Object.is(num(sh.y), lay.y) && Object.is(num(sh.width), lay.width) && Object.is(num(sh.height), lay.height)))
          fails.push('series ' + sr.seriesIndex + ' row ' + r.index + ': R2 the heatmap rect');
      }
      else if (r.point) {
        const p = cs.dataToPoint([xv, yv]);
        if (!(Object.is(num(r.point[0]), p[0]) && Object.is(num(r.point[1]), p[1])))
          fails.push('series ' + sr.seriesIndex + ' row ' + r.index + ': R2 the scatter point');
      }
    });
  });
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
const add = (id, note, option) => CASES.push({ id, note, option });
const gal = (name, note) => CASES.push({ id: 'gallery-' + name, note, gallery: name });
const vm = (min, max, extra) => Object.assign({ show: false, min, max, dimension: 2 }, extra || {});

const TREE_X = [{ value: 'A', children: ['A1', 'A2', { value: 'A3', children: ['A31', 'A32'] }] }];
const TREE_BOTH_X = [{ value: 'Q1', children: ['Jan', 'Feb', 'Mar'] }, { value: 'Q2', children: [{ value: 'Apr', children: ['w1', 'w2'] }, 'May'] }, 'H2'];
const TREE_BOTH_Y = [{ value: 'North', children: ['N1', 'N2'] }, 'South', { value: 'East', children: [{ value: 'E1', children: ['E1a'] }] }];

add('flat', 'three columns, two rows, the default box (10% all round)',
  { matrix: { x: { data: ['Mon', 'Tue', 'Wed'] }, y: { data: ['A', 'B'] } } });
add('nested-x', 'a tree on x (leaves A1 A2 A31 A32 under A / A3), two flat rows',
  { matrix: { x: { data: TREE_X }, y: { data: ['U', 'V'] }, top: 150, bottom: 150 } });
add('nested-both', 'trees on both dimensions, leaves at different depths (H2 at level 0, w1 at level 2)',
  { matrix: { x: { data: TREE_BOTH_X }, y: { data: TREE_BOTH_Y } } });
add('levels', 'levelSize on the dimension, levels[i].levelSize over it (a null level keeps the dimension one), a percentage',
  { matrix: { x: { data: TREE_X, levelSize: 40, levels: [{ levelSize: 20 }, null, { levelSize: '15%' }] }, y: { data: ['U', 'V', 'W'], levelSize: '25%', levels: [{ levelSize: 70 }] } } });
add('leaf-size', 'leaf sizes in px, a percentage, a numeric string, null and none; the rest share what is left',
  { matrix: { x: { data: [{ value: 'a', size: 120 }, { value: 'b', size: '15%' }, 'c', { value: 'd', size: null }, { value: 'e', size: '30' }] }, y: { data: ['p', { value: 'q', size: 40 }] } } });
add('all-specified', 'every unit sized: the space left over is not given to the last one',
  { matrix: { x: { data: [{ value: 'a', size: 100 }, { value: 'b', size: 100 }], levelSize: 30 }, y: { data: [{ value: 'p', size: 50 }], levelSize: 60 } } });
add('oversize', 'a leaf wider than the matrix is confined, the rest get nothing',
  { matrix: { x: { data: [{ value: 'a', size: 900 }, 'b', 'c'] }, y: { data: ['p'] } } });
add('nonleaf-size', 'a size on a non-leaf is not read',
  { matrix: { x: { data: [{ value: 'G', size: 300, children: ['g1', 'g2'] }, 'h'] }, y: { data: ['p'] } } });
add('show-x-false', 'x hidden: its levels take no room, its cells are not drawn, no corner, the divider under x is not drawn',
  { matrix: { x: { data: TREE_X, show: false }, y: { data: ['U', 'V'] } } });
add('show-both-false', 'both hidden: the body fills the box',
  { matrix: { x: { data: ['a', 'b'], show: false }, y: { data: ['p', 'q', 'r'], show: false } } });
add('length', 'length instead of data: X0, X1, ... and Y0, Y1',
  { matrix: { x: { length: 4 }, y: { length: 2 } } });
add('dupes', 'a repeated name, nulls, a numeric value, an X-name that moves the counter',
  { matrix: { x: { data: ['A', { value: 'B', children: ['A', 'C'] }, null, 'X1', { value: 5 }, 'X1'] }, y: { data: ['Y0', null, 'Y0'] } } });
add('empty-x', 'x.data empty: no columns, the row headers fill the width',
  { matrix: { x: { data: [] }, y: { data: ['a', 'b'] } } });
add('box-wh', 'a centred box of a fixed width and a percentage height',
  { matrix: { left: 'center', top: 'middle', width: 300, height: '40%', x: { data: ['a', 'b', 'c'] }, y: { data: ['p', 'q'] } } });
add('box-rb', 'right and width replace the default left; bottom alone keeps the default top',
  { matrix: { right: 20, width: '50%', bottom: 30, x: { data: ['a', 'b'] }, y: { data: ['p', 'q'] } } });
add('box-zero', 'the whole canvas',
  { matrix: { left: 0, right: 0, top: 0, bottom: 0, x: { data: ['a', 'b', 'c', 'd'] }, y: { data: ['p', 'q', 'r'] } } });
add('box-frac', 'fractional percentages: cells that are not whole pixels',
  { matrix: { left: '7.3%', right: '11.1%', top: '9.7%', bottom: '13.3%', x: { data: ['a', 'b', 'c', 'd', 'e', 'f', 'g'] }, y: { data: ['p', 'q', 'r', 's', 't', 'u'] } } });
add('styles', 'dimension, cell, body and corner itemStyles; z2 written on a cell and on y; the background and the outer border; borderZ2; the divider styles',
  { matrix: {
    x: { data: ['a', { value: 'b', itemStyle: { color: '#ffeeee' } }, { value: 'c', z2: 70 }], itemStyle: { color: '#f0f8ff', borderColor: '#333366', borderWidth: 2 }, dividerLineStyle: { color: '#0000ff', width: 2, type: 'dashed' } },
    y: { data: ['p', 'q'], z2: 60, dividerLineStyle: { width: 0 } },
    body: { itemStyle: { color: '#fafafa', borderWidth: 0 } },
    corner: { itemStyle: { color: '#dddddd', borderColor: '#ff0000', borderWidth: 1 } },
    backgroundStyle: { color: '#ffffee', borderColor: '#009900', borderWidth: 3 },
    borderZ2: 40 } });
add('styles-odd', 'odd border widths, an opacity, a dotted body border',
  { matrix: {
    x: { data: ['a', 'b'], itemStyle: { borderWidth: 3, opacity: 0.5 } },
    y: { data: ['p', 'q', 'r'], itemStyle: { borderWidth: 0 } },
    body: { itemStyle: { borderWidth: 1.5, borderType: 'dotted', borderColor: '#888888' } },
    backgroundStyle: { borderWidth: 0 } } });
add('labels', 'a dimension label style, a cell label over it, a hidden y label, a string formatter',
  { matrix: {
    x: { data: ['alpha', { value: 'beta', label: { color: '#00aa00', fontSize: 9 } }, 'gamma'], label: { fontSize: 16, color: '#cc0000', fontWeight: 'bold', padding: 0, formatter: '[{value}]' } },
    y: { data: ['p', 'q'], label: { show: false } } } });
add('labels-place', 'a position, an align, a verticalAlign and a distance on cell labels',
  { matrix: {
    x: { data: [{ value: 'L', label: { position: 'insideLeft' } }, { value: 'R', label: { align: 'right' } }, { value: 'T', label: { position: 'insideTop', distance: 5 } }, { value: 'B', label: { verticalAlign: 'bottom' } }] },
    y: { data: [{ value: 'p', label: { position: 'insideBottomRight' } }, 'q'] } } });
add('label-wrap', 'narrow, short cells: the words break, the lines that do not fit are dropped, the clip is the cell inside its border',
  { matrix: { left: 250, right: 250, top: 270, bottom: 270,
    x: { data: ['A rather long header', 'Short', 'Supercalifragilistic'] },
    y: { data: ['Two words', 'x'] } } });
add('label-tiny', 'cells shorter than the padding: a negative height keeps all the lines but the last (Array.slice with a negative end)',
  { matrix: { left: 360, right: 360, top: 297, bottom: 297,
    x: { data: ['Supercalifragilisticexpialidocious'] },
    y: { data: ['ab cd ef gh'] } } });
add('label-overflow', 'truncate, none (no clip), breakAll, a fixed label width and height, a label padding',
  { matrix: { left: 200, right: 200, top: 200, bottom: 200,
    x: { data: [{ value: 'truncate this text', label: { overflow: 'truncate' } }, { value: 'no clip at all here', label: { overflow: 'none' } },
      { value: 'breakallbreakall', label: { overflow: 'breakAll' } }, { value: 'fixed width label', label: { width: 30, height: 30 } }, { value: 'padded', label: { padding: [10, 20] } }] },
    y: { data: ['p'] } } });
add('heatmap-basic', 'a heatmap on a tree: leaves, a non-leaf, a header locator, a fractional index, an unknown name, a gap',
  { matrix: { x: { data: TREE_X }, y: { data: ['U', 'V'] }, top: 150, bottom: 150 },
    visualMap: vm(0, 80),
    series: { type: 'heatmap', coordinateSystem: 'matrix', label: { show: true },
      data: [['A1', 'U', 10], ['A1', 'V', 20], ['A2', 'U', 30], ['A31', 'V', 50], ['A32', 'U', 60], ['A3', 'V', 70], ['A', 'U', 5],
        [-1, 'U', 15], [1.5, 1, 25], [2, 0.4, 35], ['zz', 'U', 3], ['A2', 'V', '-'], ['A32', 'V', 45], [0, -1, 8]] } });
add('heatmap-index', 'a heatmap by index, all leaves, numbers and names mixed',
  { matrix: { x: { data: ['a', 'b', 'c', 'd'] }, y: { data: ['p', 'q', 'r'] } },
    visualMap: vm(0, 12),
    series: { type: 'heatmap', coordinateSystem: 'matrix', label: { show: true },
      data: [[0, 0, 0], [1, 0, 1], [2, 0, 2], [3, 0, 3], [0, 1, 4], ['b', 1, 5], [2, 'q', 6], ['d', 'q', 7], [0, 2, 8], [1, 2, 9], [2, 2, 10], [3, 2, 11]] } });
add('scatter-basic', 'a scatter on a matrix: the centre of each cell, a non-leaf, a header, a gap',
  { matrix: { x: { data: TREE_X }, y: { data: ['U', 'V'] } },
    series: { type: 'scatter', coordinateSystem: 'matrix', symbolSize: 18, label: { show: true },
      data: [['A1', 'U', 1], ['A2', 'V', 2], ['A31', 'U', 3], ['A3', 'V', 4], ['A', 'U', 5], [-1, 'V', 6], ['nope', 'U', 7], ['A32', null, 8]] } });
add('scatter-vm', 'a scatter sized and coloured by a visualMap',
  { matrix: { x: { data: ['a', 'b', 'c'] }, y: { data: ['p', 'q'] } },
    visualMap: vm(0, 10, { inRange: { symbolSize: [10, 40], color: ['#313695', '#a50026'] } }),
    series: { type: 'scatter', coordinateSystem: 'matrix',
      data: [['a', 'p', 0], ['b', 'p', 2.5], ['c', 'p', 5], ['a', 'q', 7.5], ['b', 'q', 10], ['c', 'q', 4]] } });
add('collect', 'no x / y data: the dimensions collect the names from the series, in series order',
  { matrix: {},
    visualMap: vm(0, 10),
    series: [{ type: 'heatmap', coordinateSystem: 'matrix', data: [['a', 'p', 1], ['b', 'p', 2], ['a', 'q', 3]] },
      { type: 'scatter', coordinateSystem: 'matrix', data: [['c', 'p', 4], ['b', 'r', 5]] }] });
add('collect-x', 'x collects, y is written',
  { matrix: { y: { data: ['p', 'q'] } },
    visualMap: vm(0, 10),
    series: { type: 'heatmap', coordinateSystem: 'matrix', label: { show: true }, data: [['m', 'p', 1], ['n', 'q', 2], ['m', 'q', 3], ['o', 'p', 4]] } });
add('two-matrices', 'two matrices; series by matrixIndex and matrixId',
  { matrix: [{ id: 'left', right: '55%', x: { data: ['a', 'b'] }, y: { data: ['p', 'q'] } },
    { id: 'right', left: '55%', x: { data: [{ value: 'G', children: ['g1', 'g2'] }] }, y: { data: ['r'] } }],
    visualMap: vm(0, 10),
    series: [{ type: 'heatmap', coordinateSystem: 'matrix', matrixIndex: 1, data: [['g1', 'r', 3], ['g2', 'r', 7]] },
      { type: 'scatter', coordinateSystem: 'matrix', matrixId: 'left', symbolSize: 12, data: [['a', 'p', 1], ['b', 'q', 2]] },
      { type: 'heatmap', coordinateSystem: 'matrix', data: [['a', 'q', 5]] }] });
add('box-negative-zero', 'a width of "-0" (parseFloat; getLayoutRect keeps the -0, BoundingRect only flips a negative): a sized leaf is confined to +0 and what is left to +0 (confineSize: Math.max(-0 - 0, 0)), so the equal share is +0, not -0',
  { matrix: { left: 300, width: '-0', x: { data: [{ value: 'a', size: 50 }, 'b', 'c'] }, y: { data: ['p', 'q'] } } });

gal('matrix-simple', 'the gallery: a heatmap on a tree');
gal('matrix-correlation-heatmap', 'the gallery: a correlation heatmap');
gal('matrix-correlation-scatter', 'the gallery: a correlation scatter (sizes from the visualMap)');
gal('matrix-covariance', 'the gallery: a covariance heatmap, both dimensions hidden');
gal('matrix-mbti', 'the gallery: MBTI, styled headers, a heatmap and a scatter');
gal('matrix-periodic-table', 'the gallery: the periodic table (its custom series is MX2; the matrix is compared)');
gal('matrix-pie', 'the gallery: pies in cells (MX2; the matrix is compared)');
gal('matrix-confusion', 'the gallery: a confusion matrix (custom, MX2; the matrix is compared)');
gal('matrix-graph', 'the gallery: a graph on a matrix (MX2; the matrix is compared)');

function runCase(c) {
  const option = c.gallery ? withoutFunctions(JSON.parse(fs.readFileSync(path.join(GALLERY, c.gallery + '.json'), 'utf8'))) : c.option;
  const chart = run(option, !!c.gallery);
  try {
    const dl = chart.getZr().storage.getDisplayList(true);
    const dlIndex = new Map();
    dl.forEach((el, i) => dlIndex.set(el, i));
    const fails = [];
    const matrices = [];
    chart.getModel().eachComponent('matrix', mm => {
      const rec = matrixRec(chart, mm, dlIndex, fails);
      checkMatrix(chart, mm, rec, fails);
      matrices.push(rec);
    });
    const series = seriesRecs(chart, dlIndex);
    checkSeries(chart, series, fails);
    return { id: c.id, note: c.note, gallery: c.gallery || null, option: c.gallery ? null : clone(c.option), matrices, series, fails };
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
  const m0 = id => cs(id).matrices[0];
  const n = h => num(h);
  out.cases.forEach(q => guard(q.id + ': every record matches its recipe', q.fails.length === 0));
  guard('the default box is 10% all round', n(m0('flat').rect.x) === 80 && n(m0('flat').rect.width) === 640);
  guard('the leaves come first in ordinal order', m0('nested-x').dims[0].cells.slice(0, 4).every(c => c.kind === 'leaf')
    && m0('nested-x').dims[0].cells[4].value === 'A');
  guard('a leaf at a shallow level spans down to the body', m0('nested-both').dims[0].cells.some(c => c.value === 'H2' && c.span[1] === 3));
  guard('a duplicate and a null are renamed past the largest X<n>', m0('dupes').dims[0].cells.some(c => c.value === 'X2')
    && m0('dupes').dims[0].cells.filter(c => c.value === 'A').length === 1);
  guard('length names X0..', m0('length').dims[0].cells.map(c => c.value).join() === 'X0,X1,X2,X3');
  guard('a null level keeps the dimension levelSize', n(m0('levels').dims[0].levels[1].wh) === 40);
  guard('everything specified: the last unit keeps its size', n(m0('all-specified').dims[0].cells[1].wh) === 100);
  guard('the last unit otherwise reaches the far edge', (() => {
    const m = m0('box-frac');
    const c = m.dims[0].cells[m.dims[0].cells.length - 1];
    return n(c.xy) + n(c.wh) === n(m.rect.x) + n(m.rect.width);
  })());
  guard('a hidden x draws no x cells and no corner', !m0('show-x-false').els.some(e => e.target === 'x' || e.target === 'corner'));
  guard('a hidden x has levels of no height', m0('show-x-false').dims[0].levels.every(l => n(l.wh) === 0));
  guard('right and width drop the default left', m0('box-rb').box.left === null && m0('box-rb').box.top === '10%');
  guard('a cell with an itemStyle is z2 125', m0('styles').els.some(e => e.target === 'x' && e.z2 === 125));
  guard('a written z2 wins', m0('styles').els.some(e => e.target === 'x' && e.z2 === 70) && m0('styles').els.some(e => e.target === 'y' && e.z2 === 60));
  guard('borderZ2 moves the border and the dividers', m0('styles').els.some(e => e.role === 'border' && e.z2 === 40)
    && m0('styles').els.some(e => e.role === 'divider' && e.z2 === 39));
  guard('the body cells are z2 25, the dimension cells 50, their labels 52', m0('flat').els.some(e => e.target === 'body' && e.z2 === 25)
    && m0('flat').els.some(e => e.target === 'x' && e.z2 === 50 && e.label && e.label.z2 === 52));
  guard('a label breaks into lines', m0('label-overflow').els.some(e => e.label && e.label.lines.length > 1));
  guard('the lines that do not fit are dropped', m0('label-wrap').els.some(e => e.label && e.label.text.split(' ').length > 1
    && e.label.lines.map(l => l.text).join(' ').length < e.label.text.length));
  guard('a negative height keeps all the lines but the last', m0('label-tiny').els.some(e => e.label && e.label.lines.length > 1));
  guard('overflow none has no clip', m0('label-overflow').els.some(e => e.label && e.label.text === 'no clip at all here' && e.label.clip === null));
  guard('a default label is clipped', m0('flat').els.some(e => e.label && e.label.clip !== null));
  guard('a string formatter', m0('labels').els.some(e => e.label && e.label.text === '[alpha]'));
  guard('a heatmap row on a non-leaf covers its span', cs('heatmap-basic').series[0].rows.some(r => r.drawn && n(r.shape.width) === 4 * n(m0('heatmap-basic').dims[0].cells[0].wh)));
  guard('a heatmap row on a header locator', cs('heatmap-basic').series[0].rows.some(r => r.drawn && n(r.shape.x) === n(m0('heatmap-basic').rect.x)));
  guard('an unknown name draws nothing', cs('heatmap-basic').series[0].rows.some(r => !r.drawn));
  guard('a gap value still draws a cell', cs('heatmap-basic').series[0].rows.some(r => r.drawn && r.value === null));
  guard('a collecting dimension', m0('collect').dims[0].collect && m0('collect').dims[0].cells.map(c => c.value).join() === 'a,b,c'
    && m0('collect').dims[1].cells.map(c => c.value).join() === 'p,q,r');
  guard('two matrices', cs('two-matrices').matrices.length === 2 && cs('two-matrices').series[0].matrixIndex === 1
    && cs('two-matrices').series[1].matrixIndex === 0);
  guard('a width of -0: the rect keeps it, the equal share is +0', Object.is(n(m0('box-negative-zero').rect.width), -0)
    && Object.is(n(m0('box-negative-zero').dims[0].cells[1].wh), 0) && Object.is(n(m0('box-negative-zero').dims[1].levels[0].wh), 0));
  guard('the visualMap sizes the scatter', cs('scatter-vm').series[0].rows.some(r => r.size[0] === 40));
  guard('the gallery draws', cs('gallery-matrix-covariance').series[0].rows.filter(r => r.drawn).length > 100);
  return g;
}

function generate() {
  const out = {
    source: DIST, version: echarts.version, seed: SEED, W, H,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: ' + W + ' x ' + H + ', SVG ssr, animation false; the gallery options fed verbatim.',
      'Math.random is the port\'s xorshift32 from ' + SEED + ', reset before every chart.',
      'the label font is the global textStyle\'s (12px, the family globalDefault picks on this machine).',
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
const nul = json1.indexOf('\\u0000') >= 0;
let parses = true;
try { JSON.parse(json1); } catch (e) { parses = false; }
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : ''));
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
