// D5 UT1 (batch 136): universalTransition, one to one -- the morphing engine and the
// whole-chart transitions between series of different types on the same data.
//
// Two parts, both from the real ECharts 6.1 dist:
//   engine  zrender's morphing code (tool/convertPath.ts, tool/dividePath.ts,
//           tool/morphPath.ts) cut out of the bundle and run on PathProxy data
//           that real zrender elements built: pathToBezierCurves, pathToPolygons,
//           alignBezierCurves, centroid, findBestRingOffset, reverse,
//           findBestMorphingRotation, applyTransformOnBeziers, the morph path at
//           several t (prepareMorphPath on real elements, its buildPath), split
//           (the dividers), hilbert and prepareMorphBatches.
//   charts  setOption(option) at T0, run out; setOption(next, notMerge) at T1 =
//           T0 + 10000, recorded at T1 + each sample: every item element of the
//           new series -- whether it is morphing, the morph path its replaced
//           buildPath draws (a fresh PathProxy), its style, its transform and
//           shape keys -- and every other path of the new series' views (the
//           fades).
// The clock harness is animation.js' (the replaced Date before the dist,
// chart._ssr = false, env.node = false, the seeded Math.random, hand-stepped
// frames).
// Run: node tools/advchart-oracle/universal-transition.js
//   -> tests/fixtures/advchart-universal-transition.json
'use strict';
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-universal-transition.json');

echarts.env.node = false;

const W = 400;
const H = 300;
const SAMPLES = [0, 1, 16, 50, 100, 150, 250, 300, 400, 499, 500, 501, 750, 1000, 1500];

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

// ---------- number records ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (v === undefined) v = NaN;
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hexes = a => Array.from(a, hex);

// ---------- functions in options ----------
const FNS = {
  'idx*50': idx => idx * 50,
  'ut120': (idx, count) => 120 + idx * 50 + (count - 1) * 1000,
};
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

// ---------- the compact writer of animation.js ----------
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

// ---------------------------------------------------------------------------
// the dist's own morphing code, cut out of the bundle
// ---------------------------------------------------------------------------
const SRC = fs.readFileSync(DIST, 'utf8');
function slice(from, to) {
  const a = SRC.indexOf(from);
  must(a >= 0, 'the dist has no ' + JSON.stringify(from));
  const b = SRC.indexOf(to, a + from.length);
  must(b > a, 'the dist has no ' + JSON.stringify(to) + ' after ' + JSON.stringify(from));
  must(SRC.indexOf(from, a + 1) < 0, 'the dist has two ' + JSON.stringify(from));
  return SRC.slice(a, b);
}
const Path = Object.getPrototypeOf(echarts.graphic.Rect.prototype).constructor;
const PathProxy = new echarts.graphic.Rect({ shape: { x: 0, y: 0, width: 1, height: 1 } }).getUpdatedPathProxy().constructor;
const ENGINE_SRC = [
  slice('function cubicSubdivide(p0, p1, p2, p3, t, out) {', '    function cubicProjectPoint('),
  slice('function fromPoints(points, min, max) {', '    function fromLine('),
  slice('function lerp(out, v1, v2, t) {', '    function applyTransform(out, v, m) {'),
  slice('var Point = (function () {\n        function Point(x, y) {', '\n    }());') + '\n    }());',
  slice('var CMD$4 = PathProxy.CMD;', '    function hilbert(x, y, minX, minY, maxX, maxY) {'),
  slice('function hilbert(x, y, minX, minY, maxX, maxY) {', '    function defaultDividePath(param) {'),
  slice('function prepareMorphBatches(one, many) {', '    var pathDividers = {'),
].join('\n');
const ENGINE = new Function('PathProxy', 'Rect', 'Sector', 'Polygon', 'BoundingRect', 'map', 'defaults', 'clonePath',
  'mathMin$2', 'mathMax$2',
  ENGINE_SRC + '\nreturn { cubicSubdivide: cubicSubdivide, pathToBezierCurves: pathToBezierCurves, '
  + 'pathToPolygons: pathToPolygons, alignBezierCurves: alignBezierCurves, centroid: centroid$1, '
  + 'findBestRingOffset: findBestRingOffset, reverse: reverse, findBestMorphingRotation: findBestMorphingRotation, '
  + 'applyTransformOnBeziers: applyTransformOnBeziers, prepareMorphPath: prepareMorphPath, split: split, '
  + 'hilbert: hilbert, sortPaths: sortPaths, prepareMorphBatches: prepareMorphBatches, '
  + 'getDividingGrids: getDividingGrids };')(
  PathProxy, echarts.graphic.Rect, echarts.graphic.Sector, echarts.graphic.Polygon, echarts.graphic.BoundingRect,
  echarts.util.map, echarts.util.defaults, () => { throw new OracleError('clonePath reached'); },
  Math.min, Math.max);
const CMD = PathProxy.CMD;
must(CMD.M === 1 && CMD.L === 2 && CMD.C === 3 && CMD.Q === 4 && CMD.A === 5 && CMD.Z === 6 && CMD.R === 7,
  'PathProxy.CMD is not M1 L2 C3 Q4 A5 Z6 R7');

