// Upstream's own answers for SERIES LABEL LAYOUT -- `series.labelLayout` as
// an object or as a function, handled by label/LabelManager.ts with
// label/labelLayoutHelper.ts: what updateLayoutConfig makes of x / y (px or
// percent of the chart), dx / dy (the host's textConfig.offset, applied
// INSIDE the rotation through the origin), rotate, align / verticalAlign and
// fontSize; which labels moveOverlap 'shiftX' / 'shiftY' moves and where
// (shiftLayoutOnXY, squeeze and bail-out included); which labels hideOverlap
// hides (sorted by the host rect's area, stable, AABB then OBB, touch
// threshold 0.05), the label line hidden with its label and the emphasis
// state that re-shows both; and the params a function form is called with.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 600 x 400, with
// Math.random replaced by the port's xorshift32 (seed 2463534242, reset
// before each chart). The LabelManager is reached through the chart's
// ExtensionAPI (its makeInner store) and its prototype's `layout` is wrapped
// (the original still runs): the label list is snapshotted on entry -- after
// updateLayoutConfig -- and on exit. After setOption the chart is rendered
// once to an SVG string and every series label is read off the live
// elements. A few cases dispatch `highlight` and read the labels again.
// Every chart is disposed in a finally.
//
//   node tools/advchart-oracle/label-layout.js
//
// writes tests/fixtures/advchart-label-layout.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as sampling.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (NaN 7ff8000000000000)
//   rect     [x, y, width, height] in hex
//   mat      [m0 .. m5] in hex (zrender's matrix: x' = m0 x + m2 y + m4,
//            y' = m1 x + m3 y + m5), or null for no transform
//   option   recorded as fed, every function replaced by its '@Name'
//   layout value  a resolved labelLayout as JSON with every number written
//            ['n', hex] (a labelLinePoints point is [['n', hex], ['n', hex]])
//
// Top level
//   source, W, H, seed, handlers{name: description}, notes[]
//   cases[]  one per chart:
//     id, note, option
//     manager[]   the LabelManager's _labelList in its own order (series in
//                 series order, each series' labels in its group's traverse
//                 order), each:
//       s, d (ecData.dataIndex, null when none), dataType, text,
//       host (rect: hostEl.getBoundingRect() through its computed transform,
//       or null), priority (hex: host width * height, 0 without a host),
//       labelRect (rect: the label's global bounding rect when added),
//       def {ignore, guideIgnore (null: no label line), x, y, rotation (hex:
//            the decomposed transform when added), align, verticalAlign
//            (the label style's, null when unset), attachedPos
//            (textConfig.position as JSON), attachedRot (hex or null)},
//       layout       the resolved layout option (layout value)
//       entry {     at layout(), after updateLayoutConfig:
//         rawLocal (rect: label.getBoundingRect()), marginType (null, 1
//         minMargin, 2 textMargin), margin [4 hex] | null,
//         local (rect, textMargin applied), transform (mat), rect (global,
//         minMargin applied), axisAligned,
//         inner {x, y, originX, originY, rotation, scaleX, scaleY} (hex:
//         the label's innerTransformable after the host's updateInnerText;
//         the scale is the one LabelManager decomposed from the label's
//         first transform, 0.9999999999999999 after a turn),
//         labelX, labelY (hex: label.x / label.y), position (the host's
//         textConfig.position as JSON: null once x or y is given), offset
//         [hex, hex] (textConfig.offset), ignore,
//         emph (label.states.emphasis.ignore: 'absent' (no state), null,
//         true or false), guideEmph (the same for the label line, or
//         'none' without one) }
//       exit {ignore, guideIgnore (null without a line), labelX, labelY,
//             emph, guideEmph}
//     labels[]    every label of every series after the render, series in
//                 order, each series' group in traverse order (ignored hosts
//                 skipped): s, d, text, ignore, mat (computed transform),
//                 local (rect: getBoundingRect), align / verticalAlign (the
//                 ones drawn: style, else the host's default, else
//                 left / top), fontSize (style.fontSize or null),
//                 guide {ignore, points [[hex, hex] ...]} | null
//     calls[]     a function form's invocations, in order: {s, d, dataType,
//                 text, rect, labelRect, align, verticalAlign,
//                 labelLinePoints ([[hex, hex] ...] | null)}
//     hover[]     {payload, labels: [{s, d, ignore, guideIgnore}]} -- after
//                 dispatchAction(payload) and one _onframe (where the state
//                 lists are applied); downplayed (and framed) afterwards
//   guards[]  one per mutation of the transcription: id, mutation, named,
//             changed, ok = named is a subset of changed
//
// ---------------------------------------------------------------------------
// The transcription (checked against every case, bit for bit) is
// labelLayoutHelper.ts' computeLabelGeometry (margins), shiftLayoutOnXY,
// restoreIgnore, hideOverlap and labelIntersect (BoundingRect.intersect and
// OrientedBoundingRect with the touch threshold), LabelManager.layout's
// filters, and Transformable.getLocalTransform from the recorded inner
// transformable. Its inputs are `entry`; its outputs `exit` and
// `entry.transform`.
//
// Self-checks (any failure: nothing is written, exit 1): the transcription
// reproduces every case; every guard is ok; anchors; two generations in the
// process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-label-layout.json');

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

// ---------- number records ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const rect4 = r => [hex(r.x), hex(r.y), hex(r.width), hex(r.height)];
const mat6 = m => (m ? Array.from(m).map(hex) : null);
const unrect = a => ({ x: num(a[0]), y: num(a[1]), width: num(a[2]), height: num(a[3]) });
const unmat = a => (a ? a.map(num) : null);
const clone = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
function layoutValue(v) {
  if (typeof v === 'number') return ['n', hex(v)];
  if (Array.isArray(v)) return v.map(layoutValue);
  if (v && typeof v === 'object') {
    const r = {};
    for (const k of Object.keys(v)) r[k] = layoutValue(v[k]);
    return r;
  }
  return v === undefined ? null : v;
}
function unlayout(v) {
  if (Array.isArray(v)) {
    if (v.length === 2 && v[0] === 'n' && typeof v[1] === 'string') return num(v[1]);
    return v.map(unlayout);
  }
  if (v && typeof v === 'object') {
    const r = {};
    for (const k of Object.keys(v)) r[k] = unlayout(v[k]);
    return r;
  }
  return v;
}
function stateIgnore(el) {
  if (!el) return 'none';
  const st = el.states && el.states.emphasis;
  if (!st) return 'absent';
  return st.ignore == null ? null : !!st.ignore;
}

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

