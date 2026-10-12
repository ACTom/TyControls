/*
Upstream's own answers for roadmap batch D9 [Batch 142]: the coarse pointer
(zrender Handler.findHover's pointerSize fallback, switched on by the init
options useCoarsePointer / pointerSize) and the dirty-rectangle repaint
(zrender canvas Layer.createRepaintRects with Painter._paintList's
bookkeeping, switched on by useDirtyRect).

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node:

  samples  a zrender (svg, ssr) instance with ONE far-away 2 x 2 rect whose
           box meets the enlarged pointer, so it is a candidate that no sample
           reaches: its `contain` is wrapped and records every point the
           handler asks about -- the direct test first, then the samples in
           the order findHover walks them (r = 0, 4, 8, ... < pointerSize / 2;
           theta = 0, PI / 12, ... < 2 PI, accumulated by +=).
  coarse   echarts.init(null, null, {renderer: 'svg', ssr: true, width,
           height, useCoarsePointer, pointerSize}); chart._ssr = false;
           setOption (animation: false); renderToSVGString(); then for each
           probe zr.handler.findHover(x, y) on a FRESH chart (a hover state
           must not move a symbol under the next probe). The datum is the
           ECData of the target or its host / parent chain. `direct` is the
           same point with the pointer size switched off (handler
           _pointerSize = undefined) -- what a mouse finds.
  dirty    a zrender canvas instance on a fake canvas whose 2d context swallows
           every call (nothing is drawn; the bookkeeping is real), useDirtyRect
           true. Frames are zr.refreshImmediately(); between frames the case's
           operations change real zrender displayables (Rect, Circle) through
           their own API (setStyle, setShape, attr, remove, add). Before every
           frame each element of the display list and of the previous display
           list is recorded as createRepaintRects reads it (shouldBePainted,
           __isRendered, __dirty & REDRAW_BIT, getPaintRect, getPrevPaintRect,
           in storage); the layer's createRepaintRects is wrapped to record its
           answer (null on the first frame; not called when nothing is dirty).

  node tools/advchart-oracle/coarse-dirty.js

writes tests/fixtures/advchart-coarse-dirty.json (ORACLE_OUT overrides).

Conventions
  hex     a double as the 16 hex digits of its IEEE-754 bits, big-endian
          (NaN 7ff8000000000000); every number the port must match bit for bit
          is written this way.
  rect    [x, y, width, height], each hex.

Top level
  source, notes[], strokeContainThreshold, tspanTolerance, maxRepaintRectCount
  samples[]   {id, pointerSize, x, y, rings: [count per ring], pts: [[hx, hy]]}
              (pts excludes the direct test at (x, y))
  coarse[]    {id, note, W, H, init: {useCoarsePointer?, pointerSize?},
              resolvedPointerSize (the handler's, null = off), option,
              probes: [{x, y, aim, hit: null | {s, d}, direct: null | {s, d},
              top}]}  (s the seriesIndex, d the raw dataIndex; top: findHover
              found a topTarget -- a silent element -- without a target)
  dirty[]     {id, note, W, H, elements: {id: def}, frames: [{ops, list:
              [item], prev: [item], se: [start, end], prevIdx: [start, end],
              rects: null | 'none' | [rect]}]}
              'none': createRepaintRects was not called this frame.
              item: {id, shouldPaint, rendered, dirty, inStorage, box: rect
              (getBoundingRect), paint: rect | null (getPaintRect),
              prevPaint: rect | null}
              def: {type: 'rect' | 'circle', shape, style, z, z2}
  guards[]    self-checks that each must hold (see the end of the file)
*/
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const zrender = echarts.zrender;
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-coarse-dirty.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

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

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
const rectHex = r => (r ? [hex(r.x), hex(r.y), hex(r.width), hex(r.height)] : null);

// ============================================================================
// samples
// ============================================================================
const SAMPLE_CASES = [
  { id: 's44', pointerSize: 44, x: 100, y: 100 },
  { id: 's44-odd-point', pointerSize: 44, x: 37, y: 251 },
  { id: 's45', pointerSize: 45, x: 100, y: 100 },
  { id: 's30', pointerSize: 30, x: 100, y: 100 },
  { id: 's20', pointerSize: 20, x: 100, y: 100 },
  { id: 's9', pointerSize: 9, x: 100, y: 100 },
  { id: 's8', pointerSize: 8, x: 100, y: 100 },
  { id: 's4', pointerSize: 4, x: 100, y: 100 },
  { id: 's1', pointerSize: 1, x: 100, y: 100 },
  { id: 's10.5', pointerSize: 10.5, x: 100, y: 100 },
];