// a fresh PathProxy's data for an element's buildPath (the replaced one while it morphs)
function builtData(el) {
  const pp = new PathProxy(false);
  pp.beginPath();
  el.buildPath(pp, el.shape, false);
  return Array.from(pp.data.slice(0, pp.len()));
}
function proxyData(el) {
  const pp = el.getUpdatedPathProxy();
  return Array.from(pp.data.slice(0, pp.len()));
}
function fakeProxy(data) {
  return { data, len: () => data.length };
}

// ---------------------------------------------------------------------------
// the engine cases
// ---------------------------------------------------------------------------
const G = echarts.graphic;
function shapes() {
  // every input is the PathProxy data a real element built
  const out = {};
  const put = (id, el) => { out[id] = proxyData(el); };
  put('rect', new G.Rect({ shape: { x: 10, y: 20, width: 60, height: 40 } }));
  put('rect.neg', new G.Rect({ shape: { x: 75.5, y: 220, width: 69, height: -19.375 } }));
  put('rect.r', new G.Rect({ shape: { x: 10, y: 20, width: 60, height: 40, r: 6 } }));
  put('rect.r4', new G.Rect({ shape: { x: 0, y: 0, width: 50, height: 80, r: [10, 0, 5, 20] } }));
  put('sector', new G.Sector({ shape: { cx: 200, cy: 150, r0: 0, r: 75, startAngle: -Math.PI / 2, endAngle: 0.4, clockwise: true } }));
  put('sector.ring', new G.Sector({ shape: { cx: 200, cy: 150, r0: 40, r: 90, startAngle: 1, endAngle: 3.5, clockwise: true } }));
  put('sector.anti', new G.Sector({ shape: { cx: 100, cy: 100, r0: 0, r: 50, startAngle: 2, endAngle: 0.3, clockwise: false } }));
  put('sector.full', new G.Sector({ shape: { cx: 0, cy: 0, r0: 0, r: 30, startAngle: 0, endAngle: Math.PI * 2, clockwise: true } }));
  put('sector.corner', new G.Sector({ shape: { cx: 150, cy: 150, r0: 20, r: 80, startAngle: 0.2, endAngle: 1.9, clockwise: true, cornerRadius: 6 } }));
  put('circle', new G.Circle({ shape: { cx: 5, cy: 7, r: 3 } }));
  put('polygon', new G.Polygon({ shape: { points: [[0, 0], [40, 5], [55, 40], [20, 60], [-10, 30]] } }));
  put('polyline', new G.Polyline({ shape: { points: [[0, 0], [30, 10], [60, 0], [90, 20]] } }));
  put('triangle', echarts.graphic.makePath('M0,-10L9,6L-9,6Z', {}, { x: -10, y: -10, width: 20, height: 20 }, 'center'));
  put('two', echarts.graphic.makePath('M0,0L10,0L10,10L0,10ZM20,20L30,20L30,30L20,30Z', {}, null, 'center'));
  put('quad', echarts.graphic.makePath('M0,0Q20,40,40,0L40,20Z', {}, null, 'center'));
  put('three', echarts.graphic.makePath('M0,0L10,0L5,8ZM20,0L30,0L25,8ZM40,0L50,0L45,8Z', {}, null, 'center'));
  put('arcfirst', (() => {
    const p = new G.Arc({ shape: { cx: 30, cy: 30, r: 20, startAngle: 0.3, endAngle: 2.2, clockwise: true } });
    return p;
  })());
  return out;
}

