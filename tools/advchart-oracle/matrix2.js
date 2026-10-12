/*
Upstream's own answers for roadmap D12 part two (MX2), batch 147: the
MATRIX coordinate system's positioning algebra and what is placed on it.

  the algebra   Matrix.ts dataToLayout / dataToPoint / pointToData with
                matrixCoordHelper.ts parseCoordRangeOption (a RANGE on either
                direction -- a parent's span, `[a, b]`, `[x1, x2, x3]` read as
                its two ends, a part that names nothing --, the four
                MatrixClampOption values, null covering the whole row or
                column), xyLocatorRangeToRectOneDim, and
                pointToDataOneDimPrepareCtx / pointToDataOnlyHeaderFillOut /
                pointToDataBodyCornerFillOut;
  the convert   echarts.convertToPixel / convertToLayout / convertFromPixel
                with an opt, containPixel: a matrix finder (a main type
                string, matrixIndex, matrixId), a series on a matrix, a pie
                laid out in a cell (no coordinate system of its own), the
                coordinate systems' order (a grid before a calendar before a
                matrix), and the calendar's convertToLayout;
  the series    custom (prepareCustom: coordSys, api.coord / api.layout with
                a range and an opt), graph (each node at dataToPoint of its x
                and y, simpleLayoutEdge), pie and funnel in a cell
                (createBoxLayoutReference: `coord`, else a pie's `center`);
  the view      cell labels rotated (createTextConfig's rotation, the text's
                local transform with an offset's origin, the overflow area
                through its inverse), rich labels in the overflow area;
  the pointer   the cells' silent rules (a fill, `silent`, a label's
                triggerEvent / tooltip.show), triggerEvent's eventData, the
                cells' own tooltip (setTooltipConfig, TooltipView's component
                item tooltip and formatTpl over name / xyLocator), and the
                series' items under the pointer with their tooltips.

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off and the chart prototype's getDom answering an
empty object so TooltipView runs, setTimeout a queue the steps settle,
Math.random the port's xorshift32 (seed 2463534242, reset before every
chart) and zrender's width table measuring every string. Every option is run
with animation off.

  node tools/advchart-oracle/matrix2.js

writes tests/fixtures/advchart-matrix2.json (ORACLE_OUT overrides). Ends with
process.exit().

-----------------------------------------------------------------------------
Numbers that are positions are the 16 lowercase hex digits of the IEEE double
(big-endian; NaN 7ff8000000000000); counts, flags, strings and option values
are plain JSON. A recorded value (rv): a number as hex, a string, a boolean,
null (also undefined), an array or an object of those.

Top level: source, version, seed, W, H, measure {firstCode, ratio[] (hex)},
notes[], cases[], guards[].

A case: id, group ('algebra' | 'convert' | 'series' | 'view' | 'pointer'),
note, gallery (a file under examples/advchart/gallery, fed verbatim but for
a custom series' renderItem, then option is null) or option (as run,
renderItem '@name'), fails[] (recipe mismatches; must be empty), and per
group:

  algebra   matrices[] {index, rect (hex), layouts[] {input (JSON as
            passed), clamp (JSON, null for none), rect {x, y, width, height}
            (hex), loc [[a, b], [c, d]] (hex), point [x, y] (hex)},
            points[] {p [x, y] (hex), clamp, out [x, y] (hex)}}
  convert   calls[] {fn ('toPixel' | 'toLayout' | 'fromPixel' | 'contain'),
            finder, value, opt (JSON or null), ret (rv; null for
            undefined)}
  series    matrices[] as the view's (rect only); custom[] {seriesIndex,
            calls[] {name, dataIndex, coordSys (rv), api[] {fn, args, opt,
            ret} }, roots (the item roots drawn)}; graphs[] {seriesIndex,
            nodes[] {i, p [x, y] (hex)}, edges[] {i, points[[x, y]...]
            (hex)}}; pies[] {seriesIndex, sectors[] {i, cx, cy, r0, r,
            startAngle, endAngle} (hex)}; funnels[] {seriesIndex, items[]
            {i, points [[x, y] x 4] (hex)}}
  view      matrices[] as matrix.js writes them (els with the cell labels),
            a label also carrying rot (its rotation, hex), ox / oy (its
            origin, hex) and the offset written (JSON or null)
  pointer   steps[] {p [x, y] (integers)}; states[] (one per step) {hit
            (null | {kind 'matrix', role 'rect' | 'label', target, loc} |
            {kind 'series', seriesIndex, dataIndex}), events[] {type,
            componentType, componentIndex, matrixIndex, targetType, name,
            value, coord, seriesIndex, dataIndex}, tooltip (null with no
            tooltip component | {shown, text (a component item's), rows
            (a series item's: {marker, name, value})})}

Guards (any failure: nothing is written, exit 1): every case's recipes (R1
every algebra rect is the units at its locators' ends; R2 every dataToPoint
the centre of its dataToLayout; R3 a graph node is dataToPoint of its row; R4
a pie's centre is its cell's or its box's), named discriminating facts, and
the whole fixture generated twice, byte-identical, no \u0000, parsing back.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

// ---------- the timers (TooltipView's show / hide go through setTimeout) ----------
let TIMERS = [];
let timerSeq = 0;
let NOW = 0;
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
  NOW = Math.max(NOW, at);
}

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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-matrix2.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');
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
// a recorded value: numbers hexed, undefined as null
function rv(v) {
  if (v === undefined || v === null) return null;
  if (typeof v === 'number') return hex(v);
  if (typeof v === 'string' || typeof v === 'boolean') return v;
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v).map(rv);
  if (typeof v === 'function') return '<fn>';
  if (typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      if (v[k] === undefined) continue;
      o[k] = rv(v[k]);
    }
    return o;
  }
  throw new OracleError('an unrecordable value ' + typeof v);
}

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
(function checkMeasurer() {
  RATIO.forEach((r, i) => {
    const w = new echarts.graphic.Text({ style: { text: String.fromCharCode(FIRST_CODE + i), font: '1px sans-serif' } }).getBoundingRect().width;
    must(Object.is(w, r), 'char code ' + (FIRST_CODE + i) + ': the table says ' + r + ', a 1px Text measures ' + w);
  });
})();

// ---------- the chart ----------
(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

const zr = chart => chart.getZr();
function refresh(chart) { zr(chart).storage.getDisplayList(true); }
function paint(chart) {
  chart._onframe();
  refresh(chart);
  quiet(() => chart.renderToSVGString());
  refresh(chart);
}
const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });
let ecKey = null;
function ecDataOf(el) {
  if (!el) return null;
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (k.indexOf('__ec_inner_') === 0 && v && typeof v === 'object' && ('seriesIndex' in v || 'eventData' in v || 'tooltipConfig' in v)) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}

// every renderItem call: what it was handed and what its api answered
let CALLS = [];
function recorder(name, fn) {
  return function (params, api) {
    const call = { name, dataIndex: params.dataIndex, coordSys: rv(params.coordSys), api: [] };
    const wrap = {};
    ['value', 'coord', 'layout', 'visual', 'style'].forEach(k => {
      wrap[k] = function (a, b) {
        const ret = api[k](a, b);
        if (k === 'coord' || k === 'layout') call.api.push({ fn: k, args: jsonOf(a), opt: jsonOf(b), ret: rv(ret) });
        return ret;
      };
    });
    const out = fn(params, wrap);
    CALLS.push(call);
    return out;
  };
}

// the renderItems (each mirrored in tests/test.advchart.matrix2.pas)
const RENDER = {
  // a cell's rect (api.layout) inset by a pixel, a dot at api.coord; a row
  // that names no cell draws nothing
  mxCell(params, api) {
    const x = api.value(0);
    const y = api.value(1);
    const lay = api.layout([x, y]);
    const p = api.coord([x, y]);
    if (isNaN(lay.rect.x) || isNaN(lay.rect.y)) return null;
    return { type: 'group', children: [
      { type: 'rect', shape: { x: lay.rect.x + 1, y: lay.rect.y + 1, width: lay.rect.width - 2, height: lay.rect.height - 2 }, style: { fill: '#88aadd' } },
      { type: 'circle', shape: { cx: p[0], cy: p[1], r: 3 }, style: { fill: '#ffffff' } }] };
  },
  // ranges and clamps through the api: a two-column span clamped to the
  // matrix, the whole row of the body, a span into the header, a range whose
  // far end names nothing
  mxRange(params, api) {
    const x = api.value(0);
    const y = api.value(1);
    const a = api.layout([[x, x + 1], y], { clamp: 1 });
    const b = api.layout([null, y], { clamp: 2 });
    const c = api.coord([[x, -1], y]);
    const d = api.layout([x, [y, 'zz']]);
    const e = api.layout([[x, x, x + 2], [-1, y]], { clamp: 3 });
    if (isNaN(a.rect.x)) return null;
    return { type: 'rect', shape: { x: a.rect.x, y: b.rect.y, width: a.rect.width, height: b.rect.height },
      style: { fill: '#ddaa88', opacity: 0.5 }, info: { cx: c[0], dx: d.rect.x, ex: e.rect.x } };
  },
  // the gallery's: the cell of the row's x and y
  mxGal(params, api) {
    const lay = api.layout([api.value(0), api.value(1)]);
    if (isNaN(lay.rect.x) || isNaN(lay.rect.y)) return null;
    return { type: 'rect', shape: { x: lay.rect.x, y: lay.rect.y, width: lay.rect.width, height: lay.rect.height }, style: { fill: '#cccccc' } };
  },
};
function materialize(option) {
  const o = clone(option);
  [].concat(o.series || []).forEach(s => {
    if (s && s.type === 'custom') {
      const nm = typeof s.renderItem === 'string' ? s.renderItem.replace(/^@/, '') : null;
      must(nm && RENDER[nm], 'no renderItem ' + s.renderItem);
      s.renderItem = recorder(nm, RENDER[nm]);
    }
  });
  o.animation = false;
  return o;
}
function mk() {
  rngState = SEED;
  NOW = 0;
  TIMERS = [];
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function load(c) {
  if (!c.gallery) return c.option;
  const o = JSON.parse(fs.readFileSync(path.join(GALLERY, c.gallery + '.json'), 'utf8'));
  // a gallery custom series lost its renderItem to JSON: the generic cell
  [].concat(o.series || []).forEach(s => {
    if (s && s.type === 'custom') s.renderItem = '@mxGal';
  });
  return o;
}
function run(c) {
  const chart = mk();
  CALLS = [];
  quiet(() => chart.setOption(materialize(load(c))));
  paint(chart);
  return chart;
}
const matrices = chart => {
  const out = [];
  chart.getModel().eachComponent('matrix', mm => out.push(mm));
  return out;
};
const dimsOf = mm => [mm.getDimensionModel('x').dim, mm.getDimensionModel('y').dim];

// ---------------------------------------------------------------------------
// the algebra
// ---------------------------------------------------------------------------
const CLAMPS = [null, 0, 1, 2, 3, true, 'x', false];
const PCLAMPS = [null, 1, 2, 3];
function layoutInputs(xd, yd) {
  const nx = xd._leavesCount;
  const ny = yd._leavesCount;
  const lx = xd._levels.length;
  const ly = yd._levels.length;
  const xn = xd._cells.map(c => String(c.option.value));
  const yn = yd._cells.map(c => String(c.option.value));
  const ins = [
    [0, 0], [1, 1], [-1, -1], [-ly, -lx], [-ly - 1, 0], [nx, 0], [0, ny],
    [[0, nx - 1], [0, ny - 1]], [[nx - 1, 0], 0], [[0, nx - 1], 0], [[-ly, nx - 1], [-lx, ny - 1]], [[-1, 0], [-1, 0]],
    [[0, 1, 2], 0], [[], 0], [0, []], [[0], [0]], [null, 0], [0, null], [null, null],
    [[0, null], 0], [[null, 1], 1], ['__none__', 0], [[0, '__none__'], 0],
    [[1.4, 2.6], [-0.4, 0.5]], [-0.6, -0.4], [[99, -99], 0], [[-99, 99], [-99, 99]], [0], [], 'notarray', 5,
  ];
  if (xn.length) {
    ins.push([xn[0], yn.length ? yn[0] : 0]);
    ins.push([xn[xn.length - 1], 0]);
    ins.push([[xn[xn.length - 1], xn[0]], 0]);
    ins.push([[xn[0], -1, xn[xn.length - 1]], [0, 1]]);
  }
  xn.slice(nx).forEach(v => ins.push([v, 0]));
  yn.slice(ny).forEach(v => ins.push([0, v]));
  if (yn.length) {
    ins.push([0, yn[yn.length - 1]]);
    ins.push([[-1, 0], [yn[0], yn[yn.length - 1]]]);
  }
  return ins;
}
function axisCoords(rectXY, rectWH, units) {
  const set = [rectXY - 3, rectXY, rectXY + rectWH, rectXY + rectWH + 3];
  units.forEach(u => {
    if (!isNaN(u.xy)) {
      set.push(u.xy, u.xy + u.wh / 2, u.xy + u.wh);
    }
  });
  const out = [];
  set.forEach(v => { if (!out.some(q => Object.is(q, v))) out.push(v); });
  out.sort((a, b) => a - b);
  return out;
}
function algebraRec(mm, fails) {
  const cs = mm.coordinateSystem;
  const [xd, yd] = dimsOf(mm);
  const rect = cs.getRect();
  const layouts = [];
  layoutInputs(xd, yd).forEach(input => {
    CLAMPS.forEach(clamp => {
      const opt = clamp === null ? undefined : { clamp };
      const lay = quiet(() => cs.dataToLayout(input, opt));
      const pt = quiet(() => cs.dataToPoint(input, opt));
      const loc = lay.matrixXYLocatorRange;
      layouts.push({ input: clone(input), clamp, rect: rectRec(lay.rect), loc: [[hex(loc[0][0]), hex(loc[0][1])], [hex(loc[1][0]), hex(loc[1][1])]],
        point: [hex(pt[0]), hex(pt[1])] });
      // R1: the rect is the units at the two ends
      [0, 1].forEach(d => {
        const lo = loc[d][0];
        const hi = loc[d][1];
        const unit = l => (l < 0 ? [xd, yd][1 - d] : [xd, yd][d]).getUnitLayoutInfo(d, l);
        const xy = d === 0 ? lay.rect.x : lay.rect.y;
        const wh = d === 0 ? lay.rect.width : lay.rect.height;
        if (Number.isNaN(lo) || Number.isNaN(hi)) {
          if (!Number.isNaN(xy)) fails.push('R1 a rect where the locators are NaN ' + JSON.stringify(input));
          return;
        }
        const u0 = unit(lo);
        const u1 = unit(hi);
        if (!u0 || !u1) return;
        if (!Object.is(u0.xy, xy) || !Object.is(u1.xy + u1.wh - u0.xy, wh)) fails.push('R1 ' + JSON.stringify(input) + ' clamp ' + clamp);
      });
      // R2: the point is the centre
      if (!Object.is(pt[0], lay.rect.x + lay.rect.width / 2) || !Object.is(pt[1], lay.rect.y + lay.rect.height / 2))
        fails.push('R2 ' + JSON.stringify(input));
    });
  });
  const xs = axisCoords(rect.x, rect.width, yd._levels.concat(xd._cells.slice(0, xd._leavesCount)));
  const ys = axisCoords(rect.y, rect.height, xd._levels.concat(yd._cells.slice(0, yd._leavesCount)));
  const points = [];
  xs.forEach(x => ys.forEach(y => PCLAMPS.forEach(clamp => {
    const out = cs.pointToData([x, y], clamp === null ? undefined : { clamp });
    points.push({ p: [hex(x), hex(y)], clamp, out: [hex(out[0]), hex(out[1])] });
  })));
  return { index: mm.componentIndex, rect: rectRec(rect), layouts, points };
}

// ---------------------------------------------------------------------------
// the convert
// ---------------------------------------------------------------------------
function convertCalls(chart, plan) {
  return plan.map(([fn, finder, value, opt]) => {
    let ret;
    quiet(() => {
      if (fn === 'toPixel') ret = chart.convertToPixel(finder, value, opt === null ? undefined : opt);
      else if (fn === 'toLayout') ret = chart.convertToLayout(finder, value, opt === null ? undefined : opt);
      else if (fn === 'fromPixel') ret = chart.convertFromPixel(finder, value, opt === null ? undefined : opt);
      else ret = chart.containPixel(finder, value);
    });
    let r;
    if (fn === 'toLayout' && ret) {
      r = { rect: rectRec(ret.rect) };
      if (ret.contentRect) r.contentRect = rectRec(ret.contentRect);
      if (ret.matrixXYLocatorRange) r.loc = ret.matrixXYLocatorRange.map(q => q.map(hex));
    }
    else r = rv(ret);
    return { fn, finder: clone(finder), value: clone(value), opt: jsonOf(opt), ret: r };
  });
}

// ---------------------------------------------------------------------------
// the series
// ---------------------------------------------------------------------------
function seriesRecs(chart, fails) {
  const out = { custom: [], graphs: [], pies: [], funnels: [] };
  chart.getModel().eachSeries(s => {
    const data = s.getData();
    if (s.subType === 'custom') {
      const view = chart.getViewOfSeriesModel(s);
      out.custom.push({ seriesIndex: s.seriesIndex, roots: view ? view.group.childrenRef().length : 0 });
    }
    else if (s.subType === 'graph') {
      if (s.get('coordinateSystem') !== 'matrix') return;
      const nodes = [];
      for (let i = 0; i < data.count(); i++) {
        const l = data.getItemLayout(i);
        nodes.push({ i, p: l ? [hex(l[0]), hex(l[1])] : null });
      }
      const ed = s.getEdgeData();
      const edges = [];
      for (let i = 0; i < ed.count(); i++) {
        const l = ed.getItemLayout(i);
        edges.push({ i, points: l ? l.map(p => [hex(p[0]), hex(p[1])]) : null });
      }
      // R3: a node is dataToPoint of its stored x and y
      const cs = s.coordinateSystem;
      for (let i = 0; i < data.count(); i++) {
        const v = [data.get('x', i), data.get('y', i), data.get('value', i)];
        const l = data.getItemLayout(i);
        if (v.every(q => isNaN(q))) {
          if (!(Number.isNaN(l[0]) && Number.isNaN(l[1]))) fails.push('R3 graph ' + s.seriesIndex + ' node ' + i + ' placed with no value');
          continue;
        }
        const p = cs.dataToPoint(v);
        if (!Object.is(p[0], l[0]) || !Object.is(p[1], l[1])) fails.push('R3 graph ' + s.seriesIndex + ' node ' + i);
      }
      out.graphs.push({ seriesIndex: s.seriesIndex, nodes, edges });
    }
    else if (s.subType === 'pie') {
      const sectors = [];
      for (let i = 0; i < data.count(); i++) {
        const l = data.getItemLayout(i);
        sectors.push({ i, cx: hex(l.cx), cy: hex(l.cy), r0: hex(l.r0), r: hex(l.r), startAngle: hex(l.startAngle), endAngle: hex(l.endAngle) });
      }
      out.pies.push({ seriesIndex: s.seriesIndex, box: !!s.boxCoordinateSystem, sectors });
    }
    else if (s.subType === 'funnel') {
      const items = [];
      for (let i = 0; i < data.count(); i++) {
        const l = data.getItemLayout(i);
        items.push({ i, points: l && l.points ? l.points.map(p => [hex(p[0]), hex(p[1])]) : null });
      }
      out.funnels.push({ seriesIndex: s.seriesIndex, items });
    }
  });
  // calls in the order made; a custom series' calls are its own
  const customs = [];
  chart.getModel().eachSeries(s => { if (s.subType === 'custom') customs.push(s); });
  let k = 0;
  customs.forEach(s => {
    const rec = out.custom.find(q => q.seriesIndex === s.seriesIndex);
    rec.calls = [];
    const n = s.getData().count();
    // CustomView renders every item in order, series by series
    let taken = 0;
    while (k < CALLS.length && taken < n) {
      rec.calls.push(CALLS[k++]);
      taken++;
    }
  });
  must(k === CALLS.length, 'renderItem calls left over');
  return out;
}

// ---------------------------------------------------------------------------
// the view (as matrix.js records it)
// ---------------------------------------------------------------------------
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
  const tc = host.textConfig || {};
  return {
    text: t.style.text == null ? null : String(t.style.text),
    t: Array.from(m).map(hex),
    rot: hex(t.innerTransformable ? (t.innerTransformable.rotation || 0) : (t.rotation || 0)),
    ox: hex(t.innerTransformable ? (t.innerTransformable.originX || 0) : 0),
    oy: hex(t.innerTransformable ? (t.innerTransformable.originY || 0) : 0),
    offset: tc.offset ? clone(tc.offset) : null,
    align: t.style.align || ds.align || null,
    va: t.style.verticalAlign || ds.verticalAlign || null,
    fill: t.style.fill == null ? (ds.fill == null ? null : String(ds.fill)) : String(t.style.fill),
    font: t.style.font || null,
    z2: t.z2,
    dl: dlIndex.has(t) ? dlIndex.get(t) : -1,
    silent: !!t.silent,
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
function viewRec(chart, mm, dlIndex, fails) {
  const [xDim, yDim] = dimsOf(mm);
  const view = chart.getViewOfComponentModel(mm);
  const plan = viewPlan(xDim, yDim);
  const els = [];
  let pi = 0;
  view.group.children().forEach(el => {
    const rec = { k: el.type, role: null, target: null, loc: null, dl: dlIndex.has(el) ? dlIndex.get(el) : -1 };
    if (pi < plan.length) {
      rec.role = 'cell';
      rec.target = plan[pi].target;
      rec.loc = plan[pi].loc;
      pi++;
    }
    else if (el.type === 'rect') rec.role = els.some(e => e.role === 'bg') ? 'border' : 'bg';
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
  const box = {};
  ['left', 'right', 'top', 'bottom', 'width', 'height'].forEach(k => { box[k] = jsonOf(mm.option[k]); });
  return {
    index: mm.componentIndex, id: mm.option.id == null ? null : String(mm.option.id), z: mm.get('z'),
    rect: rectRec(mm.coordinateSystem.getRect()), box,
    dims: [dimRec(xDim), dimRec(yDim)], els, probes: [],
  };
}
// R5 for a rotated label: the overflow area through the inverse transform
function checkRotated(rec, fails) {
  rec.els.forEach((e, i) => {
    if (!e.label) return;
    const t = e.label.t.map(num);
    const rot = num(e.label.rot);
    // the local transform recomputed: origin, rotation, translation
    const ox = num(e.label.ox);
    const oy = num(e.label.oy);
    const st = Math.sin(rot);
    const ct = Math.cos(rot);
    const m4 = ox || oy ? -ox : 0;
    const m5 = ox || oy ? -oy : 0;
    let a = [1, 0, 0, 1, m4, m5];
    if (rot) a = [ct, -st, st, ct, ct * m4 + st * m5, ct * m5 - st * m4];
    if (!Object.is(a[0], t[0]) || !Object.is(a[1], t[1]) || !Object.is(a[2], t[2]) || !Object.is(a[3], t[3]))
      fails.push('R5 el ' + i + ': the rotation part of the transform');
  });
}

// ---------------------------------------------------------------------------
// the pointer
// ---------------------------------------------------------------------------
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
      else row.name = m[2];
    }
    return row;
  });
}
function hitRec(chart, x, y) {
  refresh(chart);
  const t = zr(chart).handler.findHover(x, y).target;
  if (!t) return null;
  for (let e = t; e; e = e.__hostTarget || e.parent) {
    const q = ecDataOf(e);
    if (q && q.seriesIndex != null && q.dataIndex != null) return { kind: 'series', seriesIndex: q.seriesIndex, dataIndex: q.dataIndex };
  }
  // a matrix cell: the rect or its label
  let found = null;
  matrices(chart).forEach(mm => {
    if (found) return;
    const [xDim, yDim] = dimsOf(mm);
    const plan = viewPlan(xDim, yDim);
    const kids = chart.getViewOfComponentModel(mm).group.children();
    kids.forEach((el, k) => {
      if (found || k >= plan.length) return;
      const tc = el.getTextContent && el.getTextContent();
      if (el === t) found = { kind: 'matrix', matrixIndex: mm.componentIndex, role: 'rect', target: plan[k].target, loc: plan[k].loc };
      else if (tc && (tc === t || tc === t.parent))
        found = { kind: 'matrix', matrixIndex: mm.componentIndex, role: 'label', target: plan[k].target, loc: plan[k].loc };
    });
  });
  return found || { kind: 'other' };
}
const EVENT_KEYS = ['componentType', 'componentIndex', 'matrixIndex', 'targetType', 'name', 'value', 'coord', 'seriesIndex', 'dataIndex'];
function pointerCase(c, chart, fails) {
  const events = [];
  ['mouseover', 'mouseout'].forEach(type => chart.on(type, p => {
    const e = { type };
    EVENT_KEYS.forEach(k => { e[k] = p[k] === undefined ? null : clone(p[k]); });
    events.push(e);
  }));
  const tm = chart.getModel().getComponent('tooltip', 0);
  const tv = tm ? chart.getViewOfComponentModel(tm) : null;
  const states = [];
  c.steps.forEach((step, i) => {
    settle(NOW + 500);
    events.length = 0;
    zr(chart).handler.mousemove(raw(step.p[0], step.p[1]));
    paint(chart);
    settle(NOW + 500);
    paint(chart);
    const st = { hit: hitRec(chart, step.p[0], step.p[1]), events: events.slice() };
    if (tv) {
      const ct = tv._tooltipContent;
      const vis = !!(ct && ct.el && !ct.el.ignore && !ct.el.invisible);
      const text = vis ? String(ct.el.style.text) : null;
      const isRows = vis && text.indexOf('{__EC_aUTo_') >= 0;
      st.tooltip = { shown: vis, text: vis && !isRows ? text : null, rows: isRows ? tooltipRows(ct) : null };
    }
    else st.tooltip = null;
    states.push(st);
  });
  return states;
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
const add = (group, id, note, option, more) => CASES.push(Object.assign({ group, id, note, option }, more || {}));
const gal = (group, name, note) => CASES.push({ group, id: 'gallery-' + name, note, gallery: name });
const vm = (min, max, extra) => Object.assign({ show: false, min, max, dimension: 2 }, extra || {});

const TREE_X = [{ value: 'A', children: ['A1', 'A2', { value: 'A3', children: ['A31', 'A32'] }] }];
const TREE_BOTH_X = [{ value: 'Q1', children: ['Jan', 'Feb', 'Mar'] }, { value: 'Q2', children: [{ value: 'Apr', children: ['w1', 'w2'] }, 'May'] }, 'H2'];
const TREE_BOTH_Y = [{ value: 'North', children: ['N1', 'N2'] }, 'South', { value: 'East', children: [{ value: 'E1', children: ['E1a'] }] }];
const FRAC = { left: '7.3%', right: '11.1%', top: '9.7%', bottom: '13.3%' };

// ---- the algebra ----
add('algebra', 'alg-both', 'two trees, leaves at different depths, a fractional box',
  { matrix: Object.assign({ x: { data: TREE_BOTH_X }, y: { data: TREE_BOTH_Y } }, FRAC) });
add('algebra', 'alg-nested-x', 'a tree on x, flat rows',
  { matrix: { x: { data: TREE_X }, y: { data: ['U', 'V', 'W'] } } });
add('algebra', 'alg-hide-x', 'x hidden: its levels are nought, no corner on that side',
  { matrix: { x: { data: TREE_X, show: false }, y: { data: ['U', 'V'] } } });
add('algebra', 'alg-hide-y', 'y hidden',
  { matrix: { x: { data: ['a', 'b', 'c'] }, y: { data: TREE_BOTH_Y, show: false } } });
add('algebra', 'alg-hide-both', 'both hidden',
  { matrix: { x: { data: ['a', 'b'], show: false }, y: { data: ['p', 'q', 'r'], show: false } } });
add('algebra', 'alg-empty-x', 'no columns: x has no leaf and no level',
  { matrix: { x: { data: [] }, y: { data: ['p', 'q'] } } });
add('algebra', 'alg-empty-both', 'no cells at all',
  { matrix: { x: { data: [] }, y: { length: 0 } } });
add('algebra', 'alg-levels', 'level sizes and a sized leaf, all specified with room left over',
  { matrix: { x: { data: [{ value: 'a', size: 100 }, { value: 'b', size: 120 }], levelSize: 30 }, y: { data: [{ value: 'p', size: 50 }, { value: 'q', size: 70 }], levelSize: 60 } } });

// ---- the convert ----
add('convert', 'convert', 'finders: a main type, matrixIndex, matrixId, a series on a matrix, a pie in a cell, a line on a grid; the opt; containPixel; the calendar\'s convertToLayout',
  { grid: { left: 20, top: 20, width: 100, height: 80 }, xAxis: { type: 'category', data: ['g0', 'g1'] }, yAxis: { type: 'value', min: 0, max: 10 },
    calendar: { range: '2017-02', cellSize: [14, 14], left: 160, top: 20 },
    matrix: [{ id: 'm0', left: 20, top: 160, width: 360, height: 200, x: { data: TREE_X }, y: { data: ['U', 'V'] } },
      { id: 'm1', left: 420, top: 160, width: 320, height: 300, x: { data: ['a', 'b'] }, y: { data: ['p', 'q', 'r'] } }],
    visualMap: vm(0, 10),
    series: [
      { type: 'heatmap', coordinateSystem: 'matrix', data: [['A1', 'U', 1], ['A32', 'V', 5]] },
      { type: 'scatter', coordinateSystem: 'matrix', matrixId: 'm1', data: [['a', 'p', 3]] },
      { type: 'pie', coordinateSystem: 'matrix', center: ['A2', 'V'], radius: 15, data: [{ value: 1, name: 'x' }, { value: 2, name: 'y' }] },
      { type: 'custom', id: 'cu', coordinateSystem: 'matrix', matrixIndex: 1, renderItem: '@mxCell', data: [['b', 'q', 1]] },
      { type: 'line', data: [3, 7] },
      { type: 'heatmap', coordinateSystem: 'calendar', data: [['2017-02-03', 4]] }] },
  { plan: [
    ['toPixel', 'matrix', ['A1', 'U'], null], ['toPixel', { matrixIndex: 1 }, ['b', 'r'], null], ['toPixel', { matrixId: 'm1' }, [['a', 'b'], 'q'], null],
    ['toPixel', { seriesIndex: 0 }, ['A3', 'V'], null], ['toPixel', { seriesIndex: 1 }, [0, -1], null], ['toPixel', { seriesIndex: 2 }, ['A1', 'U'], null],
    ['toPixel', { seriesId: 'cu' }, ['a', 'zz'], null], ['toPixel', { seriesId: 'cu' }, ['a', 'zz'], { clamp: 1 }], ['toPixel', { matrixIndex: 1 }, [null, null], { clamp: 2 }],
    ['toPixel', { matrixIndex: 1 }, 'a', null], ['toPixel', { matrixIndex: 5 }, ['a', 'p'], null], ['toPixel', { matrixIndex: 0, seriesIndex: 1 }, ['A1', 'U'], null],
    ['toPixel', { seriesIndex: 4, matrixIndex: 0 }, ['g1', 7], null], ['toPixel', { matrixIndex: 0 }, [-1, -2], { clamp: 3 }],
    ['toLayout', 'matrix', ['A', 'U'], null], ['toLayout', { matrixIndex: 1 }, [['a', 'b'], ['p', 'r']], null], ['toLayout', { matrixIndex: 1 }, [null, 'q'], { clamp: 1 }],
    ['toLayout', { matrixIndex: 1 }, [null, 'q'], { clamp: 3 }], ['toLayout', { seriesIndex: 0 }, ['zz', 'U'], null], ['toLayout', { seriesIndex: 2 }, ['A1', 'U'], null],
    ['toLayout', 'calendar', '2017-02-05', null], ['toLayout', { seriesIndex: 5 }, ['2017-03-05'], null], ['toLayout', { matrixId: 'm1' }, 7, null],
    ['fromPixel', 'matrix', [100, 300], null], ['fromPixel', { matrixIndex: 1 }, [600, 400], null], ['fromPixel', { matrixIndex: 1 }, [10, 10], null],
    ['fromPixel', { matrixIndex: 1 }, [10, 10], { clamp: 1 }], ['fromPixel', { matrixIndex: 1 }, [10, 10], { clamp: 2 }], ['fromPixel', { seriesIndex: 0 }, [60, 200], null],
    ['fromPixel', { seriesIndex: 2 }, [60, 200], null], ['fromPixel', { matrixIndex: 0 }, [30, 170], null], ['fromPixel', { seriesId: 'cu' }, [700, 300], { clamp: 3 }],
    ['contain', 'matrix', [100, 300], null], ['contain', 'matrix', [10, 300], null], ['contain', { matrixIndex: 1 }, [740, 460], null], ['contain', { matrixIndex: 1 }, [740.5, 460], null],
    ['contain', { seriesIndex: 0 }, [100, 300], null], ['contain', { seriesIndex: 1 }, [100, 300], null], ['contain', { seriesId: 'cu' }, [500, 300], null],
    ['contain', { seriesIndex: 2 }, [100, 300], null],
  ] });

// ---- the series ----
add('series', 'custom-cells', 'a custom series on a tree: api.layout and api.coord of a leaf, a parent, a header locator, an unknown name, a fraction',
  { matrix: { x: { data: TREE_X }, y: { data: ['U', 'V'] }, top: 150, bottom: 150 },
    series: { type: 'custom', coordinateSystem: 'matrix', renderItem: '@mxCell',
      data: [['A1', 'U', 1], ['A3', 'V', 2], [-1, 'U', 3], ['zz', 'U', 4], [1.5, 0.4, 5], ['A', 'V', 6]] } });
add('series', 'custom-range', 'a custom series asking for ranges and clamps',
  { matrix: { x: { data: ['a', 'b', 'c', 'd'] }, y: { data: [{ value: 'G', children: ['p', 'q'] }, 'r'] } },
    series: { type: 'custom', coordinateSystem: 'matrix', renderItem: '@mxRange',
      data: [['a', 'p', 1], ['c', 'q', 2], ['d', 'r', 3], ['b', 'G', 4]] } });
add('series', 'graph-cells', 'a graph on a matrix: nodes by name, by number, on a parent, on a header, an unknown name with a value, a node with nothing; a curved edge',
  { matrix: { x: { data: TREE_X }, y: { data: ['U', 'V'] } },
    series: { type: 'graph', coordinateSystem: 'matrix', symbolSize: 12,
      data: [['A1', 'U', 1], ['A32', 'V', 2], [1, 1, 3], ['A3', 'U', 4], [-1, 'V', 5], ['zz', 'U', 6], ['zz', 'qq', '-'], { value: ['A2', 'V', 7], name: 'named' }, ['A1', 'V', '-']],
      links: [{ source: 0, target: 1 }, { source: 1, target: 2, lineStyle: { curveness: 0.3 } }, { source: 2, target: 5 }, { source: 3, target: 7 }] } });
add('series', 'pie-cells', 'pies in cells: center names, a coord over a percentage center, a range coord, a percentage radius, an unknown name, an explicit data usage',
  { matrix: { x: { data: [{ value: 'G1', children: ['a', 'b'] }, 'c'] }, y: { data: ['p', 'q', 'r'] }, top: 100, bottom: 100 },
    series: [
      { type: 'pie', coordinateSystem: 'matrix', center: ['a', 'p'], radius: 20, data: [1, 2, 3] },
      { type: 'pie', coordinateSystem: 'matrix', coord: ['b', 'q'], center: ['30%', '60%'], radius: ['20%', '40%'], data: [4, 5] },
      { type: 'pie', coordinateSystem: 'matrix', coord: [['a', 'b'], 'r'], radius: '45%', data: [2, 2, 1] },
      { type: 'pie', coordinateSystem: 'matrix', center: ['zz', 'p'], radius: 10, data: [1] },
      { type: 'pie', coordinateSystem: 'matrix', coordinateSystemUsage: 'data', center: [700, 80], radius: 15, data: [1, 1] },
      { type: 'pie', coordinateSystem: 'matrix', coord: 'G1', radius: 10, data: [1, 3] },
      { type: 'pie', coordinateSystem: 'matrix', center: ['G1', 'q'], left: 10, width: 40, radius: '50%', data: [3, 1] }] });
add('series', 'funnel-cell', 'a funnel in a cell, its box against the cell',
  { matrix: { x: { data: ['a', 'b'] }, y: { data: ['p', 'q'] } },
    series: [{ type: 'funnel', coordinateSystem: 'matrix', coord: ['b', 'q'], left: '10%', right: '10%', top: 5, bottom: 5, data: [{ value: 5, name: 'k' }, { value: 3, name: 'l' }, { value: 1, name: 'm' }] }] });
gal('series', 'matrix-confusion', 'the gallery: a confusion matrix (its custom series drawn by the generic cell)');
gal('series', 'matrix-periodic-table', 'the gallery: the periodic table (the generic cell)');
gal('series', 'matrix-pie', 'the gallery: pies in cells');
gal('series', 'matrix-graph', 'the gallery: a graph on a matrix');

// ---- the view ----
add('view', 'label-rotate', 'rotated cell labels: 90 on the dimension, 45 on one cell, -90 with an offset, 30 on y, an offset alone',
  { matrix: { left: 100, right: 100, top: 100, bottom: 100,
    x: { data: ['Alpha beta', { value: 'Gamma delta', label: { rotate: 45 } }, { value: 'Epsilon', label: { rotate: -90, offset: [5, 3] } }, { value: 'Zeta', label: { rotate: null, offset: [-4, 6] } }], label: { rotate: 90 } },
    y: { data: ['Row one', 'Row two words'], label: { rotate: 30 } } } });
add('view', 'label-rich', 'rich cell labels laid out in the overflow area: a break, a truncate, a fixed width, a rich label rotated',
  { matrix: { left: 150, right: 150, top: 200, bottom: 200,
    x: { data: [{ value: 'one two three four', label: { formatter: '{a|{value}}' } }, { value: 'truncated rich text here', label: { formatter: '{a|{value}}', overflow: 'truncate' } },
      { value: 'fixed', label: { formatter: '{b|{value}}\n{a|x}', width: 40 } }, { value: 'turn', label: { formatter: '{a|{value}}', rotate: 90 } }],
      label: { rich: { a: { fontSize: 14, color: '#aa0000' }, b: { fontSize: 10, padding: [1, 2] } } } },
    y: { data: ['p'] } } });

// ---- the pointer ----
add('pointer', 'ptr-events', 'triggerEvent: a filled body cell, a header label, a header rect with no fill (silent), a heatmap item over a cell, a label written silent, a cell rect written not silent, the corner',
  { tooltip: {},
    matrix: { triggerEvent: true, left: 100, right: 100, top: 100, bottom: 100,
      x: { data: ['a', 'b', { value: 'c', label: { silent: true } }] }, y: { data: ['p', { value: 'q', silent: false }] },
      body: { itemStyle: { color: '#eeeeff' } }, corner: { itemStyle: { color: '#ffeeee' } } },
    visualMap: vm(0, 10),
    series: [{ type: 'heatmap', coordinateSystem: 'matrix', data: [['b', 'q', 5]] }] },
  { steps: [{ cell: ['body', 0, 0] }, { cell: ['x', 0, -1], label: true }, { cell: ['x', 1, -1], off: true }, { cell: ['body', 1, 1] },
    { cell: ['x', 2, -1], label: true }, { cell: ['y', -1, 1], edge: true }, { cell: ['y', -1, 1], off: true }, { cell: ['corner', -1, -1] }, { p: [5, 5] }] });
add('pointer', 'ptr-tooltip', 'matrix.tooltip.show: the header labels answer the pointer with their names; a formatter over name and xyLocator on the second matrix',
  { tooltip: {},
    matrix: [{ tooltip: { show: true }, right: '52%', x: { data: TREE_X }, y: { data: ['U', 'V'] } },
      { tooltip: { show: true, formatter: '{a} @ {b}' }, left: '52%', x: { data: ['m', 'n'] }, y: { data: ['s', 't'] } }] },
  { steps: [{ cell: ['x', 0, -3], label: true, m: 0 }, { cell: ['x', 0, -2], label: true, m: 0 }, { cell: ['y', -1, 1], label: true, m: 0 },
    { cell: ['x', 1, -1], label: true, m: 1 }, { cell: ['body', 0, 0], m: 0 }] });
add('pointer', 'ptr-fill', 'no triggerEvent, no matrix tooltip: a header with a fill answers through the global tooltip; scatter, graph and pie items on the matrix show their own',
  { tooltip: {},
    matrix: { x: { data: ['a', 'b', 'c'], itemStyle: { color: '#f0f0f0' } }, y: { data: ['p', 'q'] } },
    series: [{ type: 'scatter', coordinateSystem: 'matrix', symbolSize: 16, data: [['a', 'p', 3]] },
      { type: 'graph', coordinateSystem: 'matrix', symbolSize: 16, data: [['b', 'p', 4], ['b', 'q', 6]], links: [{ source: 0, target: 1 }] },
      { type: 'pie', coordinateSystem: 'matrix', center: ['c', 'q'], radius: 20, data: [{ value: 3, name: 'u' }, { value: 1, name: 'v' }] }] },
  { steps: [{ cell: ['x', 0, -1], off: true }, { item: [0, 0] }, { item: [1, 0] }, { item: [2, 0] }, { cell: ['body', 0, 1] }] });

add('pointer', 'ptr-axis-trigger', "a global axis trigger: a component item's tooltip does not ask the trigger",
  { tooltip: { trigger: 'axis' },
    matrix: { tooltip: { show: true }, x: { data: ['m', 'n'] }, y: { data: ['s', 't'] } } },
  { steps: [{ cell: ['x', 1, -1], label: true }, { cell: ['y', -1, 0], label: true }] });

// a step's point: a cell's centre (its label's, or a corner of the rect off
// the label), a series item's, or given
function stepPoint(chart, step) {
  if (step.p) return step.p.slice();
  if (step.item) {
    const s = chart.getModel().getSeriesByIndex(step.item[0]);
    const el = s.getData().getItemGraphicEl(step.item[1]);
    const r = el.getBoundingRect().clone();
    el.getComputedTransform();
    if (el.transform) r.applyTransform(el.transform);
    // a pie sector: a point inside the ring at its middle angle
    const l = s.getData().getItemLayout(step.item[1]);
    if (l && l.startAngle != null) {
      const a = (l.startAngle + l.endAngle) / 2;
      const rr = (l.r + l.r0) / 2;
      return [Math.round(l.cx + rr * Math.cos(a)), Math.round(l.cy + rr * Math.sin(a))];
    }
    return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)];
  }
  const mm = matrices(chart)[step.m || 0];
  const [xDim, yDim] = dimsOf(mm);
  const plan = viewPlan(xDim, yDim);
  const kids = chart.getViewOfComponentModel(mm).group.children();
  const k = plan.findIndex(q => q.target === step.cell[0] && q.loc[0] === step.cell[1] && q.loc[1] === step.cell[2]);
  must(k >= 0, 'no cell ' + JSON.stringify(step.cell));
  const el = kids[k];
  if (step.label) {
    const t = el.getTextContent();
    const r = t.getBoundingRect().clone();
    t.getComputedTransform();
    if (t.transform) r.applyTransform(t.transform);
    return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)];
  }
  if (step.off) return [Math.round(el.shape.x + 3), Math.round(el.shape.y + 3)];
  // on the border's stroke band (an unfilled rect answers only there)
  if (step.edge) return [Math.round(el.shape.x + 1), Math.round(el.shape.y + el.shape.height / 2)];
  return [Math.round(el.shape.x + el.shape.width / 2), Math.round(el.shape.y + el.shape.height / 2)];
}

function runCase(c) {
  const fails = [];
  const chart = run(c);
  try {
    const rec = { id: c.id, group: c.group, note: c.note, gallery: c.gallery || null, option: c.gallery ? null : clone(c.option) };
    const dl = chart.getZr().storage.getDisplayList(true);
    const dlIndex = new Map();
    dl.forEach((el, i) => dlIndex.set(el, i));
    if (c.group === 'algebra') rec.matrices = matrices(chart).map(mm => algebraRec(mm, fails));
    else if (c.group === 'convert') rec.calls = convertCalls(chart, c.plan);
    else if (c.group === 'series') {
      rec.matrices = matrices(chart).map(mm => ({ index: mm.componentIndex, rect: rectRec(mm.coordinateSystem.getRect()) }));
      Object.assign(rec, seriesRecs(chart, fails));
    }
    else if (c.group === 'view') {
      rec.matrices = matrices(chart).map(mm => viewRec(chart, mm, dlIndex, fails));
      rec.matrices.forEach(m => checkRotated(m, fails));
    }
    else {
      rec.steps = c.steps.map(s => ({ p: stepPoint(chart, s) }));
      rec.states = pointerCase({ steps: rec.steps }, chart, fails);
    }
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
  const n = h => num(h);
  const lay = (id, input, clamp) => {
    const r = cs(id).matrices[0].layouts.find(l => JSON.stringify(l.input) === JSON.stringify(input) && l.clamp === clamp);
    must(r, id + ': no layout of ' + JSON.stringify(input) + ' clamp ' + clamp);
    return r;
  };
  out.cases.forEach(q => guard(q.id + ': every record matches its recipe', q.fails.length === 0));
  // ranges
  guard('a range covers both ends', n(lay('alg-nested-x', [[0, 3], [0, 2]], null).rect.width) > n(lay('alg-nested-x', [0, 0], null).rect.width) * 3.5);
  guard('a reversed range is the same range', JSON.stringify(lay('alg-nested-x', [[3, 0], 0], null).rect) === JSON.stringify(lay('alg-nested-x', [[0, 3], 0], null).rect));
  guard('[x1, x2, x3] reads as its two ends', JSON.stringify(lay('alg-nested-x', [[0, 1, 2], 0], null).loc[0]) === JSON.stringify([hex(0), hex(2)]));
  guard('a part that names nothing makes the direction NaN', n(lay('alg-nested-x', [[0, '__none__'], 0], null).rect.x) !== n(lay('alg-nested-x', [[0, '__none__'], 0], null).rect.x));
  guard('a clamp widens it to the whole row', !Number.isNaN(n(lay('alg-nested-x', [[0, '__none__'], 0], 1).rect.x)));
  guard('null with a clamp covers the whole column, header included', n(lay('alg-nested-x', [null, 0], 1).loc[0][0]) === -1
    && n(lay('alg-nested-x', [null, 0], 1).loc[0][1]) === 3);
  guard('clamp body keeps to the leaves', n(lay('alg-nested-x', [null, 0], 2).loc[0][0]) === 0);
  guard('clamp corner keeps to the levels', n(lay('alg-nested-x', [null, 0], 3).loc[0][1]) === -1);
  guard('a truthy clamp that is not 2 or 3 is all', JSON.stringify(lay('alg-nested-x', [null, 0], 'x').loc) === JSON.stringify(lay('alg-nested-x', [null, 0], 1).loc));
  guard('a parent covers its span', n(lay('alg-nested-x', ['A', 0], null).loc[0][1]) === 3);
  guard('a non-array data names nothing', Number.isNaN(n(lay('alg-nested-x', 'notarray', 1).rect.x)));
  guard('an empty array names nothing, a clamp still covers', Number.isNaN(n(lay('alg-nested-x', [[], 0], null).rect.x))
    && !Number.isNaN(n(lay('alg-nested-x', [[], 0], 1).rect.x)));
  guard('no level on the other side: the lower bound is -0', Object.is(n(lay('alg-empty-x', [0, null], 1).loc[1][0]), -0)
    || Object.is(n(lay('alg-hide-both', [null, 0], 1).loc[0][0]), -1));
  // pointToData
  const pts = id => cs(id).matrices[0].points;
  guard('pointToData answers a leaf in the body', pts('alg-nested-x').some(p => p.clamp === null && n(p.out[0]) === 2 && n(p.out[1]) === 1));
  guard('pointToData answers a header ordinal (a parent found by both coordinates)', pts('alg-nested-x').some(p => p.clamp === null && n(p.out[0]) === 4 && n(p.out[1]) === -3));
  guard('pointToData answers a corner level pair', pts('alg-both').some(p => p.clamp === null && n(p.out[0]) < 0 && n(p.out[1]) < 0));
  guard('outside is NaN without a clamp, an edge with one', pts('alg-nested-x').some(p => p.clamp === null && Number.isNaN(n(p.out[0])))
    && pts('alg-nested-x').filter(p => p.clamp === 1).every(p => !Number.isNaN(n(p.out[0]))));
  // convert
  const call = (fn, k) => cs('convert').calls.filter(q => q.fn === fn)[k];
  guard('a main type string finds matrix 0', call('toPixel', 0).ret !== null);
  guard('a pie in a cell has no coordinate system to convert with', call('toPixel', 5).ret === null);
  guard('a non-array value is [NaN, NaN], not nothing', Array.isArray(call('toPixel', 9).ret) && call('toPixel', 9).ret[0] === hex(NaN));
  guard('a matrix that is not there answers nothing', call('toPixel', 10).ret === null);
  guard('the grid answers before the matrix', call('toPixel', 12).ret !== null && call('toPixel', 12).ret[0] !== call('toPixel', 0).ret[0]);
  guard('convertToLayout carries the locator range', call('toLayout', 1).ret.loc !== undefined);
  guard('the calendar\'s convertToLayout has a content rect', call('toLayout', 6).ret.contentRect !== undefined);
  guard('containPixel: the rect, edges included', call('contain', 2).ret === true && call('contain', 3).ret === false);
  guard('containPixel of a series on a matrix is the matrix\'s', call('contain', 4).ret === true);
  // series
  guard('custom: the coordSys is the matrix rect', cs('custom-cells').custom[0].calls[0].coordSys.type === 'matrix');
  guard('custom: an unknown name draws nothing', cs('custom-cells').custom[0].roots < cs('custom-cells').custom[0].calls.length);
  guard('graph: an unknown name with a value is placed at NaN, a node with nothing is not placed either', cs('graph-cells').graphs[0].nodes[5].p[0] === hex(NaN));
  guard('graph: a node with no value is placed by its x and y', cs('graph-cells').graphs[0].nodes[8].p[0] !== hex(NaN));
  guard('graph: a curved edge has a control point', cs('graph-cells').graphs[0].edges.some(e => e.points && e.points.length === 3));
  guard('pie: a center read as a coord', cs('pie-cells').pies[0].box && n(cs('pie-cells').pies[0].sectors[0].r) === 20);
  guard('pie: an explicit data usage is on the canvas', !cs('pie-cells').pies[4].box && n(cs('pie-cells').pies[4].sectors[0].cx) === 700);
  guard('pie: an unknown name has no centre', Number.isNaN(n(cs('pie-cells').pies[3].sectors[0].cx)));
  guard('funnel: in the cell', cs('funnel-cell').funnels[0].items[0].points !== null);
  guard('the gallery pies are in their cells', cs('gallery-matrix-pie').pies.length > 10);
  // view
  const vl = cs('label-rotate').matrices[0].els.filter(e => e.label);
  guard('a dimension rotate turns its labels', vl.some(e => n(e.label.rot) === 90 * Math.PI / 180));
  guard('a cell rotate wins', vl.some(e => n(e.label.rot) === 45 * Math.PI / 180));
  guard('an offset moves the origin', vl.some(e => e.label.offset !== null && n(e.label.ox) !== 0));
  guard('rich labels break in the overflow area', cs('label-rich').matrices[0].els.some(e => e.label && e.label.lines.length > 1));
  // pointer
  const st = (id, k) => cs(id).states[k];
  guard('a filled body cell triggers an event with no name', st('ptr-events', 0).events.some(e => e.type === 'mouseover' && e.targetType === 'body' && e.name === null));
  guard('a header label triggers the header cell\'s event', st('ptr-events', 1).events.some(e => e.targetType === 'x' && e.name === 'a'));
  guard('a header rect with no fill is silent', st('ptr-events', 2).hit === null || st('ptr-events', 2).hit.kind !== 'matrix' || st('ptr-events', 2).hit.role !== 'rect');
  guard('a heatmap item is over the cell', st('ptr-events', 3).hit && st('ptr-events', 3).hit.kind === 'series');
  guard('a label written silent is not hit', !(st('ptr-events', 4).hit && st('ptr-events', 4).hit.role === 'label'));
  guard('a cell written not silent is hit with no fill', st('ptr-events', 5).hit && st('ptr-events', 5).hit.role === 'rect');
  guard('a header label shows its name in the tooltip', st('ptr-tooltip', 0).tooltip.shown && st('ptr-tooltip', 0).tooltip.text === 'A');
  guard('a formatter over name and xyLocator', st('ptr-tooltip', 3).tooltip.text === 'n @ 1,-1');
  guard('a filled header shows the global tooltip', st('ptr-fill', 0).tooltip.shown && st('ptr-fill', 0).tooltip.text === 'a');
  guard("an axis trigger still shows a cell's tooltip", st('ptr-axis-trigger', 0).tooltip.shown && st('ptr-axis-trigger', 0).tooltip.text === 'n');
  guard('a series item on the matrix shows its rows', st('ptr-fill', 1).tooltip.shown && st('ptr-fill', 1).tooltip.rows !== null);
  return g;
}

function generate() {
  const out = {
    source: DIST, version: echarts.version, seed: SEED, W, H,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: ' + W + ' x ' + H + ', SVG ssr with TooltipView running, animation false; the gallery options fed verbatim but for a custom series\' renderItem (@mxGal).',
      'Math.random is the port\'s xorshift32 from ' + SEED + ', reset before every chart.',
      'a pointer step settles the timers 500 ms before and after the move.',
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
