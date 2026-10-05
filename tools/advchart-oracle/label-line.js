// Upstream's own answers for LABEL-LINE ROUTING -- label/labelGuideHelper.ts:
// updateLabelLinePoints (the label's rect, four candidate anchors on it, each
// pushed out by labelLine.length2, the nearest point on the host's PATH found
// in the host's own frame -- nearestPointOnPath with projectPointToLine /
// projectPointToArc / projectPointToRect and zrender's cubicProjectPoint /
// quadraticProjectPoint -- or the distance to a pie's anchor), limitTurnAngle
// and limitSurfaceAngle, the smooth path (buildLabelLinePath) and the line's
// states (setLabelLineStyle), as LabelManager._updateLabelLine runs them for
// every series but a pie and a funnel, and for a pie whose labelLayout gives
// an x or a y. A pie's own last pass (chart/pie/labelLayout.ts) bends every
// line through the two limits too.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer). The helpers are
// module-private, so the dist is loaded through Module._compile with three
// read-only additions (each regular expression must match exactly once):
//   expose -- the helpers handed to globalThis.__lgx, for the rule records;
//   line   -- inside updateLabelLinePoints: the label's rect as it was read
//             (BEFORE getComputedTransform, which is upstream's order) and
//             every input, then the points before and after limitTurnAngle;
//   pie    -- round the pie's limitTurnAngle / limitSurfaceAngle calls.
// The dist's own code runs unchanged. After setOption the chart is rendered
// once to an SVG string and every label line is read off the live elements;
// a few cases dispatch `highlight` and read the lines again after a frame.
//
//   node tools/advchart-oracle/label-line.js
//
// writes tests/fixtures/advchart-label-line.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as label-layout.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (NaN 7ff8000000000000)
//   rect     [x, y, width, height] in hex
//   mat      [m0 .. m5] in hex (x' = m0 x + m2 y + m4, y' = m1 x + m3 y + m5),
//            or null for no transform
//   pts      [[x, y] ...] in hex
//   data     a PathProxy's data array in hex, command codes included
//            (M 1, L 2, C 3, Q 4, A 5, Z 6, R 7; an arc's eight numbers are
//            cx, cy, rx, ry, start, sweep, psi, 1 clockwise / 0 anticlockwise)
//   raw      an option value as JSON (a number, a string, a boolean, null)
//
// Top level
//   source, W, H, seed, handlers{name: what it returns}, notes[]
//   rules {
//     project[]  nearestPointOnPath on a path: {path (id), pt [hex, hex],
//                dist (hex), out ([hex, hex], or null where nothing was
//                written)}; paths{id: {note, data}}
//     turn[]     limitTurnAngle: {pts, angle (raw), out (pts)}
//     surface[]  limitSurfaceAngle: {pts, normal [hex, hex], angle (raw),
//                out (pts)}
//     smooth[]   buildLabelLinePath: {pts, smooth (hex), calls [[op, hex ...]]
//                (op M / L / C)}
//   }
//   cases[]  one per chart: id, note, W, H, option (as fed, handlers by name)
//     lines[]   every updateLabelLinePoints that reached its loop, in order:
//       s, d, host (the target's type), raw (rect: label.getBoundingRect()
//       as read), labelM (mat: label.getComputedTransform()), targetM (mat),
//       path (data | null for a non-path host), anchor ([hex, hex] | null),
//       len (hex: +(length2 || 0), the number its products coerce it to),
//       minTurnAngle (raw), pre (pts, before
//       limitTurnAngle), post (pts)
//     pie[]     a pie's last pass, every line it bends: s, d, minTurnAngle,
//               maxSurfaceAngle (raw), normal [hex, hex], pre, post
//     guides[]  every label line after the render, series in order, each
//               series' group in traverse order (ignored hosts skipped):
//       s, d, ignore, points, smooth (hex), calls (buildLabelLinePath's, as
//       smooth[]), stroke (style.stroke as a string, or null), lineWidth
//       (hex | null), opacity (hex | null), lineDash (JSON), z2, hostZ2,
//       states {emphasis, blur, select: {ignore, smooth (hex | null),
//       stroke, lineWidth} | null}
//     hover[]   {payload, guides [{s, d, ignore, smooth, stroke, lineWidth}]}
//               -- the guides as drawn after `highlight` and a frame
//   guards[]  one per mutation of the transcription: id, mutation, named,
//             changed, ok
//
// ---------------------------------------------------------------------------
// The transcription (nearestPointOnPath and its projections, the curve
// projections, updateLabelLinePoints from the recorded inputs, the two limits
// and buildLabelLinePath) must reproduce every rule and every recorded call
// bit for bit. Self-checks (any failure: nothing is written, exit 1): each
// patch matches once; the transcription reproduces everything; every guard is
// ok; anchors; two generations in the process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');
const Module = require('module');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-label-line.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- the dist, patched ----------
let SRC = fs.readFileSync(DIST, 'utf8');
function patch(re, fn, what) {
  const hits = SRC.match(re);
  must(hits && hits.length === 1, what + ' is not where it was (' + (hits ? hits.length : 0) + ' matches)');
  SRC = SRC.replace(re, fn);
}
patch(/\n(\s*)function setLabelLineStyle\(targetEl, statesModels, defaultStyle\) \{/g,
  (m, sp) => '\n' + sp + 'globalThis.__lgx = { nearestPointOnPath: nearestPointOnPath, limitTurnAngle: limitTurnAngle, '
    + 'limitSurfaceAngle: limitSurfaceAngle, buildLabelLinePath: buildLabelLinePath, Point: Point, '
    + 'createSymbol: createSymbol };' + m, 'setLabelLineStyle');
patch(/var labelRect = label\.getBoundingRect\(\)\.clone\(\);\n(\s*)labelRect\.applyTransform\(label\.getComputedTransform\(\)\);/g,
  (m, sp) => 'var labelRect = label.getBoundingRect().clone();\n' + sp + 'var __lgRaw = labelRect.clone();\n'
    + sp + 'labelRect.applyTransform(label.getComputedTransform());', 'the label rect');
patch(/limitTurnAngle\(points, labelLineModel\.get\('minTurnAngle'\)\);\n(\s*)labelLine\.setShape\(\{/g,
  (m, sp) => 'globalThis.__lgHook && globalThis.__lgHook(\'pre\', target, label, __lgRaw, targetTransform, points, anchorPoint, len, labelLineModel);\n'
    + sp + 'limitTurnAngle(points, labelLineModel.get(\'minTurnAngle\'));\n'
    + sp + 'globalThis.__lgHook && globalThis.__lgHook(\'post\', target, label, __lgRaw, targetTransform, points, anchorPoint, len, labelLineModel);\n'
    + sp + 'labelLine.setShape({', 'the limitTurnAngle call');
patch(/limitTurnAngle\(linePoints, layout\.minTurnAngle\);\n(\s*)limitSurfaceAngle\(linePoints, layout\.surfaceNormal, layout\.maxSurfaceAngle\);/g,
  (m, sp) => 'globalThis.__lgPie && globalThis.__lgPie(\'pre\', layout, linePoints);\n' + sp + m
    + '\n' + sp + 'globalThis.__lgPie && globalThis.__lgPie(\'post\', layout, linePoints);', 'the pie\'s limits');
const echarts = (() => {
  const mod = new Module(DIST, module);
  mod.filename = DIST;
  mod.paths = Module._nodeModulePaths(path.dirname(DIST));
  mod._compile(SRC, DIST);
  return mod.exports;
})();
must(typeof echarts.init === 'function', 'the patched dist does not load');
const LGX = globalThis.__lgx;
must(LGX && typeof LGX.nearestPointOnPath === 'function', 'the helpers are not exposed');

// ---------- the seeded Math.random (the port's xorshift32) ----------
const SEED = 2463534242;
let rngState = SEED;
const jsRandom = Math.random;
function xorshift() {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
}
Math.random = xorshift;

// ---------- number records ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hexOrNull = v => (v == null ? null : hex(v));
const rect4 = r => [hex(r.x), hex(r.y), hex(r.width), hex(r.height)];
const mat6 = m => (m ? Array.from(m).map(hex) : null);
const pts3 = p => (p ? p.map(q => [hex(q[0]), hex(q[1])]) : null);
const dataHex = d => Array.from(d).map(hex);
const raw = v => (v === undefined ? null : (typeof v === 'number' && !isFinite(v) ? String(v) : v));
const clone = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)));

// ECData lives in a makeInner store ('__ec_inner_<n>') on every element
let ecKey = null;
function ecData(el) {
  if (!el) return null;
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (k.indexOf('__ec_inner_') === 0 && v && typeof v === 'object'
        && ('dataIndex' in v || 'componentMainType' in v) && 'seriesIndex' in v) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}