function engineCases() {
  const E = ENGINE;
  const S = shapes();
  const cases = [];
  // pathToBezierCurves
  for (const id of Object.keys(S)) {
    const curves = E.pathToBezierCurves(fakeProxy(S[id]));
    cases.push({ id: 'bez.' + id, kind: 'bezier', data: hexes(S[id]), out: curves.map(hexes) });
  }
  // pathToPolygons at two scales
  for (const id of ['sector', 'rect.r', 'quad', 'circle']) {
    for (const scale of [1, 3.5]) {
      const polys = E.pathToPolygons(fakeProxy(S[id]), scale);
      cases.push({ id: 'poly.' + id + '@' + scale, kind: 'polygons', data: hexes(S[id]), scale: hex(scale), out: polys.map(hexes) });
    }
  }
  // align + rotation on pairs: different segment counts, subpath counts, offsets
  const PAIRS = [
    ['rect', 'sector'], ['sector', 'rect'], ['rect.neg', 'sector.ring'], ['rect', 'rect.r'], ['circle', 'rect'],
    ['rect', 'two'], ['two', 'rect'], ['three', 'two'], ['sector.anti', 'rect'], ['polygon', 'triangle'],
    ['rect.r4', 'sector.corner'], ['quad', 'polygon'], ['arcfirst', 'rect'], ['sector.full', 'triangle'],
    ['rect', 'rect'],
  ];
  for (const [a, b] of PAIRS) {
    const ca = E.pathToBezierCurves(fakeProxy(S[a]));
    const cb = E.pathToBezierCurves(fakeProxy(S[b]));
    const [na, nb] = E.alignBezierCurves(ca, cb);
    const cps = na.map((sp, i) => ({ from: hexes(E.centroid(sp)), to: hexes(E.centroid(nb[i])) }));
    const offsets = na.map((sp, i) => E.findBestRingOffset(sp, nb[i], E.centroid(sp), E.centroid(nb[i])));
    // findBestMorphingRotation clones nothing it is handed; feed copies
    const rot = E.findBestMorphingRotation(na.map(x => x.slice()), nb.map(x => x.slice()), 10, Math.PI);
    cases.push({
      id: 'align.' + a + '>' + b, kind: 'align', from: hexes(S[a]), to: hexes(S[b]),
      alignedFrom: na.map(hexes), alignedTo: nb.map(hexes), centroids: cps, offsets,
      reversed: na.map(sp => hexes(E.reverse(sp))),
      morph: rot.map(m => ({ from: hexes(m.from), to: hexes(m.to), fromCp: hexes(m.fromCp), toCp: hexes(m.toCp),
        rotation: hex(m.rotation) })),
    });
  }
  // applyTransformOnBeziers
  {
    const c = E.pathToBezierCurves(fakeProxy(S['sector.ring']));
    const m = [2, 0.5, -0.25, 1.5, 30.125, -7];
    const before = c.map(hexes);
    E.applyTransformOnBeziers(c, m);
    cases.push({ id: 'transform', kind: 'transform', curves: before, m: hexes(m), out: c.map(hexes) });
  }
  // THE MORPH PATH: prepareMorphPath on real elements (transforms included),
  // the replaced buildPath at several t
  const TS = [0, 1e-9, 0.1, 0.25, 1 / 3, 0.5, 0.75, 0.999, 1];
  const mk = (type, shape, attrs) => {
    const el = new G[type]({ shape });
    if (attrs) el.attr(attrs);
    return el;
  };
  const MORPHS = [
    ['bar>sector', () => mk('Rect', { x: 75.5, y: 220, width: 69, height: -19.375 }),
      () => mk('Sector', { cx: 200, cy: 150, r0: 0, r: 75, startAngle: -Math.PI / 2, endAngle: -0.8, clockwise: true })],
    ['sector>bar', () => mk('Sector', { cx: 200, cy: 150, r0: 30, r: 75, startAngle: 0.5, endAngle: 2.8, clockwise: true }),
      () => mk('Rect', { x: 175.5, y: 220, width: 69, height: -77.5 })],
    ['bar>circle.t', () => mk('Rect', { x: 10, y: 50, width: 30, height: 100 }),
      () => mk('Circle', { cx: 0, cy: 0, r: 1 }, { x: 120, y: 80, scaleX: 10, scaleY: 10 })],
    ['circle.t>bar', () => mk('Circle', { cx: 0, cy: 0, r: 1 }, { x: 120, y: 80, scaleX: 5, scaleY: 3, rotation: 0.4 }),
      () => mk('Rect', { x: 100, y: 60, width: 40, height: 90, r: 4 })],
    ['ring>ring', () => mk('Sector', { cx: 100, cy: 100, r0: 20, r: 60, startAngle: 0, endAngle: 1.2, clockwise: true }),
      () => mk('Sector', { cx: 120, cy: 90, r0: 10, r: 80, startAngle: 2, endAngle: 4.1, clockwise: false })],
    ['poly>rect', () => mk('Polygon', { points: [[0, 0], [40, 5], [55, 40], [20, 60], [-10, 30]] }),
      () => mk('Rect', { x: 10, y: 10, width: 20, height: 30 })],
    ['rect>rect', () => mk('Rect', { x: 10, y: 10, width: 20, height: 30 }),
      () => mk('Rect', { x: 60, y: -10, width: 50, height: 10 })],
  ];
  for (const [id, mf, mt] of MORPHS) {
    const from = mf();
    const to = mt();
    E.prepareMorphPath(from, to);
    const frames = TS.map(t => {
      to.__morphT = t;
      return hexes(builtData(to));
    });
    cases.push({ id: 'morph.' + id, kind: 'morph', ts: hexes(TS), fromData: hexes(proxyData(from)),
      fromM: from.getComputedTransform() ? hexes(from.getComputedTransform()) : null,
      toData: hexes((() => { const t = mt(); return proxyData(t); })()),
      toM: (() => { const t = mt(); const m = t.getComputedTransform(); return m ? hexes(m) : null; })(),
      frames });
  }
  // THE DIVIDERS (dividePath.ts split): rect, sector, circle, the polygon
  // fallback; each piece's shape
  const DIVS = [
    ['rect', () => mk('Rect', { x: 10, y: 20, width: 60, height: 40 }), [1, 2, 3, 5, 7, 12]],
    ['rect.tall', () => mk('Rect', { x: 0, y: 0, width: 10, height: 100 }), [2, 4, 6]],
    ['rect.neg', () => mk('Rect', { x: 75.5, y: 220, width: 69, height: -19.375 }), [3]],
    ['sector', () => mk('Sector', { cx: 200, cy: 150, r0: 10, r: 75, startAngle: -1, endAngle: 0.4, clockwise: true }), [1, 2, 3, 5, 9]],
    ['sector.thin', () => mk('Sector', { cx: 0, cy: 0, r0: 40, r: 90, startAngle: 0, endAngle: 0.1, clockwise: false }), [4]],
    ['circle', () => mk('Circle', { cx: 5, cy: 7, r: 30 }), [1, 4, 7]],
    ['polygon', () => mk('Polygon', { points: [[0, 0], [40, 5], [55, 40], [20, 60], [-10, 30]] }), [1, 2, 3, 4, 6]],
    ['two', () => echarts.graphic.makePath('M0,0L10,0L10,10L0,10ZM20,20L30,20L30,40L20,40Z', {}, null, 'center'), [2, 3, 5]],
    ['three', () => echarts.graphic.makePath('M0,0L10,0L5,8ZM20,0L30,0L25,8ZM40,0L50,0L45,8Z', {}, null, 'center'), [3, 4]],
    ['polygon.scaled', () => mk('Polygon', { points: [[0, 0], [4, 1], [5, 4], [1, 6]] }, { scaleX: 3, scaleY: 2 }), [3]],
  ];
  for (const [id, f, counts] of DIVS) {
    for (const count of counts) {
      const el = f();
      const pieces = E.split(el, count);
      cases.push({
        id: 'split.' + id + '#' + count, kind: 'split', type: el.type, count,
        data: hexes(proxyData(f())), m: el.getComputedTransform() ? hexes(el.getComputedTransform()) : null,
        shape: (() => {
          const o = {};
          for (const k of ['x', 'y', 'width', 'height', 'cx', 'cy', 'r0', 'r', 'startAngle', 'endAngle']) {
            if (typeof el.shape[k] === 'number') o[k] = hex(el.shape[k]);
          }
          if (el.type === 'sector') o.clockwise = el.shape.clockwise;
          return o;
        })(),
        pieces: pieces.map(p => {
          const o = { type: p.type };
          if (p.type === 'polygon') o.points = (p.shape.points || []).map(pt => hexes(pt));
          else for (const k of ['x', 'y', 'width', 'height', 'cx', 'cy', 'r0', 'r', 'startAngle', 'endAngle']) {
            if (p.shape[k] != null) o[k] = hex(p.shape[k]);
          }
          if (p.type === 'sector') o.clockwise = p.shape.clockwise === undefined ? null : p.shape.clockwise;
          return o;
        }),
      });
    }
  }
  // getDividingGrids
  const GRIDS = [[[60, 40], 0, 5], [[10, 100], 1, 6], [[1, 0], 0, 3], [[0, 0], 0, 4], [[3, 7], 0, 1], [[100, 1], 0, 7]];
  cases.push({ id: 'grids', kind: 'grids',
    rows: GRIDS.map(([dim, rowDim, count]) => ({ dim: hexes(dim), rowDim, count, out: E.getDividingGrids(dim, rowDim, count) })) });
  // hilbert
  const HIL = [[0, 0, 0, 0, 10, 10], [10, 10, 0, 0, 10, 10], [3, 7, 0, 0, 10, 10], [7, 3, 0, 0, 10, 10], [5, 5, 5, 5, 5, 5],
    [-20.5, 13.25, -40, 0, 60, 30], [123.456, 78.9, 100, 50, 300, 200], [299.9, 50.1, 100, 50, 300, 200],
    [NaN, 3, 0, 0, 10, 10], [1, 2, 1, 0, 1, 10]];
  cases.push({ id: 'hilbert', kind: 'hilbert', rows: HIL.map(r => ({ in: hexes(r), out: hex(E.hilbert(...r)) })) });
  // prepareMorphBatches (ids for paths)
  const BATCHES = [[[0], [[10]]], [[0, 1, 2], [[10, 11, 12, 13, 14, 15, 16]]], [[0, 1, 2, 3], [[10, 11]]],
    [[0, 1, 2, 3, 4], [[10, 11, 12]]], [[0, 1], [[10], [20, 21, 22]]], [[0, 1, 2, 3, 4, 5], [[10, 11, 12, 13]]],
    [[0, 1, 2], [[10]]],
    // milestone D5-D8: batches that do average (two lists over four), and the
    // wrap-round once a source has one path left (five)
    [[0, 1, 2, 3], [[10, 11], [20, 21]]], [[0, 1, 2, 3, 4], [[10, 11], [20, 21]]],
    [[0, 1, 2, 3, 4, 5], [[10, 11, 12], [20, 21, 22]]]];
  cases.push({ id: 'batches', kind: 'batches',
    rows: BATCHES.map(([one, many]) => ({ one, many, out: E.prepareMorphBatches(one, many).map(b => ({ one: b.one, many: b.many })) })) });
  return cases;
}