// ---------- the label geometry, as computeLabelGeometry makes it ----------
// expandOrShrinkRect(rect, delta, false, false) on a plain {x, y, width, height}
function expandOnDim(r, delta, xy, wh, lt, rb) {
  const deltaSum = delta[rb] + delta[lt];
  const oldSize = r[wh];
  r[wh] += deltaSum;
  const minSize = Math.max(0, Math.min(0, oldSize));
  if (r[wh] < minSize) {
    r[wh] = minSize;
    r[xy] += (delta[lt] >= 0 ? -delta[lt]
      : delta[rb] >= 0 ? oldSize + delta[rb]
        : Math.abs(deltaSum) > 1e-8 ? (oldSize - minSize) * delta[lt] / deltaSum : 0);
  } else {
    r[xy] -= delta[lt];
  }
}
function expandRect(r, delta) {
  expandOnDim(r, delta, 'x', 'width', 3, 1);
  expandOnDim(r, delta, 'y', 'height', 0, 2);
}
// BoundingRect.applyTransform (static), on plain objects
function applyTransform(out, m) {
  if (!m) return;
  if (m[1] < 1e-5 && m[1] > -1e-5 && m[2] < 1e-5 && m[2] > -1e-5) {
    const sx = m[0];
    const sy = m[3];
    const tx = m[4];
    const ty = m[5];
    out.x = out.x * sx + tx;
    out.y = out.y * sy + ty;
    out.width = out.width * sx;
    out.height = out.height * sy;
    if (out.width < 0) {
      out.x += out.width;
      out.width = -out.width;
    }
    if (out.height < 0) {
      out.y += out.height;
      out.height = -out.height;
    }
    return;
  }
  const pts = [[out.x, out.y], [out.x + out.width, out.y], [out.x + out.width, out.y + out.height], [out.x, out.y + out.height]];
  const tr = pts.map(p => [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]]);
  let minX = tr[0][0];
  let minY = tr[0][1];
  let maxX = tr[0][0];
  let maxY = tr[0][1];
  for (let i = 1; i < 4; i++) {
    minX = Math.min(minX, tr[i][0]);
    minY = Math.min(minY, tr[i][1]);
    maxX = Math.max(maxX, tr[i][0]);
    maxY = Math.max(maxY, tr[i][1]);
  }
  out.x = minX;
  out.y = minY;
  out.width = maxX - minX;
  out.height = maxY - minY;
}
const axisAlignedOf = m => !m || (Math.abs(m[1]) < 1e-5 && Math.abs(m[2]) < 1e-5)
  || (Math.abs(m[0]) < 1e-5 && Math.abs(m[3]) < 1e-5);
// computeLabelGeometry from the recorded pieces; mut.noTextMargin /
// mut.noMinMargin drop the two margins
function geometryOf(rawLocal, transform, marginType, margin, mut) {
  const local = Object.assign({}, rawLocal);
  const m = [0, 0, 0, 0];
  for (let i = 0; i < 4; i++) m[i] = margin ? margin[i] : 0;
  if (marginType === 2 && !mut.noTextMargin) expandRect(local, m);
  const rect = Object.assign({}, local);
  applyTransform(rect, transform);
  if (marginType === 1 && !mut.noMinMargin) expandRect(rect, m);
  return { local, transform, rect, axisAligned: axisAlignedOf(transform) };
}

// ---------- the LabelManager, reached through the chart's API ----------
let capture = null;
const LM = (() => {
  const c = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 100, height: 100 });
  try {
    c.setOption({ animation: false, xAxis: {}, yAxis: {}, series: [{ type: 'scatter', labelLayout: { hideOverlap: true }, label: { show: true }, data: [[1, 2]] }] });
    const api = c._api;
    for (const k of Object.keys(api)) {
      const v = api[k];
      if (v && typeof v === 'object' && v.labelManager) return Object.getPrototypeOf(v.labelManager);
    }
    throw new OracleError('no LabelManager on the API');
  } finally {
    c.dispose();
  }
})();
must(typeof LM.layout === 'function' && typeof LM.updateLayoutConfig === 'function', 'LabelManager without layout');

const hostEl = label => label.__hostTarget;
function entryOf(item) {
  const label = item.label;
  const t = label.getComputedTransform();
  const transform = t ? Array.from(t) : null;
  const raw = label.getBoundingRect();
  const rawLocal = { x: raw.x, y: raw.y, width: raw.width, height: raw.height };
  const st = label.style;
  const marginType = st.__marginType == null ? null : st.__marginType;
  const margin = st.margin ? Array.from(st.margin) : null;
  const g = geometryOf(rawLocal, transform, marginType, margin, {});
  const inner = label.innerTransformable;
  return {
    rawLocal: rect4(rawLocal),
    marginType,
    margin: margin ? margin.map(hex) : null,
    local: rect4(g.local),
    transform: mat6(transform),
    rect: rect4(g.rect),
    axisAligned: g.axisAligned,
    inner: inner ? {
      x: hex(inner.x), y: hex(inner.y), originX: hex(inner.originX || 0), originY: hex(inner.originY || 0),
      rotation: hex(inner.rotation || 0), scaleX: hex(inner.scaleX), scaleY: hex(inner.scaleY),
    } : null,
    labelX: hex(label.x),
    labelY: hex(label.y),
    position: clone(hostEl(label).textConfig.position),
    offset: (hostEl(label).textConfig.offset || [0, 0]).map(hex),
    ignore: !!label.ignore,
    emph: stateIgnore(label),
    guideEmph: item.labelLine ? stateIgnore(item.labelLine) : 'none',
  };
}
function exitOf(item) {
  const label = item.label;
  return {
    ignore: !!label.ignore,
    guideIgnore: item.labelLine ? !!item.labelLine.ignore : null,
    labelX: hex(label.x),
    labelY: hex(label.y),
    emph: stateIgnore(label),
    guideEmph: item.labelLine ? stateIgnore(item.labelLine) : 'none',
  };
}
function itemOf(item) {
  const def = item.defaultAttr;
  return {
    s: item.seriesModel.seriesIndex,
    d: item.dataIndex == null ? null : item.dataIndex,
    dataType: item.dataType || null,
    text: item.label.style.text,
    host: item.hostRect ? rect4(item.hostRect) : null,
    priority: hex(item.priority),
    labelRect: rect4(item.rect),
    def: {
      ignore: !!def.ignore,
      guideIgnore: item.labelLine ? !!def.labelGuideIgnore : null,
      x: hex(def.x),
      y: hex(def.y),
      rotation: hex(def.rotation),
      align: def.style.align == null ? null : def.style.align,
      verticalAlign: def.style.verticalAlign == null ? null : def.style.verticalAlign,
      attachedPos: clone(def.attachedPos),
      attachedRot: def.attachedRot == null ? null : hex(def.attachedRot),
    },
    layout: layoutValue(item.layoutOption),
  };
}
const origLayout = LM.layout;
LM.layout = function (api) {
  if (capture) {
    must(!capture.manager, 'the label layout ran twice');
    capture.manager = this._labelList.map(item => Object.assign(itemOf(item), { entry: entryOf(item) }));
  }
  const r = origLayout.call(this, api);
  if (capture) this._labelList.forEach((item, i) => { capture.manager[i].exit = exitOf(item); });
  return r;
};