// ---------- what the hooks keep ----------
let capture = null;
let pendingLine = null;
globalThis.__lgHook = function (phase, target, label, rawRect, targetTransform, points, anchorPoint, len, model) {
  if (!capture) return;
  if (phase === 'pre') {
    const d = ecData(target);
    pendingLine = {
      s: d ? d.seriesIndex : null,
      d: d && d.dataIndex != null ? d.dataIndex : null,
      host: target.type,
      raw: rect4(rawRect),
      labelM: mat6(label.transform),
      targetM: mat6(targetTransform),
      path: target.path ? dataHex(target.path.data) : null,
      anchor: anchorPoint ? [hex(anchorPoint.x), hex(anchorPoint.y)] : null,
      len: hex(+len),
      minTurnAngle: raw(model.get('minTurnAngle')),
      pre: pts3(points),
    };
    return;
  }
  must(pendingLine, 'a post hook without its pre');
  pendingLine.post = pts3(points);
  capture.lines.push(pendingLine);
  pendingLine = null;
};
let pendingPie = null;
globalThis.__lgPie = function (phase, layout, linePoints) {
  if (!capture) return;
  if (phase === 'pre') {
    const host = layout.label.__hostTarget;
    const d = ecData(host);
    pendingPie = {
      s: d ? d.seriesIndex : null,
      d: d && d.dataIndex != null ? d.dataIndex : null,
      minTurnAngle: raw(layout.minTurnAngle),
      maxSurfaceAngle: raw(layout.maxSurfaceAngle),
      normal: [hex(layout.surfaceNormal.x), hex(layout.surfaceNormal.y)],
      pre: pts3(linePoints),
    };
    return;
  }
  must(pendingPie, 'a pie post hook without its pre');
  pendingPie.post = pts3(linePoints);
  capture.pie.push(pendingPie);
  pendingPie = null;
};

// buildLabelLinePath into a recorder
function pathCalls(shape) {
  const calls = [];
  const rec = {
    moveTo: (x, y) => calls.push(['M', hex(x), hex(y)]),
    lineTo: (x, y) => calls.push(['L', hex(x), hex(y)]),
    bezierCurveTo: (a, b, c, d, e, f) => calls.push(['C', hex(a), hex(b), hex(c), hex(d), hex(e), hex(f)]),
  };
  LGX.buildLabelLinePath(rec, shape);
  return calls;
}

// ---------- the handlers ----------
const HANDLER_NOTES = {
  '@LG_FAN': '{dx: (d * 37) % 81 - 40, dy: (d * 53) % 61 - 30}',
  '@LG_XY': '{x: 40 + (d * 97) % 520, y: 30 + (d * 61) % 320}',
  '@LG_PIELINE': 'labelLinePoints: the line\'s first two points and the label rect\'s near edge at its middle (labelRect.x < W / 2: its x, else x + width)',
  '@LG_PIEXY': 'x 40 (labelRect.x < W / 2) or 560, with @LG_PIELINE\'s labelLinePoints',
};
const HANDLERS = {
  '@LG_FAN': p => ({ dx: (p.dataIndex * 37) % 81 - 40, dy: (p.dataIndex * 53) % 61 - 30 }),
  '@LG_XY': p => ({ x: 40 + (p.dataIndex * 97) % 520, y: 30 + (p.dataIndex * 61) % 320 }),
  '@LG_PIELINE': p => {
    const points = p.labelLinePoints;
    if (!points) return {};
    const isLeft = p.labelRect.x < W / 2;
    points[2][0] = isLeft ? p.labelRect.x : p.labelRect.x + p.labelRect.width;
    points[2][1] = p.labelRect.y + p.labelRect.height / 2;
    return { labelLinePoints: points };
  },
  '@LG_PIEXY': p => {
    const r = HANDLERS['@LG_PIELINE'](p);
    r.x = p.labelRect.x < W / 2 ? 40 : 560;
    return r;
  },
};
function bind(o) {
  if (Array.isArray(o)) return o.map(bind);
  if (o && typeof o === 'object') {
    const r = {};
    for (const k of Object.keys(o)) r[k] = bind(o[k]);
    return r;
  }
  if (typeof o === 'string' && Object.prototype.hasOwnProperty.call(HANDLERS, o)) return HANDLERS[o];
  return o;
}

// ---------- the cases ----------
const pts = (n, a, b) => Array.from({ length: n }, (_, i) => [(i * a) % 23, (i * b) % 17 + (i % 3) * 0.5]);
const cats = n => Array.from({ length: n }, (_, i) => 'c' + i);
const barData = n => Array.from({ length: n }, (_, i) => 10 + (i * 37) % 90);
const lineData = n => Array.from({ length: n }, (_, i) => Math.round(50 + 40 * Math.sin(i / 3)));
const pieData = (n, f) => Array.from({ length: n }, (_, i) => ({ name: 'p' + i, value: f(i) }));
function scatter(series, extra) {
  return Object.assign({ animation: false, xAxis: {}, yAxis: {}, series }, extra || {});
}
const sc = o => Object.assign({ type: 'scatter', symbolSize: 18, label: { show: true }, labelLine: { show: true },
  labelLayout: '@LG_FAN', data: pts(12, 7, 13) }, o);
const ll = o => Object.assign({ show: true }, o);
function bars(seriesExtra, n, extra) {
  n = n || 8;
  return Object.assign({
    animation: false,
    xAxis: { type: 'category', data: cats(n) },
    yAxis: {},
    series: [Object.assign({ type: 'bar', label: { show: true, position: 'top' }, labelLine: { show: true }, data: barData(n) }, seriesExtra)],
  }, extra || {});
}
function pie(seriesExtra, extra) {
  return Object.assign({
    animation: false,
    series: [Object.assign({ type: 'pie', radius: '45%', data: pieData(16, i => (i * 7) % 11 + 1) }, seriesExtra)],
  }, extra || {});
}
const crowd = n => pieData(n, i => (i * 7) % 11 + 1);
const skew = n => [{ name: 'Big', value: 120 }].concat(Array.from({ length: n }, (_, i) => ({ name: 's' + i, value: 1 + (i % 3) })));
const hov = idx => idx.map(i => ({ type: 'highlight', seriesIndex: 0, dataIndex: i }));
const sel = idx => idx.map(i => ({ type: 'select', seriesIndex: 0, dataIndex: i }));