// ---------------------------------------------------------------------------
// the charts
// ---------------------------------------------------------------------------
function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function clipCount(zr) {
  let n = 0;
  for (let c = zr.animation._head; c; c = c.next) n++;
  return n;
}
function settle(chart, start) {
  const zr = chart.getZr();
  for (let t = 16; t <= 5000; t += 250) {
    NOW = start + t;
    zr.animation.update();
  }
  zr.storage.getDisplayList(true);
  must(clipCount(zr) === 0, 'the first render did not settle');
}
function itemPaths(el) {
  const out = [];
  if (!el) return out;
  el.traverse(e => {
    if ((e instanceof Path) && !e.disableMorphing && !e.invisible && !e.ignore) out.push(e);
  });
  return out;
}
function styleOf(el) {
  const s = el.style;
  const col = v => (v == null ? null : String(v));
  return { fill: col(s.fill), stroke: col(s.stroke), lineWidth: s.lineWidth == null ? null : hex(s.lineWidth),
    opacity: s.opacity == null ? null : hex(s.opacity) };
}
const SNAP_KEYS = ['x', 'y', 'scaleX', 'scaleY', 'rotation'];
function snapOf(el, groupOf) {
  const o = {};
  for (const k of SNAP_KEYS) if (typeof el[k] === 'number') o[k] = hex(el[k]);
  if (el.shape) for (const k of Object.keys(el.shape)) if (typeof el.shape[k] === 'number') o['shape.' + k] = hex(el.shape[k]);
  if (groupOf) for (const k of SNAP_KEYS) if (typeof groupOf[k] === 'number') o['g.' + k] = hex(groupOf[k]);
  return o;
}