function runSamples(c) {
  const zr = zrender.init(null, { renderer: 'svg', ssr: true, width: 400, height: 400, useCoarsePointer: true, pointerSize: c.pointerSize });
  must(zr.handler._pointerSize === c.pointerSize, c.id + ': pointer size not taken');
  // a 2 x 2 rect whose box meets the pointer rect at its far corner: a
  // candidate (the box test is `intersect`, edges count) that no sample reaches
  const half = c.pointerSize / 2;
  const el = new echarts.graphic.Rect({ shape: { x: c.x + half, y: c.y + half, width: 2, height: 2 }, style: { fill: '#000' } });
  zr.add(el);
  const log = [];
  const orig = el.contain;
  el.contain = function (x, y) { log.push([x, y]); return orig.call(this, x, y); };
  const h = zr.handler.findHover(c.x, c.y);
  must(!h.target, c.id + ': the far rect was hit');
  must(log.length >= 1 && log[0][0] === c.x && log[0][1] === c.y, c.id + ': the direct test is not first');
  const pts = log.slice(1);
  // rings: count consecutive samples by radius
  const rings = [];
  let r = 0;
  let k = 0;
  for (; r < half; r += 4) {
    let n = 0;
    for (let theta = 0; theta < Math.PI * 2; theta += Math.PI / 12) {
      const x1 = c.x + r * Math.cos(theta);
      const y1 = c.y + r * Math.sin(theta);
      must(pts[k] && pts[k][0] === x1 && pts[k][1] === y1, c.id + ': sample ' + k + ' is not (' + x1 + ', ' + y1 + ')');
      k++;
      n++;
    }
    rings.push(n);
  }
  must(k === pts.length, c.id + ': ' + pts.length + ' samples, the transcription walks ' + k);
  zr.dispose();
  return { id: c.id, pointerSize: c.pointerSize, x: c.x, y: c.y, rings, pts: pts.map(p => [hex(p[0]), hex(p[1])]) };
}

// ============================================================================
// coarse pointer on charts
// ============================================================================
const W = 400;
const H = 300;
const GRID = { left: 40, right: 40, top: 40, bottom: 40 };
const VAL = { type: 'value', min: 0, max: 100, splitLine: { show: false } };

const OPT_SCATTER = {
  animation: false, grid: GRID, xAxis: VAL, yAxis: VAL,
  series: [{ type: 'scatter', symbolSize: 4, data: [[20, 50], [50, 50], [54, 50], [80, 20]] }],
};
// x = 40 + 3.2 v, y = 260 - 2.2 v: (104, 150) (200, 150) (212.8, 150) (296, 216)
const P_SCATTER = [
  [104, 150, 'on point 0'],
  [104, 157, 'point 0, 7 below'],
  [104, 160, 'point 0, 10 below'],
  [104, 170, 'point 0, 20 below'],
  [104, 173, 'point 0, 23 below: a candidate no sample reaches'],
  [104, 190, 'point 0, 40 below: no candidate'],
  [117, 150, 'point 0, 13 right'],
  [206, 150, 'between points 1 and 2'],
  [206, 162, 'between points 1 and 2, 12 below'],
  [190, 140, 'point 1, up-left'],
  [296, 236, 'point 3, 20 below'],
  [310, 216, 'point 3, 14 right'],
];
const OPT_LINE = {
  animation: false, grid: GRID, xAxis: VAL, yAxis: VAL,
  series: [{ type: 'line', showSymbol: false, lineStyle: { width: 1 }, data: [[20, 20], [80, 80]] }],
};
// (104, 216) to (296, 84)
const P_LINE = [
  [200, 150, 'on the line'],
  [200, 156, 'line, 6 below'],
  [200, 162, 'line, 12 below'],
  [200, 170, 'line, 20 below'],
  [200, 180, 'line, 30 below'],
  [92, 225, 'past the first end'],
];
const OPT_BARS = {
  animation: false, grid: GRID,
  xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] },
  yAxis: VAL,
  series: [{ type: 'bar', barWidth: 2, data: [30, 60, 45, 80, 20, 55, 70, 40] }],
};
// band 40 wide from x 40: centres 60, 100, ... 340; a bar 2 wide at centre
const P_BARS = [
  [60, 200, 'on bar 0'],
  [70, 200, 'bar 0, 10 right'],
  [80, 200, 'midway between bars 0 and 1'],
  [79, 200, 'one left of midway'],
  [81, 200, 'one right of midway'],
  [100, 110, 'over bar 1, 14 above its top'],
  [140, 180, 'bar 2, inside'],
  [158, 240, 'bar 2, 18 right'],
  [175, 240, 'bar 3, 4 left of its edge'],
  [120, 290, 'under the axis: out of reach'],
];
const OPT_STACK = {
  animation: false, grid: GRID, xAxis: VAL, yAxis: VAL,
  series: [
    { type: 'scatter', symbolSize: 4, data: [[50, 50]] },
    { type: 'scatter', symbolSize: 4, data: [[50, 50]] },
  ],
};
const P_STACK = [
  [200, 150, 'on both: the top one'],
  [200, 155, 'both, 5 below: inside a mouse pad, outside both circles'],
  [200, 162, 'both, 12 below: the coarse walk'],
  [212, 150, 'both, 12 right'],
];

