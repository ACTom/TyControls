/*
Upstream's own answers for round-3 batch R3-A: the OLD OPTION SPELLINGS that
ECharts 6.1 rewrites before it builds a model (preprocessor/backwardCompat.ts
with helper/compatStyle.ts, chart/radar/backwardCompat.ts,
chart/candlestick/preprocessor.ts) -- itemStyle / lineStyle / areaStyle /
label / labelLine / upperLabel / edgeLabel written with `normal` and
`emphasis`, ec2's itemStyle.normal.label, a label's `textStyle`, the series'
old keys (clipOverflow, clockWise, hoverOffset, barBorderRadius,
highlightPolicy, downplay, focusNodeAdjacency, mapType, mapLocation,
hoverAnimation, x / y / x2 / y2), the components' x / y / x2 / y2, dataRange,
a polar with an indicator, a radar's name and nameGap, type 'k' -- on every
option the manager preprocesses: the base, the timeline's frames, a media
unit with a query (never the media default), a merge.

EVERY CASE IS THREE RUNS of the same steps on charts of their own:
  legacy  the old spellings
  modern  what the author writes today for the same chart
  plain   (most cases) the chart without what the old spellings say
and the guards hold that, at every step, the legacy chart's display list
equals the modern one's -- every displayable's type, style, shape,
transform, z and states, in display order -- and differs from the plain
one's at some step: upstream itself says the old spelling draws as the
modern one, and that it draws something. The port's test runs the same three
on the port and holds the legacy bitmaps to the modern ones, pixel for
pixel, and the legacy option tree to upstream's.

A step: {kind: 'set', option, opts?} (chart.setOption; the first is an init,
a later one a merge unless opts.notMerge), {kind: 'action', payload}
(dispatchAction), {kind: 'hover', series, dataIndex} (resolved, on the
legacy chart, to the integer point at the centre of that item's element --
a sector's mid-angle and mid-radius -- and checked to hit it; the modern and
plain runs move to the same point) or {kind: 'hover', geo: [lng, lat]} (the
geo's dataToPoint). After every step the chart is rendered and a frame run
(renderToSVGString, chart._onframe).

THE TREE (legacy run only) is the raw merge layer, as timeline.js records
it: init and mergeOption of every component and series model wrapped, the
outermost call keeping a clone of the option as it arrives and merging
every later one into it (zrUtil.merge); a box-layout model's direction a
merge wrote read back from the model; the timeline's setCurrentIndex
written into it. Root keys that are no component: merged from the options
AS THE MANAGER PREPROCESSED THEM (the base, the frames, the query units --
the default as written), unlike timeline.js and media.js, because
`dataRange` is rewritten. A component main type is in the tree once a merged
option writes it non-null; the ones the preprocessors write into every
option (series, axisPointer, grid, markPoint, markLine, markArea) only where
the author wrote them -- the port keeps those models out of its tree.
Guard: every tree is a subset of getOption().

Runs the real ECharts 6.1 build (ECHARTS_DIST) in node's server-side mode
(SVG renderer), chart._ssr = false, env.node off, Math.random the port's
xorshift32, every chart 600 x 400 with `animation: false`. The map 'sq' --
two squares, A and B -- is registered on both sides (maps.sq). Upstream's
deprecation warnings are counted, not printed.

  node tools/advchart-oracle/backward-compat.js

writes tests/fixtures/advchart-backward-compat.json (ORACLE_OUT overrides):
  source, version, W, H, maps {sq}, cases[], guards[]
  case: id, group, note, legacy[], modern[], plain[] | null (the steps as
  run, hover points resolved), trees[] (after each legacy step), differs[]
  (per step: the legacy display list differs from the plain one; null
  without a plain run).
Runs twice; the two outputs must be byte-identical. Ends with process.exit().
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

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
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-backward-compat.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const clone = v => JSON.parse(JSON.stringify(v));
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}

// ---------- zrender's width table (as timeline.js): the port measures with it ----------
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
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

// ---------- the environment (as timeline.js) ----------
(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

const SQ = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', properties: { name: 'A' },
      geometry: { type: 'Polygon', coordinates: [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]] } },
    { type: 'Feature', properties: { name: 'B' },
      geometry: { type: 'Polygon', coordinates: [[[10, 0], [20, 0], [20, 10], [10, 10], [10, 0]]] } },
  ],
};
const SQ_TEXT = JSON.stringify(SQ);
echarts.registerMap('sq', SQ_TEXT);

const zrUtil = echarts.zrUtil;
const CM = echarts.ComponentModel;
const MAIN_TYPES = CM.getAllClassMainTypes().slice();
const IS_CMPT = new Set(MAIN_TYPES);
// written into every option (or every one with series) by a preprocessor;
// the port keeps their models out of its tree
const PREPROC = new Set(['series', 'axisPointer', 'grid', 'markPoint', 'markLine', 'markArea']);

// ---------- the raw-layer hooks (as timeline.js) ----------
let HOOK_LOG = null;
function wrap(proto, name) {
  if (!has(proto, name)) return;
  const orig = proto[name];
  if (orig.__mergeHook) return;
  const f = function (option) {
    const outer = !this.__rawDepth;
    if (outer) {
      if (name === 'init') this.__raw = zrUtil.clone(option);
      else this.__raw = zrUtil.merge(this.__raw, zrUtil.clone(option), true);
      if (HOOK_LOG) HOOK_LOG.push({ model: this, kind: name, option });
    }
    this.__rawDepth = (this.__rawDepth || 0) + 1;
    try {
      return orig.apply(this, arguments);
    } finally {
      this.__rawDepth--;
      if (outer && name === 'init' && this.mainType === 'legend' && !has(this.__raw, 'selected')) {
        this.__raw.selected = null;
      }
    }
  };
  f.__mergeHook = true;
  proto[name] = f;
}
const PROTOS = [CM.prototype, echarts.SeriesModel.prototype];
for (const mt of MAIN_TYPES) {
  for (const C of CM.getClassesByMainType(mt)) {
    for (let p = C.prototype; p && p !== Object.prototype; p = Object.getPrototypeOf(p)) {
      if (!PROTOS.includes(p)) PROTOS.push(p);
    }
  }
}
for (const p of PROTOS) {
  wrap(p, 'init');
  wrap(p, 'mergeOption');
}
for (const C of CM.getClassesByMainType('timeline')) {
  for (let p = C.prototype; p && p !== Object.prototype; p = Object.getPrototypeOf(p)) {
    if (has(p, 'setCurrentIndex') && !p.setCurrentIndex.__h) {
      const sci = p.setCurrentIndex;
      p.setCurrentIndex = function () {
        const r = sci.apply(this, arguments);
        if (this.__raw) this.__raw.currentIndex = this.option.currentIndex;
        return r;
      };
      p.setCurrentIndex.__h = true;
    }
  }
}
const HV = [['width', 'left', 'right'], ['height', 'top', 'bottom']];
function layoutModeOf(model) {
  return model.layoutMode || model.constructor.layoutMode;
}

let OM_LOG = null;
(function () {
  const c = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  c.setOption({ animation: false });
  const proto = Object.getPrototypeOf(c.getModel()._optionManager);
  c.dispose();
  const gm = proto.getMediaOption;
  proto.getMediaOption = function () {
    const r = gm.apply(this, arguments);
    if (OM_LOG) OM_LOG.push({ kind: 'media', returned: r.length, indices: this._currentMediaIndices.slice() });
    return r;
  };
  const gt = proto.getTimelineOption;
  proto.getTimelineOption = function (ecModel) {
    const r = gt.apply(this, arguments);
    const tl = ecModel.getComponent('timeline');
    if (OM_LOG) OM_LOG.push({ kind: 'timeline', returned: !!r, index: tl ? tl.getCurrentIndex() : null });
    return r;
  };
})();

function parseRaw(raw) {
  const declared = raw.baseOption;
  const hasMedia = !!raw.media;
  const hasTimeline = !!(raw.options || raw.timeline || (declared && declared.timeline));
  let base;
  if (declared) {
    base = declared;
    if (!base.timeline) base.timeline = raw.timeline;
  } else {
    if (hasTimeline || hasMedia) raw.options = raw.media = null;
    base = raw;
  }
  return base;
}
function unitsOf(raw) {
  const list = [];
  let def = null;
  if (raw.media && Array.isArray(raw.media)) {
    for (const u of raw.media) {
      if (u && u.option) {
        if (u.query) list.push(u);
        else if (!def) def = u;
      }
    }
  }
  return { list, def };
}
function treeOf(chart, rootRaw, written) {
  const t = {};
  for (const k of Object.keys(rootRaw)) t[k] = zrUtil.clone(rootRaw[k]);
  for (const mt of MAIN_TYPES) {
    if (!written.has(mt)) continue;
    const arr0 = chart.getModel()._componentsMap.get(mt);
    const arr = (arr0 || []).map(m => {
      if (!m) return null;
      const o = zrUtil.clone(m.__raw);
      if (mt === 'legend') o.selected = zrUtil.clone(m.option.selected);
      return o;
    });
    while (arr.length && arr[arr.length - 1] === null) arr.pop();
    t[mt] = arr;
  }
  return t;
}
function sub(a, b, where) {
  if (a === null) {
    must(b === null || b === undefined, where + ' is null here, ' + JSON.stringify(b) + ' upstream');
    return;
  }
  if (Array.isArray(a)) {
    must(Array.isArray(b) && b.length === a.length, where + ': arrays differ in length');
    a.forEach((v, i) => sub(v, b[i], where + '[' + i + ']'));
    return;
  }
  if (typeof a === 'object') {
    must(b && typeof b === 'object', where + ': an object here, ' + JSON.stringify(b) + ' upstream');
    for (const k of Object.keys(a)) sub(a[k], b[k], where + '.' + k);
    return;
  }
  must(Object.is(a, b), where + ': ' + JSON.stringify(a) + ' here, ' + JSON.stringify(b) + ' upstream');
}
function checkSubset(tree, full, where) {
  for (const k of Object.keys(tree)) {
    must(has(full, k), where + ': ' + k + ' is not in getOption');
    if (IS_CMPT.has(k)) {
      const a = tree[k];
      const b = full[k];
      must(Array.isArray(b) && b.length === a.length, where + ': ' + k + ' has ' + a.length + ' slots, getOption '
        + (Array.isArray(b) ? b.length : typeof b));
      a.forEach((o, i) => {
        if (o === null) {
          must(b[i] === null, where + ': ' + k + '[' + i + '] is a hole only here');
          return;
        }
        // what the model writes back in its own form: a geo's regions
        // (every region of the map listed), a calendar's cellSize (a pair)
        const skip = NORMALISED[k] || [];
        const o2 = Object.assign({}, o);
        skip.forEach(n => delete o2[n]);
        sub(o2, b[i], where + ': ' + k + '[' + i + ']');
      });
    } else sub(tree[k], full[k], where + ': ' + k);
  }
}
const NORMALISED = { geo: ['regions'], calendar: ['cellSize'] };
// an option the manager preprocessed (post) beside the author's (pre)
function mergeRoot(rootRaw, written, post, pre) {
  if (!post || typeof post !== 'object') return;
  for (const k of Object.keys(post)) {
    const v = post[k];
    if (v == null) continue;
    if (IS_CMPT.has(k)) {
      if (PREPROC.has(k) && !(pre && typeof pre === 'object' && pre[k] != null)) continue;
      written.add(k);
      continue;
    }
    rootRaw[k] = rootRaw[k] == null ? zrUtil.clone(v) : zrUtil.merge(rootRaw[k], zrUtil.clone(v), true);
  }
}

// ---------- the chart ----------
const W = 600;
const H = 400;
let created = 0;
let disposed = 0;
function mk() {
  rngState = SEED;
  created++;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function zev(extra) { return Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1, target: null }, extra); }
function moveTo(chart, x, y) {
  chart.getZr().handler.dispatch('mousemove', zev({ zrX: x, zrY: y, offsetX: x, offsetY: y }));
  chart._onframe();
}
function settle(chart) { chart.renderToSVGString(); chart._onframe(); }

// the display list, every displayable as text
const SIG_DROP = new Set(['id', 'animators', 'states', 'parent']);
const sigReplacer = (k, v) => (SIG_DROP.has(k) || k.indexOf('__') === 0 ? undefined : v);
function sigOf(chart) {
  return chart.getZr().storage.getDisplayList(true).map(el => JSON.stringify({
    t: el.type, s: el.style, sh: el.shape || null,
    tr: [el.x, el.y, el.rotation, el.scaleX, el.scaleY, el.originX, el.originY],
    z: [el.zlevel, el.z, el.z2], inv: !!el.invisible, st: el.currentStates || [],
  }, sigReplacer));
}
const sameSig = (a, b) => a.length === b.length && a.every((s, i) => s === b[i]);

function itemEl(chart, si, di) {
  const s = chart.getModel().getSeriesByIndex(si);
  must(s, 'no series ' + si);
  const el = s.getData().getItemGraphicEl(di);
  must(el, 'series ' + si + ' item ' + di + ' has no element');
  return el;
}
function centreOf(el) {
  const m = el.transform || [1, 0, 0, 1, 0, 0];
  let cx;
  let cy;
  const sh = el.shape;
  if (sh && sh.startAngle != null && sh.r != null && sh.cx != null) {
    const mid = (sh.startAngle + sh.endAngle) / 2;
    const rr = ((sh.r0 || 0) + sh.r) / 2;
    cx = sh.cx + rr * Math.cos(mid);
    cy = sh.cy + rr * Math.sin(mid);
  } else {
    const rc = el.getBoundingRect();
    cx = rc.x + rc.width / 2;
    cy = rc.y + rc.height / 2;
  }
  return [Math.round(m[0] * cx + m[2] * cy + m[4]), Math.round(m[1] * cx + m[3] * cy + m[5])];
}
function hits(chart, x, y, el) {
  let t = chart.getZr().handler.findHover(x, y).target;
  while (t) {
    if (t === el) return true;
    t = t.__hostTarget || t.parent;
  }
  return false;
}

// ---------- one run ----------
function run(c, steps, given, record) {
  const chart = mk();
  const out = { steps: [], trees: [], sigs: [], fails: [] };
  let rootRaw = {};
  let written = new Set();
  let first = true;
  let rawFrames = [];
  let rawUnits = { list: [], def: null };
  const om = () => chart.getModel()._optionManager;
  const absorb = replace => {
    const log = OM_LOG || [];
    OM_LOG = null;
    for (const e of log) {
      if (!e.returned) continue;
      if (e.kind === 'timeline') {
        mergeRoot(rootRaw, written, om()._timelineOptions[e.index], rawFrames[e.index]);
        for (const t of replace) written.add(t);
      } else {
        for (const i of e.indices) {
          if (i === -1) mergeRoot(rootRaw, written, om()._mediaDefault.option, rawUnits.def && rawUnits.def.option);
          else mergeRoot(rootRaw, written, om()._mediaList[i].option, rawUnits.list[i] && rawUnits.list[i].option);
        }
      }
    }
    const hl = HOOK_LOG || [];
    HOOK_LOG = null;
    for (const e of hl) {
      if (e.kind !== 'mergeOption' || !e.option) continue;
      if (!layoutModeOf(e.model)) continue;
      for (const names of HV) {
        if (!names.some(n => has(e.option, n))) continue;
        for (const n of names) {
          const v = e.model.option[n];
          e.model.__raw[n] = v === undefined ? null : zrUtil.clone(v);
        }
      }
    }
  };
  const doSet = (option, opts) => {
    const text = JSON.stringify(option);
    const notMerge = !!(opts && opts.notMerge);
    if (notMerge || first) {
      rootRaw = {};
      written = new Set();
      rawFrames = [];
      rawUnits = { list: [], def: null };
    }
    const nu = unitsOf(JSON.parse(text));
    if (nu.list.length) rawUnits.list = nu.list;
    if (nu.def) rawUnits.def = nu.def;
    const rawCopy = JSON.parse(text);
    if (Array.isArray(rawCopy.options) && rawCopy.options.length) rawFrames = JSON.parse(text).options;
    HOOK_LOG = [];
    OM_LOG = [];
    quiet(() => (opts ? chart.setOption(JSON.parse(text), opts) : chart.setOption(JSON.parse(text))));
    first = false;
    mergeRoot(rootRaw, written, om()._newBaseOption, parseRaw(rawCopy));
    absorb([]);
  };
  try {
    steps.forEach((st0, k) => {
      const st = clone(st0);
      HOOK_LOG = [];
      OM_LOG = [];
      switch (st.kind) {
        case 'set':
          doSet(st.option, st.opts || null);
          break;
        case 'action':
          quiet(() => chart.dispatchAction(clone(st.payload)));
          absorb([]);
          break;
        case 'hover': {
          if (given) {
            st.x = given[k].x;
            st.y = given[k].y;
          } else if (st.geo) {
            const geo = chart.getModel().getComponent('geo');
            const p = geo.coordinateSystem.dataToPoint(st.geo);
            st.x = Math.round(p[0]);
            st.y = Math.round(p[1]);
            must(chart.getZr().handler.findHover(st.x, st.y).target, c.id + ': nothing at the geo point');
          } else {
            settle(chart);
            const el = itemEl(chart, st.series, st.dataIndex);
            const p = centreOf(el);
            st.x = p[0];
            st.y = p[1];
            must(hits(chart, st.x, st.y, el), c.id + ': the point ' + p + ' misses series ' + st.series + ' item ' + st.dataIndex);
          }
          moveTo(chart, st.x, st.y);
          absorb([]);
          break;
        }
        default: throw new OracleError('a step of no kind ' + st.kind);
      }
      settle(chart);
      out.sigs.push(sigOf(chart));
      if (record) {
        const tree = treeOf(chart, rootRaw, written);
        try {
          checkSubset(tree, chart.getOption(), c.id + ' step ' + k);
        } catch (e) {
          if (!(e instanceof OracleError)) throw e;
          out.fails.push(e.message);
        }
        out.trees.push(tree);
      }
      out.steps.push(st);
    });
  } finally {
    chart.dispose();
    disposed++;
  }
  return out;
}

// ---------- the cases ----------
const CASES = [];
function add(group, id, note, legacy, modern, plain) {
  CASES.push({ group, id, note, legacy, modern, plain });
}
const set = option => ({ kind: 'set', option });
const merge = option => ({ kind: 'set', option });
const hover = (series, dataIndex) => ({ kind: 'hover', series, dataIndex });
const anim = o => Object.assign({ animation: false }, o);
const AX = () => ({ xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: { type: 'value' } });

// -- pie --
add('style', 'pie-ec3', 'a pie in ec3 spelling: itemStyle, label (its textStyle inside normal) and labelLine with normal and emphasis; a data item\'s own',
  [set(anim({ series: [{ type: 'pie', radius: ['20%', '60%'],
    data: [{ name: 'a', value: 4 }, { name: 'b', value: 3 },
      { name: 'c', value: 2, itemStyle: { normal: { color: '#123456' }, emphasis: { color: '#abcdef' } } }],
    itemStyle: { normal: { borderColor: '#000', borderWidth: 2 }, emphasis: { color: '#ff0000', borderWidth: 4 } },
    label: { normal: { show: true, position: 'outside', textStyle: { fontSize: 16, color: '#333' } }, emphasis: { show: true, fontWeight: 'bold' } },
    labelLine: { normal: { length: 5, lineStyle: { width: 2 } }, emphasis: { lineStyle: { width: 4 } } } }] })),
  hover(0, 1), hover(0, 2)],
  [set(anim({ series: [{ type: 'pie', radius: ['20%', '60%'],
    data: [{ name: 'a', value: 4 }, { name: 'b', value: 3 },
      { name: 'c', value: 2, itemStyle: { color: '#123456' }, emphasis: { itemStyle: { color: '#abcdef' } } }],
    itemStyle: { borderColor: '#000', borderWidth: 2 },
    label: { show: true, position: 'outside', fontSize: 16, color: '#333' },
    labelLine: { length: 5, lineStyle: { width: 2 } },
    emphasis: { itemStyle: { color: '#ff0000', borderWidth: 4 }, label: { show: true, fontWeight: 'bold' }, labelLine: { lineStyle: { width: 4 } } } }] })),
  hover(0, 1), hover(0, 2)],
  [set(anim({ series: [{ type: 'pie', radius: ['20%', '60%'],
    data: [{ name: 'a', value: 4 }, { name: 'b', value: 3 }, { name: 'c', value: 2 }] }] })),
  hover(0, 1), hover(0, 2)]);

add('series', 'pie-keys', 'clockWise, hoverOffset (written null: no growth on hover) and a label margin with alignTo edge',
  [set(anim({ series: [{ type: 'pie', radius: '50%', clockWise: false, startAngle: 30, hoverOffset: 25,
    label: { show: true, position: 'outer', alignTo: 'edge', margin: 40 },
    data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 }, { name: 'c', value: 1 }] }] })), hover(0, 0)],
  [set(anim({ series: [{ type: 'pie', radius: '50%', clockwise: false, startAngle: 30,
    label: { show: true, position: 'outer', alignTo: 'edge', edgeDistance: 40 }, emphasis: { scaleSize: 0 },
    data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 }, { name: 'c', value: 1 }] }] })), hover(0, 0)],
  [set(anim({ series: [{ type: 'pie', radius: '50%', startAngle: 30, label: { show: true, position: 'outer' },
    data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 }, { name: 'c', value: 1 }] }] })), hover(0, 0)]);

// -- bar --
add('style', 'bar-ec2', 'a bar in ec2 spelling: the label inside itemStyle.normal / .emphasis, barBorderRadius / Color / Width, a data item\'s own',
  [set(anim(Object.assign(AX(), { series: [{ type: 'bar',
    data: [3, { value: 5, itemStyle: { normal: { color: '#00aa00', barBorderRadius: [6, 6, 0, 0] } } }, 2, 4],
    itemStyle: {
      normal: { color: '#aa0000', barBorderRadius: 4, barBorderColor: '#000', barBorderWidth: 1,
        label: { show: true, position: 'top', textStyle: { color: '#0000ff', fontSize: 14 } } },
      emphasis: { color: '#00aaaa', barBorderWidth: 3, label: { show: true, position: 'top', color: '#ff00ff' } } } }] }))),
  hover(0, 1), hover(0, 2)],
  [set(anim(Object.assign(AX(), { series: [{ type: 'bar',
    data: [3, { value: 5, itemStyle: { color: '#00aa00', borderRadius: [6, 6, 0, 0] } }, 2, 4],
    itemStyle: { color: '#aa0000', borderRadius: 4, borderColor: '#000', borderWidth: 1 },
    label: { show: true, position: 'top', color: '#0000ff', fontSize: 14 },
    emphasis: { itemStyle: { color: '#00aaaa', borderWidth: 3 }, label: { show: true, position: 'top', color: '#ff00ff' } } }] }))),
  hover(0, 1), hover(0, 2)],
  [set(anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4] }] }))), hover(0, 1), hover(0, 2)]);

add('style', 'bar-ec3-focus', 'the ec3 mix: focus and blurScope inside itemStyle.emphasis lift into emphasis',
  [set(anim(Object.assign(AX(), { series: [
    { type: 'bar', data: [3, 5, 2, 4], itemStyle: { normal: { color: '#888888' }, emphasis: { color: '#ff0000', focus: 'series', blurScope: 'coordinateSystem' } } },
    { type: 'bar', data: [2, 1, 4, 3] }] }))), hover(0, 1)],
  [set(anim(Object.assign(AX(), { series: [
    { type: 'bar', data: [3, 5, 2, 4], itemStyle: { color: '#888888' }, emphasis: { focus: 'series', blurScope: 'coordinateSystem', itemStyle: { color: '#ff0000' } } },
    { type: 'bar', data: [2, 1, 4, 3] }] }))), hover(0, 1)],
  [set(anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4] }, { type: 'bar', data: [2, 1, 4, 3] }] }))), hover(0, 1)]);

// -- line, scatter --
add('style', 'line-ec3', 'a line: lineStyle, areaStyle, itemStyle, label in ec3 spelling; clipOverflow, hoverAnimation',
  [set(anim(Object.assign(AX(), { series: [{ type: 'line', data: [1, 3, 2, 4], symbolSize: 8, clipOverflow: false, hoverAnimation: false,
    lineStyle: { normal: { width: 3, type: 'dashed', color: '#884400' } }, areaStyle: { normal: { opacity: 0.3, color: '#ffcc00' } },
    itemStyle: { normal: { color: '#cc0000', borderColor: '#000', borderWidth: 1 }, emphasis: { color: '#0000cc' } },
    label: { normal: { show: true, position: 'top', textStyle: { fontSize: 13 } } } }] }))), hover(0, 2)],
  [set(anim(Object.assign(AX(), { series: [{ type: 'line', data: [1, 3, 2, 4], symbolSize: 8, clip: false,
    lineStyle: { width: 3, type: 'dashed', color: '#884400' }, areaStyle: { opacity: 0.3, color: '#ffcc00' },
    itemStyle: { color: '#cc0000', borderColor: '#000', borderWidth: 1 },
    label: { show: true, position: 'top', fontSize: 13 }, emphasis: { scale: false, itemStyle: { color: '#0000cc' } } }] }))), hover(0, 2)],
  [set(anim(Object.assign(AX(), { series: [{ type: 'line', data: [1, 3, 2, 4], symbolSize: 8 }] }))), hover(0, 2)]);

add('style', 'scatter-alias', 'a label written with only an emphasis (and a textStyle in it): the emphasis object stands in two places, both take the text style',
  [set(anim({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'scatter', symbolSize: 20, data: [[1, 1], [2, 3], [3, 2]], hoverAnimation: false,
    itemStyle: { normal: { opacity: 0.5, color: '#3366cc' }, emphasis: { opacity: 1, borderColor: '#000', borderWidth: 2 } },
    label: { emphasis: { show: true, position: 'right', textStyle: { color: '#ff0000', fontSize: 15 } } } }] })), hover(0, 1)],
  [set(anim({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'scatter', symbolSize: 20, data: [[1, 1], [2, 3], [3, 2]],
    itemStyle: { opacity: 0.5, color: '#3366cc' },
    emphasis: { scale: false, itemStyle: { opacity: 1, borderColor: '#000', borderWidth: 2 }, label: { show: true, position: 'right', color: '#ff0000', fontSize: 15 } } }] })), hover(0, 1)],
  [set(anim({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'scatter', symbolSize: 20, data: [[1, 1], [2, 3], [3, 2]] }] })), hover(0, 1)]);

// -- graph, sankey --
const GNODES = () => [{ name: 'n0', x: 100, y: 100 }, { name: 'n1', x: 300, y: 100 }, { name: 'n2', x: 200, y: 300 }, { name: 'n3', x: 450, y: 300 }];
const GLINKS = () => [{ source: 'n0', target: 'n1' }, { source: 'n1', target: 'n2' }, { source: 'n2', target: 'n3' }];
add('style', 'graph-ec3', 'a graph: categories, nodes and links in ec3 spelling, an edge label\'s textStyle, focusNodeAdjacency',
  [set(anim({ series: [{ type: 'graph', layout: 'none', symbolSize: 30, focusNodeAdjacency: true,
    categories: [{ name: 'A', itemStyle: { normal: { color: '#00aa00' } } }, { name: 'B' }],
    data: [{ name: 'n0', x: 100, y: 100, category: 0 }, { name: 'n1', x: 300, y: 100, category: 1, itemStyle: { normal: { color: '#aa00aa' } } },
      { name: 'n2', x: 200, y: 300, category: 1 }, { name: 'n3', x: 450, y: 300 }],
    links: [{ source: 'n0', target: 'n1', lineStyle: { normal: { color: '#ff0000', width: 4 } } }, { source: 'n1', target: 'n2' },
      { source: 'n2', target: 'n3', label: { normal: { show: true, textStyle: { fontSize: 11 } } } }],
    itemStyle: { normal: { borderColor: '#000', borderWidth: 2 }, emphasis: { borderWidth: 5 } },
    lineStyle: { normal: { color: '#999999', width: 2, curveness: 0.2 }, emphasis: { width: 5 } },
    label: { normal: { show: true, position: 'right', textStyle: { fontSize: 12 } } },
    edgeLabel: { normal: { show: false, textStyle: { fontSize: 10 } }, emphasis: { show: true } } }] })),
  hover(0, 0), hover(0, 3)],
  [set(anim({ series: [{ type: 'graph', layout: 'none', symbolSize: 30,
    categories: [{ name: 'A', itemStyle: { color: '#00aa00' } }, { name: 'B' }],
    data: [{ name: 'n0', x: 100, y: 100, category: 0 }, { name: 'n1', x: 300, y: 100, category: 1, itemStyle: { color: '#aa00aa' } },
      { name: 'n2', x: 200, y: 300, category: 1 }, { name: 'n3', x: 450, y: 300 }],
    links: [{ source: 'n0', target: 'n1', lineStyle: { color: '#ff0000', width: 4 } }, { source: 'n1', target: 'n2' },
      { source: 'n2', target: 'n3', label: { show: true, fontSize: 11 } }],
    itemStyle: { borderColor: '#000', borderWidth: 2 },
    lineStyle: { color: '#999999', width: 2, curveness: 0.2 },
    label: { show: true, position: 'right', fontSize: 12 },
    edgeLabel: { show: false, fontSize: 10 },
    emphasis: { focus: 'adjacency', itemStyle: { borderWidth: 5 }, lineStyle: { width: 5 }, edgeLabel: { show: true } } }] })),
  hover(0, 0), hover(0, 3)],
  [set(anim({ series: [{ type: 'graph', layout: 'none', symbolSize: 30, categories: [{ name: 'A' }, { name: 'B' }],
    data: [{ name: 'n0', x: 100, y: 100, category: 0 }, { name: 'n1', x: 300, y: 100, category: 1 },
      { name: 'n2', x: 200, y: 300, category: 1 }, { name: 'n3', x: 450, y: 300 }],
    links: GLINKS() }] })),
  hover(0, 0), hover(0, 3)]);

add('merge', 'graph-merge-focus', 'focusNodeAdjacency is rewritten in the option that has it: a later merge\'s emphasis.focus null turns the focus off',
  [set(anim({ series: [{ type: 'graph', layout: 'none', symbolSize: 30, focusNodeAdjacency: true, data: GNODES(), links: GLINKS() }] })),
    merge({ series: [{ emphasis: { focus: null } }] }), hover(0, 1)],
  [set(anim({ series: [{ type: 'graph', layout: 'none', symbolSize: 30, data: GNODES(), links: GLINKS() }] })),
    merge({ series: [{ emphasis: { focus: null } }] }), hover(0, 1)],
  [set(anim({ series: [{ type: 'graph', layout: 'none', symbolSize: 30, focusNodeAdjacency: true, data: GNODES(), links: GLINKS() }] })),
    merge({ series: [{}] }), hover(0, 1)]);

add('series', 'sankey-ec3', 'a sankey: focusNodeAdjacency (\'allEdges\' is adjacency), lineStyle and itemStyle in ec3 spelling',
  [set(anim({ series: [{ type: 'sankey', focusNodeAdjacency: 'allEdges', layoutIterations: 0,
    data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }],
    links: [{ source: 'a', target: 'b', value: 3 }, { source: 'b', target: 'c', value: 2 }, { source: 'a', target: 'd', value: 1 }],
    itemStyle: { normal: { color: '#3388ff', borderColor: '#000' } },
    lineStyle: { normal: { color: 'source', curveness: 0.4, opacity: 0.4 }, emphasis: { opacity: 0.8 } },
    label: { normal: { position: 'left', textStyle: { fontSize: 12 } } } }] })), hover(0, 1)],
  [set(anim({ series: [{ type: 'sankey', layoutIterations: 0,
    data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }],
    links: [{ source: 'a', target: 'b', value: 3 }, { source: 'b', target: 'c', value: 2 }, { source: 'a', target: 'd', value: 1 }],
    itemStyle: { color: '#3388ff', borderColor: '#000' },
    lineStyle: { color: 'source', curveness: 0.4, opacity: 0.4 },
    label: { position: 'left', fontSize: 12 },
    emphasis: { focus: 'adjacency', lineStyle: { opacity: 0.8 } } }] })), hover(0, 1)],
  [set(anim({ series: [{ type: 'sankey', layoutIterations: 0,
    data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }],
    links: [{ source: 'a', target: 'b', value: 3 }, { source: 'b', target: 'c', value: 2 }, { source: 'a', target: 'd', value: 1 }] }] })), hover(0, 1)]);

// -- map, geo --
add('series', 'map-ec3', 'a map: mapType, mapLocation (x / y into left / top), ec3 itemStyle and label, a region\'s own',
  [set(anim({ series: [{ type: 'map', mapType: 'sq', mapLocation: { x: 'center', y: 40, width: 300, height: 150 },
    itemStyle: { normal: { areaColor: '#eeeeee', borderColor: '#333333', borderWidth: 1 }, emphasis: { areaColor: '#ff8800' } },
    label: { normal: { show: true, textStyle: { color: '#0000ff' } }, emphasis: { show: true, textStyle: { color: '#ffffff' } } },
    data: [{ name: 'A', value: 1, itemStyle: { normal: { areaColor: '#00aaff' } } }, { name: 'B', value: 2 }] }] })), hover(0, 1)],
  [set(anim({ series: [{ type: 'map', map: 'sq', left: 'center', top: 40, width: 300, height: 150,
    itemStyle: { areaColor: '#eeeeee', borderColor: '#333333', borderWidth: 1 },
    label: { show: true, color: '#0000ff' },
    emphasis: { itemStyle: { areaColor: '#ff8800' }, label: { show: true, color: '#ffffff' } },
    data: [{ name: 'A', value: 1, itemStyle: { areaColor: '#00aaff' } }, { name: 'B', value: 2 }] }] })), hover(0, 1)],
  [set(anim({ series: [{ type: 'map', map: 'sq', data: [{ name: 'A', value: 1 }, { name: 'B', value: 2 }] }] })), hover(0, 1)]);

add('component', 'geo-alias', 'a geo: x / y, ec3 itemStyle, a label with only an emphasis (two places, the text style in both), a region\'s own',
  [set(anim({ geo: { map: 'sq', x: 40, y: 30, width: 300,
    itemStyle: { normal: { areaColor: '#eeeeee', borderColor: '#444444' }, emphasis: { areaColor: '#ffaa00' } },
    label: { emphasis: { show: true, textStyle: { color: '#ff0000', fontSize: 16 } } },
    regions: [{ name: 'A', itemStyle: { normal: { areaColor: '#00aaff' } } }] },
  series: [{ type: 'scatter', coordinateSystem: 'geo', data: [[5, 5]], symbolSize: 12 }] })), { kind: 'hover', geo: [15, 5] }],
  [set(anim({ geo: { map: 'sq', left: 40, top: 30, width: 300,
    itemStyle: { areaColor: '#eeeeee', borderColor: '#444444' },
    emphasis: { itemStyle: { areaColor: '#ffaa00' }, label: { show: true, color: '#ff0000', fontSize: 16 } },
    regions: [{ name: 'A', itemStyle: { areaColor: '#00aaff' } }] },
  series: [{ type: 'scatter', coordinateSystem: 'geo', data: [[5, 5]], symbolSize: 12 }] })), { kind: 'hover', geo: [15, 5] }],
  [set(anim({ geo: { map: 'sq' }, series: [{ type: 'scatter', coordinateSystem: 'geo', data: [[5, 5]], symbolSize: 12 }] })),
    { kind: 'hover', geo: [15, 5] }]);

// -- gauge, funnel --
add('series', 'gauge-ec2', 'a gauge: clockWise, the textStyle of its axisLabel, title and detail; pointer.color is never read',
  [set(anim({ series: [{ type: 'gauge', clockWise: false, startAngle: 200, endAngle: -20, min: 0, max: 100,
    data: [{ value: 40, name: 'rate' }],
    axisLabel: { textStyle: { color: '#ff0000', fontSize: 14 } }, title: { textStyle: { fontSize: 18, color: '#00aa00' } },
    detail: { textStyle: { color: '#0000ff', fontSize: 22 } }, itemStyle: { normal: { color: '#884488' } }, pointer: { color: '#ff00ff' } }] }))],
  [set(anim({ series: [{ type: 'gauge', clockwise: false, startAngle: 200, endAngle: -20, min: 0, max: 100,
    data: [{ value: 40, name: 'rate' }],
    axisLabel: { color: '#ff0000', fontSize: 14 }, title: { fontSize: 18, color: '#00aa00' },
    detail: { color: '#0000ff', fontSize: 22 }, itemStyle: { color: '#884488' } }] }))],
  [set(anim({ series: [{ type: 'gauge', startAngle: 200, endAngle: -20, min: 0, max: 100, data: [{ value: 40, name: 'rate' }] }] }))]);

add('series', 'funnel-ec3', 'a funnel: x / y / x2 / y2 as its box, ec3 itemStyle, label and labelLine',
  [set(anim({ series: [{ type: 'funnel', x: 60, y: 40, x2: 120, y2: 30,
    data: [{ name: 'a', value: 60 }, { name: 'b', value: 40 }, { name: 'c', value: 20 }],
    itemStyle: { normal: { borderColor: '#fff', borderWidth: 2 }, emphasis: { color: '#ff0000' } },
    label: { normal: { show: true, position: 'inside', textStyle: { color: '#000000' } } },
    labelLine: { normal: { show: false } } }] })), hover(0, 1)],
  [set(anim({ series: [{ type: 'funnel', left: 60, top: 40, right: 120, bottom: 30,
    data: [{ name: 'a', value: 60 }, { name: 'b', value: 40 }, { name: 'c', value: 20 }],
    itemStyle: { borderColor: '#fff', borderWidth: 2 },
    label: { show: true, position: 'inside', color: '#000000' }, labelLine: { show: false },
    emphasis: { itemStyle: { color: '#ff0000' } } }] })), hover(0, 1)],
  [set(anim({ series: [{ type: 'funnel', data: [{ name: 'a', value: 60 }, { name: 'b', value: 40 }, { name: 'c', value: 20 }] }] })), hover(0, 1)]);

// -- radar --
add('component', 'radar-polar', 'ec2: polars with an indicator are radars (type as shape), a radar series\' polarIndex its radarIndex',
  [set(anim({ polar: [
    { indicator: [{ text: 'a', max: 10 }, { text: 'b', max: 10 }, { text: 'c', max: 10 }], center: ['25%', '50%'], radius: 80 },
    { indicator: [{ name: 'x', max: 5 }, { name: 'y', max: 5 }, { name: 'z', max: 5 }, { name: 'w', max: 5 }], type: 'circle', center: ['75%', '50%'], radius: 80 }],
  series: [{ type: 'radar', polarIndex: 1, data: [{ value: [4, 3, 2, 5], name: 'p' }],
    itemStyle: { normal: { color: '#ff0000' } }, areaStyle: { normal: { opacity: 0.4 } }, lineStyle: { normal: { width: 3 } } },
  { type: 'radar', data: [{ value: [5, 6, 7] }] }] }))],
  [set(anim({ radar: [
    { indicator: [{ text: 'a', max: 10 }, { text: 'b', max: 10 }, { text: 'c', max: 10 }], center: ['25%', '50%'], radius: 80 },
    { indicator: [{ name: 'x', max: 5 }, { name: 'y', max: 5 }, { name: 'z', max: 5 }, { name: 'w', max: 5 }], shape: 'circle', center: ['75%', '50%'], radius: 80 }],
  series: [{ type: 'radar', radarIndex: 1, data: [{ value: [4, 3, 2, 5], name: 'p' }],
    itemStyle: { color: '#ff0000' }, areaStyle: { opacity: 0.4 }, lineStyle: { width: 3 } },
  { type: 'radar', data: [{ value: [5, 6, 7] }] }] }))],
  [set(anim({ radar: [
    { indicator: [{ text: 'a', max: 10 }, { text: 'b', max: 10 }, { text: 'c', max: 10 }], center: ['25%', '50%'], radius: 80 },
    { indicator: [{ name: 'x', max: 5 }, { name: 'y', max: 5 }, { name: 'z', max: 5 }, { name: 'w', max: 5 }], center: ['75%', '50%'], radius: 80 }],
  series: [{ type: 'radar', radarIndex: 1, data: [{ value: [4, 3, 2, 5], name: 'p' }] }, { type: 'radar', data: [{ value: [5, 6, 7] }] }] }))]);

add('component', 'radar-name', 'a radar\'s name (its textStyle copied up) is its axisName, nameGap its axisNameGap',
  [set(anim({ radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }],
    name: { textStyle: { color: '#ff0000', fontSize: 16 }, formatter: '[{value}]' }, nameGap: 25 },
  series: [{ type: 'radar', data: [{ value: [3, 5, 7] }] }] }))],
  [set(anim({ radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }],
    axisName: { color: '#ff0000', fontSize: 16, formatter: '[{value}]' }, axisNameGap: 25 },
  series: [{ type: 'radar', data: [{ value: [3, 5, 7] }] }] }))],
  [set(anim({ radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }] },
    series: [{ type: 'radar', data: [{ value: [3, 5, 7] }] }] }))]);

// -- candlestick --
const KAX = () => ({ xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { scale: true } });
const KDATA = () => [[20, 30, 10, 35], [30, 25, 20, 40], [25, 35, 22, 38]];
add('series', 'candlestick-k', 'type \'k\' is the candlestick; its itemStyle in ec3 spelling',
  [set(anim(Object.assign(KAX(), { series: [{ type: 'k', data: KDATA(),
    itemStyle: { normal: { color: '#00aa00', color0: '#aa0000', borderColor: '#004400', borderColor0: '#440000' } } }] }))), hover(0, 1)],
  [set(anim(Object.assign(KAX(), { series: [{ type: 'candlestick', data: KDATA(),
    itemStyle: { color: '#00aa00', color0: '#aa0000', borderColor: '#004400', borderColor0: '#440000' } }] }))), hover(0, 1)],
  [set(anim(Object.assign(KAX(), { series: [{ type: 'candlestick', data: KDATA() }] }))), hover(0, 1)]);

// -- treemap, sunburst, tree --
add('series', 'treemap-ec3', 'a treemap: levels, upperLabel, breadcrumb.itemStyle in ec3 spelling; a child\'s own itemStyle.normal is NOT rewritten (only the top data items are)',
  [set(anim({ series: [{ type: 'treemap', roam: false, nodeClick: false,
    breadcrumb: { show: true, itemStyle: { normal: { color: '#ffcc00', textStyle: { color: '#000' } } } },
    levels: [{ itemStyle: { normal: { borderColor: '#555555', borderWidth: 4, gapWidth: 4 } } },
      { itemStyle: { normal: { borderColor: '#dddddd', borderWidth: 2, gapWidth: 2 } }, upperLabel: { normal: { show: true } } }],
    upperLabel: { normal: { show: false, height: 20, textStyle: { color: '#ffffff' } } },
    label: { normal: { show: true, textStyle: { fontSize: 13 } } },
    itemStyle: { normal: { borderColor: '#ffffff' }, emphasis: { color: '#ff0000' } },
    data: [{ name: 'a', value: 6, children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 2 }] },
      { name: 'b', value: 4, children: [{ name: 'b1', value: 4, itemStyle: { normal: { color: '#0000aa' } } }] }] }] }))],
  [set(anim({ series: [{ type: 'treemap', roam: false, nodeClick: false,
    breadcrumb: { show: true, itemStyle: { color: '#ffcc00', textStyle: { color: '#000' } } },
    levels: [{ itemStyle: { borderColor: '#555555', borderWidth: 4, gapWidth: 4 } },
      { itemStyle: { borderColor: '#dddddd', borderWidth: 2, gapWidth: 2 }, upperLabel: { show: true } }],
    upperLabel: { show: false, height: 20, color: '#ffffff' },
    label: { show: true, fontSize: 13 },
    itemStyle: { borderColor: '#ffffff' }, emphasis: { itemStyle: { color: '#ff0000' } },
    data: [{ name: 'a', value: 6, children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 2 }] },
      { name: 'b', value: 4, children: [{ name: 'b1', value: 4 }] }] }] }))],
  [set(anim({ series: [{ type: 'treemap', roam: false, nodeClick: false,
    data: [{ name: 'a', value: 6, children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 2 }] },
      { name: 'b', value: 4, children: [{ name: 'b1', value: 4 }] }] }] }))]);

add('series', 'sunburst-ec4', 'a sunburst: highlightPolicy as emphasis.focus, downplay as blur (the series\' and every node\'s), ec3 itemStyle and label',
  [set(anim({ series: [{ type: 'sunburst', radius: [20, 150], highlightPolicy: 'ancestor', downplay: { itemStyle: { opacity: 0.2 } },
    itemStyle: { normal: { borderColor: '#ffffff', borderWidth: 2 }, emphasis: { color: '#ff0000' } },
    label: { normal: { show: true, textStyle: { fontSize: 11 } } },
    data: [{ name: 'a', value: 6, downplay: { itemStyle: { opacity: 0.5 } },
      children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 2, downplay: { label: { opacity: 0.1 } } }] },
    { name: 'b', value: 4, children: [{ name: 'b1', value: 4 }] }] }] })), hover(0, 2)],
  [set(anim({ series: [{ type: 'sunburst', radius: [20, 150],
    emphasis: { focus: 'ancestor', itemStyle: { color: '#ff0000' } }, blur: { itemStyle: { opacity: 0.2 } },
    itemStyle: { borderColor: '#ffffff', borderWidth: 2 }, label: { show: true, fontSize: 11 },
    data: [{ name: 'a', value: 6, blur: { itemStyle: { opacity: 0.5 } },
      children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 2, blur: { label: { opacity: 0.1 } } }] },
    { name: 'b', value: 4, children: [{ name: 'b1', value: 4 }] }] }] })), hover(0, 2)],
  [set(anim({ series: [{ type: 'sunburst', radius: [20, 150],
    data: [{ name: 'a', value: 6, children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 2 }] },
    { name: 'b', value: 4, children: [{ name: 'b1', value: 4 }] }] }] })), hover(0, 2)]);

add('series', 'tree-leaves', 'a tree: itemStyle, lineStyle, label and its leaves\' in ec3 spelling',
  [set(anim({ series: [{ type: 'tree', expandAndCollapse: false, symbolSize: 10,
    data: [{ name: 'r', children: [{ name: 'a', children: [{ name: 'a1' }, { name: 'a2' }] }, { name: 'b' }] }],
    itemStyle: { normal: { color: '#ff0000', borderColor: '#000' } }, lineStyle: { normal: { color: '#00aa00', width: 2 } },
    label: { normal: { position: 'left', textStyle: { fontSize: 13, color: '#0000ff' } } },
    leaves: { label: { normal: { position: 'right', color: '#aa00aa' } }, itemStyle: { normal: { color: '#ffcc00' } } } }] }))],
  [set(anim({ series: [{ type: 'tree', expandAndCollapse: false, symbolSize: 10,
    data: [{ name: 'r', children: [{ name: 'a', children: [{ name: 'a1' }, { name: 'a2' }] }, { name: 'b' }] }],
    itemStyle: { color: '#ff0000', borderColor: '#000' }, lineStyle: { color: '#00aa00', width: 2 },
    label: { position: 'left', fontSize: 13, color: '#0000ff' },
    leaves: { label: { position: 'right', color: '#aa00aa' }, itemStyle: { color: '#ffcc00' } } }] }))],
  [set(anim({ series: [{ type: 'tree', expandAndCollapse: false, symbolSize: 10,
    data: [{ name: 'r', children: [{ name: 'a', children: [{ name: 'a1' }, { name: 'a2' }] }, { name: 'b' }] }] }] }))]);

// -- markers --
add('style', 'markers-ec2', 'markPoint / markLine / markArea: ec2 itemStyle.normal.label, ec3 lineStyle and label, a marker datum\'s own, a pair\'s end',
  [set(anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4],
    markPoint: { itemStyle: { normal: { color: '#ff0000', label: { show: true, color: '#ffffff', textStyle: { fontSize: 10 } } } },
      data: [{ type: 'max', name: 'M' }, { type: 'min', itemStyle: { normal: { color: '#00aa00' } } }] },
    markLine: { symbol: 'none', lineStyle: { normal: { color: '#0000ff', type: 'solid', width: 2 } },
      label: { normal: { position: 'start', textStyle: { color: '#0000ff' } } },
      data: [{ type: 'average' }, [{ coord: [0, 1], lineStyle: { normal: { color: '#ff00ff' } } }, { coord: [3, 4] }]] },
    markArea: { itemStyle: { normal: { color: 'rgba(255,0,0,0.2)' } }, label: { normal: { show: true, textStyle: { color: '#880000' } } },
      data: [[{ xAxis: 'a' }, { xAxis: 'b' }]] } }] })))],
  [set(anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4],
    markPoint: { itemStyle: { color: '#ff0000' }, label: { show: true, color: '#ffffff', fontSize: 10 },
      data: [{ type: 'max', name: 'M' }, { type: 'min', itemStyle: { color: '#00aa00' } }] },
    markLine: { symbol: 'none', lineStyle: { color: '#0000ff', type: 'solid', width: 2 }, label: { position: 'start', color: '#0000ff' },
      data: [{ type: 'average' }, [{ coord: [0, 1], lineStyle: { color: '#ff00ff' } }, { coord: [3, 4] }]] },
    markArea: { itemStyle: { color: 'rgba(255,0,0,0.2)' }, label: { show: true, color: '#880000' },
      data: [[{ xAxis: 'a' }, { xAxis: 'b' }]] } }] })))],
  [set(anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4],
    markPoint: { data: [{ type: 'max', name: 'M' }, { type: 'min' }] },
    markLine: { symbol: 'none', data: [{ type: 'average' }, [{ coord: [0, 1] }, { coord: [3, 4] }]] },
    markArea: { data: [[{ xAxis: 'a' }, { xAxis: 'b' }]] } }] })))]);

// -- calendar, axes --
add('component', 'calendar-ec3', 'a calendar: its itemStyle in ec3 spelling, the textStyle of its day, month and year labels; a heatmap on it',
  [set(anim({ visualMap: { show: false, min: 0, max: 10 },
    calendar: { range: '2020-01', cellSize: 30, itemStyle: { normal: { borderColor: '#ff0000', borderWidth: 2, color: '#eeeeee' } },
      dayLabel: { textStyle: { color: '#0000ff', fontSize: 13 } }, monthLabel: { textStyle: { color: '#00aa00' } },
      yearLabel: { show: true, textStyle: { color: '#aa00aa' } } },
    series: [{ type: 'heatmap', coordinateSystem: 'calendar', data: [['2020-01-03', 5], ['2020-01-10', 9]],
      itemStyle: { normal: { borderColor: '#000', borderWidth: 1 } } }] }))],
  [set(anim({ visualMap: { show: false, min: 0, max: 10 },
    calendar: { range: '2020-01', cellSize: 30, itemStyle: { borderColor: '#ff0000', borderWidth: 2, color: '#eeeeee' },
      dayLabel: { color: '#0000ff', fontSize: 13 }, monthLabel: { color: '#00aa00' }, yearLabel: { show: true, color: '#aa00aa' } },
    series: [{ type: 'heatmap', coordinateSystem: 'calendar', data: [['2020-01-03', 5], ['2020-01-10', 9]],
      itemStyle: { borderColor: '#000', borderWidth: 1 } }] }))],
  [set(anim({ visualMap: { show: false, min: 0, max: 10 }, calendar: { range: '2020-01', cellSize: 30, yearLabel: { show: true } },
    series: [{ type: 'heatmap', coordinateSystem: 'calendar', data: [['2020-01-03', 5], ['2020-01-10', 9]] }] }))]);

add('component', 'axes-textstyle', 'an axis label\'s and an axis pointer label\'s textStyle',
  [set(anim({ xAxis: { type: 'category', data: ['a', 'b', 'c'], axisLabel: { textStyle: { color: '#ff0000', fontSize: 15 } } },
    yAxis: { type: 'value', axisLabel: { textStyle: { color: '#0000ff' } } }, series: [{ type: 'line', data: [1, 2, 3] }] }))],
  [set(anim({ xAxis: { type: 'category', data: ['a', 'b', 'c'], axisLabel: { color: '#ff0000', fontSize: 15 } },
    yAxis: { type: 'value', axisLabel: { color: '#0000ff' } }, series: [{ type: 'line', data: [1, 2, 3] }] }))],
  [set(anim({ xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' }, series: [{ type: 'line', data: [1, 2, 3] }] }))]);

// -- the components' layout keys, dataRange --
add('component', 'components-layout', 'x / y / x2 / y2 on a title, a legend, a grid, a toolbox and a slider dataZoom; the toolbox\'s iconStyle in ec3 spelling',
  [set(anim(Object.assign(AX(), { title: { text: 'T', x: 'center', y: 10 }, legend: { data: ['s'], x: 'right', y: 'bottom' },
    grid: { x: 70, y: 50, x2: 40, y2: 60 },
    toolbox: { x: 'left', y: 'top', feature: { saveAsImage: { iconStyle: { normal: { borderColor: '#ff0000' } } }, restore: {} },
      iconStyle: { normal: { borderColor: '#00aa00' }, emphasis: { borderColor: '#0000ff' } } },
    dataZoom: [{ type: 'slider', x: 80, x2: 80, y2: 10 }],
    series: [{ name: 's', type: 'bar', data: [3, 5, 2, 4] }] })))],
  [set(anim(Object.assign(AX(), { title: { text: 'T', left: 'center', top: 10 }, legend: { data: ['s'], left: 'right', top: 'bottom' },
    grid: { left: 70, top: 50, right: 40, bottom: 60 },
    toolbox: { left: 'left', top: 'top', feature: { saveAsImage: { iconStyle: { borderColor: '#ff0000' } }, restore: {} },
      iconStyle: { borderColor: '#00aa00' }, emphasis: { iconStyle: { borderColor: '#0000ff' } } },
    dataZoom: [{ type: 'slider', left: 80, right: 80, bottom: 10 }],
    series: [{ name: 's', type: 'bar', data: [3, 5, 2, 4] }] })))],
  [set(anim(Object.assign(AX(), { title: { text: 'T' }, legend: { data: ['s'] }, toolbox: { feature: { saveAsImage: {}, restore: {} } },
    dataZoom: [{ type: 'slider' }], series: [{ name: 's', type: 'bar', data: [3, 5, 2, 4] }] })))]);

add('component', 'datarange', 'dataRange is the visualMap: its splitList (start / end) its pieces, x / y its left / top; the root dataRange stays the same object',
  [set(anim({ xAxis: { type: 'value' }, yAxis: { type: 'value' },
    dataRange: { splitList: [{ start: 0, end: 5, color: '#ff0000' }, { start: 5, end: 10, color: '#0000ff' }], dimension: 1, x: 'left', y: 'center' },
    series: [{ type: 'scatter', symbolSize: 15, data: [[1, 2], [2, 7], [3, 4], [4, 9]] }] }))],
  [set(anim({ xAxis: { type: 'value' }, yAxis: { type: 'value' },
    visualMap: { pieces: [{ min: 0, max: 5, color: '#ff0000' }, { min: 5, max: 10, color: '#0000ff' }], dimension: 1, left: 'left', top: 'center' },
    series: [{ type: 'scatter', symbolSize: 15, data: [[1, 2], [2, 7], [3, 4], [4, 9]] }] }))],
  [set(anim({ xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [{ type: 'scatter', symbolSize: 15, data: [[1, 2], [2, 7], [3, 4], [4, 9]] }] }))]);

// -- the timeline's frames, media, a merge --
const TLDATA = legacy => ['2001', legacy ? { value: '2002', label: { normal: { color: '#ff00ff' } } } : { value: '2002', label: { color: '#ff00ff' } }];
add('option', 'timeline-ec3', 'a timeline in ec3 spelling (label, itemStyle, controlStyle with its own keys, a data item\'s label, x / x2 / y2); frames in ec3 spelling, the second with only an emphasis',
  [set({ baseOption: anim(Object.assign(AX(), {
    timeline: { axisType: 'category', data: TLDATA(true), x: 20, x2: 20, y2: 0,
      label: { normal: { color: '#ff0000', textStyle: { fontSize: 14 } }, emphasis: { color: '#0000ff' } },
      itemStyle: { normal: { color: '#00aa00' }, emphasis: { color: '#aa0000' } },
      controlStyle: { normal: { color: '#333333', borderColor: '#333333' }, emphasis: { color: '#ff0000' }, showPlayBtn: false },
      checkpointStyle: { color: '#ff8800' } },
    series: [{ type: 'bar' }] })),
  options: [{ series: [{ data: [1, 2, 3, 4], itemStyle: { normal: { color: '#ff0000' } }, label: { normal: { show: true, textStyle: { color: '#000000' } } } }] },
    { series: [{ data: [4, 3, 2, 1], itemStyle: { emphasis: { color: '#00ff00' } } }] }] }),
  { kind: 'action', payload: { type: 'timelineChange', currentIndex: 1 } }, hover(0, 1)],
  [set({ baseOption: anim(Object.assign(AX(), {
    timeline: { axisType: 'category', data: TLDATA(false), left: 20, right: 20, bottom: 0,
      label: { color: '#ff0000', fontSize: 14 }, itemStyle: { color: '#00aa00' },
      controlStyle: { color: '#333333', borderColor: '#333333', showPlayBtn: false }, checkpointStyle: { color: '#ff8800' },
      emphasis: { label: { color: '#0000ff' }, itemStyle: { color: '#aa0000' }, controlStyle: { color: '#ff0000' } } },
    series: [{ type: 'bar' }] })),
  options: [{ series: [{ data: [1, 2, 3, 4], itemStyle: { color: '#ff0000' }, label: { show: true, color: '#000000' } }] },
    { series: [{ data: [4, 3, 2, 1], emphasis: { itemStyle: { color: '#00ff00' } } }] }] }),
  { kind: 'action', payload: { type: 'timelineChange', currentIndex: 1 } }, hover(0, 1)],
  [set({ baseOption: anim(Object.assign(AX(), {
    timeline: { axisType: 'category', data: ['2001', '2002'] }, series: [{ type: 'bar' }] })),
  options: [{ series: [{ data: [1, 2, 3, 4] }] }, { series: [{ data: [4, 3, 2, 1] }] }] }),
  { kind: 'action', payload: { type: 'timelineChange', currentIndex: 1 } }, hover(0, 1)]);

add('option', 'timeline-alias', 'a timeline itemStyle with only an emphasis, a label in it: the timeline preprocessor moves the label out of both places',
  [set(anim({ timeline: { axisType: 'category', data: ['x', 'y'], itemStyle: { emphasis: { color: '#ff0000', label: { color: '#0000ff' } } } },
    series: [{ type: 'pie', data: [1, 2] }] }))],
  [set(anim({ timeline: { axisType: 'category', data: ['x', 'y'], emphasis: { itemStyle: { color: '#ff0000' } } },
    series: [{ type: 'pie', data: [1, 2] }] }))],
  null);

add('option', 'media-query', 'a media unit with a query is preprocessed: its ec3 itemStyle and label apply',
  [set({ baseOption: anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4] }, { type: 'bar', data: [1, 2, 3, 4] }] })),
    media: [{ query: { minWidth: 100 }, option: { series: [{ itemStyle: { normal: { color: '#ff0000' } }, label: { normal: { show: true, textStyle: { fontSize: 15 } } } }] } },
      { option: { series: [{}, { itemStyle: { normal: { color: '#00ff00' } } }] } }] }), hover(0, 1)],
  [set({ baseOption: anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4] }, { type: 'bar', data: [1, 2, 3, 4] }] })),
    media: [{ query: { minWidth: 100 }, option: { series: [{ itemStyle: { color: '#ff0000' }, label: { show: true, fontSize: 15 } }] } },
      { option: { series: [{}, { itemStyle: { color: '#00ff00' } }] } }] }), hover(0, 1)],
  [set({ baseOption: anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4] }, { type: 'bar', data: [1, 2, 3, 4] }] })),
    media: [{ query: { minWidth: 100 }, option: { series: [{}] } }] }), hover(0, 1)]);

add('option', 'media-default', 'the media default is never preprocessed: its ec3 itemStyle and label stay as written and draw nothing',
  [set({ baseOption: anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4] }] })),
    media: [{ query: { maxWidth: 100 }, option: { series: [{ itemStyle: { color: '#0000ff' } }] } },
      { option: { series: [{ itemStyle: { normal: { color: '#00ff00' } }, label: { normal: { show: true } } }] } }] })],
  [set({ baseOption: anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4] }] })),
    media: [{ query: { maxWidth: 100 }, option: { series: [{ itemStyle: { color: '#0000ff' } }] } }, { option: { series: [{}] } }] })],
  null);

add('merge', 'merge-ec3', 'a merge in ec3 spelling is rewritten; with no type in it, its barBorderRadius is not',
  [set(anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4] }] }))),
    merge({ series: [{ itemStyle: { normal: { color: '#ff0000', barBorderRadius: 8 }, emphasis: { color: '#0000ff' } }, label: { normal: { show: true, position: 'insideTop' } } }] }),
    hover(0, 1)],
  [set(anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4] }] }))),
    merge({ series: [{ itemStyle: { color: '#ff0000' }, emphasis: { itemStyle: { color: '#0000ff' } }, label: { show: true, position: 'insideTop' } }] }),
    hover(0, 1)],
  [set(anim(Object.assign(AX(), { series: [{ type: 'bar', data: [3, 5, 2, 4] }] }))), merge({ series: [{}] }), hover(0, 1)]);

// ---------- the guards ----------
function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => out.cases.find(q => q.id === id);
  out.cases.forEach(c => {
    guard(c.id + ': the legacy run draws as the modern one at every step', c.equal.every(x => x));
    if (c.differs) guard(c.id + ': the legacy run draws something the plain one does not', c.differs.some(x => x));
    guard(c.id + ': every tree is a subset of getOption', c.fails.length === 0);
  });
  const t = id => cs(id).trees;
  guard('pie-ec3: the label is the normal, its textStyle copied up', t('pie-ec3')[0].series[0].label.fontSize === 16
    && t('pie-ec3')[0].series[0].emphasis.label.fontWeight === 'bold');
  guard('pie-keys: hoverOffset writes emphasis.scaleSize null', t('pie-keys')[0].series[0].emphasis.scaleSize === null
    && t('pie-keys')[0].series[0].label.edgeDistance === 40 && t('pie-keys')[0].series[0].clockwise === false);
  guard('bar-ec2: the label out of itemStyle.normal, null left behind', t('bar-ec2')[0].series[0].itemStyle.label === null
    && t('bar-ec2')[0].series[0].label.color === '#0000ff' && t('bar-ec2')[0].series[0].itemStyle.borderRadius === 4);
  const sa = t('scatter-alias')[0].series[0];
  guard('scatter-alias: the emphasis-only label keeps its emphasis, and both have the text style', sa.label.emphasis.color === '#ff0000'
    && sa.emphasis.label.color === '#ff0000' && sa.emphasis.scale === false);
  const ga = t('geo-alias')[0].geo[0];
  guard('geo-alias: the same in a geo', ga.label.emphasis.fontSize === 16 && ga.emphasis.label.fontSize === 16 && ga.left === 40);
  guard('graph-merge-focus: the merged focus is null, the old key stays', t('graph-merge-focus')[1].series[0].emphasis.focus === null
    && t('graph-merge-focus')[1].series[0].focusNodeAdjacency === true);
  const dr = t('datarange')[0];
  guard('datarange: the root dataRange is the visualMap object, pieces and all', JSON.stringify(dr.dataRange.pieces) === JSON.stringify(dr.visualMap[0].pieces)
    && dr.dataRange.left === 'left' && !('splitList' in dr.dataRange));
  const rp = t('radar-polar')[0];
  guard('radar-polar: two radars, the polar list empty', rp.radar.length === 2 && rp.radar[1].shape === 'circle' && rp.series[0].radarIndex === 1);
  guard('radar-name: name moved', t('radar-name')[0].radar[0].axisName.fontSize === 16 && !('name' in t('radar-name')[0].radar[0])
    && t('radar-name')[0].radar[0].axisNameGap === 25);
  guard('candlestick-k: the type renamed', t('candlestick-k')[0].series[0].type === 'candlestick');
  const tl = t('timeline-ec3');
  guard('timeline-ec3: controlStyle keeps its own keys, normal and emphasis null', tl[0].timeline[0].controlStyle.normal === null
    && tl[0].timeline[0].controlStyle.emphasis === null && tl[0].timeline[0].controlStyle.color === '#333333' && tl[0].timeline[0].left === 20);
  guard('timeline-ec3: the second frame merged, its emphasis-only itemStyle in two places', tl[1].series[0].emphasis.itemStyle.color === '#00ff00'
    && tl[1].series[0].itemStyle.emphasis.color === '#00ff00');
  const ta = t('timeline-alias')[0].timeline[0];
  guard('timeline-alias: the label moved out of both copies (into a label nobody wrote: gone)', !('label' in ta.emphasis.itemStyle)
    && !('label' in ta.itemStyle.emphasis) && !('label' in ta));
  guard('media-default: the default stays as written', t('media-default')[0].series[0].itemStyle.normal.color === '#00ff00');
  guard('merge-ec3: the untyped merge keeps barBorderRadius', t('merge-ec3')[1].series[0].itemStyle.barBorderRadius === 8
    && !('borderRadius' in t('merge-ec3')[1].series[0].itemStyle));
  guard('treemap-ec3: a child\'s itemStyle.normal stays', t('treemap-ec3')[0].series[0].data[1].children[0].itemStyle.normal.color === '#0000aa');
  guard('gauge-ec2: pointer.color stays unread', t('gauge-ec2')[0].series[0].pointer.color === '#ff00ff' && !('itemStyle' in t('gauge-ec2')[0].series[0].pointer));
  guard('every chart disposed', created === disposed);
  return g;
}

function generate() {
  const cases = CASES.map(c => {
    const L = run(c, c.legacy, null, true);
    const M = run(c, c.modern, L.steps, false);
    must(M.sigs.length === L.sigs.length, c.id + ': the modern run has other steps');
    const equal = L.sigs.map((s, i) => sameSig(s, M.sigs[i]));
    let differs = null;
    let plain = null;
    if (c.plain) {
      const P = run(c, c.plain, L.steps, false);
      must(P.sigs.length === L.sigs.length, c.id + ': the plain run has other steps');
      differs = L.sigs.map((s, i) => !sameSig(s, P.sigs[i]));
      plain = P.steps;
    }
    if (process.env.ORACLE_DEBUG && !equal.every(x => x)) {
      const k = equal.indexOf(false);
      const a = L.sigs[k];
      const b = M.sigs[k];
      console.log(c.id + ' step ' + k + ': ' + a.length + ' vs ' + b.length + ' elements');
      for (let i = 0; i < Math.max(a.length, b.length); i++) {
        if (a[i] !== b[i]) {
          console.log('  L ' + i + ' ' + a[i]);
          console.log('  M ' + i + ' ' + b[i]);
          break;
        }
      }
    }
    return { id: c.id, group: c.group, note: c.note, legacy: L.steps, modern: M.steps, plain, trees: L.trees,
      differs, equal, fails: L.fails };
  });
  const out = { source: DIST, version: echarts.version, W, H, measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    maps: { sq: SQ_TEXT }, cases };
  out.guards = guards(out);
  return out;
}

let out1;
let json1;
let json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = process.env.ORACLE_ONCE ? json1 : JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
out1.cases.forEach(q => q.fails.slice(0, 8).forEach(f => console.log('  ' + q.id + ': ' + f)));
const deterministic = json1 === json2;
const nul = json1.indexOf('\\u0000') >= 0;
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes'
  + (nul ? '; a \\u0000 in the JSON' : '') + '; ' + warnings + ' warnings');
if (bad.length || !deterministic || nul) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