// one timeline: the new series' item elements and the views' other paths
function record(chart, start) {
  const zr = chart.getZr();
  const recs = new Map();
  const order = [];
  const rec = (id, base) => {
    let r = recs.get(id);
    if (!r) {
      r = Object.assign({ id, present: new Array(SAMPLES.length).fill(false), morph: new Array(SAMPLES.length).fill(false),
        d: new Array(SAMPLES.length).fill(null), style: {}, snap: {}, anim: new Array(SAMPLES.length).fill(0) }, base);
      recs.set(id, r);
      order.push(r);
    }
    return r;
  };
  const clips = [];
  SAMPLES.forEach((t, si) => {
    NOW = start + t;
    if (si > 0) zr.animation.update();
    zr.storage.getDisplayList(true);
    clips.push(clipCount(zr));
    const model = chart.getModel();
    model.eachSeries(s => {
      const view = chart.getViewOfSeriesModel(s);
      const data = s.getData();
      const seen = new Set();
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        itemPaths(el).forEach((p, k) => {
          seen.add(p);
          const r = rec('s' + s.seriesIndex + '/' + i + '/' + k, { series: s.seriesIndex, type: p.type,
            seriesType: s.subType, dataIndex: i, item: true });
          r.present[si] = true;
          const morphing = p.__morphT >= 0;
          r.morph[si] = morphing;
          if (morphing) r.d[si] = hexes(builtData(p));
          const st = styleOf(p);
          for (const k2 of Object.keys(st)) {
            (r.style[k2] = r.style[k2] || new Array(SAMPLES.length).fill(null))[si] = st[k2];
          }
          const parent = p.parent && p.parent !== view.group && p.parent.parent ? p.parent : null;
          const sn = snapOf(p, parent);
          for (const k2 of Object.keys(sn)) {
            (r.snap[k2] = r.snap[k2] || new Array(SAMPLES.length).fill(null))[si] = sn[k2];
          }
          r.anim[si] = p.animators.length + (parent ? parent.animators.length : 0);
        });
      });
      let k = 0;
      view.group.traverse(e => {
        if (!(e instanceof Path) || seen.has(e)) return;
        const r = rec('s' + s.seriesIndex + '/x/' + (k++), { series: s.seriesIndex, type: e.type, seriesType: s.subType,
          item: false });
        r.present[si] = true;
        const op = e.style.opacity == null ? null : hex(e.style.opacity);
        (r.style.opacity = r.style.opacity || new Array(SAMPLES.length).fill(null))[si] = op;
        r.anim[si] = e.animators.length;
      });
    });
  });
  // compact: a key constant over the samples where present is kept once
  const out = order.map(r => {
    const o = { id: r.id, series: r.series, type: r.type, seriesType: r.seriesType, item: r.item };
    if (r.item) o.dataIndex = r.dataIndex;
    o.present = r.present.every(x => x) ? null : r.present;
    o.morph = r.morph.some(x => x) ? r.morph : null;
    if (o.morph) o.d = r.d;
    o.style = {};
    for (const k of Object.keys(r.style)) o.style[k] = r.style[k];
    o.snap = {};
    for (const k of Object.keys(r.snap)) o.snap[k] = r.snap[k];
    o.anim = r.anim;
    return o;
  });
  return { clips, elements: out };
}

const T1_OFFSET = 10000;
function runCase(option, next, mid, then) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  try {
    chart.setOption(materialize(option));
    let t1;
    if (mid != null) {
      // the next option arrives while the first one's enter still runs
      const zr = chart.getZr();
      for (const t of [16, mid / 2, mid]) {
        NOW = T_BASE + t;
        zr.animation.update();
      }
      t1 = T_BASE + mid;
    }
    else {
      settle(chart, T_BASE);
      t1 = T_BASE + T1_OFFSET;
    }
    NOW = t1;
    chart.setOption(materialize(next), true);
    if (then) {
      // a third option while the second one's transition runs
      const zr = chart.getZr();
      for (const t of [16, then.at / 2, then.at]) {
        NOW = t1 + t;
        zr.animation.update();
      }
      t1 = t1 + then.at;
      NOW = t1;
      chart.setOption(materialize(then.next), true);
    }
    const tl = record(chart, t1);
    const resolved = [];
    chart.getModel().eachSeries(s => resolved.push({ seriesIndex: s.seriesIndex, type: s.subType, id: s.id.replace(/\0/g, '<0>'),
      ut: !!s.isUniversalTransitionEnabled(), animation: !!s.isAnimationEnabled(), count: s.getData().count() }));
    return { resolved, clips: tl.clips, elements: tl.elements };
  }
  finally {
    chart.dispose();
  }
}