const COARSE_CASES = [
  { id: 'scatter-small', note: 'four 4 px scatter symbols, pointer 44', init: { useCoarsePointer: true }, option: OPT_SCATTER, probes: P_SCATTER },
  { id: 'scatter-20', note: 'the same at pointerSize 20', init: { useCoarsePointer: true, pointerSize: 20 }, option: OPT_SCATTER, probes: P_SCATTER },
  { id: 'scatter-9', note: 'pointerSize 9: rings 0 and 4', init: { useCoarsePointer: true, pointerSize: 9 }, option: OPT_SCATTER, probes: P_SCATTER },
  { id: 'scatter-0', note: 'pointerSize 0 is falsy: no fallback', init: { useCoarsePointer: true, pointerSize: 0 }, option: OPT_SCATTER, probes: P_SCATTER },
  { id: 'scatter-off', note: 'useCoarsePointer false: a mouse', init: { useCoarsePointer: false, pointerSize: 44 }, option: OPT_SCATTER, probes: P_SCATTER },
  { id: 'scatter-auto', note: "'auto' in node: no touch events, off", init: { useCoarsePointer: 'auto' }, option: OPT_SCATTER, probes: P_SCATTER },
  { id: 'thin-line', note: 'a 1 px line without symbols, pointer 44', init: { useCoarsePointer: true }, option: OPT_LINE, probes: P_LINE },
  { id: 'thin-bars', note: 'bars 2 px wide, pointer 44', init: { useCoarsePointer: true }, option: OPT_BARS, probes: P_BARS },
  { id: 'thin-bars-30', note: 'bars 2 px wide, pointer 30', init: { useCoarsePointer: true, pointerSize: 30 }, option: OPT_BARS, probes: P_BARS },
  { id: 'stack', note: 'two series on one spot: direct is the top, coarse the bottom', init: { useCoarsePointer: true }, option: OPT_STACK, probes: P_STACK },
];

let ecKey = null;
function discoverECKey() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  chart.setOption({ animation: false, xAxis: { type: 'category', data: ['a'] }, yAxis: {}, series: [{ type: 'bar', data: [1] }] });
  chart.renderToSVGString();
  const el = chart.getModel().getSeriesByIndex(0).getData().getItemGraphicEl(0);
  for (const k of Object.getOwnPropertyNames(el)) {
    const v = el[k];
    if (v && typeof v === 'object' && hasOwn(v, 'dataIndex') && v.dataIndex === 0 && hasOwn(v, 'seriesIndex')) { ecKey = k; break; }
  }
  chart.dispose();
  must(ecKey !== null, 'the ECData key was not found');
}
function datumOf(el) {
  let e = el;
  while (e) {
    const d = e[ecKey];
    // a line's polyline carries its series and no row: {s, d: null}
    if (d && d.seriesIndex != null) return { s: d.seriesIndex, d: d.dataIndex == null ? null : d.dataIndex };
    e = e.__hostTarget || e.parent;
  }
  return null;
}

function newChart(init) {
  rngState = SEED;
  const opts = Object.assign({ renderer: 'svg', ssr: true, width: W, height: H }, init);
  const chart = echarts.init(null, null, opts);
  chart._ssr = false;
  return chart;
}