const CASES = [
  // ---- a scatter's lines ----
  { id: 'scatter.plain', note: 'labelLine.show without labelLayout: every label gets a line, its rect read before the host\'s alignment reaches it',
    option: scatter([sc({ labelLayout: undefined })]) },
  { id: 'scatter.dxdy', note: 'labelLayout dx / dy: the line from the nearest point of the circle to the label\'s nearest side',
    option: scatter([sc({ labelLayout: { dx: 30, dy: -25 } })]) },
  { id: 'scatter.len2', note: 'length2 12: the middle point stands off the label',
    option: scatter([sc({ labelLine: ll({ length2: 12 }) })]) },
  { id: 'scatter.len2.str', note: 'length2 a numeric string',
    option: scatter([sc({ labelLine: ll({ length2: '9' }) })]) },
  { id: 'scatter.right', note: 'label on the right, moved up 30',
    option: scatter([sc({ label: { show: true, position: 'right' }, labelLayout: { dy: -30 } })]) },
  { id: 'scatter.xy', note: 'every label at one point: x 520, y 40',
    option: scatter([sc({ labelLayout: { x: 520, y: 40 } })]) },
  { id: 'scatter.fnxy', note: 'a function placing each label at its own x / y',
    option: scatter([sc({ labelLayout: '@LG_XY', labelLine: ll({ length2: 8 }) })]) },
  { id: 'scatter.align', note: 'the label\'s own align and verticalAlign, no labelLayout',
    option: scatter([sc({ label: { show: true, align: 'right', verticalAlign: 'bottom' }, labelLayout: undefined })]) },
  { id: 'scatter.rotate', note: 'turned labels moved by dx / dy',
    option: scatter([sc({ label: { show: true, rotate: 35 }, labelLayout: { dx: 25, dy: -20 } })]) },
  { id: 'scatter.rich', note: 'rich labels in a box, no labelLayout',
    option: scatter([sc({ label: { show: true, formatter: '{a|{c}}', backgroundColor: '#eee', padding: [2, 4], rich: { a: { fontSize: 13 } } }, labelLayout: undefined })]) },
  { id: 'scatter.rich.fan', note: 'rich labels moved by a function',
    option: scatter([sc({ label: { show: true, formatter: '{a|{c}}', rich: { a: { fontSize: 13, padding: [0, 3] } } } })]) },
  // ---- symbol paths ----
  { id: 'sym.rect', note: 'rect symbols', option: scatter([sc({ symbol: 'rect' })]) },
  { id: 'sym.roundRect', note: 'roundRect symbols: corner arcs', option: scatter([sc({ symbol: 'roundRect', symbolSize: 24 })]) },
  { id: 'sym.triangle', note: 'triangles: lines and a close', option: scatter([sc({ symbol: 'triangle' })]) },
  { id: 'sym.diamond', note: 'diamonds', option: scatter([sc({ symbol: 'diamond' })]) },
  { id: 'sym.pin', note: 'pins: an arc and two cubics', option: scatter([sc({ symbol: 'pin', symbolSize: 26 })]) },
  { id: 'sym.arrow', note: 'arrows', option: scatter([sc({ symbol: 'arrow' })]) },
  { id: 'sym.path', note: 'a path:// icon with a cubic and a quadratic (a Float32Array)',
    option: scatter([sc({ symbol: 'path://M0 0 C 4 -6 10 -6 14 0 Q 7 12 0 0 Z', symbolSize: 22 })]) },
  { id: 'sym.emptyCircle', note: 'empty circles', option: scatter([sc({ symbol: 'emptyCircle' })]) },
  { id: 'sym.ellipse', note: 'symbolSize [30, 12]: the circle scaled unevenly, distances weighed in its own frame',
    option: scatter([sc({ symbolSize: [30, 12] })]) },
  { id: 'sym.rotate', note: 'symbolRotate 35 on triangles', option: scatter([sc({ symbol: 'triangle', symbolRotate: 35, symbolSize: 22 })]) },
  { id: 'sym.offset', note: 'symbolOffset [6, -4]', option: scatter([sc({ symbol: 'diamond', symbolOffset: [6, -4] })]) },
  { id: 'sym.tiny', note: 'symbolSize 2: the path needs no local transform', option: scatter([sc({ symbolSize: 2 })]) },
  { id: 'sym.line.top', note: 'line symbols, labels on top: the rect of no height places them', option: scatter([sc({ symbol: 'line', symbolSize: 24, label: { show: true, position: 'top' } })]) },
  { id: 'sym.line', note: 'line symbols: a path of one segment, its rect of no height', option: scatter([sc({ symbol: 'line', symbolSize: 24 })]) },
  // ---- the turn limit ----
  { id: 'turn.30', note: 'minTurnAngle 30', option: scatter([sc({ labelLine: ll({ length2: 15, minTurnAngle: 30 }) })]) },
  { id: 'turn.90', note: 'minTurnAngle 90', option: scatter([sc({ labelLine: ll({ length2: 15, minTurnAngle: 90 }) })]) },
  { id: 'turn.150', note: 'minTurnAngle 150', option: scatter([sc({ labelLine: ll({ length2: 15, minTurnAngle: 150 }) })]) },
  { id: 'turn.180', note: 'minTurnAngle 180', option: scatter([sc({ labelLine: ll({ length2: 15, minTurnAngle: 180 }) })]) },
  { id: 'turn.0', note: 'minTurnAngle 0: no limit', option: scatter([sc({ labelLine: ll({ length2: 15, minTurnAngle: 0 }) })]) },
  { id: 'turn.200', note: 'minTurnAngle 200: out of range, no limit', option: scatter([sc({ labelLine: ll({ length2: 15, minTurnAngle: 200 }) })]) },
  { id: 'turn.str', note: 'minTurnAngle \'120\', a string', option: scatter([sc({ labelLine: ll({ length2: 15, minTurnAngle: '120' }) })]) },
  // ---- smooth ----
  { id: 'smooth.true', note: 'smooth true: 0.3', option: scatter([sc({ labelLine: ll({ length2: 15, smooth: true }) })]) },
  { id: 'smooth.num', note: 'smooth 0.6', option: scatter([sc({ labelLine: ll({ length2: 15, smooth: 0.6 }) })]) },
  { id: 'smooth.big', note: 'smooth 2', option: scatter([sc({ labelLine: ll({ length2: 15, smooth: 2 }) })]) },
  { id: 'smooth.neg', note: 'smooth -1: none', option: scatter([sc({ labelLine: ll({ length2: 15, smooth: -1 }) })]) },
  { id: 'smooth.str', note: 'smooth \'0.4\', a string', option: scatter([sc({ labelLine: ll({ length2: 15, smooth: '0.4' }) })]) },
  { id: 'smooth.zero', note: 'smooth with length2 0: a segment of no length, straight', option: scatter([sc({ labelLine: ll({ smooth: 0.5 }) })]) },
  // ---- bars ----
  { id: 'bar.top.y', note: 'bar labels on top, y 20: the line drops to the bar\'s top edge', option: bars({ labelLayout: { y: 20 } }) },
  { id: 'bar.inside.dxdy', note: 'labels inside, moved out by dx / dy', option: bars({ label: { show: true, position: 'inside' }, labelLayout: { dx: 25, dy: -60 } }) },
  { id: 'bar.neg', note: 'negative bars (a rect of negative height)', option: bars({ data: barData(8).map((v, i) => (i % 2 ? -v : v)), labelLayout: { dy: 40 } }) },
  { id: 'bar.horiz', note: 'a horizontal bar chart, labels at x 560',
    option: { animation: false, yAxis: { type: 'category', data: cats(8) }, xAxis: {},
      series: [{ type: 'bar', label: { show: true, position: 'right' }, labelLine: { show: true, length2: 6 }, labelLayout: { x: 560 }, data: barData(8) }] } },
  { id: 'bar.radius', note: 'rounded bars: the corner arcs', option: bars({ itemStyle: { borderRadius: 8 }, labelLayout: { dx: 30, dy: -40 } }) },
  { id: 'bar.plain', note: 'labelLine on bars without labelLayout', option: bars({}) },
  { id: 'bar.border', note: 'bordered bars', option: bars({ itemStyle: { borderColor: '#333', borderWidth: 3 }, labelLayout: { dx: -20, dy: -30 } }) },
  // ---- lines ----
  { id: 'line.symbols', note: 'a line\'s symbols with labels moved up',
    option: { animation: false, xAxis: { type: 'category', data: cats(10) }, yAxis: {},
      series: [{ type: 'line', label: { show: true }, labelLine: { show: true, length2: 6 }, labelLayout: { dy: -30, dx: 10 }, data: lineData(10) }] } },
  { id: 'line.plain', note: 'a line\'s symbols, labelLine without labelLayout',
    option: { animation: false, xAxis: { type: 'category', data: cats(10) }, yAxis: {},
      series: [{ type: 'line', symbol: 'circle', label: { show: true }, labelLine: { show: true }, data: lineData(10) }] } },
  // ---- effectScatter ----
  { id: 'effect', note: 'an effectScatter\'s labels moved by a function',
    option: scatter([Object.assign(sc({}), { type: 'effectScatter' })]) },
  // ---- hideOverlap ----
  { id: 'hide', note: 'a dense scatter with hideOverlap: hidden labels hide their lines; hovering one shows both',
    option: scatter([sc({ data: pts(40, 7, 13), labelLayout: { hideOverlap: true, dx: 20, dy: -20 } })]),
    hover: hov([1, 2, 3, 5]) },
  // ---- the line's style ----
  { id: 'style', note: 'lineStyle color, width, dashed, opacity',
    option: scatter([sc({ labelLine: ll({ lineStyle: { color: '#c23531', width: 3, type: 'dashed', opacity: 0.5 } }) })]) },
  { id: 'style.width', note: 'lineStyle width 2.5, the colour from the item',
    option: scatter([sc({ labelLine: ll({ lineStyle: { width: 2.5 } }), itemStyle: { color: '#91cc75' } })]) },
  { id: 'showAbove', note: 'showAbove: the line over its host', option: scatter([sc({ labelLine: ll({ showAbove: true }) })]) },
  // ---- states ----
  { id: 'emph.style', note: 'emphasis lineStyle and smooth', hover: hov([0, 4]),
    option: scatter([sc({ emphasis: { labelLine: { lineStyle: { color: '#000', width: 4 }, smooth: 0.5 } } })]) },
  { id: 'emph.hide', note: 'emphasis.labelLine.show false', hover: hov([0, 4]),
    option: scatter([sc({ emphasis: { labelLine: { show: false } } })]) },
  { id: 'emph.only', note: 'a label shown only under emphasis: its line too', hover: hov([0, 4]),
    option: scatter([sc({ label: { show: false }, emphasis: { label: { show: true } } })]) },
  { id: 'line.emph.only', note: 'labelLine.show false, emphasis.labelLine.show true', hover: hov([0, 4]),
    option: scatter([sc({ labelLine: { show: false }, emphasis: { labelLine: { show: true } } })]) },
  { id: 'smooth.hover', note: 'a smooth line goes straight under emphasis', hover: hov([0, 4]),
    option: scatter([sc({ labelLine: ll({ length2: 15, smooth: true }) })]) },
  { id: 'emph.only.select', note: 'a label shown only under emphasis, selected: its line stays hidden', hover: sel([2, 4]),
    option: scatter([sc({ label: { show: false }, emphasis: { label: { show: true } }, selectedMode: 'single' })]) },
  { id: 'line.emph.only.select', note: 'labelLine.show false, only emphasis says true; selected: hidden', hover: sel([2, 4]),
    option: scatter([sc({ labelLine: { show: false }, emphasis: { labelLine: { show: true } }, selectedMode: 'single' })]) },
  { id: 'hide.select', note: 'hideOverlap, then selecting labels it hid: the line follows the label as laid out', hover: sel([1, 14, 22, 31]),
    option: scatter([sc({ data: pts(40, 7, 13), labelLayout: { hideOverlap: true, dx: 20, dy: -20 }, selectedMode: 'single' })]) },
  { id: 'select', note: 'selectedMode: a selected item\'s line state', hover: [{ type: 'select', seriesIndex: 0, dataIndex: 2 }],
    option: scatter([sc({ selectedMode: 'single', select: { labelLine: { lineStyle: { color: '#f00' } } } })]) },
  // ---- pies ----
  { id: 'pie.x', note: 'a pie with labelLayout x 85%: the line routed from the anchor', option: pie({ labelLayout: { x: '85%' } }) },
  { id: 'pie.y', note: 'a pie with labelLayout y 30', option: pie({ labelLayout: { y: 30 } }) },
  { id: 'pie.xy.turn', note: 'x 560, y 50%, minTurnAngle 150', option: pie({ labelLayout: { x: 560, y: '50%' }, labelLine: { minTurnAngle: 150 } }) },
  { id: 'pie.xy.len2', note: 'x / y from a function, length2 10', option: pie({ labelLayout: '@LG_XY', labelLine: { length2: 10 } }) },
  { id: 'pie.points', note: 'labelLinePoints from a function: the line is not routed again', option: pie({ labelLayout: '@LG_PIELINE' }) },
  { id: 'pie.points.xy', note: 'an x and labelLinePoints from a function: the points stand, not routed', option: pie({ labelLayout: '@LG_PIEXY' }) },
  { id: 'pie.xy.turn179', note: 'x / y from a function, minTurnAngle 179, length2 40: routed lines bent', option: pie({ labelLayout: '@LG_XY', labelLine: { minTurnAngle: 179, length2: 40 } }) },
  { id: 'pie.x.smooth', note: 'x 85% on a smooth pie: the routed line keeps its curves', option: pie({ labelLayout: { x: '85%' }, labelLine: { smooth: 0.5 } }) },
  { id: 'pie.dy', note: 'dy alone: no routing, the two limits still bend', option: pie({ labelLayout: { dy: -12 }, labelLine: { minTurnAngle: 140 } }) },
  { id: 'pie.turn.120', note: 'crowded, minTurnAngle 120', option: pie({ data: crowd(40), labelLine: { minTurnAngle: 120 } }) },
  { id: 'pie.turn.45', note: 'crowded, minTurnAngle 45', option: pie({ data: crowd(40), labelLine: { minTurnAngle: 45 } }) },
  { id: 'pie.turn.0', note: 'minTurnAngle 0, maxSurfaceAngle 0: no limits', option: pie({ data: crowd(40), labelLine: { minTurnAngle: 0, maxSurfaceAngle: 0 } }) },
  { id: 'pie.surface.45', note: 'maxSurfaceAngle 45', option: pie({ data: crowd(40), labelLine: { maxSurfaceAngle: 45 } }) },
  { id: 'pie.surface.150', note: 'maxSurfaceAngle 150, minTurnAngle 170', option: pie({ data: crowd(40), labelLine: { maxSurfaceAngle: 150, minTurnAngle: 170 } }) },
  { id: 'pie.surface.180', note: 'maxSurfaceAngle 180', option: pie({ data: skew(16), labelLine: { maxSurfaceAngle: 180 } }) },
  { id: 'pie.solver', note: 'a crowded side: the solver moves labels, the defaults bend their lines', option: pie({ data: skew(18) }) },
  { id: 'pie.solver.edge', note: 'alignTo edge, crowded', option: pie({ data: crowd(30), label: { alignTo: 'edge' } }) },
  { id: 'pie.solver.labelLine', note: 'alignTo labelLine, crowded', option: pie({ data: crowd(30), label: { alignTo: 'labelLine' } }) },
  { id: 'pie.unmoved.150', note: 'nothing moved, minTurnAngle 150: unmoved lines bend too', option: pie({ data: crowd(8), labelLine: { minTurnAngle: 150 } }) },
  { id: 'pie.smooth.true', note: 'smooth true', option: pie({ data: skew(14), labelLine: { smooth: true } }) },
  { id: 'pie.smooth.num', note: 'smooth 0.7', option: pie({ data: crowd(20), labelLine: { smooth: 0.7 } }) },
  { id: 'pie.smooth.hover', note: 'a smooth pie line under emphasis', hover: hov([0, 3]), option: pie({ data: crowd(10), labelLine: { smooth: 0.5 } }) },
  { id: 'pie.hide.select', note: 'a pie whose hideOverlap hid labels, slices selected: the line as styled before the layout', hover: sel([3, 7, 12, 20, 21]),
    option: pie({ data: crowd(40), avoidLabelOverlap: false, selectedMode: 'single' }) },
  { id: 'pie.emph.style', note: 'a pie line\'s emphasis lineStyle', hover: hov([1]),
    option: pie({ data: crowd(10), emphasis: { labelLine: { lineStyle: { width: 3, color: '#333' } } } }) },
];