// the default palette, written out so the port (whose palette is its skin's)
// paints the same colours
const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
const CATS = ['A', 'B', 'C', 'D'];
const VALS = [5, 20, 36, 10];
const named = (names, vals) => names.map((n, i) => ({ name: n, value: vals[i] }));
const cart = (series, cats) => ({ color: PALETTE, xAxis: { type: 'category', data: cats || CATS }, yAxis: { type: 'value' },
  series: [series] });
const solo = series => ({ color: PALETTE, series: [series] });
const bar = (extra, vals) => cart(Object.assign({ type: 'bar', universalTransition: true, data: vals || VALS }, extra || {}));
const pie = (extra, data) => solo(Object.assign({ type: 'pie', universalTransition: true, radius: '60%', label: { show: false },
  data: data || named(CATS, VALS) }, extra || {}));
const scatter = (extra, vals) => cart(Object.assign({ type: 'scatter', universalTransition: true, symbolSize: 20,
  data: vals || VALS }, extra || {}));
const line = (extra, vals) => cart(Object.assign({ type: 'line', universalTransition: true, data: vals || VALS }, extra || {}));

function chartCases() {
  const list = [];
  const add = (id, note, option, next, mid, then) => list.push({ id, note, option, next, mid: mid == null ? null : mid,
    then: then || null });
  add('bar-pie', 'four bars become four slices: the ids are the category names on both sides', bar(), pie());
  add('pie-bar', 'four slices become four bars', pie(), bar());
  add('bar-scatter', 'bars become scatter symbols (circles, symbol transform)', bar(), scatter());
  add('scatter-bar', 'scatter symbols become bars: the symbol opacity 0.8 goes to the bar\'s 1', scatter(), bar());
  add('line-bar', 'a line\'s empty circles become bars; the polyline goes with its view', line(), bar());
  add('bar-line', 'bars become a line\'s symbols; the polyline has no animator and fades in', bar(), line());
  add('scatter-pie.triangle', 'turned triangles (symbolRotate 30, size [24, 16]) become slices',
    scatter({ symbol: 'triangle', symbolRotate: 30, symbolSize: [24, 16] }), pie());
  add('pie-bar.ring', 'a ring (radius 30% - 60%) becomes bars', pie({ radius: ['30%', '60%'] }), bar());
  add('bar-pie.round', 'bars with borderRadius 6 become slices', bar({ itemStyle: { borderRadius: 6 } }), pie());
  add('bar-pie.horizontal', 'horizontal bars (a category y axis) become slices',
    { color: PALETTE, yAxis: { type: 'category', data: CATS }, xAxis: { type: 'value' },
      series: [{ type: 'bar', universalTransition: true, data: VALS }] }, pie());
  add('bar-pie.border', 'bars with a border and an opacity: stroke, lineWidth and opacity are the old style\'s own keys',
    bar({ itemStyle: { borderColor: '#333333', borderWidth: 3, opacity: 0.5 } }), pie({ itemStyle: { borderColor: '#ffffff', borderWidth: 2 } }));
  add('bar-pie.ids', 'both series carry id "sales": the same transition key', bar({ id: 'sales' }), pie({ id: 'sales' }));
  add('bar-pie.otherid', 'series ids differ ("a", "b"): no batch, the pie enters as a new view', bar({ id: 'a' }), pie({ id: 'b' }));
  add('bar-pie.seriesKey', 'ids differ but universalTransition.seriesKey is "k" on both',
    bar({ id: 'a', universalTransition: { enabled: true, seriesKey: 'k' } }),
    pie({ id: 'b', universalTransition: { enabled: true, seriesKey: 'k' } }));
  add('bar-pie.offnew', 'the pie has no universalTransition: it enters', bar(), pie({ universalTransition: false }));
  add('bar-pie.offold', 'only the pie asks for it: the old series is still a source', bar({ universalTransition: false }), pie());
  add('bar-pie.enabledfalse', 'universalTransition: {enabled: false} on the pie', bar(), pie({ universalTransition: { enabled: false } }));
  add('bar-pie.animoff', 'the pie does not animate (animation: false): no transition', bar(), pie({ animation: false }));
  add('bar-pie.unmatched', 'A, B morph; C and D have no old element by their names (E, F): they enter, C and D of the bars go',
    bar(), pie({}, named(['A', 'B', 'E', 'F'], VALS)));
  add('bar-pie.dataid', 'item ids x1..x4 on both sides, names that differ', bar({}, VALS.map((v, i) => ({ value: v, id: 'x' + i }))),
    pie({}, VALS.map((v, i) => ({ value: v, id: 'x' + i, name: 'n' + i }))));
  add('bar-pie.nullold', 'bar B is null (no element): slice B fades in (initProps, enter timing)', bar({}, [5, null, 36, 10]), pie());
  add('bar-pie.timing', 'the pie\'s update timing: 800 ms linear, delay idx * 50',
    bar(), pie({ animationDurationUpdate: 800, animationEasingUpdate: 'linear', animationDelayUpdate: { $fn: 'idx*50' } }));
  add('bar-pie.delay', 'universalTransition.delay (idx, count) => 120 + idx * 50 + (count - 1) * 1000: one to one is (0, 1)',
    bar(), pie({ universalTransition: { enabled: true, delay: { $fn: 'ut120' } } }));
  add('bar-pie.split', 'divideShape split: no division one to one', bar(), pie({ universalTransition: { enabled: true, divideShape: 'split' } }));
  add('bar-pie.clone', 'divideShape clone: no division one to one', bar(), pie({ universalTransition: { enabled: true, divideShape: 'clone' } }));
  add('bar-bar.style', 'the same series, recoloured: the same elements, their style from the old one (animateElementStyles)',
    bar(), bar({ itemStyle: { color: '#ff0000' } }, [5, 25, 36, 10]));
  add('bar-pie.inflight', 'the pie arrives 300 ms into the bars\' enter: the bars morph from where they are',
    bar(), pie(), 300);
  add('line-scatter', 'a line\'s symbols become scatter symbols', line(), scatter());
  add('scatter-scatter.symbol', 'the same scatter series, its symbol rect -> circle: SymbolDraw makes new symbols, which morph',
    scatter({ symbol: 'rect' }), scatter({ symbol: 'circle' }));
  add('scatter-scatter.symbolmove', 'the symbol changes, and the points and the size: the old rects morph from where they were',
    scatter({ symbol: 'rect' }), scatter({ symbol: 'circle', symbolSize: 30 }, [8, 15, 30, 22]));
  add('bar-pie-bar.inflight', 'bars -> slices, and 200 ms into that morph bars again: the slices morph back from where they are',
    bar(), pie(), null, { at: 200, next: bar({ itemStyle: { color: '#3fbe95' } }) });
  add('bar-bar.added', 'the same series gains a bar and is recoloured: the kept bars\' style from the old one, the new bar enters',
    bar(), cart({ type: 'bar', universalTransition: true, itemStyle: { color: '#ff0000' }, data: [5, 25, 36, 10, 7] },
      ['A', 'B', 'C', 'D', 'E']));
  add('bar-pie.keylist', 'seriesKey ["k", "j"] and ["j", "k"]: sorted and joined, the same key',
    bar({ id: 'a', universalTransition: { enabled: true, seriesKey: ['k', 'j'] } }),
    pie({ id: 'b', universalTransition: { enabled: true, seriesKey: ['j', 'k'] } }));
  add('bar-pie.rootdelay', 'the delay on the root option\'s universalTransition, the series\' own is true',
    bar(), Object.assign(pie(), { universalTransition: { delay: { $fn: 'ut120' } } }));
  // milestone D5-D8
  add('scatter-bar.opaque', 'symbols written opaque (itemStyle.opacity 1: an own key) become half-opaque bars, which fade from 1',
    scatter({ itemStyle: { opacity: 1 } }), bar({ itemStyle: { opacity: 0.5 } }));
  add('bar-pie.opacity', 'bars become slices whose itemStyle.opacity is 0.6: the pie draws its own opacity',
    bar(), pie({ itemStyle: { opacity: 0.6 } }));
  return list;
}