function runCoarse(c) {
  const probes = [];
  let resolved;
  for (const p of c.probes) {
    const chart = newChart(c.init);
    chart.setOption(c.option);
    chart.renderToSVGString();
    const handler = chart.getZr().handler;
    resolved = handler._pointerSize;
    const h = handler.findHover(p[0], p[1]);
    must(!h.target || datumOf(h.target), c.id + ': a target without a datum at ' + p[0] + ',' + p[1]);
    const keep = handler._pointerSize;
    handler._pointerSize = undefined;
    const hd = handler.findHover(p[0], p[1]);
    handler._pointerSize = keep;
    probes.push({
      x: p[0], y: p[1], aim: p[2],
      hit: h.target ? datumOf(h.target) : null,
      direct: hd.target ? datumOf(hd.target) : null,
      top: !h.target && !!h.topTarget,
    });
    chart.dispose();
  }
  return { id: c.id, note: c.note, W, H, init: c.init, resolvedPointerSize: resolved === undefined ? null : resolved, option: c.option, probes };
}

// ============================================================================
// dirty rectangles
// ============================================================================
function fakeCanvas(w, h) {
  const ctx = new Proxy({}, {
    get: (t, k) => (k in t ? t[k] : (typeof k === 'string' && /^[a-z]/.test(k) ? function () { return { addColorStop() {} }; } : undefined)),
    set: (t, k, v) => { t[k] = v; return true; },
  });
  return { nodeName: 'CANVAS', width: w, height: h, style: {}, getContext: () => ctx, setAttribute() {}, getAttribute() { return null; } };
}

function R(x, y, w, h, style, extra) {
  return Object.assign({ type: 'rect', shape: { x, y, width: w, height: h }, style: Object.assign({ fill: '#c00' }, style || {}) }, extra || {});
}
function C(cx, cy, r, style, extra) {
  return Object.assign({ type: 'circle', shape: { cx, cy, r }, style: Object.assign({ fill: '#0c0' }, style || {}) }, extra || {});
}

const BARS5 = { b0: R(10, 100, 20, 80), b1: R(50, 60, 20, 120), b2: R(90, 120, 20, 60), b3: R(130, 40, 20, 140), b4: R(170, 90, 20, 90) };
function spread(n) {
  // n small squares on a 6-column lattice, 40 px apart
  const els = {};
  for (let i = 0; i < n; i++) els['e' + i] = R(10 + (i % 6) * 40, 10 + Math.floor(i / 6) * 40, 8, 8);
  return els;
}
function allStyle(n, fill) {
  const ops = [];
  for (let i = 0; i < n; i++) ops.push({ op: 'style', el: 'e' + i, style: { fill } });
  return ops;
}