// ---------- one case ----------
function stateRec(g, name) {
  const st = g.states && g.states[name];
  if (!st) return null;
  return {
    ignore: st.ignore == null ? null : !!st.ignore,
    smooth: st.shape && st.shape.smooth != null ? hex(+st.shape.smooth) : null,
    stroke: st.style && st.style.stroke != null ? String(st.style.stroke) : null,
    lineWidth: st.style && st.style.lineWidth != null ? hex(st.style.lineWidth) : null,
  };
}
function guideRec(s, el, g) {
  const d = ecData(el);
  const st = g.style || {};
  return {
    s: s.seriesIndex,
    d: d && d.dataIndex != null ? d.dataIndex : null,
    ignore: !!g.ignore,
    points: pts3(g.shape.points),
    smooth: hex(+g.shape.smooth || 0),
    calls: pathCalls(g.shape),
    stroke: st.stroke == null ? null : String(st.stroke),
    lineWidth: hexOrNull(st.lineWidth),
    opacity: hexOrNull(st.opacity),
    lineDash: st.lineDash == null ? null : clone(st.lineDash),
    z2: g.z2,
    hostZ2: el.z2,
    states: { emphasis: stateRec(g, 'emphasis'), blur: stateRec(g, 'blur'), select: stateRec(g, 'select') },
  };
}
function eachGuide(chart, fn) {
  chart.getModel().eachSeries(s => {
    chart.getViewOfSeriesModel(s).group.traverse(el => {
      if (el.ignore) return true;
      const g = el.getTextGuideLine && el.getTextGuideLine();
      if (!g) return;
      fn(s, el, g);
    });
  });
}
function runCase(c) {
  rngState = SEED;
  capture = { lines: [], pie: [] };
  pendingLine = null;
  pendingPie = null;
  const w = c.W || W;
  const h = c.H || H;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: w, height: h });
  try {
    chart.setOption(bind(c.option));
    chart.renderToSVGString();
    const lines = capture.lines;
    const pieRecs = capture.pie;
    capture = null;
    const guides = [];
    eachGuide(chart, (s, el, g) => guides.push(guideRec(s, el, g)));
    const hover = [];
    for (const payload of c.hover || []) {
      chart.dispatchAction(payload);
      chart._onframe();
      const rec = [];
      eachGuide(chart, (s, el, g) => {
        const d = ecData(el);
        rec.push({
          s: s.seriesIndex,
          d: d && d.dataIndex != null ? d.dataIndex : null,
          ignore: !!g.ignore,
          smooth: hex(+g.shape.smooth || 0),
          stroke: g.style.stroke == null ? null : String(g.style.stroke),
          lineWidth: hexOrNull(g.style.lineWidth),
        });
      });
      hover.push({ payload, guides: rec });
      const back = payload.type === 'select' ? 'unselect' : 'downplay';
      chart.dispatchAction(Object.assign({}, payload, { type: back }));
      chart._onframe();
    }
    return { id: c.id, note: c.note, W: w, H: h, option: clone(c.option), lines, pie: pieRecs, guides, hover };
  } finally {
    capture = null;
    chart.dispose();
  }
}

