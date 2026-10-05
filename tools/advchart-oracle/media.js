/*
Upstream's own answers for MEDIA QUERIES (B12): how an option's `media`
units are read (parseRawOption), which apply at a chart size
(applyMediaQuery: min/max prefixed width, height and aspectRatio), in what
order they are merged over the base (getMediaOption), what a later merge or
a notMerge does to them, and what a resize does (resetOption('media'): the
units merged again only when the set that applies has changed). Sources:
model/OptionManager.ts, model/Global.ts _resetOption, core/echarts.ts
setOption / resize.

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node, SVG renderer with ssr, `animation: false` in the
first option of every case, process.env.TZ = 'UTC'. A resize is
chart.resize({width, height}).

  node tools/advchart-oracle/media.js

writes tests/fixtures/advchart-media.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
THE RAW LAYER, as tools/advchart-oracle/option-merge.js records it (A10):
`init` and `mergeOption` on every prototype of every component class are
wrapped, the outermost call keeps a clone of the option as it arrives
(`__raw`) and every later mergeOption is merged into it with the dist's own
zrUtil.merge; a box-layout model's direction a merge wrote is read back from
the model (mergeLayoutParam writes all three keys). The root keys that are
no component are merged the way _mergeOption merges them, from the options
merged: the base the script reads off the raw option the way parseRawOption
does, then the units getMediaOption handed over -- which the script knows
from the manager's own `_currentMediaIndices` after the call (a wrapper on
getMediaOption records whether it returned anything), and takes from its
own copy of the raw option, before the preprocessors wrote into it. A
component main type is written once a merged option writes it non-null, or
names it in a replaceMerge of a merge that ran.

Per case: {id, w, h, steps[]}; steps:
  {kind: 'set', notMerge, text}        chart.setOption(JSON.parse(text), notMerge)
  {kind: 'set', notMerge, opts, text}  chart.setOption(JSON.parse(text), JSON.parse(opts))
  {kind: 'resize', w, h}               chart.resize({width: w, height: h})
  {kind: 'action', payload}            chart.dispatchAction(payload)
Per step (after it, the chart rendered):
  w, h     the chart's size
  indices  the manager's _currentMediaIndices (-1: the default)
  merged   how many media options the step merged
  tree     the raw merge (what the port's GetOptionJson must give)
  models   {mainType: [null | {id, name, sub}]}
  out      {series: [null | {count, shown, els, bars?, expanded?}],
            grids: [[x, y, w, h]], titles: [null | [x, y, w, h]],
            legend: [null | {names, x, y, content}]}
           els = the data items with a graphic element; bars = each bar's
           shape [x, y, width, height]; expanded = a tree's isExpand per
           data index; legend x / y = the legend view group's position,
           content = the items' extent [x, y, w, h], absolute
  views    [view number per series]: the same number across steps is the
           same series view
Also: queries[] -- applyMediaQuery's answer for a table of queries at sizes,
read by calling the manager's getMediaOption on a one-unit list.

Cross-check (any failure: nothing is written, exit 1):
  1. every leaf of every recorded tree equals upstream's getOption() at the
     same path (the raw layer is a subset of what upstream holds);
  2. per case expectations read off the source (inclusive boundaries, the
     later unit winning, the default only when nothing applies, nothing
     merged when the set is the same, a resize to no unit without a default
     keeping the last unit's values, a merge re-merging what applies, a
     notMerge forgetting the units, the default visiting no series);
  3. the query table agrees with a transcription of applyMediaQuery;
  4. the whole fixture is generated twice (byte-identical).
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-media.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const zr = echarts.zrUtil;
const CM = echarts.ComponentModel;
const MAIN_TYPES = CM.getAllClassMainTypes().slice();
const IS_CMPT = new Set(MAIN_TYPES);

// ---------- the raw-layer hooks (as option-merge.js) ----------
let HOOK_LOG = null;
function wrap(proto, name) {
  if (!Object.prototype.hasOwnProperty.call(proto, name)) return;
  const orig = proto[name];
  if (orig.__mergeHook) return;
  const f = function (option) {
    const outer = !this.__rawDepth;
    if (outer) {
      if (name === 'init') this.__raw = zr.clone(option);
      else {
        this.__raw = zr.merge(this.__raw, zr.clone(option), true);
        if (this.mainType === 'dataset' && option && Object.prototype.hasOwnProperty.call(option, 'transform')) {
          this.__raw.transform = zr.clone(option.transform);
        }
      }
      if (HOOK_LOG) HOOK_LOG.push({ model: this, kind: name, option });
    }
    this.__rawDepth = (this.__rawDepth || 0) + 1;
    try {
      return orig.apply(this, arguments);
    } finally {
      this.__rawDepth--;
      if (outer && name === 'init' && this.mainType === 'legend'
        && !Object.prototype.hasOwnProperty.call(this.__raw, 'selected')) {
        this.__raw.selected = null;
      }
    }
  };
  f.__mergeHook = true;
  proto[name] = f;
}
const PROTOS = [echarts.ComponentModel.prototype, echarts.SeriesModel.prototype];
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
const HV = [['width', 'left', 'right'], ['height', 'top', 'bottom']];
function layoutModeOf(model) {
  return model.layoutMode || model.constructor.layoutMode;
}

// ---------- the option manager's prototype, hooked once ----------
let MEDIA_LOG = null;   // per call: {returned}
let OM_PROTO = null;
function hookManager(chart) {
  const om = chart.getModel()._optionManager;
  const proto = Object.getPrototypeOf(om);
  if (OM_PROTO) {
    must(proto === OM_PROTO, 'one OptionManager class');
    return;
  }
  OM_PROTO = proto;
  const orig = proto.getMediaOption;
  proto.getMediaOption = function () {
    const r = orig.apply(this, arguments);
    if (MEDIA_LOG) MEDIA_LOG.push({ returned: r.length, indices: this._currentMediaIndices.slice() });
    return r;
  };
}

// hooked before any case runs: the first setOption of the first case is
// recorded too
(function () {
  const c = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  c.setOption({ animation: false });
  hookManager(c);
  c.dispose();
})();

// ---------- parseRawOption, transcribed, on the script's own copy ----------
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
function unitsOf(text) {
  const raw = JSON.parse(text);
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

// ---------- applyMediaQuery, transcribed (guard 3) ----------
const QUERY_REG = /^(min|max)?(.+)$/;
function applies(query, w, h) {
  const real = { width: w, height: h, aspectratio: w / h };
  let ok = true;
  zr.each(query, function (value, attr) {
    const m = attr.match(QUERY_REG);
    if (!m || !m[1] || !m[2]) return;
    const r = real[m[2].toLowerCase()];
    if (m[1] === 'min' ? !(r >= value) : !(r <= value)) ok = false;
  });
  return ok;
}

// ---------- one case ----------
function newChart(w, h) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: w, height: h });
  return chart;
}

function seriesSlots(chart) {
  return (chart.getModel()._componentsMap.get('series') || []).map(m => m || null);
}
function slotsOf(chart, mt) {
  const arr = chart.getModel()._componentsMap.get(mt);
  return arr ? arr.map(m => m || null) : null;
}

function treeOf(chart, rootRaw, written) {
  const t = {};
  for (const k of Object.keys(rootRaw)) t[k] = zr.clone(rootRaw[k]);
  for (const mt of MAIN_TYPES) {
    if (!written.has(mt)) continue;
    const slots = slotsOf(chart, mt) || [];
    const arr = slots.map(m => {
      if (!m) return null;
      const o = zr.clone(m.__raw);
      if (mt === 'legend') o.selected = zr.clone(m.option.selected);
      return o;
    });
    while (arr.length && arr[arr.length - 1] === null) arr.pop();
    t[mt] = arr;
  }
  return t;
}

function modelsOf(chart, written) {
  const r = {};
  const types = new Set(['series', ...written]);
  for (const mt of MAIN_TYPES) {
    if (!types.has(mt)) continue;
    const slots = slotsOf(chart, mt);
    if (!slots) continue;
    r[mt] = slots.map(m => m ? { id: m.id, name: m.name, sub: m.subType || '' } : null);
  }
  return r;
}

function outOf(chart) {
  const ecModel = chart.getModel();
  const series = seriesSlots(chart).map(m => {
    if (!m) return null;
    const data = m.getData();
    const o = { count: data.count(), shown: !ecModel.isSeriesFiltered(m) };
    let els = 0;
    for (let i = 0; i < data.count(); i++) if (data.getItemGraphicEl(i)) els++;
    o.els = els;
    if (m.subType === 'bar') {
      o.bars = [];
      for (let i = 0; i < data.count(); i++) {
        const el = data.getItemGraphicEl(i);
        o.bars.push(el && el.shape ? [el.shape.x, el.shape.y, el.shape.width, el.shape.height] : null);
      }
    }
    if (m.subType === 'tree') {
      o.expanded = [];
      for (let i = 0; i < data.count(); i++) o.expanded.push(!!data.tree.getNodeByDataIndex(i).isExpand);
    }
    return o;
  });
  const grids = (slotsOf(chart, 'grid') || []).map(g => {
    if (!g || !g.coordinateSystem) return null;
    const r = g.coordinateSystem.getRect();
    return [r.x, r.y, r.width, r.height];
  });
  const titles = (slotsOf(chart, 'title') || []).map(t => {
    if (!t) return null;
    const v = chart.getViewOfComponentModel(t);
    const g = v && v.group;
    const bg = g && g.children().find(e => e.type === 'rect');
    if (!bg) return null;
    return [g.x + bg.shape.x, g.y + bg.shape.y, bg.shape.width, bg.shape.height];
  });
  const legend = (slotsOf(chart, 'legend') || []).map(l => {
    if (!l) return null;
    const names = l.getData().map(d => d.get('name')).filter(n => l._availableNames.indexOf(n) >= 0);
    const v = chart.getViewOfComponentModel(l);
    // the items' extent, absolute: the group, the content group, its rect
    const cg = v.getContentGroup();
    const r = cg.getBoundingRect();
    return { names, x: v.group.x, y: v.group.y,
      content: [v.group.x + cg.x + r.x, v.group.y + cg.y + r.y, r.width, r.height] };
  });
  return { series, grids, titles, legend };
}

function checkSubset(tree, full, where) {
  for (const k of Object.keys(tree)) {
    must(Object.prototype.hasOwnProperty.call(full, k), where + ': ' + k + ' is not in getOption');
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
        sub(o, b[i], where + ': ' + k + '[' + i + ']');
      });
    } else {
      sub(tree[k], full[k], where + ': ' + k);
    }
  }
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

// the root keys of one merged option, as _mergeOption merges them
function mergeRoot(rootRaw, written, opt) {
  if (!opt || typeof opt !== 'object') return;
  for (const k of Object.keys(opt)) {
    const v = opt[k];
    if (v == null) continue;
    if (IS_CMPT.has(k)) {
      written.add(k);
      continue;
    }
    rootRaw[k] = rootRaw[k] == null ? zr.clone(v) : zr.merge(rootRaw[k], zr.clone(v), true);
  }
}

function runCase(c) {
  let w = c.w || 600;
  let h = c.h || 400;
  const chart = newChart(w, h);
  const steps = [];
  let rootRaw = {};
  let written = new Set();
  // the units the manager holds, the script's copies (before preprocessing)
  let units = { list: [], def: null };
  const viewIds = new Map();
  let viewNext = 0;
  let first = true;
  try {
    for (const st of c.steps) {
      const rec = { step: st };
      HOOK_LOG = [];
      MEDIA_LOG = [];
      let replace = [];
      if (st.kind === 'set') {
        const opt = JSON.parse(st.text);
        const opts = st.opts ? JSON.parse(st.opts) : null;
        const notMerge = !!st.notMerge || !!(opts && opts.notMerge);
        const fresh = notMerge || first;
        if (opts && opts.replaceMerge != null) {
          replace = (zr.isArray(opts.replaceMerge) ? opts.replaceMerge : [opts.replaceMerge]).filter(t => IS_CMPT.has(t));
        }
        if (fresh) {
          rootRaw = {};
          written = new Set();
          units = { list: [], def: null };
        } else {
          // a merge's replaceMerge types are written as `[]` when absent
          for (const t of replace) written.add(t);
        }
        const nu = unitsOf(st.text);
        if (nu.list.length) units.list = nu.list;
        if (nu.def) units.def = nu.def;
        mergeRoot(rootRaw, written, parseRaw(JSON.parse(st.text)));
        if (opts) chart.setOption(opt, opts);
        else chart.setOption(opt, !!st.notMerge);
        first = false;
      } else if (st.kind === 'resize') {
        w = st.w;
        h = st.h;
        chart.resize({ width: w, height: h });
      } else {
        chart.dispatchAction(st.payload);
      }
      // the media merges this step did: in order, the indices the manager kept
      const mlog = MEDIA_LOG;
      MEDIA_LOG = null;
      rec.merged = 0;
      for (const e of mlog) {
        if (!e.returned) continue;
        must(e.returned === e.indices.length, c.id + ': merged ' + e.returned + ' for ' + e.indices.length + ' indices');
        for (const i of e.indices) {
          const u = i === -1 ? units.def : units.list[i];
          must(u, c.id + ': no unit ' + i);
          mergeRoot(rootRaw, written, u.option);
          rec.merged++;
        }
        // the setOption's replaceMerge goes to the media merges too, a
        // fresh one's included
        if (st.kind === 'set') for (const t of replace) written.add(t);
      }
      const log = HOOK_LOG;
      HOOK_LOG = null;
      for (const e of log) {
        if (e.kind !== 'mergeOption' || !e.option) continue;
        const lm = layoutModeOf(e.model);
        if (!lm) continue;
        for (const names of HV) {
          if (!names.some(n => Object.prototype.hasOwnProperty.call(e.option, n))) continue;
          for (const n of names) {
            const v = e.model.option[n];
            e.model.__raw[n] = v === undefined ? null : zr.clone(v);
          }
        }
      }
      // which units merged in the series this step (the default visits none)
      rec.seriesMerged = log.filter(e => e.kind === 'mergeOption' && e.model.mainType === 'series').length;
      chart.renderToSVGString();
      rec.w = w;
      rec.h = h;
      rec.indices = chart.getModel()._optionManager._currentMediaIndices.slice();
      rec.tree = treeOf(chart, rootRaw, written);
      rec.models = modelsOf(chart, written);
      rec.out = outOf(chart);
      rec.views = seriesSlots(chart).map(m => {
        if (!m) return null;
        const v = chart.getViewOfSeriesModel(m);
        if (!viewIds.has(v)) viewIds.set(v, viewNext++);
        return viewIds.get(v);
      });
      checkSubset(rec.tree, chart.getOption(), c.id + ' step ' + steps.length);
      steps.push(rec);
    }
  } finally {
    chart.dispose();
  }
  return { steps };
}

// ---------- the cases ----------
const CAT = ['Mon', 'Tue', 'Wed', 'Thu'];
const S = (o) => JSON.stringify(o);
const TS = { textStyle: { fontSize: 18, fontWeight: 'bold' }, subtextStyle: { fontSize: 12 } };
const T = (o) => Object.assign({}, o, TS);
function bars(extra) {
  return Object.assign({
    animation: false,
    xAxis: { type: 'category', data: CAT },
    yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [1, 2, 3, 4] }],
  }, extra);
}
const set = (o, notMerge) => ({ kind: 'set', notMerge: !!notMerge, text: S(o) });
const setO = (o, opts) => ({ kind: 'set', notMerge: !!opts.notMerge, opts: S(opts), text: S(o) });
const rs = (w, h) => ({ kind: 'resize', w, h });
const act = (p) => ({ kind: 'action', payload: p });
// the title a unit writes: which one applies is read off the tree
const TT = (text) => ({ title: T({ text }) });
const UNIT = (query, text) => ({ query, option: TT(text) });
const DEF = (text) => ({ option: TT(text) });
const titleText = (r, i) => {
  const t = r.steps[i].tree.title;
  return t && t[0] ? t[0].text : undefined;
};

// one key at its boundary: the unit and a default, resized across it
function keyCase(id, query, sizes, expectTexts) {
  return {
    id, w: sizes[0][0], h: sizes[0][1],
    steps: [set(bars({ media: [UNIT(query, 'M'), DEF('D')] }))].concat(sizes.slice(1).map(s => rs(s[0], s[1]))),
    expect: (r) => expectTexts.forEach((t, i) => must(titleText(r, i) === t,
      id + ' step ' + i + ': ' + titleText(r, i) + ', expected ' + t)),
  };
}

const LEGEND_BASE = {
  animation: false,
  color: ['#aa0000', '#00aa00', '#0000aa'],
  legend: { textStyle: { fontSize: 12 } },
  grid: { left: 60, right: 40, top: 50, bottom: 50 },
  xAxis: { type: 'category', data: CAT },
  yAxis: { type: 'value' },
  series: [
    { type: 'bar', name: 'A', data: [1, 2, 3, 4] },
    { type: 'bar', name: 'B', data: [4, 3, 2, 1] },
  ],
};
const LEGEND_MEDIA = [
  { query: { maxWidth: 500 }, option: {
    legend: { orient: 'vertical', right: 0, top: 'middle' },
    grid: { right: 100 },
    series: [{ barWidth: 10 }, { barWidth: 6 }],
  } },
  { query: { minWidth: 501, maxWidth: 800 }, option: {
    legend: { orient: 'horizontal', left: 'center', bottom: 0, top: null },
    grid: { right: 40, bottom: 60 },
  } },
  { query: { minWidth: 801 }, option: {
    legend: { left: 0, top: 0 },
    grid: { left: 120 },
    series: [{ barWidth: 30 }],
  } },
];
const TREE = {
  animation: false,
  series: [{ type: 'tree', initialTreeDepth: 1,
    data: [{ name: 'r', children: [{ name: 'a', children: [{ name: 'a1' }] }, { name: 'b', children: [{ name: 'b1' }] }] }] }],
};

const CASES = [
  // ---- each key at its boundary: >= and <= are inclusive ----
  keyCase('minWidth', { minWidth: 600 }, [[600, 400], [599, 400], [600, 400], [601, 400]], ['M', 'D', 'M', 'M']),
  keyCase('maxWidth', { maxWidth: 600 }, [[600, 400], [601, 400], [600, 400], [599, 400]], ['M', 'D', 'M', 'M']),
  keyCase('minHeight', { minHeight: 400 }, [[600, 400], [600, 399], [600, 400], [600, 401]], ['M', 'D', 'M', 'M']),
  keyCase('maxHeight', { maxHeight: 400 }, [[600, 400], [600, 401], [600, 400], [600, 399]], ['M', 'D', 'M', 'M']),
  keyCase('minAspectRatio', { minAspectRatio: 1.5 }, [[600, 400], [599, 400], [600, 400], [601, 400]], ['M', 'D', 'M', 'M']),
  keyCase('maxAspectRatio', { maxAspectRatio: 1.5 }, [[600, 400], [601, 400], [600, 400], [599, 400]], ['M', 'D', 'M', 'M']),
  // 7/3 is not exact: width / height as a double against the same double
  keyCase('aspect-inexact', { minAspectRatio: 700 / 300, maxAspectRatio: 700 / 300 },
    [[700, 300], [701, 300], [700, 300], [700, 301]], ['M', 'D', 'M', 'D']),
  keyCase('aspect-min-max', { minAspectRatio: 1, maxAspectRatio: 2 },
    [[600, 400], [400, 401], [400, 400], [800, 400], [801, 400]], ['M', 'D', 'M', 'M', 'D']),
  keyCase('two-keys-and', { minWidth: 500, maxHeight: 300 },
    [[600, 300], [600, 301], [499, 300], [500, 300]], ['M', 'D', 'D', 'M']),
  // ---- what the regular expression and the comparison make of a key ----
  keyCase('plain-width-ignored', { width: 500 }, [[600, 400], [500, 400]], ['M', 'M']),
  keyCase('plain-aspect-ignored', { aspectRatio: 9 }, [[600, 400]], ['M']),
  keyCase('capital-min-ignored', { MinWidth: 9000 }, [[600, 400]], ['M']),
  keyCase('upper-attr', { minWIDTH: 601 }, [[600, 400], [601, 400]], ['D', 'M']),
  keyCase('unknown-attr', { minFoo: 1 }, [[600, 400]], ['D']),
  keyCase('min-alone', { min: 1, max: 1 }, [[600, 400]], ['M']),
  keyCase('string-value', { maxWidth: '600' }, [[600, 400], [601, 400]], ['M', 'D']),
  keyCase('string-hex', { maxWidth: '0x258' }, [[600, 400], [601, 400]], ['M', 'D']),
  keyCase('string-junk', { maxWidth: '600px' }, [[600, 400]], ['D']),
  keyCase('null-value', { maxWidth: null }, [[600, 400]], ['D']),
  keyCase('null-min', { minHeight: null }, [[600, 400]], ['M']),
  keyCase('true-value', { maxAspectRatio: true }, [[600, 400], [400, 400]], ['D', 'M']),
  keyCase('array-value', { maxWidth: [600] }, [[600, 400], [601, 400]], ['M', 'D']),
  keyCase('array-nested', { maxWidth: [['600']] }, [[600, 400]], ['M']),
  keyCase('array-two', { maxWidth: [1, 2] }, [[600, 400]], ['D']),
  keyCase('array-empty', { minWidth: [] }, [[600, 400]], ['M']),
  keyCase('object-value', { minWidth: {} }, [[600, 400]], ['D']),
  keyCase('empty-query', {}, [[600, 400]], ['M']),
  keyCase('number-query', 1, [[600, 400]], ['M']),
  keyCase('true-query', true, [[600, 400]], ['M']),
  keyCase('empty-array-query', [], [[600, 400]], ['M']),
  keyCase('length-zero-query', { length: 0, maxWidth: 1 }, [[600, 400]], ['M']),
  keyCase('newline-key', { 'max\nWidth': 1 }, [[600, 400]], ['M']),
  { id: 'falsy-query-is-default', steps: [
    set(bars({ media: [{ query: 0, option: TT('Z') }, { query: { maxWidth: 1 }, option: TT('M') }, DEF('D')] })),
  ], expect: (r) => must(titleText(r, 0) === 'Z' && r.steps[0].indices.join() === '-1', 'falsy-query-is-default') },
  { id: 'first-default-wins', steps: [
    set(bars({ media: [DEF('D1'), { query: { maxWidth: 1 }, option: TT('M') }, DEF('D2')] })),
  ], expect: (r) => must(titleText(r, 0) === 'D1', 'first-default-wins') },
  { id: 'unit-without-option', steps: [
    set(bars({ media: [{ query: { minWidth: 1 } }, { query: { minWidth: 1 }, option: null }, null, 5,
      { query: { minWidth: 1 }, option: TT('M') }] })),
  ], expect: (r) => must(r.steps[0].indices.join() === '0' && titleText(r, 0) === 'M', 'unit-without-option') },
  // ---- several units: merged in the list's order, the later wins ----
  { id: 'multi-in-order', steps: [
    set(bars({ grid: { left: 30 }, media: [
      { query: { minWidth: 100 }, option: { grid: { left: 10, top: 11 }, title: T({ text: 'one' }) } },
      { query: { minWidth: 9000 }, option: { grid: { left: 99 } } },
      { query: { maxHeight: 500 }, option: { grid: { left: 20 }, title: T({ text: 'three', left: 5 }) } },
    ] })),
    rs(600, 600),
    rs(600, 400),
  ], expect: (r) => {
    must(r.steps[0].indices.join() === '0,2' && r.steps[0].tree.grid[0].left === 20, 'multi-in-order: the later wins');
    must(r.steps[1].indices.join() === '0' && r.steps[1].merged === 1 && r.steps[1].tree.grid[0].left === 10,
      'multi-in-order: the one left is merged again');
    must(r.steps[2].merged === 2, 'multi-in-order: both again');
  } },
  { id: 'same-set-not-merged', steps: [
    set(bars({ media: [UNIT({ minWidth: 100 }, 'M')] })),
    set({ title: T({ text: 'merged' }) }),
    rs(700, 400),
    rs(50, 400),
    rs(800, 400),
  ], expect: (r) => {
    must(titleText(r, 1) === 'M', 'same-set-not-merged: a merge re-merges what applies');
    must(r.steps[2].merged === 0, 'same-set-not-merged: a resize to the same set merges nothing');
    must(r.steps[3].merged === 0 && r.steps[3].indices.length === 0 && titleText(r, 3) === 'M',
      'same-set-not-merged: none applies, nothing undone');
    must(r.steps[4].merged === 1, 'same-set-not-merged: back, merged again');
  } },
  { id: 'same-set-keeps-state', steps: [
    set(Object.assign({}, TREE, { media: [{ query: { minWidth: 500 }, option: { title: T({ text: 'wide' }) } }] })),
    act({ type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 2 }),
    rs(700, 400),
    rs(400, 400),
    rs(600, 400),
  ], expect: (r) => {
    must(r.steps[2].merged === 0 && r.steps[2].out.series[0].expanded[2] === true,
      'same-set-keeps-state: the same set merges nothing, the expand state stays');
    must(r.steps[3].out.series[0].expanded[2] === true, 'same-set-keeps-state: none applies, nothing merged');
    must(r.steps[4].merged === 1 && r.steps[4].out.series[0].expanded[2] === false,
      'same-set-keeps-state: merged again, the data rebuilt');
  } },
  // a legend a unit makes, and the next unit of the same setOption merging
  // into it: `selected` made at its init sits before the second unit's keys
  { id: 'legend-made-by-media', steps: [
    set(bars({ series: [{ type: 'bar', name: 'A', data: [1, 2, 3, 4] }], media: [
      { query: { minWidth: 1 }, option: { legend: { top: 5, textStyle: { fontSize: 12 } } } },
      { query: { minWidth: 1 }, option: { legend: { itemGap: 20 } } },
    ] })),
  ], expect: (r) => {
    const k = Object.keys(r.steps[0].tree.legend[0]);
    must(k.indexOf('selected') < k.indexOf('itemGap'), 'legend-made-by-media: ' + k.join());
  } },
  // ---- the default ----
  { id: 'default-when-none', steps: [
    set(bars({ grid: { left: 30 }, media: [
      { query: { maxWidth: 500 }, option: { grid: { left: 5 } } },
      { option: { grid: { left: 77 } } },
    ] })),
    rs(400, 400),
    rs(600, 400),
    rs(700, 400),
    rs(500, 400),
  ], expect: (r) => {
    must(r.steps[0].tree.grid[0].left === 77 && r.steps[0].indices.join() === '-1', 'default-when-none: default');
    must(r.steps[1].tree.grid[0].left === 5, 'default-when-none: the unit');
    must(r.steps[2].tree.grid[0].left === 77, 'default-when-none: the default again');
    must(r.steps[3].merged === 0, 'default-when-none: the default again is the same set');
  } },
  { id: 'default-visits-no-series', steps: [
    set(Object.assign({}, TREE, { media: [
      { query: { maxWidth: 500 }, option: { title: T({ text: 'narrow' }) } },
      { option: { title: T({ text: 'wide' }) } },
    ] })),
    act({ type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 2 }),
    rs(400, 400),
    act({ type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 2 }),
    rs(600, 400),
  ], expect: (r) => {
    must(r.steps[1].out.series[0].expanded[2] === true, 'default-visits-no-series: expanded');
    must(r.steps[2].out.series[0].expanded[2] === false && r.steps[2].seriesMerged === 1,
      'default-visits-no-series: a listed unit visits the series');
    must(r.steps[3].out.series[0].expanded[2] === true, 'default-visits-no-series: expanded again');
    must(r.steps[4].out.series[0].expanded[2] === true && r.steps[4].seriesMerged === 0,
      'default-visits-no-series: the default does not');
  } },
  // ---- resizes back and forth: legend, grid and series layout ----
  { id: 'layout-breakpoints', w: 900, h: 400, steps: [
    set(Object.assign({}, LEGEND_BASE, { media: LEGEND_MEDIA })),
    rs(700, 400),
    rs(400, 400),
    rs(700, 400),
    rs(1000, 400),
    rs(500, 400),
    rs(501, 400),
    rs(800, 400),
  ], expect: (r) => {
    const ix = r.steps.map(s => s.indices.join());
    must(ix.join('|') === '2|1|0|1|2|0|1|1', 'layout-breakpoints: ' + ix.join('|'));
    must(r.steps[7].merged === 0, 'layout-breakpoints: same set');
  } },
  { id: 'baseoption-form', w: 400, h: 400, steps: [
    set({ baseOption: LEGEND_BASE, media: LEGEND_MEDIA, title: T({ text: 'ignored' }) }),
    rs(900, 400),
    rs(600, 400),
  ], expect: (r) => must(r.steps[0].tree.title === undefined && r.steps[0].indices.join() === '0', 'baseoption-form') },
  // ---- a later merge ----
  { id: 'merge-remerges-media', steps: [
    set(bars({ media: [{ query: { maxWidth: 700 }, option: { grid: { left: 11 } } }] })),
    set({ grid: { left: 99, top: 33 } }),
    set({ series: [{ data: [4, 4, 4, 4] }] }),
  ], expect: (r) => {
    must(r.steps[1].tree.grid[0].left === 11 && r.steps[1].tree.grid[0].top === 33,
      'merge-remerges-media: the unit over the merge');
  } },
  { id: 'merge-new-media', steps: [
    set(bars({ media: [{ query: { maxWidth: 700 }, option: { grid: { left: 11 } } }, DEF('D')] })),
    set({ media: [{ query: { minWidth: 650 }, option: { grid: { top: 22 } } }] }),
    rs(700, 400),
    set({ media: [{ option: TT('D2') }] }),
    rs(600, 400),
    set({ media: [] }),
    rs(400, 400),
    rs(800, 400),
  ], expect: (r) => {
    must(titleText(r, 1) === 'D' && r.steps[1].indices.join() === '-1', 'merge-new-media: the old default kept');
    must(r.steps[2].tree.grid[0].top === 22, 'merge-new-media: the new list');
    must(r.steps[3].merged === 1 && titleText(r, 3) === 'D', 'merge-new-media: a default alone keeps the list');
    must(titleText(r, 4) === 'D2', 'merge-new-media: the new default');
    must(r.steps[5].merged === 1 && r.steps[6].merged === 0, 'merge-new-media: media [] keeps both');
    must(r.steps[7].indices.join() === '0', 'merge-new-media: the list is still there');
  } },
  { id: 'merge-baseoption', steps: [
    set(bars({ media: [{ query: { maxWidth: 700 }, option: { grid: { left: 11 } } }] })),
    set({ baseOption: { grid: { left: 50, bottom: 20 } }, media: [{ query: { minWidth: 1 }, option: TT('B') }] }),
  ], expect: (r) => must(titleText(r, 1) === 'B' && r.steps[1].tree.grid[0].left === 50, 'merge-baseoption') },
  { id: 'replacemerge-reaches-media', steps: [
    set(bars({ series: [{ id: 'a', type: 'bar', data: [1, 2, 3, 4] }, { id: 'b', type: 'bar', data: [2, 2, 2, 2] }],
      media: [{ query: { minWidth: 1 }, option: { grid: { left: 40 } } }] })),
    setO({ series: [{ id: 'b', data: [3, 3, 3, 3] }] }, { replaceMerge: ['series'] }),
  ] },
  { id: 'replacemerge-first-media', steps: [
    setO(bars({ series: [{ id: 'a', type: 'bar', data: [1, 2, 3, 4] }],
      media: [{ query: { minWidth: 1 }, option: { series: [{ id: 'a', data: [5, 5, 5, 5] }] } }] }), { replaceMerge: ['series'] }),
  ] },
  // ---- notMerge ----
  { id: 'notmerge-forgets', steps: [
    set(bars({ media: [{ query: { maxWidth: 500 }, option: { grid: { left: 5 } } }, DEF('D')] })),
    set(bars({ grid: { left: 30 } }), true),
    rs(400, 400),
    set(bars({ media: [{ query: { maxWidth: 500 }, option: { grid: { left: 6 } } }] }), true),
    rs(600, 400),
    rs(300, 400),
  ], expect: (r) => {
    must(r.steps[2].indices.length === 0 && r.steps[2].tree.grid[0].left === 30, 'notmerge-forgets: no media');
    must(r.steps[3].tree.grid[0].left === 6, 'notmerge-forgets: the new media');
    must(r.steps[5].merged === 1, 'notmerge-forgets: back');
  } },
  // ---- the root option's own `media` and `options` ----
  { id: 'media-not-array', steps: [
    set(bars({ media: { query: { minWidth: 1 }, option: TT('M') } })),
  ], expect: (r) => must(r.steps[0].tree.media === undefined && r.steps[0].tree.title === undefined, 'media-not-array') },
  { id: 'media-falsy-kept', steps: [
    set(bars({ media: 0 })),
  ], expect: (r) => must(r.steps[0].tree.media === 0, 'media-falsy-kept') },
  { id: 'options-dropped', steps: [
    set(bars({ options: [TT('X')], media: [UNIT({ minWidth: 1 }, 'M')] })),
  ], expect: (r) => must(r.steps[0].tree.options === undefined && titleText(r, 0) === 'M', 'options-dropped') },
  { id: 'unit-adds-series', steps: [
    set(bars({ legend: {}, series: [{ type: 'bar', name: 'A', data: [1, 2, 3, 4] }],
      media: [{ query: { maxWidth: 500 }, option: { series: [{}, { type: 'line', name: 'L', data: [4, 1, 4, 1] }] } }] })),
    rs(500, 400),
    rs(600, 400),
  ], expect: (r) => must(r.steps[1].models.series.length === 2 && r.steps[2].models.series.length === 2, 'unit-adds-series') },
  // ---- a media unit at another size than 600 x 400 at the start ----
  { id: 'start-small', w: 320, h: 480, steps: [
    set(Object.assign({}, LEGEND_BASE, { media: LEGEND_MEDIA })),
    rs(1024, 480),
  ] },
];

// guard 3: the query table, the manager's own answer
const QUERY_TABLE = [
  [{ minWidth: 600 }, 600, 400], [{ minWidth: 600 }, 599.5, 400], [{ maxWidth: 600 }, 600.25, 400],
  [{ minHeight: 400 }, 600, 400], [{ maxHeight: 399.75 }, 600, 400], [{ minAspectRatio: 1.5 }, 600, 400],
  [{ maxAspectRatio: 1.4999999999999998 }, 600, 400], [{ minAspectRatio: 1 }, 0, 0],
  [{ maxAspectRatio: 1 }, 0, 0], [{ minAspectRatio: 1e308 }, 600, 0], [{ maxAspectRatio: 1e308 }, 600, 0],
  [{ maxWidth: 'Infinity' }, 600, 400], [{ minWidth: '-Infinity' }, 600, 400], [{ minWidth: ' 600 ' }, 600, 400],
  [{ minWidth: '' }, 600, 400], [{ minWidth: '1e3' }, 600, 400], [{ maxWidth: '0b1' }, 600, 400],
  [{ maxwidth: 1 }, 600, 400], [{ minHeIght: 400 }, 600, 400], [{ minconstructor: 1 }, 600, 400],
  [{ maxWidth: false }, 0, 400], [{ maxWidth: [null] }, 0, 400], [{ maxWidth: [true] }, 0, 400],
  // an unknown attribute is undefined -- not nought: max of it fails too
  [{ maxFoo: 1 }, 600, 400], [{ minconstructor: -1 }, 600, 400],
];
function queryTable() {
  const out = [];
  const chart = newChart(10, 10);
  try {
    chart.setOption({ animation: false });
    const om = chart.getModel()._optionManager;
    for (const [q, w, h] of QUERY_TABLE) {
      // the manager's own getMediaOption, at the size asked
      const api = om._api;
      const saved = [api.getWidth, api.getHeight];
      api.getWidth = () => w;
      api.getHeight = () => h;
      om._mediaList = [{ query: q, option: {} }];
      om._mediaDefault = null;
      om._currentMediaIndices = [];
      const r = OM_PROTO.getMediaOption.call(om, chart.getModel());
      api.getWidth = saved[0];
      api.getHeight = saved[1];
      const got = r.length === 1;
      must(got === applies(q, w, h), 'query table: ' + JSON.stringify(q) + ' at ' + w + ' x ' + h);
      out.push({ query: S(q), w, h, applies: got });
    }
  } finally {
    chart.dispose();
  }
  return out;
}

function generate() {
  const recs = [];
  for (const c of CASES) {
    const r = runCase(c);
    if (c.expect) c.expect(r);
    recs.push({ id: c.id, w: c.w || 600, h: c.h || 400, steps: r.steps.map(s => ({
      kind: s.step.kind, notMerge: s.step.notMerge, opts: s.step.opts, text: s.step.text,
      payload: s.step.payload, w: s.w, h: s.h, indices: s.indices, merged: s.merged,
      tree: s.tree, models: s.models, out: s.out, views: s.views })) });
  }
  const ids = new Set(CASES.map(c => c.id));
  for (const need of ['minWidth', 'maxWidth', 'minHeight', 'maxHeight', 'minAspectRatio', 'maxAspectRatio',
    'multi-in-order', 'default-when-none', 'layout-breakpoints', 'merge-remerges-media', 'notmerge-forgets'])
    must(ids.has(need), 'missing case ' + need);
  const queries = queryTable();
  return JSON.stringify({
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg)',
    queries,
    cases: recs,
  }, null, 1);
}

try {
  const json1 = generate();
  if (!process.env.ORACLE_ONCE) {
    const json2 = generate();
    must(json1 === json2, 'two generations differ');
  }
  fs.writeFileSync(OUT, json1);
  const n = CASES.reduce((a, c) => a + c.steps.length, 0);
  console.log(CASES.length + ' cases, ' + n + ' steps, ' + QUERY_TABLE.length + ' queries -> ' + OUT);
} catch (e) {
  console.log('FAILED: ' + (e instanceof OracleError ? e.message : e.stack));
  process.exit(1);
}
process.exit(0);