// ---------- the function forms ----------
let calls = null;
function recordCall(p) {
  if (calls) {
    calls.push({
      s: p.seriesIndex,
      d: p.dataIndex == null ? null : p.dataIndex,
      dataType: p.dataType || null,
      text: p.text,
      rect: p.rect ? rect4(p.rect) : null,
      labelRect: rect4(p.labelRect),
      align: p.align == null ? null : p.align,
      verticalAlign: p.verticalAlign == null ? null : p.verticalAlign,
      labelLinePoints: p.labelLinePoints ? p.labelLinePoints.map(pt => [hex(pt[0]), hex(pt[1])]) : null,
    });
  }
}
const HANDLER_NOTES = {
  '@LL_DX': '{dx: d * 3 - 6, dy: (d % 3) * 2, hideOverlap: d % 2 === 0}',
  '@LL_RIGHT': '{x: rect.x + rect.width + 4, y: labelRect.y, align: "left", verticalAlign: "top", moveOverlap: "shiftY"}',
  '@LL_NONE': 'undefined',
  '@LL_ALIGN': '{align: align == null ? "right" : "left", fontSize: 16 + seriesIndex * 2, hideOverlap: true}',
  '@LL_TEXT': '{rotate: text.length * 10, hideOverlap: true}',
  '@LL_TOUCH': '{x: 100 + d * labelRect.width, y: 100, align: "left", verticalAlign: "top", hideOverlap: true}',
  '@LL_PIELINE': 'labelLinePoints with the last point moved to the label\'s near edge (labelRect.x < W / 2: its x, else x + width)',
};
const HANDLERS = {
  '@LL_DX': p => { recordCall(p); return { dx: p.dataIndex * 3 - 6, dy: (p.dataIndex % 3) * 2, hideOverlap: p.dataIndex % 2 === 0 }; },
  '@LL_RIGHT': p => {
    recordCall(p);
    return { x: p.rect.x + p.rect.width + 4, y: p.labelRect.y, align: 'left', verticalAlign: 'top', moveOverlap: 'shiftY' };
  },
  '@LL_NONE': p => { recordCall(p); return undefined; },
  '@LL_ALIGN': p => { recordCall(p); return { align: p.align == null ? 'right' : 'left', fontSize: 16 + p.seriesIndex * 2, hideOverlap: true }; },
  '@LL_TEXT': p => { recordCall(p); return { rotate: String(p.text).length * 10, hideOverlap: true }; },
  '@LL_TOUCH': p => { recordCall(p); return { x: 100 + p.dataIndex * p.labelRect.width, y: 100, align: 'left', verticalAlign: 'top', hideOverlap: true }; },
  '@LL_PIELINE': p => {
    recordCall(p);
    const isLeft = p.labelRect.x < W / 2;
    const points = p.labelLinePoints;
    if (!points) return {};
    points[2][0] = isLeft ? p.labelRect.x : p.labelRect.x + p.labelRect.width;
    return { labelLinePoints: points };
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
function scatter(series, extra) {
  return Object.assign({ animation: false, xAxis: {}, yAxis: {}, series }, extra || {});
}
const sc = (o) => Object.assign({ type: 'scatter', label: { show: true }, data: pts(40, 7, 13) }, o);
const lineData = n => Array.from({ length: n }, (_, i) => Math.round(50 + 40 * Math.sin(i / 3)));
const cats = n => Array.from({ length: n }, (_, i) => 'c' + i);
const barData = n => Array.from({ length: n }, (_, i) => 10 + (i * 37) % 90);
const pieData = (n, f) => Array.from({ length: n }, (_, i) => ({ name: 'p' + i, value: f(i) }));
function pie(seriesExtra, extra) {
  return Object.assign({
    animation: false,
    series: [Object.assign({ type: 'pie', radius: '45%', avoidLabelOverlap: false, data: pieData(24, i => (i * 7) % 11 + 1) }, seriesExtra)],
  }, extra || {});
}
function bars(seriesExtra, n) {
  n = n || 40;
  return {
    animation: false,
    xAxis: { type: 'category', data: cats(n) },
    yAxis: {},
    series: [Object.assign({ type: 'bar', label: { show: true, position: 'top' }, data: barData(n) }, seriesExtra)],
  };
}
const cluster = () => [[0, 0], [40, 40]].concat(Array.from({ length: 10 }, (_, i) => [20 + i * 0.3, 20 + (i % 3) * 0.3]));
const sized = n => pts(n, 7, 13).map((p, i) => ({ value: p, symbolSize: 4 + (i % 5) * 4 }));

const CASES = [
  // ---- hideOverlap ----
  { id: 'scatter.hide', note: 'a dense scatter, every label the same priority: traverse order decides',
    option: scatter([sc({ labelLayout: { hideOverlap: true } })]) },
  { id: 'scatter.nolayout', note: 'the same without labelLayout: nothing is hidden, the manager sees nothing',
    option: scatter([sc({})]) },
  { id: 'scatter.hide.sizes', note: 'symbol sizes differ: the bigger host keeps its label',
    option: scatter([sc({ labelLayout: { hideOverlap: true }, data: sized(40) })]) },
  { id: 'line.hide', note: 'a line\'s symbol labels on 60 categories',
    option: { animation: false, xAxis: { type: 'category', data: cats(60) }, yAxis: {},
      series: [{ type: 'line', showAllSymbol: true, label: { show: true }, labelLayout: { hideOverlap: true }, data: lineData(60) }] } },
  { id: 'bar.hide.top', note: 'bar labels on top; the priority is the bar\'s area',
    option: bars({ label: { show: true, position: 'top', formatter: 'v{c}' }, labelLayout: { hideOverlap: true }, data: lineData(60) }, 60) },
  { id: 'bar.hide.rotate90', note: 'labels turned 90 degrees: still axis aligned',
    option: bars({ label: { show: true, position: 'insideBottom', rotate: 90, formatter: 'value {c}' }, labelLayout: { hideOverlap: true } }, 60) },
  { id: 'scatter.rotate45', note: 'labels turned 45 degrees: the oriented boxes decide',
    option: scatter([sc({ label: { show: true, rotate: 45, formatter: 'v{c}' }, labelLayout: { hideOverlap: true }, data: pts(30, 5, 3) })]) },
  { id: 'scatter.layout.rotate30', note: 'labelLayout.rotate over label.rotate, hidden by oriented boxes',
    option: scatter([sc({ label: { show: true, rotate: 70, formatter: 'value {c}' }, labelLayout: { rotate: 30, hideOverlap: true }, data: pts(30, 5, 3) })]) },
  { id: 'touch', note: 'labels placed edge to edge: the 0.05 threshold keeps them',
    option: scatter([sc({ data: pts(6, 7, 13), label: { show: true, formatter: 'ab' }, labelLayout: '@LL_TOUCH' })]) },
  // ---- several series ----
  { id: 'multi.priority', note: 'two series on the same points: the bigger symbols win',
    option: scatter([sc({ symbolSize: 6, labelLayout: { hideOverlap: true }, data: pts(25, 7, 13) }),
      sc({ symbolSize: 14, labelLayout: { hideOverlap: true }, data: pts(25, 7, 13).map(p => [p[0] + 0.1, p[1]]) })]) },
  { id: 'multi.tie', note: 'two series, equal symbols: series order breaks the tie',
    option: scatter([sc({ labelLayout: { hideOverlap: true }, data: pts(25, 7, 13) }),
      sc({ labelLayout: { hideOverlap: true }, data: pts(25, 7, 13).map(p => [p[0] + 0.1, p[1]]) })]) },
  { id: 'multi.one', note: 'only the second series asks: the first one\'s labels are not in the list',
    option: scatter([sc({ symbolSize: 20, data: pts(25, 7, 13) }),
      sc({ labelLayout: { hideOverlap: true }, data: pts(25, 7, 13).map(p => [p[0] + 0.1, p[1]]) })]) },
  { id: 'multi.bar.line', note: 'a bar and a line on one category axis, both hiding',
    option: { animation: false, xAxis: { type: 'category', data: cats(30) }, yAxis: {},
      series: [{ type: 'bar', label: { show: true, position: 'top' }, labelLayout: { hideOverlap: true }, data: barData(30) },
        { type: 'line', label: { show: true }, labelLayout: { hideOverlap: true }, data: barData(30).map(v => v + 3) }] } },
  // ---- states ----
  { id: 'state.only', note: 'shown only under emphasis: ignored at rest, outside the layout',
    option: scatter([sc({ label: { show: false }, emphasis: { label: { show: true } }, labelLayout: { hideOverlap: true } })]) },
  { id: 'state.only.shift', note: 'labels ignored at rest take no part in a shift',
    option: scatter([sc({ label: { show: false }, emphasis: { label: { show: true } }, labelLayout: { x: '80%', moveOverlap: 'shiftY' },
      data: pts(12, 5, 3) }), sc({ labelLayout: { x: '80%', moveOverlap: 'shiftY' }, data: pts(12, 7, 13) })]) },
  { id: 'emphasis.reshow', note: 'a hidden label comes back under highlight',
    option: scatter([sc({ labelLayout: { hideOverlap: true }, data: cluster() })]),
    hover: [{ type: 'highlight', seriesIndex: 0, dataIndex: 3 }, { type: 'highlight', seriesIndex: 0, dataIndex: 2 }] },
  { id: 'emphasis.keep', note: 'emphasis.label.show false: a hidden label stays hidden under highlight',
    option: scatter([sc({ labelLayout: { hideOverlap: true }, emphasis: { label: { show: false } }, data: cluster() })]),
    hover: [{ type: 'highlight', seriesIndex: 0, dataIndex: 3 }, { type: 'highlight', seriesIndex: 0, dataIndex: 2 }] },
  // ---- text styles ----
  { id: 'rich.box', note: 'labels in a box: padding, background and border count',
    option: scatter([sc({ label: { show: true, backgroundColor: '#eee', padding: [3, 6], borderColor: '#999', borderWidth: 1 }, labelLayout: { hideOverlap: true } })]) },
  { id: 'rich.text', note: 'rich text in two lines',
    option: scatter([sc({ label: { show: true, formatter: '{a|{c}}\n{b|x}', rich: { a: { fontSize: 14 }, b: { fontSize: 9, padding: [0, 4] } } }, labelLayout: { hideOverlap: true } })]) },
  { id: 'text.border', note: 'a written text border is part of the rect',
    option: scatter([sc({ label: { show: true, textBorderColor: '#000', textBorderWidth: 6 }, labelLayout: { hideOverlap: true } })]) },
  { id: 'text.border.thin', note: 'a thin written border: the rect is the TSpan rect unioned with itself, (x + w) - x',
    option: scatter([sc({ label: { show: true, textBorderColor: '#000', textBorderWidth: 1.7 }, labelLayout: { hideOverlap: true } })]) },
  { id: 'margin.min', note: 'label.minMargin grows the global rect',
    option: scatter([sc({ label: { show: true, minMargin: 12 }, labelLayout: { hideOverlap: true } })]) },
  { id: 'margin.text', note: 'label.textMargin grows the local rect',
    option: scatter([sc({ label: { show: true, rotate: 30, textMargin: [4, 10] }, labelLayout: { hideOverlap: true } })]) },
  // ---- pie ----
  { id: 'pie.default', note: 'a pie\'s default labelLayout hides crowded labels and their lines',
    option: pie({}),
    hover: [{ type: 'highlight', seriesIndex: 0, dataIndex: 3 }, { type: 'highlight', seriesIndex: 0, dataIndex: 11 }] },
  { id: 'pie.inside', note: 'inside labels on thin slices',
    option: pie({ label: { position: 'inside' } }) },
  { id: 'pie.null', note: 'labelLayout null switches the default off',
    option: pie({ labelLayout: null }) },
  { id: 'pie.dxdy', note: 'dx / dy on a pie (merged over the default)',
    option: pie({ labelLayout: { dx: 10, dy: -6 }, data: pieData(8, i => i + 1) }) },
  { id: 'pie.shiftY', note: 'shiftY moves a pie\'s free labels',
    option: pie({ labelLayout: { moveOverlap: 'shiftY', hideOverlap: false }, data: pieData(16, i => (i % 4) + 1) }) },
  { id: 'pie.fn.line', note: 'a function moving the line\'s end (labelLinePoints)',
    option: pie({ labelLayout: '@LL_PIELINE', data: pieData(8, i => i * 2 + 1) }) },
  { id: 'pie.offset', note: 'label.offset survives the default layout on a pie: it is baked into x / y',
    option: pie({ label: { offset: [5, 7] }, data: pieData(6, i => i + 2) }) },
  // ---- moveOverlap ----
  { id: 'shiftY.x', note: 'labels moved to x 85% and shifted apart on y',
    option: scatter([sc({ labelLayout: { x: '85%', moveOverlap: 'shiftY' }, data: pts(18, 7, 13) })]) },
  { id: 'shiftX.y', note: 'labels moved to y 30 and shifted apart on x',
    option: scatter([sc({ labelLayout: { y: 30, moveOverlap: 'shiftX' }, data: pts(14, 7, 13) })]) },
  { id: 'shiftY.attached.hide', note: 'shiftY on attached labels draws nothing different, and hideOverlap reads them where they are drawn',
    option: scatter([sc({ labelLayout: { moveOverlap: 'shiftY', hideOverlap: true } })]) },
  { id: 'shiftY.squeeze', note: 'more labels than the height holds: squeezed, then let overlap',
    option: scatter([sc({ labelLayout: { x: 500, moveOverlap: 'shiftY' }, label: { show: true, fontSize: 14 }, data: pts(40, 7, 13) })]) },
  { id: 'shiftY.free.hide', note: 'labels moved to x 500, shifted on y past the height, then hidden where the shift put them',
    option: scatter([sc({ labelLayout: { x: 500, moveOverlap: 'shiftY', hideOverlap: true }, label: { show: true, fontSize: 14 }, data: pts(40, 7, 13) })]) },
  { id: 'shiftX.bounds', note: 'labels past the right edge: moved back by the free gap',
    option: scatter([sc({ labelLayout: { y: '50%', dx: 120, moveOverlap: 'shiftX' }, label: { show: true, formatter: 'label {c}' }, data: pts(12, 7, 13).map(p => [p[0] + 10, p[1]]) })]) },
  // ---- the config ----
  { id: 'cfg.dxdy', note: 'dx / dy on bar labels',
    option: bars({ labelLayout: { dx: 4, dy: -3 } }, 12) },
  { id: 'cfg.rotate', note: 'labelLayout.rotate over label.rotate',
    option: bars({ label: { show: true, position: 'top', rotate: 20 }, labelLayout: { rotate: -30 } }, 12) },
  { id: 'cfg.rotate.factor', note: 'rotate 23: rotate * (Math.PI / 180), the factor first',
    option: bars({ labelLayout: { rotate: 23 } }, 8) },
  { id: 'offset.rotate.nolayout', note: 'no labelLayout: label.rotate 41 (rotate * (PI / 180)) and label.offset inside the turn',
    option: bars({ label: { show: true, position: 'top', rotate: 41, offset: [6, -4] } }, 8) },
  { id: 'cfg.rotate.dxdy', note: 'a turned label\'s dx / dy run along the turned axes',
    option: bars({ labelLayout: { rotate: 40, dx: 10, dy: 5 } }, 12) },
  { id: 'cfg.xy', note: 'every label at one point, centred',
    option: scatter([sc({ labelLayout: { x: 120, y: 80, align: 'center', verticalAlign: 'middle' }, data: pts(5, 7, 13) })]) },
  { id: 'cfg.xy.pct', note: 'x / y as percentages of the chart',
    option: scatter([sc({ labelLayout: { x: '50%', y: '25%' }, data: pts(5, 7, 13) })]) },
  { id: 'cfg.y.only', note: 'y alone: x stays where the label was, the alignment is lost',
    option: bars({ label: { show: true, position: 'insideTop' }, labelLayout: { y: 50 } }, 8) },
  { id: 'cfg.offset.dropped', note: 'label.offset is replaced by [dx, dy] on an attached label',
    option: bars({ label: { show: true, position: 'top', offset: [10, 8] }, labelLayout: { dy: 2 } }, 8) },
  { id: 'cfg.fontSize', note: 'labelLayout.fontSize resizes the text before the overlap test',
    option: scatter([sc({ labelLayout: { fontSize: 18, hideOverlap: true }, data: pts(20, 7, 13) })]) },
  { id: 'cfg.align.words', note: '\'middle\' and \'center\' read as zrender reads them',
    option: bars({ labelLayout: { align: 'middle', verticalAlign: 'center' } }, 8) },
  { id: 'cfg.x.string', note: 'x a numeric string, y a position word',
    option: scatter([sc({ labelLayout: { x: '200', y: 'center' }, data: pts(4, 7, 13) })]) },
  { id: 'cfg.label.align', note: 'the label\'s own align survives an x',
    option: scatter([sc({ label: { show: true, align: 'right', verticalAlign: 'bottom' }, labelLayout: { x: 300 }, data: pts(5, 7, 13) })]) },
  // ---- the function form ----
  { id: 'fn.dx', note: 'a function: dx / dy by index, hideOverlap on every other label',
    option: scatter([sc({ labelLayout: '@LL_DX', data: pts(24, 7, 13) })]) },
  { id: 'fn.right', note: 'a function placing labels right of their host, shifted on y',
    option: scatter([sc({ labelLayout: '@LL_RIGHT', data: pts(16, 7, 13) })]) },
  { id: 'fn.none', note: 'a function returning nothing: an empty layout (the offset still dropped)',
    option: bars({ label: { show: true, position: 'top', offset: [0, -6] }, labelLayout: '@LL_NONE' }, 6) },
  { id: 'fn.align', note: 'a function reading params.align; two series',
    option: scatter([sc({ labelLayout: '@LL_ALIGN', data: pts(10, 7, 13) }),
      sc({ label: { show: true, align: 'left' }, labelLayout: '@LL_ALIGN', data: pts(10, 5, 3) })]) },
  { id: 'fn.text', note: 'a function turning each label by its text\'s length',
    option: scatter([sc({ label: { show: true, formatter: '{c}' }, labelLayout: '@LL_TEXT', data: pts(20, 5, 3) })]) },
  // ---- other series ----
  { id: 'effectScatter.hide', note: 'an effectScatter\'s labels',
    option: scatter([Object.assign(sc({ labelLayout: { hideOverlap: true }, data: pts(20, 7, 13) }), { type: 'effectScatter' })]) },
];

// ---------- one case ----------
function runCase(c) {
  rngState = SEED;
  calls = [];
  capture = {};
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(bind(c.option));
    const manager = capture.manager || [];
    capture = null;
    chart.renderToSVGString();
    const labels = [];
    chart.getModel().eachSeries(s => {
      const view = chart.getViewOfSeriesModel(s);
      view.group.traverse(el => {
        if (el.ignore) return true;
        const t = el.getTextContent && el.getTextContent();
        if (!t) return;
        const d = ecData(el);
        const m = t.getComputedTransform();
        const r = t.getBoundingRect();
        const ds = t._defaultStyle || {};
        const g = el.getTextGuideLine && el.getTextGuideLine();
        labels.push({
          s: s.seriesIndex,
          d: d && d.dataIndex != null ? d.dataIndex : null,
          text: t.style.text,
          ignore: !!t.ignore,
          mat: mat6(m),
          local: rect4(r),
          align: t.style.align || ds.align || 'left',
          verticalAlign: t.style.verticalAlign || ds.verticalAlign || 'top',
          fontSize: t.style.fontSize == null ? null : t.style.fontSize,
          guide: g ? { ignore: !!g.ignore, points: (g.shape.points || []).map(p => [hex(p[0]), hex(p[1])]) } : null,
        });
      });
    });
    const hover = [];
    for (const payload of c.hover || []) {
      chart.dispatchAction(payload);
      // the state lists are made in the frame (applyChangedStates)
      chart._onframe();
      const rec = [];
      chart.getModel().eachSeries(s => {
        chart.getViewOfSeriesModel(s).group.traverse(el => {
          if (el.ignore) return true;
          const t = el.getTextContent && el.getTextContent();
          if (!t) return;
          const d = ecData(el);
          const g = el.getTextGuideLine && el.getTextGuideLine();
          rec.push({ s: s.seriesIndex, d: d && d.dataIndex != null ? d.dataIndex : null, ignore: !!t.ignore, guideIgnore: g ? !!g.ignore : null });
        });
      });
      hover.push({ payload, labels: rec });
      chart.dispatchAction(Object.assign({}, payload, { type: 'downplay' }));
      chart._onframe();
    }
    const out = { id: c.id, note: c.note, option: clone(c.option), manager, labels, calls, hover };
    calls = null;
    return out;
  } finally {
    capture = null;
    calls = null;
    chart.dispose();
  }
}

// ---------- the transcription ----------
// BoundingRect.intersect without mtv, with the touch threshold
function rectIntersect(a, b, t) {
  const ax0 = a.x + t;
  const ax1 = a.x + a.width - t;
  const ay0 = a.y + t;
  const ay1 = a.y + a.height - t;
  const bx0 = b.x + t;
  const bx1 = b.x + b.width - t;
  const by0 = b.y + t;
  const by1 = b.y + b.height - t;
  if (ax0 > ax1 || ay0 > ay1 || bx0 > bx1 || by0 > by1) return false;
  return !(ax1 < bx0 || bx1 < ax0 || ay1 < by0 || by1 < ay0);
}
function obbOf(local, m) {
  const x = local.x;
  const y = local.y;
  const x2 = x + local.width;
  const y2 = y + local.height;
  const c = [[x, y], [x2, y], [x2, y2], [x, y2]];
  if (m) for (let i = 0; i < 4; i++) c[i] = [m[0] * c[i][0] + m[2] * c[i][1] + m[4], m[1] * c[i][0] + m[3] * c[i][1] + m[5]];
  const axes = [[c[1][0] - c[0][0], c[1][1] - c[0][1]], [c[3][0] - c[0][0], c[3][1] - c[0][1]]];
  for (const a of axes) {
    const d = Math.sqrt(a[0] * a[0] + a[1] * a[1]);
    a[0] /= d;
    a[1] /= d;
  }
  const origin = [axes[0][0] * c[0][0] + axes[0][1] * c[0][1], axes[1][0] * c[0][0] + axes[1][1] * c[0][1]];
  return { c, axes, origin };
}
function proj(self, corners, dim, t) {
  const ax = self.axes[dim];
  let p = corners[0][0] * ax[0] + corners[0][1] * ax[1] + self.origin[dim];
  let mn = p;
  let mx = p;
  for (let i = 1; i < 4; i++) {
    p = corners[i][0] * ax[0] + corners[i][1] * ax[1] + self.origin[dim];
    mn = Math.min(p, mn);
    mx = Math.max(p, mx);
  }
  const lo = mn + t;
  const hi = mx - t;
  return { lo, hi, neg: hi < lo };
}
function oneSide(self, other, t) {
  for (let i = 0; i < 2; i++) {
    const e1 = proj(self, self.c, i, t);
    const e2 = proj(self, other.c, i, t);
    if (e2.neg || e1.hi < e2.lo || e1.lo > e2.hi) return false;
  }
  return true;
}
function labelIntersect(a, b, mut) {
  const t = mut.touch0 ? 0 : 0.05;
  if (!rectIntersect(a.rect, b.rect, t)) return false;
  if (mut.aabbOnly || (a.axisAligned && b.axisAligned)) return true;
  const oa = obbOf(a.local, a.transform);
  const ob = obbOf(b.local, b.transform);
  return oneSide(oa, ob, t) && oneSide(ob, oa, t);
}
function shiftLayoutOnXY(list, dimIdx, minBound, maxBound, mut) {
  const len = list.length;
  const xy = dimIdx ? 'y' : 'x';
  const wh = dimIdx ? 'height' : 'width';
  const lxy = dimIdx ? 'labelY' : 'labelX';
  if (len < 2) return;
  list.sort((a, b) => a.rect[xy] - b.rect[xy]);
  let lastPos = 0;
  let delta;
  for (let i = 0; i < len; i++) {
    const item = list[i];
    const rect = item.rect;
    delta = rect[xy] - lastPos;
    if (delta < 0) {
      rect[xy] -= delta;
      item[lxy] -= delta;
    }
    lastPos = rect[xy] + rect[wh];
  }
  const first = list[0];
  const last = list[len - 1];
  let minGap;
  let maxGap;
  function updateMinMaxGap() {
    minGap = first.rect[xy] - minBound;
    maxGap = maxBound - last.rect[xy] - last.rect[wh];
  }
  function shiftList(d, start, end) {
    for (let i = start; i < end; i++) {
      list[i].rect[xy] += d;
      list[i][lxy] += d;
    }
  }
  function squeezeGaps(d, maxPct) {
    if (mut.noSqueeze) return;
    const gaps = [];
    let totalGaps = 0;
    for (let i = 1; i < len; i++) {
      const prev = list[i - 1].rect;
      const gap = Math.max(list[i].rect[xy] - prev[xy] - prev[wh], 0);
      gaps.push(gap);
      totalGaps += gap;
    }
    if (!totalGaps) return;
    const pct = Math.min(Math.abs(d) / totalGaps, maxPct);
    if (d > 0) {
      for (let i = 0; i < len - 1; i++) shiftList(gaps[i] * pct, 0, i + 1);
    } else {
      for (let i = len - 1; i > 0; i--) shiftList(-gaps[i - 1] * pct, i, len);
    }
  }
  function takeBoundsGap(gapThis, gapOther, dir) {
    if (mut.noTakeGap) return;
    if (gapThis < 0) {
      const moveFromMaxGap = Math.min(gapOther, -gapThis);
      if (moveFromMaxGap > 0) {
        shiftList(moveFromMaxGap * dir, 0, len);
        const remained = moveFromMaxGap + gapThis;
        if (remained < 0) squeezeGaps(-remained * dir, 1);
      } else {
        squeezeGaps(-gapThis * dir, 1);
      }
    }
  }
  function squeezeWhenBailout(d) {
    if (mut.noBailout) return;
    const dir = d < 0 ? -1 : 1;
    d = Math.abs(d);
    const each = Math.ceil(d / (len - 1));
    for (let i = 0; i < len - 1; i++) {
      if (dir > 0) shiftList(each, 0, i + 1);
      else shiftList(-each, len - i - 1, len);
      d -= each;
      if (d <= 0) return;
    }
  }
  updateMinMaxGap();
  minGap < 0 && squeezeGaps(-minGap, 0.8);
  maxGap < 0 && squeezeGaps(maxGap, 0.8);
  updateMinMaxGap();
  takeBoundsGap(minGap, maxGap, 1);
  takeBoundsGap(maxGap, minGap, -1);
  updateMinMaxGap();
  if (minGap < 0) squeezeWhenBailout(-minGap);
  if (maxGap < 0) squeezeWhenBailout(maxGap);
}
// LabelManager.layout over the recorded entries
function transcribe(caseRec, mut) {
  const items = caseRec.manager.map(m => {
    const e = m.entry;
    const g = geometryOf(unrect(e.rawLocal), unmat(e.transform), e.marginType, e.margin ? e.margin.map(num) : null, mut);
    const lay = unlayout(m.layout) || {};
    return {
      lay, def: m.def, priority: num(m.priority), entry: e,
      local: g.local, transform: g.transform, rect: g.rect, axisAligned: g.axisAligned,
      labelX: num(e.labelX), labelY: num(e.labelY),
      ignore: e.ignore, guideIgnore: m.def.guideIgnore, hasGuide: m.def.guideIgnore !== null,
      emph: e.emph, guideEmph: e.guideEmph,
    };
  });
  const list = items.filter(it => mut.withIgnored || !it.def.ignore);
  shiftLayoutOnXY(list.filter(it => it.lay.moveOverlap === 'shiftX'), 0, 0, W, mut);
  shiftLayoutOnXY(list.filter(it => it.lay.moveOverlap === 'shiftY'), 1, 0, H, mut);
  const hide = list.filter(it => it.lay.hideOverlap);
  for (const it of hide) {
    it.ignore = it.def.ignore;
    if (it.hasGuide) it.guideIgnore = it.def.guideIgnore;
  }
  // ensureLabelLayoutWithGeometry: the OBB bit left dirty counts under the
  // all-bits mask, so the geometry is computed again from the label as it
  // stands -- a free label's shifted x / y through its transform, an
  // attached one's from its host, where the shift never lands
  if (!mut.hideShifted) {
    for (const it of hide) {
      const e = it.entry;
      let tr = unmat(e.transform);
      if (e.position == null && e.inner && e.transform) {
        tr = localTransform(Object.assign({}, e.inner, {
          x: hex(it.labelX + num(e.offset[0])), y: hex(it.labelY + num(e.offset[1])),
        }), mut);
      }
      const g = geometryOf(unrect(e.rawLocal), tr, e.marginType, e.margin ? e.margin.map(num) : null, mut);
      Object.assign(it, { local: g.local, transform: g.transform, rect: g.rect, axisAligned: g.axisAligned });
    }
  }
  if (mut.sortAsc) hide.sort((a, b) => a.priority - b.priority);
  else if (mut.reverseTies) hide.sort((a, b) => (b.priority - a.priority) || (hide.indexOf(b) - hide.indexOf(a)));
  else if (!mut.noSort) hide.sort((a, b) => b.priority - a.priority);
  const shown = [];
  const hideEl = (isGuide, it) => {
    const ig = isGuide ? it.guideIgnore : it.ignore;
    if (!ig && !mut.noEmphasis) {
      if (isGuide) {
        if (it.guideEmph === 'absent' || it.guideEmph === null) it.guideEmph = false;
      } else if (it.emph === 'absent' || it.emph === null) {
        it.emph = false;
      }
    }
    if (isGuide) it.guideIgnore = true;
    else it.ignore = true;
  };
  for (const it of hide) {
    if (it.ignore) continue;
    let hit = false;
    for (const o of shown) {
      if (labelIntersect(it, o, mut)) {
        hit = true;
        break;
      }
    }
    if (hit) {
      hideEl(false, it);
      if (it.hasGuide && !mut.guideKept) hideEl(true, it);
    } else {
      shown.push(it);
    }
  }
  return items.map(it => ({
    ignore: it.ignore, guideIgnore: it.hasGuide ? it.guideIgnore : null,
    labelX: hex(it.labelX), labelY: hex(it.labelY), emph: it.emph, guideEmph: it.guideEmph,
  }));
}
// Transformable.getLocalTransform from the inner transformable (scale 1, no
// skew, no anchor); mut.noOrigin drops the origin
function localTransform(inner, mut) {
  const ox = mut.noOrigin ? 0 : num(inner.originX);
  const oy = mut.noOrigin ? 0 : num(inner.originY);
  const x = num(inner.x);
  const y = num(inner.y);
  const rotation = num(inner.rotation);
  const sx = num(inner.scaleX);
  const sy = num(inner.scaleY);
  const m = [1, 0, 0, 1, 0, 0];
  if (ox || oy) {
    m[4] = -ox * sx - 0 * oy * sy;
    m[5] = -oy * sy - 0 * ox * sx;
  } else {
    m[4] = m[5] = 0;
  }
  m[0] = sx;
  m[3] = sy;
  m[1] = 0 * sx;
  m[2] = 0 * sy;
  if (rotation) {
    const aa = m[0];
    const ac = m[2];
    const atx = m[4];
    const ab = m[1];
    const ad = m[3];
    const aty = m[5];
    const st = Math.sin(rotation);
    const ct = Math.cos(rotation);
    m[0] = aa * ct + ab * st;
    m[1] = -aa * st + ab * ct;
    m[2] = ac * ct + ad * st;
    m[3] = -ac * st + ct * ad;
    m[4] = ct * (atx - 0) + st * (aty - 0) + 0;
    m[5] = ct * (aty - 0) - st * (atx - 0) + 0;
  }
  m[4] += ox + x;
  m[5] += oy + y;
  return m;
}
const sameExit = (a, b) => a.ignore === b.ignore && a.guideIgnore === b.guideIgnore && a.labelX === b.labelX
  && a.labelY === b.labelY && a.emph === b.emph && a.guideEmph === b.guideEmph;
function caseChanged(caseRec, mut) {
  const got = transcribe(caseRec, mut);
  for (let i = 0; i < got.length; i++) if (!sameExit(got[i], caseRec.manager[i].exit)) return true;
  if (mut.noOrigin) {
    for (const m of caseRec.manager) {
      if (!m.entry.inner || !m.entry.transform) continue;
      if (localTransform(m.entry.inner, mut).map(hex).join() !== m.entry.transform.join()) return true;
    }
  }
  return false;
}

const GUARDS = [
  { id: 'sortAsc', mutation: 'hideOverlap sorts by priority ascending', mut: { sortAsc: true }, named: ['scatter.hide.sizes', 'bar.hide.top', 'multi.priority'] },
  { id: 'noSort', mutation: 'hideOverlap keeps the list order', mut: { noSort: true }, named: ['scatter.hide.sizes', 'multi.priority'] },
  { id: 'reverseTies', mutation: 'equal priorities in reverse order (an unstable sort)', mut: { reverseTies: true }, named: ['scatter.hide', 'multi.tie'] },
  { id: 'aabbOnly', mutation: 'turned labels tested by their axis-aligned rects only', mut: { aabbOnly: true }, named: ['scatter.rotate45', 'scatter.layout.rotate30'] },
  { id: 'touch0', mutation: 'touch threshold 0', mut: { touch0: true }, named: ['touch'] },
  { id: 'hideShifted', mutation: 'hideOverlap reads the shifted rects, not the labels as they stand', mut: { hideShifted: true }, named: ['shiftY.attached.hide'] },
  { id: 'withIgnored', mutation: 'labels ignored at rest join the layout', mut: { withIgnored: true }, named: ['state.only.shift'] },
  { id: 'guideKept', mutation: 'the label line stays when its label is hidden', mut: { guideKept: true }, named: ['pie.default'] },
  { id: 'noEmphasis', mutation: 'a hidden label gets no emphasis state', mut: { noEmphasis: true }, named: ['scatter.hide', 'pie.default', 'emphasis.reshow'] },
  { id: 'noSqueeze', mutation: 'shiftLayoutOnXY never squeezes the gaps', mut: { noSqueeze: true }, named: ['shiftX.bounds'] },
  { id: 'noBailout', mutation: 'shiftLayoutOnXY never bails out', mut: { noBailout: true }, named: ['shiftY.squeeze'] },
  { id: 'noTakeGap', mutation: 'shiftLayoutOnXY never borrows the other bound\'s gap', mut: { noTakeGap: true }, named: ['shiftX.bounds'] },
  { id: 'noMinMargin', mutation: 'minMargin ignored', mut: { noMinMargin: true }, named: ['margin.min'] },
  { id: 'noTextMargin', mutation: 'textMargin ignored', mut: { noTextMargin: true }, named: ['margin.text'] },
  { id: 'noOrigin', mutation: 'the offset applied outside the rotation (no origin)', mut: { noOrigin: true }, named: ['cfg.rotate.dxdy'] },
];

// ---------- generation ----------
function generate() {
  const cases = CASES.map(runCase);
  // the transcription reproduces every case
  for (const c of cases) {
    const got = transcribe(c, {});
    must(got.length === c.manager.length, c.id + ': transcription length');
    for (let i = 0; i < got.length; i++) {
      must(sameExit(got[i], c.manager[i].exit), c.id + ': the transcription disagrees at label ' + i + ': '
        + JSON.stringify(got[i]) + ' vs ' + JSON.stringify(c.manager[i].exit));
    }
    for (const m of c.manager) {
      if (!m.entry.inner || !m.entry.transform) continue;
      must(localTransform(m.entry.inner, {}).map(hex).join() === m.entry.transform.join(),
        c.id + ': the local transform disagrees for "' + m.text + '"');
    }
  }
  const byId = {};
  for (const c of cases) byId[c.id] = c;
  // anchors
  const hidden = id => byId[id].manager.filter(m => m.exit.ignore && !m.def.ignore).length;
  must(byId['scatter.nolayout'].manager.length === 0, 'anchor: no labelLayout, no manager list');
  must(hidden('scatter.hide') > 0, 'anchor: the dense scatter hides labels');
  must(hidden('pie.default') > 0, 'anchor: the pie default hides labels');
  must(byId['pie.default'].manager.some(m => m.exit.ignore && m.exit.guideIgnore === true), 'anchor: a pie line goes with its label');
  must(hidden('pie.null') === 0 && byId['pie.null'].manager.length === 0, 'anchor: labelLayout null switches the pie default off');
  must(byId['state.only'].manager.length > 0 && byId['state.only'].manager.every(m => m.def.ignore), 'anchor: state-only labels are listed and ignored');
  must(byId['fn.dx'].calls.length === byId['fn.dx'].manager.length, 'anchor: one call per label');
  const hiddenAtRest = (c, d) => c.manager.some(m => m.d === d && m.exit.ignore);
  const underHover = (h, d) => h.labels.find(l => l.d === d);
  const rh = byId['emphasis.reshow'];
  must(rh.hover.some(h => hiddenAtRest(rh, h.payload.dataIndex) && !underHover(h, h.payload.dataIndex).ignore),
    'anchor: a label hidden at rest comes back under highlight');
  const kp = byId['emphasis.keep'];
  must(kp.hover.some(h => hiddenAtRest(kp, h.payload.dataIndex) && underHover(h, h.payload.dataIndex).ignore),
    'anchor: emphasis.label.show false keeps a hidden label hidden');
  // guards
  const guards = GUARDS.map(g => {
    const changed = cases.filter(c => caseChanged(c, g.mut)).map(c => c.id);
    const ok = g.named.every(n => changed.indexOf(n) >= 0);
    return { id: g.id, mutation: g.mutation, named: g.named, changed, ok };
  });
  if (process.env.LL_DEBUG) {
    for (const c of cases) {
      console.error(c.id, 'listed', c.manager.length, 'hidden', c.manager.filter(m => m.exit.ignore && !m.def.ignore).length,
        'labels', c.labels.length);
    }
    for (const g of guards) console.error('guard', g.id, g.ok, JSON.stringify(g.changed));
  }
  for (const g of guards) must(g.ok, 'guard ' + g.id + ' does not change ' + g.named.filter(n => g.changed.indexOf(n) < 0).join(', '));
  return {
    source: 'echarts ' + echarts.version + ' (' + path.basename(DIST) + '), node SSR, SVG renderer',
    W, H, seed: SEED,
    handlers: HANDLER_NOTES,
    notes: [
      'manager[] is the LabelManager list in its own order; labels[] every series label after the render.',
      'A label attached to its host keeps the host\'s position: shiftX / shiftY move label.x / y and its rect, not what is drawn.',
    ],
    cases,
    guards,
  };
}

try {
  const a = JSON.stringify(generate(), null, 1);
  const b = JSON.stringify(generate(), null, 1);
  must(a === b, 'two generations differ');
  fs.writeFileSync(OUT, a + '\n');
  const n = JSON.parse(a).cases.length;
  console.log('wrote ' + OUT + ' (' + n + ' cases)');
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e);
  process.exit(1);
}