// ---------- the rules ----------
function pathOf(el) {
  el.getBoundingRect();
  return el.path.data;
}
function rulePaths() {
  const G = echarts.graphic;
  const P = {};
  const sector = (id, note, shape) => { P[id] = { note, data: pathOf(new G.Sector({ shape: Object.assign({ cx: 300, cy: 200 }, shape) })) }; };
  sector('sector.q1', 'a quarter, clockwise', { r0: 0, r: 120, startAngle: -Math.PI / 2, endAngle: 0, clockwise: true });
  sector('sector.wide', 'three quarters, clockwise, a ring', { r0: 40, r: 120, startAngle: 0.3, endAngle: 0.3 + Math.PI * 1.5, clockwise: true });
  sector('sector.ccw', 'a thin slice, anticlockwise', { r0: 0, r: 100, startAngle: 2.0, endAngle: 1.6, clockwise: false });
  sector('sector.full', 'a whole ring', { r0: 60, r: 100, startAngle: 0, endAngle: Math.PI * 2, clockwise: true });
  sector('sector.wrap', 'a slice across angle 0, anticlockwise ring', { r0: 30, r: 90, startAngle: 0.4, endAngle: -0.5, clockwise: false });
  P['rect'] = { note: 'a rect', data: pathOf(new G.Rect({ shape: { x: 100, y: 80, width: 140, height: 60 } })) };
  P['rect.neg'] = { note: 'a rect of negative width and height', data: pathOf(new G.Rect({ shape: { x: 300, y: 300, width: -90, height: -150 } })) };
  P['rect.round'] = { note: 'a rounded rect', data: pathOf(new G.Rect({ shape: { x: 50, y: 50, width: 120, height: 70, r: [10, 20, 0, 30] } })) };
  P['polyline'] = { note: 'an open polyline', data: pathOf(new G.Polyline({ shape: { points: [[50, 50], [200, 90], [120, 220], [260, 260]] } })) };
  P['polygon'] = { note: 'a closed polygon', data: pathOf(new G.Polygon({ shape: { points: [[300, 60], [420, 140], [380, 260], [250, 200]] } })) };
  P['svg.cq'] = { note: 'an svg path with a cubic and a quadratic', data: pathOf(G.makePath('M10 10 C 60 -40 120 80 160 20 Q 200 120 90 150 L 10 10 Z', {}, null)) };
  P['svg.arc'] = { note: 'an svg elliptical arc (rx 80, ry 40)', data: pathOf(G.makePath('M 100 200 A 80 40 0 0 1 260 200 L 180 260 Z', {}, null)) };
  P['svg.arc.ccw'] = { note: 'an svg arc swept the other way', data: pathOf(G.makePath('M 100 200 A 60 60 0 1 0 220 200', {}, null)) };
  P['raw.lineFirst'] = { note: 'a data array that starts with a line: the first command seeds the point from its own numbers', data: [2, 100, 80, 2, 220, 260, 2, 60, 240, 6] };
  for (const s of ['circle', 'rect', 'roundRect', 'triangle', 'diamond', 'pin', 'arrow', 'emptyCircle']) {
    P['sym.' + s] = { note: 'createSymbol(\'' + s + '\', -1, -1, 2, 2)', data: pathOf(LGX.createSymbol(s, -1, -1, 2, 2, null, true)) };
  }
  return P;
}
function rulePoints(data) {
  // the path's bounding box from its data, then a 7 x 7 grid over it grown by 30 % each side
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  const take = (x, y) => { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); };
  for (let i = 0; i < data.length;) {
    const cmd = data[i++];
    const n = { 1: 2, 2: 2, 3: 6, 4: 4, 5: 8, 6: 0, 7: 4 }[cmd];
    if (cmd === 5) {
      take(data[i] - data[i + 2], data[i + 1] - data[i + 3]);
      take(data[i] + data[i + 2], data[i + 1] + data[i + 3]);
    }
    else if (cmd === 7) {
      take(data[i], data[i + 1]);
      take(data[i] + data[i + 2], data[i + 1] + data[i + 3]);
    }
    else for (let k = 0; k < n; k += 2) take(data[i + k], data[i + k + 1]);
    i += n;
  }
  const w = x1 - x0;
  const h = y1 - y0;
  const out = [];
  for (let a = 0; a < 7; a++) {
    for (let b = 0; b < 7; b++) out.push([x0 - 0.3 * w + a * (1.6 * w / 6) + 0.137, y0 - 0.3 * h + b * (1.6 * h / 6) - 0.071]);
  }
  out.push([(x0 + x1) / 2, (y0 + y1) / 2]);
  return out;
}
function genRules() {
  const paths = rulePaths();
  const project = [];
  const pathRecs = {};
  for (const id of Object.keys(paths)) {
    const data = paths[id].data;
    pathRecs[id] = { note: paths[id].note, data: dataHex(data) };
    for (const q of rulePoints(data)) {
      const out = new LGX.Point(12345.5, -6789.25);
      const d = LGX.nearestPointOnPath(new LGX.Point(q[0], q[1]), { data }, out);
      const written = !(out.x === 12345.5 && out.y === -6789.25);
      project.push({ path: id, pt: [hex(q[0]), hex(q[1])], dist: hex(d), out: written ? [hex(out.x), hex(out.y)] : null });
    }
  }
  rngState = SEED;
  const rp = () => [40 + xorshift() * 300, 40 + xorshift() * 300];
  const turn = [];
  const surface = [];
  const smooth = [];
  const ANGLES = [undefined, 0, 1, 30, 60, 90, 120, 150, 179, 180, 200, '120'];
  for (let k = 0; k < 360; k++) {
    let p = [rp(), rp(), rp()];
    if (k % 17 === 5) p[1] = p[0].slice();
    if (k % 19 === 7) p[2] = [p[1][0], p[1][1] + 30];
    if (k % 23 === 3) p[2] = [p[1][0] + 1e-4, p[1][1]];
    const angle = ANGLES[k % ANGLES.length];
    const a = p.map(q => q.slice());
    LGX.limitTurnAngle(a, angle);
    turn.push({ pts: pts3(p), angle: raw(angle), out: pts3(a) });
    const t = xorshift() * Math.PI * 2;
    const nrm = new LGX.Point(Math.cos(t), Math.sin(t));
    const b = p.map(q => q.slice());
    LGX.limitSurfaceAngle(b, nrm, angle);
    surface.push({ pts: pts3(p), normal: [hex(nrm.x), hex(nrm.y)], angle: raw(angle), out: pts3(b) });
    const sm = [0.3, 0.5, 1, 2, 0.05, 0][k % 6];
    smooth.push({ pts: pts3(p), smooth: hex(sm), calls: pathCalls({ points: p, smooth: sm }) });
  }
  // a line of two points, and none
  smooth.push({ pts: pts3([[10, 10], [50, 30]]), smooth: hex(0.5), calls: pathCalls({ points: [[10, 10], [50, 30]], smooth: 0.5 }) });
  return { paths: pathRecs, project, turn, surface, smooth };
}