const DIRTY_CASES = [
  { id: 'hover-style', note: 'a bar restyled and back: the first change has no previous rect (painted only in the full frame)',
    elements: BARS5, frames: [[], [{ op: 'style', el: 'b2', style: { fill: '#f80' } }], [{ op: 'style', el: 'b2', style: { fill: '#c00' } }], []] },
  { id: 'move-after-full', note: 'moving an element painted only in the full frame: upstream adds the new rect only (its old pixels stay)',
    elements: BARS5, frames: [[], [{ op: 'shape', el: 'b1', shape: { x: 260 } }]] },
  { id: 'move-twice', note: 'a second move: the old and the new rect',
    elements: BARS5, frames: [[], [{ op: 'shape', el: 'b1', shape: { x: 260 } }], [{ op: 'shape', el: 'b1', shape: { x: 300, y: 30 } }]] },
  { id: 'overlap-merge', note: 'two changed elements whose rects overlap become one',
    elements: { a: R(10, 10, 40, 40), b: R(45, 30, 40, 40), c: R(200, 200, 10, 10) },
    frames: [[], [{ op: 'style', el: 'a', style: { fill: '#00f' } }, { op: 'style', el: 'b', style: { fill: '#00f' } }]] },
  { id: 'touching', note: 'rects that only touch are merged: intersect counts the edge',
    elements: { a: R(10, 10, 20, 20), b: R(31, 10, 20, 20), c: R(100, 100, 5, 5) },
    frames: [[], [{ op: 'style', el: 'a', style: { fill: '#00f' } }, { op: 'style', el: 'b', style: { fill: '#00f' } }, { op: 'style', el: 'c', style: { fill: '#00f' } }]] },
  { id: 'four', note: 'four disjoint changes: four rects', elements: spread(4), frames: [[], allStyle(4, '#00f')] },
  { id: 'five', note: 'five: the pool is full after the fifth', elements: spread(5), frames: [[], allStyle(5, '#00f')] },
  { id: 'six', note: 'six: the sixth merges into the rect it grows least', elements: spread(6), frames: [[], allStyle(6, '#00f')] },
  { id: 'twelve', note: 'twelve small changes on two rows merged into five', elements: spread(12), frames: [[], allStyle(12, '#00f'), allStyle(12, '#c00')] },
  { id: 'remove', note: 'a removed element: its previous rect from the previous list',
    elements: BARS5, frames: [[], [{ op: 'style', el: 'b3', style: { fill: '#0f0' } }], [{ op: 'remove', el: 'b3' }]] },
  { id: 'add', note: 'an added element: its rect, never rendered',
    elements: BARS5, frames: [[], [{ op: 'add', el: 'n', def: R(220, 20, 30, 30) }]] },
  { id: 'ignore', note: 'ignore on: the previous rect only; off again: the current rect',
    elements: BARS5, frames: [[], [{ op: 'style', el: 'b4', style: { fill: '#0f0' } }], [{ op: 'attr', el: 'b4', attr: { ignore: true } }], [{ op: 'attr', el: 'b4', attr: { ignore: false } }]] },
  { id: 'opacity-0', note: 'opacity 0 is not painted',
    elements: BARS5, frames: [[], [{ op: 'style', el: 'b0', style: { fill: '#0f0' } }], [{ op: 'style', el: 'b0', style: { opacity: 0 } }], [{ op: 'style', el: 'b0', style: { opacity: 1 } }]] },
  { id: 'stroke-shadow', note: 'stroke widths, stroke without fill (strokeContainThreshold 5), shadows',
    elements: {
      a: R(20.5, 20.25, 30, 20, { stroke: '#000', lineWidth: 3 }),
      b: R(80, 20, 30, 20, { fill: null, stroke: '#000', lineWidth: 1 }),
      c: R(140, 20, 30, 20, { shadowBlur: 4, shadowOffsetX: 2, shadowOffsetY: -3, shadowColor: '#000' }),
      d: R(200, 20, 30, 20, { fill: null, stroke: '#000', lineWidth: 7 }),
      e: R(20, 120, 0, 20),
    },
    frames: [[], [{ op: 'style', el: 'a', style: { fill: '#00f' } }, { op: 'style', el: 'b', style: { stroke: '#00f' } }, { op: 'style', el: 'c', style: { fill: '#00f' } }, { op: 'style', el: 'd', style: { stroke: '#00f' } }, { op: 'style', el: 'e', style: { fill: '#00f' } }],
      [{ op: 'style', el: 'a', style: { fill: '#c00' } }, { op: 'style', el: 'c', style: { fill: '#c00' } }]] },
  { id: 'circles', note: 'circles at fractional centres',
    elements: { a: C(30.3, 40.7, 6.2), b: C(80.5, 40.5, 10), c: C(140.25, 90.75, 3.3, { stroke: '#000', lineWidth: 2 }) },
    frames: [[], [{ op: 'style', el: 'a', style: { fill: '#00f' } }, { op: 'style', el: 'b', style: { fill: '#00f' } }, { op: 'style', el: 'c', style: { fill: '#00f' } }],
      [{ op: 'shape', el: 'b', shape: { cx: 82.5 } }]] },
  { id: 'chain', note: 'rects that only meet after merging: the final pass joins them',
    elements: { a: R(10, 10, 20, 20), b: R(60, 10, 20, 20), c: R(25, 25, 40, 5), d: R(200, 200, 4, 4), e: R(250, 10, 4, 4), f: R(10, 200, 4, 4), g: R(150, 150, 4, 4) },
    frames: [[], [{ op: 'style', el: 'a', style: { fill: '#00f' } }, { op: 'style', el: 'b', style: { fill: '#00f' } }, { op: 'style', el: 'd', style: { fill: '#00f' } }, { op: 'style', el: 'e', style: { fill: '#00f' } }, { op: 'style', el: 'f', style: { fill: '#00f' } }, { op: 'style', el: 'g', style: { fill: '#00f' } }, { op: 'style', el: 'c', style: { fill: '#00f' } }]] },
  { id: 'z-order', note: 'a z2 change marks the element dirty: one rect, whatever the order',
    elements: { a: R(10, 10, 40, 40, null, { z2: 1 }), b: R(30, 30, 40, 40, null, { z2: 2 }) },
    frames: [[], [{ op: 'attr', el: 'a', attr: { z2: 3 } }]] },
  { id: 'nothing', note: 'a frame where nothing changed: no rects computed', elements: BARS5, frames: [[], [], []] },
];