// ---------------------------------------------------------------------------
// guards
// ---------------------------------------------------------------------------
function guards(engine, charts) {
  const byId = id => charts.find(c => c.id === id);
  const items = c => c.elements.filter(e => e.item);
  const morphs = c => items(c).filter(e => e.morph);
  const at = (arr, t) => arr[SAMPLES.indexOf(t)];
  // engine
  const align = engine.filter(c => c.kind === 'align');
  for (const c of align) {
    must(c.alignedFrom.length === c.alignedTo.length, c.id + ': aligned subpath counts differ');
    c.alignedFrom.forEach((sp, i) => must(sp.length === c.alignedTo[i].length, c.id + ': subpath ' + i + ' lengths differ'));
  }
  must(engine.find(c => c.id === 'align.rect>two').alignedFrom.length === 2, 'rect>two has one subpath on the left');
  must(engine.find(c => c.id === 'align.three>two').alignedTo.length === 3, 'three>two: the third created');
  must(engine.find(c => c.id === 'align.rect.neg>sector.ring').alignedFrom[0].length
    > engine.find(c => c.id === 'bez.rect.neg').out[0].length, 'rect.neg>sector.ring did not subdivide the rect');
  must(align.some(c => c.offsets.some(o => o > 0)), 'no pair needs a ring offset');
  must(align.some(c => c.morph.some(m => m.rotation !== hex(-0) && m.rotation !== hex(0))), 'no pair turns');
  for (const c of engine.filter(x => x.kind === 'morph')) {
    const last = c.frames[c.frames.length - 1];
    must(c.frames[0].length > 0 && last.length > 0, c.id + ': empty frame');
    must(c.frames[0][0] === hex(1), c.id + ': a frame starts with a move');
  }
  must(engine.find(c => c.id === 'split.rect#5').pieces.length === 5, 'rect split 5');
  must(engine.find(c => c.id === 'split.polygon#3').pieces.every(p => p.type === 'polygon'), 'polygon split');
  must(engine.find(c => c.id === 'split.circle#4').pieces.every(p => p.type === 'sector'), 'circle split is sectors');
  // charts
  for (const id of ['bar-pie', 'pie-bar', 'bar-scatter', 'scatter-bar', 'line-bar', 'bar-line', 'scatter-pie.triangle',
    'pie-bar.ring', 'bar-pie.round', 'bar-pie.horizontal', 'bar-pie.border', 'bar-pie.ids', 'bar-pie.seriesKey', 'bar-pie.offold',
    'bar-pie.dataid', 'bar-pie.timing', 'bar-pie.delay', 'bar-pie.split', 'bar-pie.clone', 'bar-pie.inflight', 'line-scatter']) {
    const c = byId(id);
    must(morphs(c).length === 4, id + ': not four morphs but ' + morphs(c).length);
    for (const e of morphs(c)) {
      must(at(e.morph, 0), id + ' ' + e.id + ': not morphing at 0');
      must(!e.morph[e.morph.length - 1], id + ' ' + e.id + ': still morphing at the end');
    }
  }
  for (const id of ['bar-pie.otherid', 'bar-pie.offnew', 'bar-pie.enabledfalse', 'bar-pie.animoff']) {
    must(morphs(byId(id)).length === 0, id + ': morphs');
  }
  must(morphs(byId('bar-pie.unmatched')).length === 2, 'unmatched: two morphs');
  for (const id of ['scatter-scatter.symbol', 'scatter-scatter.symbolmove', 'bar-pie-bar.inflight', 'bar-pie.keylist', 'bar-pie.rootdelay']) {
    must(morphs(byId(id)).length === 4, id + ': not four morphs');
  }
  must(morphs(byId('bar-bar.added')).length === 0, 'bar-bar.added morphs');
  must(JSON.stringify(morphs(byId('bar-pie.rootdelay')).map(e => e.d)) === JSON.stringify(morphs(byId('bar-pie.delay')).map(e => e.d)),
    'the root delay differs from the series delay');
  {
    // the third option starts from the morph in flight, not from the slices at rest
    const a = morphs(byId('bar-pie-bar.inflight'))[1].d[0];
    must(a && a[0] === hex(1), 'inflight morph back has no frame');
  }
  must(morphs(byId('bar-pie.nullold')).length === 3, 'nullold: three morphs');
  {
    const c = byId('bar-pie.nullold');
    const b = items(c).find(e => e.dataIndex === 1);
    must(b && !b.morph && b.style.opacity[0] === hex(0), 'nullold: B does not fade in from 0');
  }
  {
    // the morph ends at the update duration: 500 ms by default, 800 timed (+ the delay)
    const end = c => SAMPLES.findIndex((t, i) => i > 0 && morphs(c).every(e => !e.morph[i]));
    must(SAMPLES[end(byId('bar-pie'))] === 500, 'bar-pie does not end at 500');
    const tm = byId('bar-pie.timing');
    must(morphs(tm).every(e => e.morph[SAMPLES.indexOf(750)]), 'timing: over at 750');
    const dl = byId('bar-pie.delay');
    must(morphs(dl).every(e => JSON.stringify(e.d[SAMPLES.indexOf(100)]) === JSON.stringify(e.d[0])
      && JSON.stringify(e.d[SAMPLES.indexOf(150)]) !== JSON.stringify(e.d[0])), 'delay: not held for 120 ms');
  }
  {
    // divideShape has nothing to divide one to one
    const base = JSON.stringify(byId('bar-pie').elements);
    must(JSON.stringify(byId('bar-pie.split').elements) === base, 'split differs from the default');
    must(JSON.stringify(byId('bar-pie.clone').elements) === base, 'clone differs from the default');
    must(JSON.stringify(byId('bar-pie.ids').elements) === base, 'ids differ from the default');
  }
  {
    // the same elements: no morph, the fill from the old colour
    const c = byId('bar-bar.style');
    must(morphs(c).length === 0, 'bar-bar morphs');
    must(items(c).every(e => e.style.fill[0] !== e.style.fill[e.style.fill.length - 1]), 'bar-bar: a fill does not move');
  }
  {
    // the polyline fades in
    const c = byId('bar-line');
    const poly = c.elements.find(e => !e.item && e.type === 'ec-polyline');
    must(poly && poly.style.opacity[0] === hex(0), 'bar-line: the polyline does not fade from 0');
  }
  {
    // in flight: the first frame differs from the settled run's
    must(JSON.stringify(morphs(byId('bar-pie.inflight'))[2].d[0]) !== JSON.stringify(morphs(byId('bar-pie'))[2].d[0]),
      'inflight: the bars were settled');
  }
}