// ---------- the transcription ----------
const PI2 = Math.PI * 2;
const fromHex = s => {
  for (let i = 0; i < 8; i++) bits.setUint8(i, parseInt(s.substr(i * 2, 2), 16));
  return bits.getFloat64(0);
};
const unhex2 = a => [fromHex(a[0]), fromHex(a[1])];
function normalizeRadian(angle) {
  angle %= PI2;
  if (angle < 0) angle += PI2;
  return angle;
}
function projectPointToArc(cx, cy, r, startAngle, endAngle, anticlockwise, x, y, out, mut) {
  x -= cx;
  y -= cy;
  const d = Math.sqrt(x * x + y * y);
  x /= d;
  y /= d;
  const ox = x * r + cx;
  const oy = y * r + cy;
  if (Math.abs(startAngle - endAngle) % PI2 < 1e-4) {
    out[0] = ox;
    out[1] = oy;
    return mut.absArc ? Math.abs(d - r) : d - r;
  }
  if (anticlockwise) {
    const tmp = startAngle;
    startAngle = normalizeRadian(endAngle);
    endAngle = normalizeRadian(tmp);
  }
  else {
    startAngle = normalizeRadian(startAngle);
    endAngle = normalizeRadian(endAngle);
  }
  if (startAngle > endAngle) endAngle += PI2;
  let angle = Math.atan2(y, x);
  if (angle < 0) angle += PI2;
  if ((angle >= startAngle && angle <= endAngle) || (angle + PI2 >= startAngle && angle + PI2 <= endAngle)) {
    out[0] = ox;
    out[1] = oy;
    return mut.absArc ? Math.abs(d - r) : d - r;
  }
  const x1 = r * Math.cos(startAngle) + cx;
  const y1 = r * Math.sin(startAngle) + cy;
  const x2 = r * Math.cos(endAngle) + cx;
  const y2 = r * Math.sin(endAngle) + cy;
  // upstream measures the ends against the UNIT direction, x and y having
  // been divided by d above
  const px = mut.arcEndsTrue ? x * d + cx : x;
  const py = mut.arcEndsTrue ? y * d + cy : y;
  const d1 = (x1 - px) * (x1 - px) + (y1 - py) * (y1 - py);
  const d2 = (x2 - px) * (x2 - px) + (y2 - py) * (y2 - py);
  if (d1 < d2) {
    out[0] = x1;
    out[1] = y1;
    return Math.sqrt(d1);
  }
  out[0] = x2;
  out[1] = y2;
  return Math.sqrt(d2);
}
function projectPointToLine(x1, y1, x2, y2, x, y, out, limitToEnds) {
  const dx = x - x1;
  const dy = y - y1;
  let dx1 = x2 - x1;
  let dy1 = y2 - y1;
  const lineLen = Math.sqrt(dx1 * dx1 + dy1 * dy1);
  dx1 /= lineLen;
  dy1 /= lineLen;
  const projectedLen = dx * dx1 + dy * dy1;
  let t = projectedLen / lineLen;
  if (limitToEnds) t = Math.min(Math.max(t, 0), 1);
  t *= lineLen;
  const ox = out[0] = x1 + t * dx1;
  const oy = out[1] = y1 + t * dy1;
  return Math.sqrt((ox - x) * (ox - x) + (oy - y) * (oy - y));
}
function projectPointToRect(x1, y1, width, height, x, y, out, mut) {
  if (!mut.rectSigned) {
    if (width < 0) {
      x1 = x1 + width;
      width = -width;
    }
    if (height < 0) {
      y1 = y1 + height;
      height = -height;
    }
  }
  const x2 = x1 + width;
  const y2 = y1 + height;
  const ox = out[0] = Math.min(Math.max(x, x1), x2);
  const oy = out[1] = Math.min(Math.max(y, y1), y2);
  return Math.sqrt((ox - x) * (ox - x) + (oy - y) * (oy - y));
}
function cubicAt(p0, p1, p2, p3, t) {
  const onet = 1 - t;
  return onet * onet * (onet * p0 + 3 * t * p1) + t * t * (t * p3 + 3 * onet * p2);
}
function quadraticAt(p0, p1, p2, t) {
  const onet = 1 - t;
  return onet * (onet * p0 + 2 * t * p1) + t * t * p2;
}
function curveProject(at, xs, ys, x, y, out, mut) {
  let t;
  let interval = 0.005;
  let d = Infinity;
  const sq = (ax, ay) => (ax - x) * (ax - x) + (ay - y) * (ay - y);
  for (let _t = 0; _t < 1; _t += 0.05) {
    const d1 = sq(at(xs, _t), at(ys, _t));
    if (d1 < d) {
      t = _t;
      d = d1;
    }
  }
  d = Infinity;
  for (let i = 0; i < (mut.fewSteps ? 4 : 32); i++) {
    if (interval < 1e-4) break;
    const prev = t - interval;
    const next = t + interval;
    const d1 = sq(at(xs, prev), at(ys, prev));
    if (prev >= 0 && d1 < d) {
      t = prev;
      d = d1;
    }
    else {
      const d2 = sq(at(xs, next), at(ys, next));
      if (next <= 1 && d2 < d) {
        t = next;
        d = d2;
      }
      else interval *= 0.5;
    }
  }
  out[0] = at(xs, t);
  out[1] = at(ys, t);
  return Math.sqrt(d);
}
const cubicAtArr = (p, t) => cubicAt(p[0], p[1], p[2], p[3], t);
const quadAtArr = (p, t) => quadraticAt(p[0], p[1], p[2], t);
// note: the curve functions square through distSquare(v1, v0) in either
// order; (a - x)^2 == (x - a)^2 bit for bit
function nearestPointOnPath(px, py, data, out, mut) {
  let xi = 0;
  let yi = 0;
  let x0 = 0;
  let y0 = 0;
  let minDist = Infinity;
  const tmp = [0, 0];
  const x = px;
  const y = py;
  for (let i = 0; i < data.length;) {
    const cmd = data[i++];
    if (i === 1 && !mut.noSeed) {
      xi = data[i];
      yi = data[i + 1];
      x0 = xi;
      y0 = yi;
    }
    let d = minDist;
    switch (cmd) {
      case 1:
        x0 = data[i++];
        y0 = data[i++];
        xi = x0;
        yi = y0;
        break;
      case 2:
        d = projectPointToLine(xi, yi, data[i], data[i + 1], x, y, tmp, !mut.lineUnclamped);
        xi = data[i++];
        yi = data[i++];
        break;
      case 3:
        d = curveProject(cubicAtArr, [xi, data[i], data[i + 2], data[i + 4]], [yi, data[i + 1], data[i + 3], data[i + 5]], x, y, tmp, mut);
        i += 4;
        xi = data[i++];
        yi = data[i++];
        break;
      case 4:
        d = curveProject(quadAtArr, [xi, data[i], data[i + 2]], [yi, data[i + 1], data[i + 3]], x, y, tmp, mut);
        i += 2;
        xi = data[i++];
        yi = data[i++];
        break;
      case 5: {
        const cx = data[i++];
        const cy = data[i++];
        const rx = data[i++];
        const ry = data[i++];
        const theta = data[i++];
        const dTheta = data[i++];
        i += 1;
        const anticlockwise = !!(1 - data[i++]);
        const _x = mut.arcNoScale ? x : (x - cx) * ry / rx + cx;
        d = projectPointToArc(cx, cy, ry, theta, theta + dTheta, anticlockwise, _x, y, tmp, mut);
        xi = Math.cos(theta + dTheta) * rx + cx;
        yi = Math.sin(theta + dTheta) * ry + cy;
        break;
      }
      case 7: {
        x0 = xi = data[i++];
        y0 = yi = data[i++];
        const width = data[i++];
        const height = data[i++];
        d = projectPointToRect(x0, y0, width, height, x, y, tmp, mut);
        break;
      }
      case 6:
        if (!mut.noClose) d = projectPointToLine(xi, yi, x0, y0, x, y, tmp, true);
        xi = x0;
        yi = y0;
        break;
    }
    if (mut.lessEqual ? d <= minDist : d < minDist) {
      minDist = d;
      out[0] = tmp[0];
      out[1] = tmp[1];
    }
  }
  return minDist;
}
function invert(a) {
  const aa = a[0], ac = a[2], atx = a[4], ab = a[1], ad = a[3], aty = a[5];
  let det = aa * ad - ab * ac;
  if (!det) return null;
  det = 1.0 / det;
  return [ad * det, -ab * det, -ac * det, aa * det, (ac * aty - ad * atx) * det, (ab * atx - aa * aty) * det];
}
function applyM(m, p) {
  if (!m) return p;
  return [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]];
}
function rectApply(r, m) {
  if (!m) return r.slice();
  if (m[1] < 1e-5 && m[1] > -1e-5 && m[2] < 1e-5 && m[2] > -1e-5) {
    const o = [r[0] * m[0] + m[4], r[1] * m[3] + m[5], r[2] * m[0], r[3] * m[3]];
    if (o[2] < 0) { o[0] += o[2]; o[2] = -o[2]; }
    if (o[3] < 0) { o[1] += o[3]; o[3] = -o[3]; }
    return o;
  }
  const c = [applyM(m, [r[0], r[1]]), applyM(m, [r[0] + r[2], r[1]]), applyM(m, [r[0] + r[2], r[1] + r[3]]), applyM(m, [r[0], r[1] + r[3]])];
  // mathMin(lt.x, rb.x, lb.x, rt.x)
  const xs = [c[0][0], c[2][0], c[3][0], c[1][0]];
  const ys = [c[0][1], c[2][1], c[3][1], c[1][1]];
  const x = Math.min(...xs);
  const y = Math.min(...ys);
  return [x, y, Math.max(...xs) - x, Math.max(...ys) - y];
}
// updateLabelLinePoints from what it read; answers the points before the turn limit
function updateLine(rec, mut) {
  const rawRect = rec.raw.map(fromHex);
  const labelM = rec.labelM ? rec.labelM.map(fromHex) : null;
  const tm = rec.targetM ? rec.targetM.map(fromHex) : null;
  const r = mut.rectFresh ? rawRect : rectApply(rawRect, labelM);
  const inv = tm ? invert(tm) : null;
  const len = fromHex(rec.len);
  const anchor = rec.anchor ? unhex2(rec.anchor) : null;
  const data = rec.path ? rec.path.map(fromHex) : null;
  const points = [[0, 0], [0, 0], [0, 0]];
  let pt2 = anchor ? anchor.slice() : [0, 0];
  let minDist = Infinity;
  const order = mut.order ? ['right', 'top', 'bottom', 'left'] : ['top', 'right', 'bottom', 'left'];
  for (const cand of order) {
    let p0, dir;
    if (cand === 'top') { p0 = [r[0] + r[2] / 2, r[1] - 0]; dir = [0, -1]; }
    else if (cand === 'bottom') { p0 = [r[0] + r[2] / 2, r[1] + r[3] + 0]; dir = [0, 1]; }
    else if (cand === 'left') { p0 = [r[0] - 0, r[1] + r[3] / 2]; dir = [-1, 0]; }
    else { p0 = [r[0] + r[2] + 0, r[1] + r[3] / 2]; dir = [1, 0]; }
    const l = mut.noLen ? 0 : len;
    let p1 = [p0[0] + dir[0] * l, p0[1] + dir[1] * l];
    if (!mut.noInverse) p1 = applyM(inv, p1);
    let dist;
    if (anchor) {
      const dx = anchor[0] - p1[0];
      const dy = anchor[1] - p1[1];
      dist = Math.sqrt(dx * dx + dy * dy);
    }
    else {
      must(data, 'a non-path host');
      const o = [pt2[0], pt2[1]];
      dist = nearestPointOnPath(p1[0], p1[1], data, o, mut);
      pt2 = o;
    }
    if (mut.lessEqual ? dist <= minDist : dist < minDist) {
      minDist = dist;
      if (!mut.noInverse) p1 = applyM(tm, p1);
      pt2 = applyM(tm, pt2);
      points[0] = pt2.slice();
      points[1] = p1.slice();
      points[2] = p0.slice();
    }
  }
  return points;
}
function cosOf(a) { return Math.cos(a); }
function limitTurnAngle(p, minTurnAngle, mut) {
  if (!(minTurnAngle <= 180 && minTurnAngle > 0)) return;
  minTurnAngle = minTurnAngle / 180 * Math.PI;
  const pt0 = p[0].slice(), pt1 = p[1].slice(), pt2 = p[2].slice();
  let dir = [pt0[0] - pt1[0], pt0[1] - pt1[1]];
  let dir2 = [pt2[0] - pt1[0], pt2[1] - pt1[1]];
  const len1 = Math.sqrt(dir[0] * dir[0] + dir[1] * dir[1]);
  const len2 = Math.sqrt(dir2[0] * dir2[0] + dir2[1] * dir2[1]);
  if (len1 < 1e-3 || len2 < 1e-3) return;
  dir = [dir[0] * (1 / len1), dir[1] * (1 / len1)];
  dir2 = [dir2[0] * (1 / len2), dir2[1] * (1 / len2)];
  const angleCos = dir[0] * dir2[0] + dir[1] * dir2[1];
  const minTurnAngleCos = cosOf(minTurnAngle);
  if (minTurnAngleCos < angleCos) {
    const tmp = [0, 0];
    const d = projectPointToLine(pt1[0], pt1[1], pt2[0], pt2[1], pt0[0], pt0[1], tmp, false);
    const k = d / Math.tan(Math.PI - minTurnAngle);
    const proj = [tmp[0] + dir2[0] * k, tmp[1] + dir2[1] * k];
    const t = pt2[0] !== pt1[0] ? (proj[0] - pt1[0]) / (pt2[0] - pt1[0]) : (proj[1] - pt1[1]) / (pt2[1] - pt1[1]);
    if (isNaN(t)) return;
    let q = proj;
    if (!mut.noClamp) {
      if (t < 0) q = pt1;
      else if (t > 1) q = pt2;
    }
    p[1] = [q[0], q[1]];
  }
}
function limitSurfaceAngle(p, normal, maxSurfaceAngle, mut) {
  if (!(maxSurfaceAngle <= 180 && maxSurfaceAngle > 0)) return;
  maxSurfaceAngle = maxSurfaceAngle / 180 * Math.PI;
  const pt0 = p[0].slice(), pt1 = p[1].slice(), pt2 = p[2].slice();
  let dir = [pt1[0] - pt0[0], pt1[1] - pt0[1]];
  let dir2 = [pt2[0] - pt1[0], pt2[1] - pt1[1]];
  const len1 = Math.sqrt(dir[0] * dir[0] + dir[1] * dir[1]);
  const len2 = Math.sqrt(dir2[0] * dir2[0] + dir2[1] * dir2[1]);
  if (len1 < 1e-3 || len2 < 1e-3) return;
  dir = [dir[0] * (1 / len1), dir[1] * (1 / len1)];
  dir2 = [dir2[0] * (1 / len2), dir2[1] * (1 / len2)];
  const angleCos = dir[0] * normal[0] + dir[1] * normal[1];
  const maxSurfaceAngleCos = Math.cos(maxSurfaceAngle);
  if (angleCos < maxSurfaceAngleCos) {
    const tmp = [0, 0];
    const d = projectPointToLine(pt1[0], pt1[1], pt2[0], pt2[1], pt0[0], pt0[1], tmp, false);
    let q = [tmp[0], tmp[1]];
    const HALF_PI = Math.PI / 2;
    const angle2 = Math.acos(dir2[0] * normal[0] + dir2[1] * normal[1]);
    const newAngle = HALF_PI + angle2 - maxSurfaceAngle;
    if (newAngle >= HALF_PI && !mut.noParallel) {
      q = pt2;
    }
    else {
      const k = d / Math.tan(Math.PI / 2 - newAngle);
      q = [q[0] + dir2[0] * k, q[1] + dir2[1] * k];
      const t = pt2[0] !== pt1[0] ? (q[0] - pt1[0]) / (pt2[0] - pt1[0]) : (q[1] - pt1[1]) / (pt2[1] - pt1[1]);
      if (isNaN(t)) return;
      if (!mut.noClamp) {
        if (t < 0) q = pt1;
        else if (t > 1) q = pt2;
      }
    }
    p[1] = [q[0], q[1]];
  }
}
function smoothCalls(p, smooth, mut) {
  const calls = [['M', hex(p[0][0]), hex(p[0][1])]];
  if (smooth > 0 && p.length >= 3) {
    const dd = (a, b) => Math.sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]));
    const len1 = dd(p[0], p[1]);
    const len2 = dd(p[1], p[2]);
    if (!len1 || !len2) {
      calls.push(['L', hex(p[1][0]), hex(p[1][1])], ['L', hex(p[2][0]), hex(p[2][1])]);
      return calls;
    }
    const moveLen = (mut.smoothMax ? Math.max(len1, len2) : Math.min(len1, len2)) * smooth;
    const lerp = (a, b, t) => [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])];
    const m0 = lerp(p[1], p[0], moveLen / len1);
    const m2 = lerp(p[1], p[2], moveLen / len2);
    const m1 = lerp(m0, m2, 0.5);
    calls.push(['C', hex(m0[0]), hex(m0[1]), hex(m0[0]), hex(m0[1]), hex(m1[0]), hex(m1[1])]);
    calls.push(['C', hex(m2[0]), hex(m2[1]), hex(m2[0]), hex(m2[1]), hex(p[2][0]), hex(p[2][1])]);
  }
  else for (let i = 1; i < p.length; i++) calls.push(['L', hex(p[i][0]), hex(p[i][1])]);
  return calls;
}
const angleOf = v => (typeof v === 'string' && v.indexOf('Infinity') >= 0 ? +v : v);
const unpts = a => a.map(unhex2);
const ptsHex = a => a.map(q => [hex(q[0]), hex(q[1])]).join();