function makeEl(def) {
  const Ctor = def.type === 'circle' ? echarts.graphic.Circle : echarts.graphic.Rect;
  const opts = { shape: Object.assign({}, def.shape), style: Object.assign({}, def.style) };
  if (def.z != null) opts.z = def.z;
  if (def.z2 != null) opts.z2 = def.z2;
  return new Ctor(opts);
}

function itemOf(id, el, w, h) {
  const box = el.getBoundingRect();
  const paint = el.getPaintRect();
  return {
    id,
    shouldPaint: el.shouldBePainted(w, h, true, true),
    rendered: !!el.__isRendered,
    dirty: (el.__dirty & 1) !== 0,
    inStorage: !!el.__zr,
    box: rectHex(box),
    paint: rectHex(paint),
    prevPaint: rectHex(el.getPrevPaintRect()),
  };
}

function runDirty(c) {
  const w = 400;
  const h = 300;
  const zr = zrender.init(fakeCanvas(w, h), { renderer: 'canvas', useDirtyRect: true, width: w, height: h });
  const layer = zr.painter.getLayer(0);
  must(layer && typeof layer.createRepaintRects === 'function', c.id + ': no layer');
  let answer;
  let called;
  const origCreate = layer.createRepaintRects;
  layer.createRepaintRects = function (list, prev, vw, vh) {
    called = true;
    const r = origCreate.call(this, list, prev, vw, vh);
    answer = r === null ? null : r.map(rr => [hex(rr.x), hex(rr.y), hex(rr.width), hex(rr.height)]);
    return r;
  };
  const els = {};
  const idOf = new Map();
  for (const id of Object.keys(c.elements)) {
    const el = makeEl(c.elements[id]);
    els[id] = el;
    idOf.set(el, id);
    zr.add(el);
  }
  const frames = [];
  for (const ops of c.frames) {
    for (const o of ops) {
      const el = els[o.el];
      if (o.op === 'style') el.setStyle(o.style);
      else if (o.op === 'shape') el.setShape(o.shape);
      else if (o.op === 'attr') el.attr(o.attr);
      else if (o.op === 'remove') zr.remove(el);
      else if (o.op === 'add') {
        const nel = makeEl(o.def);
        els[o.el] = nel;
        idOf.set(nel, o.el);
        zr.add(nel);
      } else throw new OracleError(c.id + ': op ' + o.op);
    }
    // what createRepaintRects will read: the storage's new list and the
    // painter's previous one
    const list = zr.storage.getDisplayList(true);
    const prevList = zr.painter._prevDisplayList || [];
    const rec = {
      ops,
      list: list.map(el => itemOf(idOf.get(el), el, w, h)),
      prev: prevList.map(el => itemOf(idOf.get(el), el, w, h)),
      prevIdx: [layer.__prevIdx.startIdx, layer.__prevIdx.endIdx],
    };
    called = false;
    answer = undefined;
    zr.refreshImmediately();
    rec.rects = called ? answer : 'none';
    frames.push(rec);
  }
  zr.dispose();
  const defs = {};
  for (const id of Object.keys(c.elements)) defs[id] = c.elements[id];
  for (const ops of c.frames) for (const o of ops) if (o.op === 'add') defs[o.el] = o.def;
  return { id: c.id, note: c.note, W: w, H: h, elements: defs, frames };
}

// ============================================================================
// output
// ============================================================================
function sanitize(v) {
  if (typeof v === 'number') {
    if (Number.isNaN(v)) return null;
    if (v === Infinity) return 'Infinity';
    if (v === -Infinity) return '-Infinity';
    if (Object.is(v, -0)) return '-0';
    return v;
  }
  if (v === undefined) return undefined;
  if (v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return v.map(x => { const s = sanitize(x); return s === undefined ? null : s; });
  const o = {};
  for (const k of Object.keys(v)) {
    const s = sanitize(v[k]);
    if (s !== undefined) o[k] = s;
  }
  return o;
}
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
  if (Array.isArray(v)) return '[\n' + Array.from(v, x => inner + fmt(x === undefined ? null : x, inner)).join(',\n') + '\n' + ind + ']';
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner)).join(',\n') + '\n' + ind + '}';
}

