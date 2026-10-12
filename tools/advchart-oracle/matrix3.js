/*
Upstream's own answers for roadmap D12 part three (MX3), batch 149: the
MATRIX's body and corner cells -- MatrixBodyCorner.ts (the sparse cell map
from `body.data` / `corner.data`: each item located by its `coord` through
parseCoordRangeOption, `coordClamp` clamping to the body or the corner, the
options assigned in order so a later item wins a cell, and `mergeCells`:
resolveXYLocatorRangeByCellMerge's union of every earlier merge it meets,
the earlier ones giving up, a moved top-left cell handing its range to a
shallow copy of the option pushed at the end, and the stale span a merge
keeps when its top-left did not move), Matrix.ts _resize's
layOutBodyCornerCellMerge (the spanRect), dataToLayout's
expandRangeByCellMerge (the default, `ignoreMergeCells`, the clamp that
skips the body or the corner), MatrixView's createBodyAndCorner (a cell in
another's span is not drawn, a merged cell is its spanRect, a cell's
`value` is its label, its own itemStyle makes it z2 100) and
createMatrixCell's function formatter -- and, around them, the series
placed in merged cells, the cells' pointer, the box written back when a
later setOption merges into the matrix, and the three gallery files that
need them (matrix-stock, matrix-mini-bar-geo, matrix-mini-bar-data-
collection).

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off and the chart prototype's getDom answering an
empty object so TooltipView runs, setTimeout a queue the steps settle,
Math.random the port's xorshift32 (seed 2463534242, reset before every
chart) and zrender's width table measuring every string. Every option is run
with animation off.

  node tools/advchart-oracle/matrix3.js

writes tests/fixtures/advchart-matrix3.json (ORACLE_OUT overrides). Ends with
process.exit().

-----------------------------------------------------------------------------
Numbers that are positions are the 16 lowercase hex digits of the IEEE double
(big-endian; NaN 7ff8000000000000); counts, flags, strings and option values
are plain JSON. A recorded value (rv): a number as hex, a string, a boolean,
null (also undefined), an array or an object of those.

Top level: source, version, seed, W, H, measure {firstCode, ratio[] (hex)},
notes[], cases[], guards[].

A case: id, group ('view' | 'algebra' | 'series' | 'pointer' | 'merge'),
note, gallery (a file under examples/advchart/gallery, fed verbatim but for
a custom series' renderItem, then option is null) or option (as run; a
formatter or a renderItem '@name'), options[] for the merge group (each
setOption in turn), fails[] (recipe mismatches; must be empty), and per
group:

  view      matrices[] as matrix.js writes them (box, rect, dims, els in the
            view group's order -- a body or corner cell in another's span is
            not there --, probes [x, y] through dataToLayout / dataToPoint
            with no opt), a label also carrying rot / ox / oy / offset; a
            rect's style.fill is a gradient's first stop, and fillObj
            {type, x, y, x2, y2, r, global, stops[] {offset, color}} when the
            fill is an object; style.decal true when zrender holds one; and
            per matrix maps {body, corner}: {cells[] in the map's order {id
            [x, y], src (the index in data of the option the cell holds, -1
            for none), copy (the option is a shallow copy made for a moved
            merge), owner (cellMergeOwner), inSpanOf [x, y] | null, span
            [x, y] | null, loc [[a, b], [c, d]] (hex) | null, spanRect {x, y,
            width, height} (hex) | null}, owners[] [x, y] in
            _cellMergeOwnerList order}
  algebra   matrices[] {index, rect, layouts[] {input (JSON), opt (JSON or
            null), rect {x, y, width, height}, loc [[a, b], [c, d]], point
            [x, y]} (hex)}
  series    matrices[] {index, rect}; series[] as matrix.js records heatmap /
            scatter rows; custom[] {seriesIndex, calls[] {name, dataIndex,
            api[] {fn, args, opt, ret}}, roots}; pies[] {seriesIndex,
            sectors[] {i, cx, cy, r0, r}} (hex); calls[] the conversions
            {fn, finder, value, opt, ret}
  pointer   steps[] {p [x, y]}; states[] {hit, events[], tooltip} as
            matrix2.js records them
  merge     matrices[] {index, rect (hex), box {left, right, top, bottom,
            width, height} as the model holds them (JSON, null where
            undefined)}

Guards (any failure: nothing is written, exit 1): every case's recipes (R1
every body or corner cell's shape is its unit rect or, merged, its
spanRect, sub-pixel optimised; R2 every spanRect is its id and span's units;
R3 every probe's rect is the units at its locator range's ends; R4 the
display order of a matrix's elements is the group order stably sorted by
z2), named discriminating facts, and the whole fixture generated twice,
byte-identical, no \u0000, parsing back.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-matrix3.json');
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

// the cell label formatters (each mirrored in tests/test.advchart.matrix3.pas)
const FORMATTERS = {
  // the name, the matrix and the locator pair
  mx3Fmt(p) { return p.name + '#' + p.componentIndex + '@' + p.coord.join(':'); },
  // the value as String() prints it, bracketed
  mx3Val(p) { return '[' + p.value + ']'; },
};

// every renderItem call: what it was handed and what its api answered
let CALLS = [];
function recorder(name, fn) {
  return function (params, api) {
    const call = { name, dataIndex: params.dataIndex, api: [] };
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
const RENDER = {
  // the row's cell as dataToLayout sees it by default (merged cells
  // expanded), the cell alone (ignoreMergeCells), the centre
  mx3Cell(params, api) {
    const x = api.value(0);
    const y = api.value(1);
    const a = api.layout([x, y]);
    const b = api.layout([x, y], { ignoreMergeCells: true });
    const c = api.coord([x, y]);
    const d = api.layout([[x, x], y], { clamp: 2 });
    if (isNaN(a.rect.x) || isNaN(a.rect.y)) return null;
    return { type: 'group', children: [
      { type: 'rect', shape: { x: a.rect.x + 2, y: a.rect.y + 2, width: a.rect.width - 4, height: a.rect.height - 4 }, style: { fill: '#88aadd' } },
      { type: 'rect', shape: { x: b.rect.x + 4, y: b.rect.y + 4, width: b.rect.width - 8, height: b.rect.height - 8 }, style: { fill: '#ddaa88' } },
      { type: 'circle', shape: { cx: c[0], cy: c[1], r: 2 + (d.rect.width > 0 ? 1 : 0) }, style: { fill: '#ffffff' } }] };
  },
  // the gallery's: the cell of the row's first two values
  mx3Gal(params, api) {
    const lay = api.layout([api.value(0), api.value(1)]);
    if (isNaN(lay.rect.x) || isNaN(lay.rect.y)) return null;
    return { type: 'rect', shape: { x: lay.rect.x, y: lay.rect.y, width: lay.rect.width, height: lay.rect.height }, style: { fill: '#cccccc' } };
  },
};
// '@name' in an option to the functions above: a renderItem, and a
// `formatter` anywhere under a matrix
function materialize(option) {
  const o = clone(option);
  [].concat(o.series || []).forEach(s => {
    if (s && s.type === 'custom') {
      const nm = typeof s.renderItem === 'string' ? s.renderItem.replace(/^@/, '') : null;
      must(nm && RENDER[nm], 'no renderItem ' + s.renderItem);
      s.renderItem = recorder(nm, RENDER[nm]);
    }
  });
  (function walk(v) {
    if (Array.isArray(v)) v.forEach(walk);
    else if (v && typeof v === 'object') {
      Object.keys(v).forEach(k => {
        if (k === 'formatter' && typeof v[k] === 'string' && v[k].charAt(0) === '@') {
          const f = FORMATTERS[v[k].slice(1)];
          must(f, 'no formatter ' + v[k]);
          v[k] = f;
        }
        else walk(v[k]);
      });
    }
  })(o.matrix);
  o.animation = false;
  return o;
}
// matrix-mini-bar-geo's map is fetched in the browser: a stand-in with one
// square per region it names (the geo is D13's; the matrix is compared)
(function registerStandInMap() {
  const names = ['Valais', 'Ticino', 'Graub\u00fcnden', 'Uri', 'Lucerne', 'Neuch\u00e2tel', 'Jura', 'Vaud', 'Thurgau', 'Schwyz'];
  echarts.registerMap('target_map', { type: 'FeatureCollection', features: names.map((name, i) => ({
    type: 'Feature', properties: { name },
    geometry: { type: 'Polygon', coordinates: [[[i, 0], [i + 1, 0], [i + 1, 1], [i, 1], [i, 0]]] } })) });
})();
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
    if (s && s.type === 'custom') s.renderItem = '@mx3Gal';
  });
  return o;
}
function run(c) {
  const chart = mk();
  CALLS = [];
  if (c.options) c.options.forEach(o => quiet(() => chart.setOption(materialize(o))));
  else quiet(() => chart.setOption(materialize(load(c))));
  paint(chart);
  return chart;
}
const matrices = chart => {
  const out = [];
  chart.getModel().eachComponent('matrix', mm => out.push(mm));
  return out;
};
const dimsOf = mm => [mm.getDimensionModel('x').dim, mm.getDimensionModel('y').dim];
const unitOf = (dims, dimIdx, loc) => (loc < 0 ? dims[1 - dimIdx] : dims[dimIdx]).getUnitLayoutInfo(dimIdx, loc);

// ---------------------------------------------------------------------------
// the view
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
function fillObjRec(f) {
  return {
    type: f.type || null,
    x: f.x == null ? null : f.x, y: f.y == null ? null : f.y,
    x2: f.x2 == null ? null : f.x2, y2: f.y2 == null ? null : f.y2, r: f.r == null ? null : f.r,
    global: !!f.global,
    stops: (f.colorStops || []).map(s => ({ offset: s.offset, color: String(s.color) })),
  };
}
function styleRec(s) {
  const obj = s.fill && typeof s.fill === 'object';
  return {
    // a gradient degrades to its first stop, which is what the port holds
    fill: s.fill == null ? null : obj ? (s.fill.colorStops && s.fill.colorStops.length ? String(s.fill.colorStops[0].color) : null) : String(s.fill),
    fillObj: obj ? fillObjRec(s.fill) : null,
    stroke: s.stroke == null ? null : String(s.stroke),
    lineWidth: hex(s.lineWidth == null ? 1 : s.lineWidth),
    opacity: s.opacity == null ? null : s.opacity,
    lineDash: s.lineDash == null ? null : (Array.isArray(s.lineDash) ? s.lineDash.slice() : String(s.lineDash)),
    decal: !!s.decal,
    shadowBlur: s.shadowBlur == null ? null : s.shadowBlur,
  };
}
// THE CELL ORDER OF MatrixView: the dimension cells (x then y, in ordinal
// order, a hidden dimension none), the body cells (y leaves, then x leaves),
// the corner cells when both dimensions show (x levels, then y levels) --
// a body or corner cell in another cell's span not drawn
function viewPlan(mm) {
  const [xDim, yDim] = dimsOf(mm);
  const plan = [];
  [xDim, yDim].forEach((d, di) => {
    if (!d.shouldShow()) return;
    d._cells.forEach(c => plan.push({ target: di === 0 ? 'x' : 'y', loc: [c.id.x, c.id.y] }));
  });
  const skip = (bc, x, y) => {
    const cell = bc.getCell([x, y]);
    return !!(cell && cell.inSpanOf && cell.inSpanOf !== cell);
  };
  for (let iy = 0; iy < yDim._leavesCount; iy++)
    for (let ix = 0; ix < xDim._leavesCount; ix++)
      if (!skip(mm.getBody(), ix, iy)) plan.push({ target: 'body', loc: [ix, iy] });
  if (xDim.shouldShow() && yDim.shouldShow()) {
    const nx = xDim._levels.length;
    const ny = yDim._levels.length;
    for (let ly = 0; ly < nx; ly++)
      for (let lx = 0; lx < ny; lx++)
        if (!skip(mm.getCorner(), lx - ny, ly - nx)) plan.push({ target: 'corner', loc: [lx - ny, ly - nx] });
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
const locRec = l => [[hex(l[0][0]), hex(l[0][1])], [hex(l[1][0]), hex(l[1][1])]];
// the item of `data` a cell's option is, or the one a merge copied it from
// (extend({}, option) with coord nulled: every other key the same value)
function srcOf(opt, data) {
  if (!opt || !Array.isArray(data)) return { src: -1, copy: false };
  const i = data.indexOf(opt);
  if (i >= 0) return { src: i, copy: false };
  must(opt.coord === null, 'a cell option that is neither an item nor a copy');
  const j = data.findIndex(d => d && typeof d === 'object'
    && Object.keys(d).every(k => k === 'coord' || d[k] === opt[k])
    && Object.keys(opt).every(k => k === 'coord' || d[k] === opt[k]));
  must(j >= 0, 'a copied cell option with no source');
  return { src: j, copy: true };
}
function cellMapRec(bc, kind, mm) {
  const sub = mm.option[kind];
  const data = sub && Array.isArray(sub.data) ? sub.data : null;
  const cells = [];
  bc.travelExistingCells(cell => {
    const s = srcOf(cell.option, data);
    cells.push({
      id: [cell.id.x, cell.id.y], src: s.src, copy: s.copy, owner: !!cell.cellMergeOwner,
      inSpanOf: cell.inSpanOf ? [cell.inSpanOf.id.x, cell.inSpanOf.id.y] : null,
      span: cell.span ? [cell.span.x, cell.span.y] : null,
      loc: cell.locatorRange ? locRec(cell.locatorRange) : null,
      spanRect: cell.spanRect ? rectRec(cell.spanRect) : null,
    });
  });
  return { cells, owners: bc._cellMergeOwnerList.map(c => [c.id.x, c.id.y]) };
}
function probeInputs(mm) {
  const [xDim, yDim] = dimsOf(mm);
  const ins = [];
  // every locator pair, the header levels included, and one past each end
  for (let y = -xDim._levels.length - 1; y <= yDim._leavesCount; y++)
    for (let x = -yDim._levels.length - 1; x <= xDim._leavesCount; x++) ins.push([x, y]);
  ins.push([null, 0], [0, null], ['__none__', 0]);
  xDim._cells.forEach(c => ins.push([String(c.option.value), 0]));
  yDim._cells.forEach(c => ins.push([0, String(c.option.value)]));
  return ins;
}
function viewRec(chart, mm, dlIndex, fails) {
  const [xDim, yDim] = dimsOf(mm);
  const dims = [xDim, yDim];
  const cs = mm.coordinateSystem;
  const view = chart.getViewOfComponentModel(mm);
  const plan = viewPlan(mm);
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
  const probes = probeInputs(mm).map(input => {
    const lay = cs.dataToLayout(input);
    const pt = cs.dataToPoint(input);
    // R3: the rect is the units at the ends of its locator range
    [0, 1].forEach(d => {
      const lo = lay.matrixXYLocatorRange[d][0];
      const hi = lay.matrixXYLocatorRange[d][1];
      const xy = d === 0 ? lay.rect.x : lay.rect.y;
      const wh = d === 0 ? lay.rect.width : lay.rect.height;
      const u0 = Number.isNaN(lo) ? null : unitOf(dims, d, lo);
      const u1 = Number.isNaN(hi) ? null : unitOf(dims, d, hi);
      if (!u0 || !u1) {
        if (!Number.isNaN(xy)) fails.push('R3 a rect with no units ' + JSON.stringify(input));
        return;
      }
      if (!Object.is(u0.xy, xy) || !Object.is(u1.xy + u1.wh - u0.xy, wh)) fails.push('R3 ' + JSON.stringify(input));
    });
    return { input, rect: rectRec(lay.rect), point: [hex(pt[0]), hex(pt[1])], loc: locRec(lay.matrixXYLocatorRange) };
  });
  const box = {};
  ['left', 'right', 'top', 'bottom', 'width', 'height'].forEach(k => { box[k] = jsonOf(mm.option[k]); });
  const maps = { body: cellMapRec(mm.getBody(), 'body', mm), corner: cellMapRec(mm.getCorner(), 'corner', mm) };
  checkCells(mm, dims, els, maps, fails);
  return {
    index: mm.componentIndex, id: mm.option.id == null ? null : String(mm.option.id), z: mm.get('z'),
    rect: rectRec(cs.getRect()), box,
    dims: [dimRec(xDim), dimRec(yDim)], els, probes, maps,
  };
}

function subPixel(p, lw) {
  if (!lw) return p;
  const d = Math.round(p * 2);
  return (d + Math.round(lw)) % 2 === 0 ? d / 2 : (d + 1) / 2;
}
// R1 / R2 / R4
function checkCells(mm, dims, els, maps, fails) {
  const where = 'matrix ' + mm.componentIndex;
  const kinds = { body: mm.getBody(), corner: mm.getCorner() };
  // R2: a spanRect is its id and span's units
  ['body', 'corner'].forEach(kind => maps[kind].cells.forEach(c => {
    if (!c.spanRect) return;
    [0, 1].forEach(d => {
      const u0 = unitOf(dims, d, c.id[d]);
      const u1 = unitOf(dims, d, c.id[d] + c.span[d] - 1);
      const xy = u0 ? u0.xy : NaN;
      const wh = c.span[d] > 1 ? (u1 ? u1.xy + u1.wh - u0.xy : NaN) : (u0 ? u0.wh : NaN);
      const rx = num(d === 0 ? c.spanRect.x : c.spanRect.y);
      const rw = num(d === 0 ? c.spanRect.width : c.spanRect.height);
      if (!Object.is(xy, rx) || !Object.is(wh, rw)) fails.push(where + ' ' + kind + ' ' + c.id + ': R2 axis ' + d);
    });
  }));
  // R1: a body or corner cell's shape
  els.forEach((e, i) => {
    if (e.role !== 'cell' || (e.target !== 'body' && e.target !== 'corner')) return;
    const cell = kinds[e.target].getCell(e.loc);
    let r;
    if (cell && cell.span) r = cell.spanRect;
    else {
      const ux = unitOf(dims, 0, e.loc[0]);
      const uy = unitOf(dims, 1, e.loc[1]);
      r = { x: ux ? ux.xy : NaN, y: uy ? uy.xy : NaN, width: ux ? ux.wh : NaN, height: uy ? uy.wh : NaN };
    }
    const lw = num(e.style.lineWidth);
    const x = subPixel(r.x, lw);
    const y = subPixel(r.y, lw);
    const w = subPixel(r.x + r.width, lw) - x;
    const h = subPixel(r.y + r.height, lw) - y;
    if (!(Object.is(num(e.shape.x), x) && Object.is(num(e.shape.y), y) && Object.is(num(e.shape.width), w) && Object.is(num(e.shape.height), h)))
      fails.push(where + ' el ' + i + ': R1 the cell shape');
  });
  // R4: the display order
  const withDl = [];
  els.forEach((e, i) => {
    withDl.push({ i, z2: e.z2, dl: e.dl });
    if (e.label) withDl.push({ i: i + 0.5, z2: e.label.z2, dl: e.label.dl });
  });
  const sorted = withDl.filter(q => q.dl >= 0).slice().sort((a, b) => a.z2 - b.z2 || a.i - b.i);
  const byDl = withDl.filter(q => q.dl >= 0).slice().sort((a, b) => a.dl - b.dl);
  if (sorted.map(q => q.i).join() !== byDl.map(q => q.i).join()) fails.push(where + ': R4 the display order is not the z2 order');
}

// ---------------------------------------------------------------------------
// the algebra
// ---------------------------------------------------------------------------
const OPTS = [null, { ignoreMergeCells: true }, { ignoreMergeCells: false }, { clamp: 1 }, { clamp: 2 }, { clamp: 3 },
  { clamp: 2, ignoreMergeCells: true }, { clamp: 3, ignoreMergeCells: 0 }, { ignoreMergeCells: 'yes' }, { clamp: true }];
function algebraInputs(mm) {
  const [xDim, yDim] = dimsOf(mm);
  const nx = xDim._leavesCount;
  const ny = yDim._leavesCount;
  const lx = xDim._levels.length;
  const ly = yDim._levels.length;
  const ins = [];
  for (let y = -lx; y < ny; y++) for (let x = -ly; x < nx; x++) ins.push([x, y]);
  ins.push([[0, 1], 0], [[1, nx - 1], [1, 1]], [null, 0], [0, null], [null, null], [[0, nx - 1], [0, ny - 1]],
    [[-1, 0], [-1, 0]], [[nx - 1, 0], ny - 1], [nx - 1, [0, ny - 1]], ['__none__', 1], [[1, '__none__'], 1], [-1, null]);
  xDim._cells.slice(nx).forEach(c => ins.push([String(c.option.value), 0]));
  yDim._cells.slice(ny).forEach(c => ins.push([0, String(c.option.value)]));
  return ins;
}
function algebraRec(mm, fails) {
  const cs = mm.coordinateSystem;
  const dims = dimsOf(mm);
  const layouts = [];
  algebraInputs(mm).forEach(input => OPTS.forEach(opt => {
    const lay = quiet(() => cs.dataToLayout(input, opt === null ? undefined : opt));
    const pt = quiet(() => cs.dataToPoint(input, opt === null ? undefined : opt));
    const loc = lay.matrixXYLocatorRange;
    [0, 1].forEach(d => {
      const lo = loc[d][0];
      const hi = loc[d][1];
      const xy = d === 0 ? lay.rect.x : lay.rect.y;
      const wh = d === 0 ? lay.rect.width : lay.rect.height;
      if (Number.isNaN(lo) || Number.isNaN(hi)) return;
      const u0 = unitOf(dims, d, lo);
      const u1 = unitOf(dims, d, hi);
      if (!u0 || !u1) return;
      if (!Object.is(u0.xy, xy) || !Object.is(u1.xy + u1.wh - u0.xy, wh)) fails.push('R3 ' + JSON.stringify(input) + ' ' + JSON.stringify(opt));
    });
    if (!Object.is(pt[0], lay.rect.x + lay.rect.width / 2) || !Object.is(pt[1], lay.rect.y + lay.rect.height / 2))
      fails.push('the point is not the centre ' + JSON.stringify(input));
    layouts.push({ input: clone(input), opt: jsonOf(opt), rect: rectRec(lay.rect), loc: locRec(loc), point: [hex(pt[0]), hex(pt[1])] });
  }));
  return { index: mm.componentIndex, rect: rectRec(cs.getRect()), layouts };
}

// ---------------------------------------------------------------------------
// the series
// ---------------------------------------------------------------------------
function seriesRecs(chart, dlIndex, fails) {
  const out = { series: [], custom: [], pies: [] };
  chart.getModel().eachSeries(s => {
    if (s.get('coordinateSystem') !== 'matrix') return;
    const type = s.subType;
    const data = s.getData();
    if (type === 'custom') {
      const view = chart.getViewOfSeriesModel(s);
      out.custom.push({ seriesIndex: s.seriesIndex, roots: view ? view.group.childrenRef().length : 0, n: data.count() });
      return;
    }
    if (type === 'pie') {
      const sectors = [];
      for (let i = 0; i < data.count(); i++) {
        const l = data.getItemLayout(i);
        sectors.push({ i, cx: hex(l.cx), cy: hex(l.cy), r0: hex(l.r0), r: hex(l.r) });
      }
      out.pies.push({ seriesIndex: s.seriesIndex, sectors });
      return;
    }
    if (type !== 'heatmap' && type !== 'scatter') return;
    const mm = s.getReferringComponents('matrix', { useDefault: true, enableAll: false, enableNone: false }).models[0];
    const cs = mm.coordinateSystem;
    const rows = [];
    const g = v => (typeof v === 'number' ? (Number.isNaN(v) ? null : hex(v)) : (v == null ? null : String(v)));
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      const row = { index: i, x: g(data.get('x', i)), y: g(data.get('y', i)), value: g(data.get('value', i)), drawn: !!el };
      const xv = data.get('x', i);
      const yv = data.get('y', i);
      if (type === 'heatmap') {
        row.shape = el ? rectRec(el.shape) : null;
        if (el) {
          const lay = cs.dataToLayout([xv, yv]).rect;
          if (!(Object.is(el.shape.x, lay.x) && Object.is(el.shape.width, lay.width) && Object.is(el.shape.y, lay.y) && Object.is(el.shape.height, lay.height)))
            fails.push('series ' + s.seriesIndex + ' row ' + i + ': the heatmap rect is not dataToLayout');
        }
      }
      else {
        const lay = data.getItemLayout(i);
        row.point = lay ? [hex(lay[0]), hex(lay[1])] : null;
      }
      rows.push(row);
    }
    out.series.push({ seriesIndex: s.seriesIndex, type, matrixIndex: mm.componentIndex, count: data.count(), rows });
  });
  // the renderItem calls, series by series in order
  let k = 0;
  out.custom.forEach(rec => {
    rec.calls = [];
    let taken = 0;
    while (k < CALLS.length && taken < rec.n) {
      rec.calls.push(CALLS[k++]);
      taken++;
    }
    delete rec.n;
  });
  must(k === CALLS.length, 'renderItem calls left over');
  return out;
}
function convertCalls(chart, plan) {
  return plan.map(([fn, finder, value, opt]) => {
    let ret;
    quiet(() => {
      if (fn === 'toPixel') ret = chart.convertToPixel(finder, value, opt === null ? undefined : opt);
      else if (fn === 'toLayout') ret = chart.convertToLayout(finder, value, opt === null ? undefined : opt);
      else ret = chart.convertFromPixel(finder, value, opt === null ? undefined : opt);
    });
    let r;
    if (fn === 'toLayout' && ret) {
      r = { rect: rectRec(ret.rect) };
      if (ret.matrixXYLocatorRange) r.loc = locRec(ret.matrixXYLocatorRange);
    }
    else r = rv(ret);
    return { fn, finder: clone(finder), value: clone(value), opt: jsonOf(opt), ret: r };
  });
}

// ---------------------------------------------------------------------------
// the pointer (matrix2.js's)
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
  let found = null;
  matrices(chart).forEach(mm => {
    if (found) return;
    const plan = viewPlan(mm);
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
function pointerCase(steps, chart) {
  const events = [];
  ['mouseover', 'mouseout'].forEach(type => chart.on(type, p => {
    const e = { type };
    EVENT_KEYS.forEach(k => { e[k] = p[k] === undefined ? null : clone(p[k]); });
    events.push(e);
  }));
  const tm = chart.getModel().getComponent('tooltip', 0);
  const tv = tm ? chart.getViewOfComponentModel(tm) : null;
  return steps.map(step => {
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
    return st;
  });
}
function stepPoint(chart, step) {
  if (step.p) return step.p.slice();
  const mm = matrices(chart)[step.m || 0];
  const plan = viewPlan(mm);
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
  if (step.far) return [Math.round(el.shape.x + el.shape.width - 4), Math.round(el.shape.y + el.shape.height - 4)];
  return [Math.round(el.shape.x + el.shape.width / 2), Math.round(el.shape.y + el.shape.height / 2)];
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
const add = (group, id, note, option, more) => CASES.push(Object.assign({ group, id, note, option }, more || {}));
const gal = (group, name, note) => CASES.push({ group, id: 'gallery-' + name, note, gallery: name });
const vm = (min, max, extra) => Object.assign({ show: false, min, max, dimension: 2 }, extra || {});

const TREE_BOTH_X = [{ value: 'Q1', children: ['Jan', 'Feb', 'Mar'] }, { value: 'Q2', children: [{ value: 'Apr', children: ['w1', 'w2'] }, 'May'] }, 'H2'];
const TREE_BOTH_Y = [{ value: 'North', children: ['N1', 'N2'] }, 'South', { value: 'East', children: [{ value: 'E1', children: ['E1a'] }] }];
const BOX = { left: 100, right: 100, top: 100, bottom: 100 };
const LET = n => Array.from({ length: n }, (_, i) => String.fromCharCode(97 + i));

// ---- the view ----
add('view', 'body-flat', 'body.data on flat headers: a value (a string, a number, a boolean), an own itemStyle (z2 100), an own label, a written z2, a column by coordClamp, a later item winning a cell whole, a range with no merge, the items that name nothing (an unknown name, a coord that is not an array, no coord, not an object); a corner cell',
  { matrix: Object.assign({
    x: { data: LET(4) }, y: { data: ['p', 'q', 'r'] },
    body: { label: { fontSize: 11 },
      data: [
        { coord: ['a', 'p'], value: 'A1' },
        { coord: [2, 'p'], value: 42 },
        { coord: ['c', 'q'], value: 'styled', itemStyle: { color: '#ffeecc', borderColor: '#cc6600', borderWidth: 2 } },
        { coord: ['d', 2], value: true, label: { color: '#0000aa', fontSize: 15 } },
        { coord: ['b', null], coordClamp: true, itemStyle: { color: '#eef6ff' } },
        { coord: ['b', 'q'], value: 'over', z2: 30 },
        { coord: ['zz', 'p'], value: 'lost' },
        { coord: 'a', value: 'not an array' },
        { value: 'no coord' },
        'a string',
        { coord: [['a', 'b'], 'r'], value: 'range, no merge', itemStyle: { color: '#f0fff0' } },
        { coord: ['a'], value: 'one part' },
      ] },
    corner: { data: [{ coord: [-1, -1], value: 'corner', itemStyle: { color: '#eeeeee' } }] } }, BOX) });
add('view', 'body-nested', 'body.data on trees: a parent coord spreading a style over its leaves, a header locator in body.data (in the map, never drawn), a clamped last row; corner.data on nested headers, a clamped corner row, a corner range reaching into the x header',
  { matrix: Object.assign({
    x: { data: TREE_BOTH_X }, y: { data: TREE_BOTH_Y },
    body: { data: [
      { coord: ['Q1', 'N1'], value: 'Q1N1', itemStyle: { color: '#fff0f0' } },
      { coord: ['H2', 'East'], value: 'H2E' },
      { coord: [-1, 'South'], value: 'in the header' },
      { coord: [[0, 6], [3, 3]], coordClamp: true, value: 'last row' },
      { coord: [null, 'N2'], value: 'no clamp: nothing' }] },
    corner: { data: [
      { coord: [-3, -3], value: 'TL' },
      { coord: [-1, -1], value: 'inner', itemStyle: { color: '#eeffee' } },
      { coord: [null, -2], coordClamp: true, itemStyle: { color: '#f5f5f5' } },
      { coord: [[-2, 0], -1], value: 'crosses' }] } }, { left: 60, right: 60, top: 60, bottom: 60 }) });
add('view', 'merge-basic', 'merged cells: a 2 x 2 with a fill, a tall one, a 1 x 1, a wide one with its label inside left, mergeCells 1 (truthy) and false; a merged corner',
  { matrix: Object.assign({
    x: { data: LET(5) }, y: { data: ['p', 'q', 'r', 's'] },
    body: { data: [
      { coord: [['a', 'b'], ['p', 'q']], mergeCells: true, value: '2x2 merged', itemStyle: { color: '#e8f0ff' } },
      { coord: ['d', ['p', 's']], mergeCells: true, value: 'tall merged cell with words' },
      { coord: ['c', 'r'], mergeCells: true, value: 'one' },
      { coord: [['a', 'c'], 's'], mergeCells: true, label: { position: 'insideLeft' }, value: 'wide' },
      { coord: ['e', 'q'], mergeCells: 1, value: 'truthy' },
      { coord: ['e', ['r', 's']], mergeCells: false, value: 'not merged' }] },
    corner: { data: [{ coord: [-1, -1], mergeCells: true, value: 'c' }] } }, BOX) });
add('view', 'merge-overlap', 'overlapping merges: the union taken, the earlier giving up, a moved top-left handing a copy of the option the whole union; a style inside a merge lost to the copy; a chain of three unions',
  { matrix: Object.assign({
    x: { data: LET(6) }, y: { data: ['p', 'q', 'r', 's', 't'] },
    body: { data: [
      { coord: [['a', 'b'], 'p'], mergeCells: true, value: 'A', itemStyle: { color: '#ffe0e0' } },
      { coord: [['b', 'c'], ['p', 'q']], mergeCells: true, value: 'B' },
      { coord: ['b', 'q'], value: 'style only', itemStyle: { color: '#e0ffe0' } },
      { coord: [['d', 'e'], ['r', 's']], mergeCells: true, value: 'D' },
      { coord: [['e', 'f'], ['s', 't']], mergeCells: true, value: 'E', itemStyle: { color: '#e0e0ff' } },
      { coord: ['c', 'r'], mergeCells: true, value: 'C' },
      { coord: [['c', 'd'], 'r'], mergeCells: true, value: 'chain' },
      { coord: ['a', 't'], value: 'alone' }] } }, BOX) });
add('view', 'merge-stale', 'a merge whose top-left does not move keeps its own span while its range grows: the cell past it drawn on its own, a probe there expanded to the whole range; the same down y',
  { matrix: Object.assign({
    x: { data: LET(4) }, y: { data: ['p', 'q', 'r'] },
    body: { data: [
      { coord: [['b', 'c'], 'p'], mergeCells: true, value: 'first' },
      { coord: [['a', 'b'], 'p'], mergeCells: true, value: 'second' },
      { coord: ['d', ['q', 'r']], mergeCells: true, value: 'down' },
      { coord: ['d', ['p', 'q']], mergeCells: true, value: 'up' }] } }, BOX) });
add('view', 'merge-nest', 'a merge inside an earlier one: the union is the outer, the inner\'s option (no itemStyle) takes it all; a bigger merge after a smaller one it covers',
  { matrix: Object.assign({
    x: { data: LET(7) }, y: { data: ['p', 'q', 'r', 's'] },
    body: { data: [
      { coord: [['a', 'd'], ['p', 'r']], mergeCells: true, value: 'outer', itemStyle: { color: '#f0f0ff' } },
      { coord: [['b', 'c'], 'q'], mergeCells: true, value: 'inner' },
      { coord: ['f', 's'], mergeCells: true, value: 'small first', itemStyle: { color: '#ffffe0' } },
      { coord: [['f', 'g'], ['r', 's']], mergeCells: true, value: 'big later' }] } }, BOX) });
add('view', 'merge-headers', 'merges among the header locators: a body merge on the y header levels (in the body map, never drawn, yet dataToLayout there expands), corner merges across and down the levels, a clamped whole column merged',
  { matrix: Object.assign({
    x: { data: TREE_BOTH_X }, y: { data: TREE_BOTH_Y },
    body: { data: [
      { coord: [[-2, -1], 'N1'], mergeCells: true, value: 'in the header' },
      { coord: ['May', null], coordClamp: true, mergeCells: true, value: 'whole May column', itemStyle: { color: '#fff8e0' } }] },
    corner: { data: [
      { coord: [[-3, -1], -1], mergeCells: true, value: 'wide corner', itemStyle: { color: '#f0f0f0' } },
      { coord: [-3, [-3, -2]], mergeCells: true, value: 'tall corner' }] } }, { left: 60, right: 60, top: 60, bottom: 60 }) });
add('view', 'merge-hidden', 'both headers hidden (the stock layout): merges over the body only, a template formatter over value and coord',
  { matrix: { left: 10, right: 10, top: 10, bottom: 10,
    x: { show: false, data: Array(5).fill(null) }, y: { show: false, data: Array(6).fill(null) },
    body: { label: { formatter: '{value} @ {coord}' }, data: [
      { coord: [[0, 3], [0, 3]], mergeCells: true, value: 'price' },
      { coord: [[0, 3], [5, 5]], mergeCells: true, value: 'volume' },
      { coord: [[0, 3], [4, 4]], mergeCells: true, value: 'macd' },
      { coord: [[4, 4], [0, 3]], mergeCells: true, value: 'book' },
      { coord: [[4, 4], [4, 5]], mergeCells: true, value: 'depth' }] } } });
add('view', 'labels-body', 'body and corner labels: a template over name, value and coord, function formatters through handles (on the x dimension, on the body, on one cell), a merged cell wrapping its words, a merged label turned',
  { matrix: { left: 150, right: 150, top: 150, bottom: 150,
    x: { data: ['a', 'b', 'c'], label: { formatter: '@mx3Fmt' } }, y: { data: ['p', 'q', 'r'] },
    body: { label: { formatter: '{name}|{value}|{coord}' }, data: [
      { coord: ['a', 'p'], value: 3.5 },
      { coord: [['b', 'c'], ['p', 'q']], mergeCells: true, value: 'a merged cell with enough words to wrap', label: { formatter: null } },
      { coord: ['a', 'q'], value: 'fn', label: { formatter: '@mx3Val' } },
      { coord: [['a', 'c'], 'r'], mergeCells: true, value: 'turned', label: { rotate: 90, formatter: '@mx3Fmt' } }] },
    corner: { label: { formatter: '@mx3Val' }, data: [{ coord: [-1, -1], value: 7 }] } } });
add('view', 'styles-body', 'cell styles: a linear and a radial gradient, a decal (not applied upstream), a shadow, an opacity, a dashed border, silent written, the body\'s z2 and a cell\'s',
  { matrix: Object.assign({
    x: { data: LET(4) }, y: { data: ['p', 'q', 'r'] },
    body: { z2: 10, data: [
      { coord: ['a', 'p'], value: 'linear', itemStyle: { color: { type: 'linear', x: 0, y: 0, x2: 1, y2: 1, colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } } },
      { coord: ['b', 'p'], value: 'radial', itemStyle: { color: { type: 'radial', x: 0.5, y: 0.5, r: 0.5, colorStops: [{ offset: 0, color: '#ffffff' }, { offset: 1, color: '#00aa00' }] } } },
      { coord: ['c', 'p'], value: 'decal', itemStyle: { color: '#ddeeff', decal: { symbol: 'circle', dashArrayX: 4, dashArrayY: 4 } } },
      { coord: ['d', 'p'], value: 'shadow', itemStyle: { color: '#eeeeee', shadowBlur: 6, shadowColor: 'rgba(0,0,0,0.4)' } },
      { coord: ['a', 'q'], value: 'faint', itemStyle: { color: '#336699', opacity: 0.3 } },
      { coord: ['b', 'q'], value: 'dashed', itemStyle: { borderType: 'dashed', borderColor: '#333333', borderWidth: 1 } },
      { coord: ['c', 'q'], value: 'loud', silent: false, z2: 200 },
      { coord: [['c', 'd'], 'r'], mergeCells: true, value: 'last', itemStyle: { color: '#fafafa' }, label: { color: '#aa0000' } }] } }, BOX) });
gal('view', 'matrix-stock', 'the gallery: stock, both headers hidden, five merged regions');
gal('view', 'matrix-mini-bar-geo', 'the gallery: mini bars and geo, the region names as body values');
gal('view', 'matrix-mini-bar-data-collection', 'the gallery: both headers collected from a dataset by the series\' encode');

// ---- the algebra ----
add('algebra', 'alg-overlap', 'dataToLayout over the merges of merge-overlap: every locator pair and some ranges under ten opts',
  CASES.find(c => c.id === 'merge-overlap').option);
add('algebra', 'alg-headers', 'dataToLayout over the merges crossing the headers',
  CASES.find(c => c.id === 'merge-headers').option);
add('algebra', 'alg-stale', 'dataToLayout over the stale spans',
  CASES.find(c => c.id === 'merge-stale').option);

// ---- the series ----
add('series', 'series-merged', 'series in merged cells: heatmap and scatter rows expanded to the merge, a custom series asking with and without ignoreMergeCells, a pie in a merged cell; the conversions with the opt',
  { matrix: { left: 80, right: 80, top: 80, bottom: 80, x: { data: LET(4) }, y: { data: ['p', 'q', 'r'] },
    body: { data: [
      { coord: [['a', 'b'], ['p', 'q']], mergeCells: true },
      { coord: ['d', ['p', 'r']], mergeCells: true, value: 'tall' }] } },
    visualMap: vm(0, 10),
    series: [
      { type: 'heatmap', coordinateSystem: 'matrix', data: [['b', 'q', 3], ['c', 'q', 5], ['d', 'r', 7], ['a', 'r', 1]] },
      { type: 'scatter', coordinateSystem: 'matrix', symbolSize: 10, data: [['a', 'q', 2], ['d', 'p', 4], ['c', 'r', 6]] },
      { type: 'custom', coordinateSystem: 'matrix', renderItem: '@mx3Cell', data: [['b', 'p', 1], ['d', 'q', 2], ['c', 'p', 3]] },
      { type: 'pie', coordinateSystem: 'matrix', coord: ['b', 'q'], radius: '40%', data: [1, 2] },
      { type: 'pie', coordinateSystem: 'matrix', center: ['d', 'r'], radius: 15, data: [3, 1] }] },
  { plan: [
    ['toLayout', 'matrix', ['b', 'q'], null], ['toLayout', 'matrix', ['b', 'q'], { ignoreMergeCells: true }],
    ['toLayout', 'matrix', ['d', 'q'], { clamp: 3 }], ['toLayout', 'matrix', [['c', 'd'], 'q'], null],
    ['toPixel', 'matrix', ['a', 'p'], null], ['toPixel', 'matrix', ['a', 'p'], { ignoreMergeCells: 1 }],
    ['toPixel', { seriesIndex: 0 }, ['d', 'r'], { clamp: 2 }], ['fromPixel', 'matrix', [300, 200], null],
  ] });

// ---- the pointer ----
add('pointer', 'ptr-cells', 'body cells with values: a merged filled cell (rect and label), a value cell with no fill (its label), the corner value; triggerEvent and matrix.tooltip.show',
  { tooltip: {},
    matrix: Object.assign({ triggerEvent: true, tooltip: { show: true },
      x: { data: LET(3) }, y: { data: ['p', 'q'] },
      body: { data: [
        { coord: [['a', 'b'], ['p', 'q']], mergeCells: true, value: 'merged', itemStyle: { color: '#eef' } },
        { coord: ['c', 'p'], value: 9 },
        { coord: ['c', 'q'], value: 'fmt', label: { formatter: '@mx3Fmt' } }] },
      corner: { data: [{ coord: [-1, -1], value: 'corner' }] } }, BOX) },
  { steps: [{ cell: ['body', 0, 0] }, { cell: ['body', 0, 0], far: true }, { cell: ['body', 0, 0], label: true }, { cell: ['body', 2, 0], label: true },
    { cell: ['body', 2, 1], label: true }, { cell: ['corner', -1, -1], label: true }, { p: [5, 5] }] });

// ---- the box merged by a later setOption ----
add('merge', 'box-right-width', 'left, then right and width: the left dropped',
  null, { options: [{ matrix: { left: 50, x: { data: ['a', 'b'] }, y: { data: ['p'] } } }, { matrix: { right: 30, width: 300 } }] });
add('merge', 'box-top-then-bottom', 'top, then bottom and height, then the default left kept',
  null, { options: [{ matrix: { top: 40, x: { data: ['a'] }, y: { data: ['p', 'q'] } } }, { matrix: { bottom: '20%', height: 200 } }] });
add('merge', 'box-width-then-left', 'width, then left alone',
  null, { options: [{ matrix: { width: 200, x: { data: ['a', 'b', 'c'] } } }, { matrix: { left: 'center' } }] });
add('merge', 'box-three', 'right, then left, then width',
  null, { options: [{ matrix: { right: 60, x: { data: ['a'] } } }, { matrix: { left: 20 } }, { matrix: { width: '30%' } }] });

function runCase(c) {
  const fails = [];
  const chart = run(c);
  try {
    const rec = { id: c.id, group: c.group, note: c.note, gallery: c.gallery || null, option: c.gallery || c.options ? null : clone(c.option) };
    if (c.options) rec.options = clone(c.options);
    const dl = chart.getZr().storage.getDisplayList(true);
    const dlIndex = new Map();
    dl.forEach((el, i) => dlIndex.set(el, i));
    if (c.group === 'view') rec.matrices = matrices(chart).map(mm => viewRec(chart, mm, dlIndex, fails));
    else if (c.group === 'algebra') rec.matrices = matrices(chart).map(mm => algebraRec(mm, fails));
    else if (c.group === 'series') {
      rec.matrices = matrices(chart).map(mm => ({ index: mm.componentIndex, rect: rectRec(mm.coordinateSystem.getRect()) }));
      Object.assign(rec, seriesRecs(chart, dlIndex, fails));
      rec.calls = convertCalls(chart, c.plan);
    }
    else if (c.group === 'pointer') {
      rec.steps = c.steps.map(s => ({ p: stepPoint(chart, s) }));
      rec.states = pointerCase(rec.steps, chart);
    }
    else {
      rec.matrices = matrices(chart).map(mm => {
        const box = {};
        ['left', 'right', 'top', 'bottom', 'width', 'height'].forEach(k => { box[k] = jsonOf(mm.option[k]); });
        return { index: mm.componentIndex, rect: rectRec(mm.coordinateSystem.getRect()), box };
      });
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
  // each guard lazily: one that throws is a failure, not the end of the run
  const guard = (name, fn) => {
    let ok = false;
    try { ok = !!fn(); } catch (e) { ok = false; }
    g.push({ name, ok });
  };
  const cs = id => out.cases.find(q => q.id === id);
  const m0 = id => cs(id).matrices[0];
  const n = h => num(h);
  const cell = (id, kind, x, y) => m0(id).maps[kind].cells.find(c => c.id[0] === x && c.id[1] === y);
  const el = (id, target, x, y) => m0(id).els.find(e => e.target === target && e.loc && e.loc[0] === x && e.loc[1] === y);
  const probe = (id, x, y) => m0(id).probes.find(p => JSON.stringify(p.input) === JSON.stringify([x, y]));
  out.cases.forEach(q => guard(q.id + ': every record matches its recipe', () => q.fails.length === 0));
  // the cell map
  guard('a body value is its label', () => el('body-flat', 'body', 0, 0).label && el('body-flat', 'body', 0, 0).label.text === 'A1');
  guard('a number value prints as String()', () => el('body-flat', 'body', 2, 0).label.text === '42');
  guard('a boolean value prints too', () => el('body-flat', 'body', 3, 2).label.text === 'true');
  guard('a cell with its own itemStyle is z2 100', () => el('body-flat', 'body', 2, 1).z2 === 100);
  guard('a written z2 wins', () => el('body-flat', 'body', 1, 1).z2 === 30);
  guard('coordClamp: a whole column of the body', () => cell('body-flat', 'body', 1, 0) && cell('body-flat', 'body', 1, 0).src === 4
    && cell('body-flat', 'body', 1, 2).src === 10 && !cell('body-flat', 'body', 1, -1));
  guard('a later item takes the cell whole (its style gone)', () => cell('body-flat', 'body', 1, 1).src === 5 && el('body-flat', 'body', 1, 1).style.fill === 'none');
  guard('an item that names nothing is dropped', () => !m0('body-flat').maps.body.cells.some(c => c.src === 6 || c.src === 7 || c.src === 8 || c.src === 9 || c.src === 11));
  guard('a range with no merge styles every cell', () => el('body-flat', 'body', 0, 2).label.text === 'range, no merge' && el('body-flat', 'body', 1, 2).label.text === 'range, no merge');
  guard('a corner value', () => el('body-flat', 'corner', -1, -1).label.text === 'corner');
  guard('a parent coord spreads over its leaves', () => [0, 1, 2].every(x => cell('body-nested', 'body', x, 0) && cell('body-nested', 'body', x, 0).src === 0));
  guard('a body item at a header locator is in the map, not drawn', () => cell('body-nested', 'body', -1, 2) && !el('body-nested', 'body', -1, 2));
  guard('no clamp: a null part names nothing', () => !m0('body-nested').maps.body.cells.some(c => c.src === 4));
  guard('a corner clamp keeps to the corner', () => cell('body-nested', 'corner', -3, -2) && cell('body-nested', 'corner', -1, -2) && !cell('body-nested', 'corner', 0, -2));
  // merges
  guard('a merged cell is drawn once, as its spanRect', () => el('merge-basic', 'body', 0, 0) && !el('merge-basic', 'body', 1, 0) && !el('merge-basic', 'body', 0, 1)
    && n(el('merge-basic', 'body', 0, 0).shape.width) > n(el('merge-basic', 'body', 2, 0).shape.width) * 1.9);
  guard('a 1 x 1 merge has a span of its own', () => cell('merge-basic', 'body', 2, 2).owner && cell('merge-basic', 'body', 2, 2).span[0] === 1);
  guard('mergeCells: 1 merges, false does not', () => cell('merge-basic', 'body', 4, 1).owner && !cell('merge-basic', 'body', 4, 2).owner);
  guard('a merged corner', () => cell('merge-basic', 'corner', -1, -1).owner);
  guard('overlapping merges unite and the earlier gives up', () => !cell('merge-overlap', 'body', 0, 0).owner || cell('merge-overlap', 'body', 0, 0).copy);
  guard('a moved top-left hands a copy the union', () => cell('merge-overlap', 'body', 0, 0).copy && cell('merge-overlap', 'body', 0, 0).src === 1
    && cell('merge-overlap', 'body', 0, 0).span.join() === '3,2');
  guard('a style inside a merge loses to the copy', () => cell('merge-overlap', 'body', 1, 1).src === 1);
  guard('a chain of unions: one owner over the three', () => m0('merge-overlap').maps.body.owners.length === 2
    && cell('merge-overlap', 'body', 2, 2).owner && cell('merge-overlap', 'body', 2, 2).span.join() === '4,3');
  guard('a stale span: the top-left kept, the span not grown', () => cell('merge-stale', 'body', 0, 0).owner && cell('merge-stale', 'body', 0, 0).span.join() === '2,1'
    && n(cell('merge-stale', 'body', 0, 0).loc[0][1]) === 2);
  guard('a stale span: the cell past it drawn on its own', () => el('merge-stale', 'body', 2, 0) && el('merge-stale', 'body', 2, 0).label.text === 'first');
  guard('a stale span: dataToLayout there expands to the whole range', () => n(probe('merge-stale', 2, 0).loc[0][0]) === 0 && n(probe('merge-stale', 2, 0).loc[0][1]) === 2);
  guard('a nested merge: the inner option takes the outer region', () => cell('merge-nest', 'body', 0, 0).src === 1 && cell('merge-nest', 'body', 0, 0).copy
    && el('merge-nest', 'body', 0, 0).z2 === 25);
  guard('a body merge on header locators is in the body map, not drawn', () => cell('merge-headers', 'body', -2, 0) && cell('merge-headers', 'body', -2, 0).owner
    && !el('merge-headers', 'body', -2, 0));
  guard('a body merge on header locators expands dataToLayout there', () => n(probe('merge-headers', -1, 0).loc[0][0]) === -2);
  guard('a corner merge across the levels is drawn as one', () => el('merge-headers', 'corner', -3, -1) && !el('merge-headers', 'corner', -2, -1));
  guard('a corner merge expands a corner probe', () => n(probe('merge-headers', -1, -1).loc[0][0]) === -3);
  guard('A MERGE CROSSING FROM THE HEADER INTO THE BODY THROWS in _resize (layOutRectOneDimBasedOnUnit asks the header tree for a body locator)', () => (() => {
    const chart = mk();
    let threw = false;
    try {
      quiet(() => chart.setOption({ animation: false, matrix: { x: { data: ['a', 'b'] }, y: { data: ['p'] }, body: { data: [{ coord: [[-1, 0], 0], mergeCells: true }] } } }));
    } catch (e) { threw = e instanceof TypeError; }
    chart.dispose();
    return threw;
  })());
  guard('the hidden headers: five merged regions', () => m0('merge-hidden').maps.body.owners.length === 5);
  // labels and styles
  guard('a template over name, value and coord', () => el('labels-body', 'body', 0, 0).label.text === '3.5|3.5|0,0');
  guard('a function formatter on the x dimension', () => m0('labels-body').els.some(e => e.target === 'x' && e.label && e.label.text === 'a#0@0:-1'));
  guard('a function formatter on one cell', () => el('labels-body', 'body', 0, 1).label.text === '[fn]');
  guard('a null formatter on a cell takes the body\'s back (Model.get)', () => el('labels-body', 'body', 1, 0).label.text.indexOf('|') > 0);
  guard('a merged label wraps', () => el('labels-body', 'body', 1, 0).label.lines.length > 1);
  guard('a gradient fill', () => el('styles-body', 'body', 0, 0).style.fillObj && el('styles-body', 'body', 0, 0).style.fillObj.type === 'linear');
  guard('a decal is not applied to a cell', () => !el('styles-body', 'body', 2, 0).style.decal);
  guard('the body z2 and a cell z2', () => el('styles-body', 'body', 1, 1).z2 === 10 && el('styles-body', 'body', 2, 1).z2 === 200);
  // algebra
  const lay = (id, input, opt) => {
    const r = cs(id).matrices[0].layouts.find(l => JSON.stringify(l.input) === JSON.stringify(input) && JSON.stringify(l.opt) === JSON.stringify(opt));
    must(r, id + ': no layout of ' + JSON.stringify(input) + ' ' + JSON.stringify(opt));
    return r;
  };
  guard('by default a merged cell expands', () => n(lay('alg-overlap', [1, 0], null).loc[0][0]) === 0 && n(lay('alg-overlap', [1, 0], null).loc[0][1]) === 2);
  guard('ignoreMergeCells: the cell alone', () => n(lay('alg-overlap', [1, 0], { ignoreMergeCells: true }).loc[0][0]) === 1);
  guard('ignoreMergeCells is read as a truthy value', () => n(lay('alg-overlap', [1, 0], { ignoreMergeCells: 'yes' }).loc[0][0]) === 1);
  guard('a range meeting a merge grows to cover it', () => n(lay('alg-overlap', [[0, 1], 0], null).loc[1][1]) === 1);
  guard('clamp 3 skips the body\'s merges', () => n(lay('alg-overlap', [1, 0], { clamp: 3 }).loc[0][0]) !== 0);
  guard('clamp 2 skips the corner\'s merges', () => n(lay('alg-headers', [-1, -1], null).loc[0][0]) === -3
    && n(lay('alg-headers', [-1, -1], { clamp: 3 }).loc[0][0]) === -3 && n(lay('alg-headers', [-1, -1], { clamp: 2 }).loc[0][0]) !== -3);
  // series
  const sr = cs('series-merged');
  guard('a heatmap row in a merged cell covers the merge', () => n(sr.series[0].rows[0].shape.width) > n(sr.series[0].rows[1].shape.width) * 1.9);
  guard('a custom series: ignoreMergeCells answers the cell alone', () => sr.custom[0].calls[0].api[0].ret.rect.width !== sr.custom[0].calls[0].api[1].ret.rect.width);
  guard('convertToLayout expands by default, not with the opt', () => cs('series-merged').calls[0].ret.rect.width !== cs('series-merged').calls[1].ret.rect.width);
  // pointer
  const st = k => cs('ptr-cells').states[k];
  guard('a merged cell answers anywhere in it', () => st(0).hit && st(0).hit.kind === 'matrix' && st(1).hit && st(1).hit.loc && st(1).hit.loc.join() === '0,0');
  guard('a body value shows in the tooltip', () => st(3).tooltip.shown && st(3).tooltip.text === '9');
  guard('the event of a body cell carries its value', () => st(0).events.some(e => e.type === 'mouseover' && e.targetType === 'body' && e.value === 'merged'));
  // the box merged
  const box = id => m0(id).box;
  guard('a later right and width drop an earlier left', () => box('box-right-width').left === null && box('box-right-width').right === 30);
  guard('a later left alone keeps the width', () => box('box-width-then-left').width === 200 && box('box-width-then-left').left === 'center');
  // the gallery
  guard('the stock gallery merges five regions', () => m0('gallery-matrix-stock').maps.body.owners.length === 5);
  guard('the mini bars write the region names', () => m0('gallery-matrix-mini-bar-geo').els.some(e => e.target === 'body' && e.label && e.label.text === 'Valais'));
  guard('the collecting gallery collects both headers', () => m0('gallery-matrix-mini-bar-data-collection').dims[0].leaves === 3
    && m0('gallery-matrix-mini-bar-data-collection').dims[1].leaves === 10);
  return g;
}

function generate() {
  const out = {
    source: DIST, version: echarts.version, seed: SEED, W, H,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: ' + W + ' x ' + H + ', SVG ssr with TooltipView running, animation false; the gallery options fed verbatim but for a custom series\' renderItem (@mx3Gal).',
      'Math.random is the port\'s xorshift32 from ' + SEED + ', reset before every chart.',
      'a pointer step settles the timers 500 ms before and after the move.',
      'a formatter or a renderItem written \'@name\' is one of this file\'s functions (FORMATTERS, RENDER).',
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