// what a mutation changes: the rules' ids and the cases' ids
function rulesChanged(rules, mut) {
  const changed = new Set();
  for (const r of rules.project) {
    const data = rules.paths[r.path].data.map(fromHex);
    const o = [12345.5, -6789.25];
    const d = nearestPointOnPath(fromHex(r.pt[0]), fromHex(r.pt[1]), data, o, mut);
    const out = (o[0] === 12345.5 && o[1] === -6789.25) ? null : [hex(o[0]), hex(o[1])];
    if (hex(d) !== r.dist || JSON.stringify(out) !== JSON.stringify(r.out)) changed.add('project:' + r.path);
  }
  for (const r of rules.turn) {
    const p = unpts(r.pts);
    limitTurnAngle(p, angleOf(r.angle), mut);
    if (ptsHex(p) !== r.out.join()) changed.add('turn');
  }
  for (const r of rules.surface) {
    const p = unpts(r.pts);
    limitSurfaceAngle(p, unhex2(r.normal), angleOf(r.angle), mut);
    if (ptsHex(p) !== r.out.join()) changed.add('surface');
  }
  for (const r of rules.smooth) {
    if (JSON.stringify(smoothCalls(unpts(r.pts), fromHex(r.smooth), mut)) !== JSON.stringify(r.calls)) changed.add('smooth');
  }
  return changed;
}
function caseChanged(c, mut) {
  for (const l of c.lines) {
    const pre = updateLine(l, mut);
    if (ptsHex(pre) !== l.pre.join()) return true;
    const post = pre.map(q => q.slice());
    limitTurnAngle(post, angleOf(l.minTurnAngle), mut);
    if (ptsHex(post) !== l.post.join()) return true;
  }
  for (const r of c.pie) {
    const p = unpts(r.pre);
    limitTurnAngle(p, angleOf(r.minTurnAngle), mut);
    limitSurfaceAngle(p, unhex2(r.normal), angleOf(r.maxSurfaceAngle), mut);
    if (ptsHex(p) !== r.post.join()) return true;
  }
  for (const g of c.guides) {
    if (JSON.stringify(smoothCalls(unpts(g.points), fromHex(g.smooth), mut)) !== JSON.stringify(g.calls)) return true;
  }
  return false;
}