function generate() {
  if (ecKey === null) discoverECKey();
  return {
    samples: SAMPLE_CASES.map(runSamples),
    coarse: COARSE_CASES.map(runCoarse),
    dirty: DIRTY_CASES.map(runDirty),
  };
}

// guards: facts the fixture must show, each read off the upstream source
function guards(g) {
  const out = [];
  const add = (id, ok, note) => out.push({ id, ok: !!ok, note });
  const S = id => g.samples.find(s => s.id === id);
  const Cc = id => g.coarse.find(s => s.id === id);
  const D = id => g.dirty.find(s => s.id === id);
  const probe = (c, x, y) => Cc(c).probes.find(p => p.x === x && p.y === y);
  add('ring-count-25', S('s44').rings.every(n => n === 25), 'theta += PI / 12 accumulates below 2 PI after 24 steps: 25 samples a ring');
  add('rings-44', S('s44').rings.length === 6, 'r = 0, 4, ... 20 < 22: six rings');
  add('rings-45', S('s45').rings.length === 6, 'r < 22.5: still six rings');
  add('rings-8', S('s8').rings.length === 1, 'r < 4: one ring');
  add('rings-9', S('s9').rings.length === 2, 'r < 4.5: two rings');
  add('ring-zero-repeats', S('s44').pts.slice(0, 25).every(p => p[0] === S('s44').pts[0][0] && p[1] === S('s44').pts[0][1]), 'ring 0 asks the same point 25 times');
  add('auto-off', Cc('scatter-auto').resolvedPointerSize === null, "'auto' without touch events: no pointer size");
  add('off-off', Cc('scatter-off').resolvedPointerSize === null, 'useCoarsePointer false: no pointer size');
  add('zero-falsy', Cc('scatter-0').resolvedPointerSize === 0 && Cc('scatter-0').probes.every(p => JSON.stringify(p.hit) === JSON.stringify(p.direct)), 'pointerSize 0 is kept but falsy: never a fallback');
  add('default-44', Cc('scatter-small').resolvedPointerSize === 44, 'the default pointer size');
  add('coarse-finds', probe('scatter-small', 104, 160).hit && !probe('scatter-small', 104, 160).direct, 'a point 10 px off a 4 px symbol: found only by the fallback');
  add('out-of-reach', !probe('scatter-small', 104, 173).hit, '23 px off: a candidate, but r < 22 never reaches');
  add('stack-direct-top', probe('stack', 200, 150).hit.s === 1, 'on both symbols: the top one');
  add('stack-coarse-bottom', probe('stack', 200, 162).hit.s === 0, 'off both: the candidates are walked bottom first');
  add('stack-near-bottom', probe('stack', 200, 155).hit.s === 0 && !probe('stack', 200, 155).direct, '5 px off both: no direct hit, the bottom one by the rings');
  add('line-found', probe('thin-line', 200, 162).hit && !probe('thin-line', 200, 162).direct, 'a 1 px line 12 px away: found by the fallback');
  add('first-frame-null', g.dirty.every(c => c.frames[0].rects === null), 'the first frame paints everything');
  add('nothing-not-called', D('nothing').frames.slice(1).every(f => f.rects === 'none'), 'no dirty element, a clean layer: createRepaintRects is not called');
  add('ghost', D('move-after-full').frames[1].rects.length === 1, 'an element moved after only a full frame: the new rect alone');
  add('move-two', D('move-twice').frames[2].rects.length === 2, 'a second move: old and new');
  add('overlap-one', D('overlap-merge').frames[1].rects.length === 1, 'overlapping rects merge');
  add('touch-one', D('touching').frames[1].rects.length === 2, 'touching rects merge (two left of three)');
  add('four-four', D('four').frames[1].rects.length === 4, 'four disjoint: four');
  add('five-five', D('five').frames[1].rects.length === 5, 'five disjoint: five');
  add('six-five', D('six').frames[1].rects.length === 5, 'six disjoint: still five');
  add('twelve-le-five', D('twelve').frames[1].rects.length <= 5, 'twelve: at most five');
  add('chain-joined', D('chain').frames[1].rects.length < 7, 'the final pass joins what merging made meet');
  return out;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

let json1;
let json2;
let gd;
let g1;
try {
  g1 = generate();
  gd = guards(g1);
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + zrender.version + '; node ' + process.version,
    notes: [
      'findHover (Handler.ts): the direct walk first (setHoverTarget over the whole display list, top first). Only when it found no target and _pointerSize is truthy: candidates = every element of the display list, top first, not ignored, without ignoreCoarsePointer (nor a parent with it), whose box (getBoundingRect through its transform) intersects the pointer rect (x - size / 2, y - size / 2, size, size) -- silent ones included. Then for r = 0; r < size / 2; r += 4 and theta = 0; theta < 2 PI; theta += PI / 12: setHoverTarget(candidates, x + r cos theta, y + r sin theta) -- which walks the candidates from the END of the array, i.e. BOTTOM first -- and the first sample with a target ends the search.',
      'init: useCoarsePointer defaults to \'auto\' (echarts: root.__ECHARTS__DEFAULT__COARSE_POINTER may change the default); \'auto\' or null means env.touchEventsSupported (\'ontouchstart\' in window, not IE / old Edge); a boolean otherwise. pointerSize = retrieve2(opts.pointerSize, 44) only when it is on; the handler tests it for truthiness, so 0 (and NaN) is off. Large series (bar, candlestick, lines, scatter batches) set ignoreCoarsePointer.',
      'createRepaintRects (canvas/Layer.ts): null on the layer\'s first paint. Otherwise, for each element of this frame\'s list (the layer\'s range): shouldPaint = shouldBePainted(w, h, true, true); the previous paint rect joins the pool when it was rendered and (dirty or not to be painted); the current paint rect joins when it is to be painted and (dirty or not rendered). Then for each element of the previous list (the previous range) that is not to be painted or no longer in storage but was rendered: its previous rect. A rect joins only when finite and not zero (width or height exactly 0). Pool: the first rect starts it; a rect is merged (union) into the FIRST pool rect it intersects (edges touching count); once the pool reached maxRepaintRectCount (5) it is "full" and a rect that meets none is merged into the rect whose union grows the least (area of union - both areas; the first of equals); otherwise it starts a new pool rect. Finally a loop merges any two pool rects that intersect (dropping zero ones) until none do.',
      'getPaintRect (Displayable.ts): the box (getBoundingRect -- for a path the path box grown by the line width when stroked, by max(lineWidth, strokeContainThreshold 5) when it has no fill; through the transform), grown by the shadow (width += 2 blur + |offsetX|, x = min(x, x + offsetX - blur), likewise y), then when not zero: x = floor(x - tolerance), y = floor(y - tolerance), width = ceil(width + 1 + 2 tolerance), height likewise. tolerance is 0, 10 for a TSpan.',
      'Bookkeeping (Painter._paintPerCursorInRect / graphic.brush): with rects, each rect clips and every element of the list whose CURRENT paint rect intersects it is brushed and gets setPrevPaintRect(paint rect); a brushed element that is not to be painted is marked not rendered. On a full paint (no rects -- the first frame) elements are brushed WITHOUT setPrevPaintRect, so an element painted only in full frames has no previous rect: moving it later adds only its new rect (case move-after-full) and its old pixels stay on the canvas.',
      'An empty array (nothing dirty but the layer flagged) paints nothing; a frame with no dirty element and a clean layer never calls createRepaintRects (case nothing).',
    ],
    strokeContainThreshold: echarts.graphic.Rect.prototype.strokeContainThreshold,
    tspanTolerance: 10,
    maxRepaintRectCount: 5,
    samples: g1.samples,
    coarse: g1.coarse,
    dirty: g1.dirty,
    guards: gd,
  };
  json1 = fmt(sanitize(out), '') + '\n';
  must(json1.indexOf('\\u0000') < 0, 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(sanitize(out)), 'the written JSON does not parse back');
  const g2 = generate();
  json2 = fmt(sanitize(Object.assign({}, out, { samples: g2.samples, coarse: g2.coarse, dirty: g2.dirty, guards: guards(g2) })), '') + '\n';
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
const bad = gd.filter(x => !x.ok);
gd.forEach(x => console.log('guard ' + (x.ok ? 'ok  ' : 'FAIL') + ' ' + x.id + ': ' + x.note));
const deterministic = json1 === json2;
console.log(g1.samples.length + ' sample walks, ' + g1.coarse.length + ' coarse cases (' + g1.coarse.reduce((a, c) => a + c.probes.length, 0) + ' probes), '
  + g1.dirty.length + ' dirty cases (' + g1.dirty.reduce((a, c) => a + c.frames.length, 0) + ' frames); '
  + (gd.length - bad.length) + '/' + gd.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; '
  + json1.length + ' bytes; ' + logged.length + ' console messages' + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