function generate() {
  NOW = T_BASE;
  rngState = SEED;
  const engine = engineCases();
  const charts = chartCases().map(c => Object.assign(c, runCase(c.option, c.next, c.mid, c.then)));
  guards(engine, charts);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'D5 UT1: engine = zrender\'s morphing functions cut out of the dist, on PathProxy data real elements built; '
      + 'charts = option at T0 (run out, or `mid` ms into its enter), next with notMerge at T1, recorded at T1 + samplesMs. '
      + 'Each element: an item path of a new series (id s<series>/<dataIndex>/<path>) or another path of its view '
      + '(s<series>/x/<k>); morph[i] = __morphT >= 0, d[i] the replaced buildPath\'s PathProxy data (codes M1 L2 C3); '
      + 'style = the effective fill / stroke / lineWidth / opacity; snap = the path\'s transform and shape keys, g.* its '
      + 'Symbol group\'s. Every number is the hex of its double.',
    W, H, seed: SEED, clock: { T0: T_BASE, T1Offset: T1_OFFSET }, samplesMs: SAMPLES,
    engine, charts,
  };
}

let json1;
let json2;
try {
  json1 = fmt(generate(), '') + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  json2 = fmt(generate(), '') + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (json1 !== json2) {
  console.log('FAILED: two generations differ');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT, json1.length, 'bytes');
process.exit(0);