const GUARDS = [
  { id: 'absArc', mutation: 'projectPointToArc answers |d - r| (a point inside a circle no nearer than one outside)', mut: { absArc: true }, named: ['scatter.plain', 'project:sym.circle'] },
  { id: 'arcEndsTrue', mutation: 'the arc\'s ends measured against the point itself, not its unit direction', mut: { arcEndsTrue: true }, named: ['project:sector.wrap', 'sym.pin'] },
  { id: 'arcNoScale', mutation: 'an elliptical arc measured without scaling x by ry / rx', mut: { arcNoScale: true }, named: ['project:svg.arc', 'project:sym.pin'] },
  { id: 'lineUnclamped', mutation: 'a line segment projected without clamping to its ends', mut: { lineUnclamped: true }, named: ['project:polyline', 'sym.triangle'] },
  { id: 'noClose', mutation: 'closePath\'s segment not measured', mut: { noClose: true }, named: ['project:polygon'] },
  { id: 'rectSigned', mutation: 'a rect of negative size not normalised', mut: { rectSigned: true }, named: ['project:rect.neg', 'bar.neg'] },
  { id: 'fewSteps', mutation: 'the curve projection refined in 4 steps, not 32', mut: { fewSteps: true }, named: ['project:svg.cq', 'sym.pin'] },
  { id: 'lessEqual', mutation: 'a later candidate or segment wins a tie', mut: { lessEqual: true }, named: ['project:rect.round', 'bar.neg'] },
  { id: 'order', mutation: 'the candidates searched right, top, bottom, left', mut: { order: true }, named: ['bar.neg'] },
  { id: 'noLen', mutation: 'length2 ignored', mut: { noLen: true }, named: ['scatter.len2', 'pie.x'] },
  { id: 'noInverse', mutation: 'the candidate not carried into the host\'s frame (nor back)', mut: { noInverse: true }, named: ['scatter.dxdy', 'sym.rotate'] },
  { id: 'rectFresh', mutation: 'the label rect left untransformed', mut: { rectFresh: true }, named: ['scatter.dxdy', 'bar.top.y'] },
  { id: 'noClamp', mutation: 'the limits never clamp the new middle point to the segment', mut: { noClamp: true }, named: ['turn', 'pie.turn.120'] },
  { id: 'noParallel', mutation: 'limitSurfaceAngle without its parallel branch', mut: { noParallel: true }, named: ['surface', 'pie.surface.45'] },
  { id: 'noSeed', mutation: 'the first command does not seed the current point', mut: { noSeed: true }, named: ['project:raw.lineFirst'] },
  { id: 'smoothMax', mutation: 'the smooth length from the longer segment', mut: { smoothMax: true }, named: ['smooth', 'smooth.num', 'pie.smooth.num'] },
];

// ---------- generation ----------
function generate() {
  const rules = genRules();
  // the transcription reproduces the rules
  const none = rulesChanged(rules, {});
  must(none.size === 0, 'the transcription disagrees with the rules: ' + Array.from(none).join(', '));
  const cases = CASES.map(runCase);
  for (const c of cases) must(!caseChanged(c, {}), c.id + ': the transcription disagrees');
  const byId = {};
  for (const c of cases) byId[c.id] = c;
  // anchors
  const lineCount = id => byId[id].lines.length;
  must(lineCount('scatter.plain') === 12 && byId['scatter.plain'].guides.length === 12, 'anchor: every scatter label has a line');
  must(lineCount('pie.x') > 0 && byId['pie.x'].lines.every(l => l.anchor), 'anchor: a pie given an x routes from its anchor');
  must(lineCount('pie.points') === 0, 'anchor: labelLinePoints are not routed again');
  must(lineCount('pie.points.xy') === 0, 'anchor: an x with labelLinePoints is not routed');
  must(byId['pie.xy.turn179'].lines.some(l => l.pre.join() !== l.post.join()), 'anchor: minTurnAngle 179 bends a routed pie line');
  must(byId['pie.x.smooth'].guides.some(g => g.calls.some(k => k[0] === 'C')), 'anchor: a routed smooth pie line curves');
  must(lineCount('pie.dy') === 0 && byId['pie.dy'].pie.length > 0, 'anchor: dy alone is not routed, the pie still bends');
  must(byId['pie.solver'].pie.some(r => r.pre.join() !== r.post.join()), 'anchor: the default limits bend a moved pie label\'s line');
  must(byId['pie.unmoved.150'].pie.some(r => r.pre.join() !== r.post.join()), 'anchor: minTurnAngle 150 bends unmoved lines');
  must(byId['turn.150'].lines.some(l => l.pre.join() !== l.post.join()), 'anchor: minTurnAngle bends a scatter line');
  must(byId['hide'].guides.some(g => g.ignore) && byId['hide'].guides.some(g => !g.ignore), 'anchor: hideOverlap hides some lines');
  must(byId['smooth.true'].guides.every(g => g.calls.some(k => k[0] === 'C')), 'anchor: smooth lines curve');
  must(byId['smooth.hover'].hover.some(h => h.guides.some(g => g.smooth === hex(0) && !g.ignore)), 'anchor: a smooth line straightens under emphasis');
  must(byId['emph.only'].guides.length > 0 && byId['emph.only'].guides.every(g => g.ignore), 'anchor: an emphasis-only label\'s line is hidden at rest');
  must(byId['scatter.plain'].lines.every(l => fromHex(l.raw[0]) === 0 && fromHex(l.raw[1]) === 0), 'anchor: without labelLayout the rect is read left / top');
  // guards
  const ruleIds = rulesChanged;
  const guards = GUARDS.map(g => {
    const changed = Array.from(ruleIds(rules, g.mut)).concat(cases.filter(c => caseChanged(c, g.mut)).map(c => c.id));
    const ok = g.named.every(n => changed.indexOf(n) >= 0);
    return { id: g.id, mutation: g.mutation, named: g.named, changed, ok };
  });
  if (process.env.LG_DEBUG) {
    for (const c of cases) console.error(c.id, 'lines', c.lines.length, 'pie', c.pie.length, 'guides', c.guides.length);
    for (const g of guards) console.error('guard', g.id, g.ok, JSON.stringify(g.changed));
  }
  for (const g of guards) must(g.ok, 'guard ' + g.id + ' does not change ' + g.named.filter(n => g.changed.indexOf(n) < 0).join(', '));
  return {
    source: 'echarts ' + echarts.version + ' (' + path.basename(DIST) + '), node SSR, SVG renderer',
    W, H, seed: SEED,
    handlers: HANDLER_NOTES,
    notes: [
      'lines[] are LabelManager\'s updateLabelLinePoints calls; pie[] the pie layout\'s own limit calls; guides[] every label line as drawn.',
      'The label rect is read before getComputedTransform: a label LabelManager never laid out still has no alignment from its host.',
      'projectPointToArc answers d - r on the arc (negative inside a circle) and measures the ends against the unit direction.',
    ],
    rules,
    cases,
    guards,
  };
}

let code = 0;
try {
  const a = JSON.stringify(generate(), null, 1);
  const b = JSON.stringify(generate(), null, 1);
  must(a === b, 'two generations differ');
  fs.writeFileSync(OUT, a + '\n');
  console.log('wrote ' + OUT + ' (' + a.length + ' bytes)');
}
catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e);
  code = 1;
}
Math.random = jsRandom;
process.exit(code);
