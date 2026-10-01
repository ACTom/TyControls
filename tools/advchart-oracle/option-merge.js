/*
Upstream's own answers for a MERGE setOption (A10 / MG1): how a second, third
... setOption without notMerge maps its components and series onto the
models that exist (by id, then by name, then by index, appended when nothing
matches), how it deep-merges them (objects merged, arrays and nulls written
as they are, a type change rebuilt from the new option alone), the ids and
names the models carry, and the chart those merged options draw. The rules
are in the A10 brief (wf-a10/merge.md; Global.ts _mergeOption,
util/model.ts mappingToExists / makeIdAndName, zrender merge, layout.ts
mergeLayoutParam).

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node, SVG renderer with ssr, 600 x 400, `animation: false`
in the first option of every case, process.env.TZ = 'UTC'.

  node tools/advchart-oracle/option-merge.js

writes tests/fixtures/advchart-option-merge.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
The two layers of "the merged option". upstream's getOption() is the MODELS'
options: theme and defaults merged in, and what the models write (legend
`selected`, dataZoom's calculated window, emphasis.label.show ...). The port
applies defaults when it reads, so its tree holds the RAW merge: what the
author wrote, merged by upstream's rules. That layer is recorded from hooks:
`init` and `mergeOption` on every prototype of every registered component
class's chain are wrapped -- the outermost call keeps a clone of the option as it arrives,
before any default (`__raw`), and every later mergeOption is merged into it
with the dist's own zrUtil.merge. Root keys that are no component are merged
the way _mergeOption merges them (null ignored, clone when absent, else
zrUtil.merge on the root value -- arrays BY INDEX). Then the model writes
the port also keeps in its tree are laid over it, read from the model:
  - a legend's `selected` (always: the port makes it when it loads);
  - a box-layout model's left/right/width or top/bottom/height when a merge
    wrote any key of that direction (mergeLayoutParam writes all three;
    `undefined` is recorded as null);
(dataset `transform` is merged the way disableTransformOptionMerge makes
zrUtil.merge do it: replaced whole), and a dataZoom's start / end /
startValue / endValue are NOT compared (the
port keeps an action's window outside its tree; the window is compared as an
outcome instead).

Per case: {id, steps[], compare[]}; steps:
  {kind: 'set', notMerge, text}  chart.setOption(JSON.parse(text), notMerge)
  {kind: 'set', notMerge, opts, text}
                                 chart.setOption(JSON.parse(text),
                                 JSON.parse(opts)) -- the options form (A11:
                                 replaceMerge, lazyUpdate, silent, notMerge);
                                 a lazy step runs the frame it waits for
                                 (chart._onframe) before it is recorded --
                                 unless it says noFrame: then nothing is
                                 drawn and only tree, models and the events
                                 are recorded (out and views null), and the
                                 next step's update is the one it waits for
  {kind: 'action', payload, frame}
                                 frame: a frame runs after the dispatch
  {kind: 'action', payload}      chart.dispatchAction(payload)
Per step (after it):
  tree    the raw merge, as the port's GetOptionJson must give it: every
          component main type written (non-null) since the last notMerge, as
          an array over componentIndex (null in a hole, trailing nulls
          trimmed); the other root keys merged; NaN never occurs
  models  {mainType: [null | {id, name, sub}]} for series and every main type
          in tree: the model's id (NULs kept, '\0' + name + '\0' + n), name,
          subType ('' for none)
  out     {series: [null | {count, shown, fill, sel, bars?, barFills?,
            expanded?, centre?, zoom?}],
           grids: [{x, y, w, h}], titles: [null | [x, y, w, h]],
           dz: [[start, end]]}
          count = getData().count(); shown = not filtered by the legend; fill
          = the series' style visual fill; sel = getSelectedDataIndices()
          (raw, ascending); expanded = a tree's isExpand per data index;
          bars = every bar element's shape
          [x, y, width, height] as drawn (null where the item has none);
          centre / zoom = a graph's option.center / option.zoom (what a roam
          writes back); grids = coordinateSystem.getRect(); titles = the
          background rect of each title (group position + shape); dz =
          getPercentRange() (a third entry: the x axis it zooms, where that is
          not xAxis 0); barFills = each bar's own style fill
  views   [view number per series]: the n-th distinct series view object
          seen in this case -- the same number across steps is the same view
          (an update), a new number a new view (an entrance)
  updNow  the `updated` events the call itself triggered (0 for a lazy or a
          silent setOption)
  upd     the `updated` events of the whole step, the lazy frame included
  sel     an action step: the `selected` of every selectchanged it fired
  (out.legend: per legend slot the names it lists -- getData() over the
          available names; null in a hole)
A main type named in a merge's replaceMerge is written (as `[]` when the
option leaves it out); a notMerge or the first setOption ignores
replaceMerge, as initBase does.
Also: mainTypes (getAllClassMainTypes, the component main types), deps
(main type -> the main types it depends on), subTypes (main types whose
classes are per subType, with their subtypes).

Cross-check (any failure: nothing is written, exit 1):
  1. every leaf of every recorded tree equals upstream's getOption() at the
     same path (undefined there == null here), so the raw layer is a subset
     of what upstream holds;
  2. explicit expectations read off the source, per case (ids kept across a
     rename, a type change keeps the id and drops the old option, a hole
     filled first, root arrays merged by index ...);
  3. coverage: the cases that map by id, by name, by index, append, replace
     a model and keep a hole are present, and at least one merge wrote a
     box back;
  4. the whole fixture is generated twice (byte-identical).
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-option-merge.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const zr = echarts.zrUtil;
const CM = echarts.ComponentModel;
const MAIN_TYPES = CM.getAllClassMainTypes().slice();
const IS_CMPT = new Set(MAIN_TYPES);

// ---------- the hooks ----------
let HOOK_LOG = null;   // per setOption: [{model, kind, option}]
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
        // dataset/install.ts disableTransformOptionMerge: `transform` is
        // marked primitive, so zrUtil.merge replaces it whole
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
      // a legend's init makes `selected` (option.selected ||= {}) after the
      // keys it was given: that is where it sits in the raw layer too
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
// every prototype on the chain of every registered class: an abstract base
// (DataZoomModel, VisualMapModel ...) owns the init its subclasses run
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

const DEPS = {};
const SUBTYPES = {};
for (const mt of MAIN_TYPES) {
  const s = new Set();
  for (const C of CM.getClassesByMainType(mt)) (C.dependencies || []).forEach(d => s.add(d));
  DEPS[mt] = [...s].sort();
  if (CM.hasSubTypes(mt)) {
    SUBTYPES[mt] = CM.getClassesByMainType(mt).map(C => C.type.slice(mt.length + 1)).filter(t => t && !t.startsWith('__')).sort();
  }
}

const HV = [['width', 'left', 'right'], ['height', 'top', 'bottom']];
function layoutModeOf(model) {
  return model.layoutMode || model.constructor.layoutMode;
}

// ---------- one case ----------
function newChart() {
  return echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
}

function runCase(c) {
  const chart = newChart();
  const steps = [];
  let rootRaw = {};
  let written = new Set();
  const viewIds = new Map();
  let viewNext = 0;
  const caseStats = { box: 0 };
  let upd = 0;
  chart.on('updated', () => { upd++; });
  let selLog = [];
  chart.on('selectchanged', (e) => { selLog.push(zr.clone(e.selected)); });
  try {
    for (const st of c.steps) {
      const rec = { step: st };
      const updBefore = upd;
      selLog = [];
      if (st.kind === 'set') {
        const opt = JSON.parse(st.text);
        const opts = st.opts ? JSON.parse(st.opts) : null;
        const notMerge = !!st.notMerge || !!(opts && opts.notMerge);
        const fresh = notMerge || steps.length === 0;
        if (fresh) {
          rootRaw = {};
          written = new Set();
        }
        // replaceMerge: a merge visits the named types as `[]` when absent
        if (!fresh && opts && opts.replaceMerge != null) {
          for (const t of zr.isArray(opts.replaceMerge) ? opts.replaceMerge : [opts.replaceMerge]) {
            if (IS_CMPT.has(t)) written.add(t);
          }
        }
        // the root keys that are no component, as _mergeOption merges them
        for (const k of Object.keys(opt)) {
          const v = opt[k];
          if (v == null) continue;
          if (IS_CMPT.has(k)) {
            written.add(k);
            continue;
          }
          rootRaw[k] = rootRaw[k] == null ? zr.clone(v) : zr.merge(rootRaw[k], zr.clone(v), true);
        }
        HOOK_LOG = [];
        if (opts) chart.setOption(opt, opts);
        else chart.setOption(opt, !!st.notMerge);
        rec.updNow = upd - updBefore;
        // the frame a lazy setOption waits for
        if (opts && opts.lazyUpdate && !st.noFrame) chart._onframe();
        const log = HOOK_LOG;
        HOOK_LOG = null;
        // a box merge: mergeLayoutParam wrote all three keys of a direction
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
            caseStats.box++;
          }
        }
      } else {
        chart.dispatchAction(st.payload);
        rec.updNow = upd - updBefore;
        rec.sel = selLog.slice();
        if (st.frame) chart._onframe();
      }
      rec.upd = upd - updBefore;
      if (st.noFrame) {
        // nothing drawn: the update waits for the next step
        rec.tree = treeOf(chart, rootRaw, written);
        rec.models = modelsOf(chart, written);
        rec.out = null;
        rec.views = null;
        checkSubset(rec.tree, chart.getOption(), c.id + ' step ' + steps.length);
        steps.push(rec);
        continue;
      }
      chart.renderToSVGString();
      rec.tree = treeOf(chart, rootRaw, written);
      rec.models = modelsOf(chart, written);
      rec.out = outOf(chart);
      rec.views = (chart.getModel().getSeries ? seriesSlots(chart) : []).map(m => {
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
  return { steps, stats: caseStats };
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
    const style = data.getVisual('style');
    o.fill = style && typeof style.fill === 'string' ? style.fill : null;
    if (m.subType === 'bar') {
      o.bars = [];
      o.barFills = [];
      for (let i = 0; i < data.count(); i++) {
        const el = data.getItemGraphicEl(i);
        o.bars.push(el && el.shape ? [el.shape.x, el.shape.y, el.shape.width, el.shape.height] : null);
        // the bar's own fill: a visualMap colours the items, not the series
        o.barFills.push(el && el.style && typeof el.style.fill === 'string' ? el.style.fill : null);
      }
    }
    o.sel = (m.getSelectedDataIndices() || []).slice().sort((a, b) => a - b);
    if (m.subType === 'tree') {
      o.expanded = [];
      for (let i = 0; i < data.count(); i++) o.expanded.push(!!data.tree.getNodeByDataIndex(i).isExpand);
    }
    if (m.subType === 'graph') {
      o.centre = m.option.center === undefined ? null : zr.clone(m.option.center);
      o.zoom = m.option.zoom === undefined ? null : m.option.zoom;
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
  const dz = (slotsOf(chart, 'dataZoom') || []).map(z => {
    // a dataZoom whose axes are gone has no window
    const r = z ? z.getPercentRange() : null;
    if (!r) return null;
    // the x axis it zooms first, where that is not xAxis 0
    let xi = 0;
    let found = false;
    z.eachTargetAxis((dim, idx) => { if (!found && dim === 'x') { xi = idx; found = true; } });
    return xi === 0 ? r : [r[0], r[1], xi];
  });
  const legend = (slotsOf(chart, 'legend') || []).map(l => l
    ? l.getData().map(d => d.get('name')).filter(n => l._availableNames.indexOf(n) >= 0)
    : null);
  return { series, grids, titles, dz, legend };
}

// ---------- guard 1: the raw layer is a subset of getOption ----------
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
        sub(o, b[i], where + ': ' + k + '[' + i + ']', k === 'dataZoom');
      });
    } else {
      sub(tree[k], full[k], where + ': ' + k, false);
    }
  }
}
function sub(a, b, where, dz) {
  if (a === null) {
    must(b === null || b === undefined, where + ' is null here, ' + JSON.stringify(b) + ' upstream');
    return;
  }
  if (Array.isArray(a)) {
    must(Array.isArray(b) && b.length === a.length, where + ': arrays differ in length');
    a.forEach((v, i) => sub(v, b[i], where + '[' + i + ']', false));
    return;
  }
  if (typeof a === 'object') {
    must(b && typeof b === 'object', where + ': an object here, ' + JSON.stringify(b) + ' upstream');
    for (const k of Object.keys(a)) {
      if (dz && ['start', 'end', 'startValue', 'endValue'].includes(k)) continue;
      sub(a[k], b[k], where + '.' + k, false);
    }
    return;
  }
  must(Object.is(a, b), where + ': ' + JSON.stringify(a) + ' here, ' + JSON.stringify(b) + ' upstream');
}

// ---------- the cases ----------
const CAT = ['Mon', 'Tue', 'Wed', 'Thu'];
function bars(extra) {
  return Object.assign({
    animation: false,
    xAxis: { type: 'category', data: CAT },
    yAxis: { type: 'value' },
  }, extra);
}
const S = (o) => JSON.stringify(o);
// a title's fonts written out: the port's theme picks its own, upstream's
// defaults are 18 px bold over 12 px
const TS = { textStyle: { fontSize: 18, fontWeight: 'bold' }, subtextStyle: { fontSize: 12 } };
const T = (o) => Object.assign({}, o, TS);
const set = (o, notMerge) => ({ kind: 'set', notMerge: !!notMerge, text: S(o) });
// the options form: setOption(option, opts)
const setO = (o, opts) => ({ kind: 'set', notMerge: !!opts.notMerge, opts: S(opts), text: S(o) });
const RM = (types) => ({ replaceMerge: types });
// a lazy setOption whose frame does not come before the next step
const setLazy = (o, opts) => Object.assign(setO(o, Object.assign({ lazyUpdate: true }, opts)), { noFrame: true });
const actF = (p) => ({ kind: 'action', payload: p, frame: true });
const act = (p) => ({ kind: 'action', payload: p });
const LEGEND3 = bars({
  legend: {},
  series: [
    { type: 'bar', name: 'A', data: [1, 2, 3, 4] },
    { type: 'bar', name: 'B', data: [4, 3, 2, 1] },
    { type: 'bar', name: 'C', data: [2, 2, 2, 2] },
  ],
});
// LEGEND3 with ids written, and a palette: the port's theme has its own
const LEGEND_ID3 = bars({
  color: ['#aa0000', '#00aa00', '#0000aa', '#aaaa00', '#00aaaa'],
  legend: {},
  series: [
    { id: 'a', type: 'bar', name: 'A', data: [1, 2, 3, 4] },
    { id: 'b', type: 'bar', name: 'B', data: [4, 3, 2, 1] },
    { id: 'c', type: 'bar', name: 'C', data: [2, 2, 2, 2] },
  ],
});
const GRAPH = {
  animation: false,
  series: [{
    type: 'graph', layout: 'none', roam: true,
    data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 50 }, { name: 'c', x: 40, y: 120 }],
    links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }],
  }],
};
const DZ = bars({
  xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'] },
  dataZoom: [{ type: 'inside' }],
  series: [{ type: 'bar', data: [5, 3, 8, 1, 9, 2, 7, 4, 6, 10] }],
});

const CASES = [
  // ---- series ----
  { id: 'series-by-index', steps: [
    set(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4] }, { type: 'bar', data: [2, 3, 4, 5] }] })),
    set({ series: [{ data: [9, 8, 7, 6] }] }),
  ], expect: (r) => {
    const m = r.steps[1].models.series;
    must(m.length === 2 && m[0].id === '\0series\u00000\u00000', 'series-by-index: ids');
  } },
  { id: 'series-append', steps: [
    set(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ series: [{}, { type: 'bar', name: 'N', data: [4, 4, 4, 4] }] }),
    set({ series: [{}, {}, { type: 'bar', data: [1, 1, 1, 1] }] }),
  ], expect: (r) => must(r.steps[2].models.series.length === 3, 'series-append: three') },
  { id: 'series-by-name', steps: [
    set(bars({ series: [{ type: 'bar', name: 'A', data: [1, 2, 3, 4] }, { type: 'bar', name: 'B', data: [2, 3, 4, 5] }] })),
    set({ series: [{ name: 'B', data: [7, 7, 7, 7] }] }),
  ], expect: (r) => must(r.steps[1].tree.series[1].data[0] === 7 && r.steps[1].tree.series[0].data[0] === 1, 'series-by-name') },
  { id: 'series-by-id', steps: [
    set(bars({ series: [{ type: 'bar', id: 'a', data: [1, 2, 3, 4] }, { type: 'bar', id: 'b', data: [2, 3, 4, 5] }] })),
    set({ series: [{ id: 'b', data: [6, 6, 6, 6] }, { id: 'a', name: 'renamed' }] }),
  ], expect: (r) => must(r.steps[1].models.series[0].name === 'renamed', 'series-by-id') },
  { id: 'series-id-appends', steps: [
    set(bars({ series: [{ type: 'bar', name: 'A', data: [1, 2, 3, 4] }, { type: 'bar', id: 'b', data: [2, 3, 4, 5] }] })),
    set({ series: [{ id: 'c', type: 'bar', data: [3, 3, 3, 3] }] }),
  ], expect: (r) => must(r.steps[1].models.series[2].id === 'c', 'series-id-appends') },
  { id: 'series-id-before-name', steps: [
    set(bars({ series: [{ type: 'bar', id: 'p', name: 'Q', data: [1, 2, 3, 4] }, { type: 'bar', name: 'P', data: [2, 3, 4, 5] }] })),
    set({ series: [{ name: 'Y', data: [6, 6, 6, 6] }, { id: 'p', name: 'P', data: [7, 7, 7, 7] }] }),
  ], expect: (r) => {
    const t = r.steps[1].tree.series;
    must(t[0].data[0] === 7 && t[0].name === 'P' && t[1].data[0] === 6, 'series-id-before-name');
  } },
  { id: 'series-numeric-id', steps: [
    set(bars({ series: [{ type: 'bar', id: 5, data: [1, 2, 3, 4] }, { type: 'bar', data: [2, 3, 4, 5] }] })),
    set({ series: [{ data: [3, 3, 3, 3] }, { id: '5', data: [8, 8, 8, 8] }] }),
  ], expect: (r) => must(r.steps[1].tree.series[0].data[0] === 8 && r.steps[1].tree.series[1].data[0] === 3, 'series-numeric-id') },
  { id: 'series-name-then-index', steps: [
    set(bars({ series: [{ type: 'bar', name: 'A', data: [1, 2, 3, 4] }, { type: 'bar', name: 'B', data: [2, 3, 4, 5] }, { type: 'bar', name: 'C', data: [1, 1, 1, 1] }] })),
    set({ series: [{ name: 'C', data: [5, 5, 5, 5] }, { data: [8, 8, 8, 8] }] }),
  ], expect: (r) => must(r.steps[1].tree.series[0].data[0] === 8 && r.steps[1].tree.series[2].data[0] === 5, 'series-name-then-index') },
  { id: 'series-name-with-id', steps: [
    set(bars({ series: [{ type: 'bar', id: 'x', name: 'A', data: [1, 2, 3, 4] }, { type: 'bar', name: 'A', data: [2, 3, 4, 5] }] })),
    set({ series: [{ name: 'A', data: [6, 6, 6, 6] }] }),
    set({ series: [{ id: 'y', name: 'A', type: 'bar', data: [3, 3, 3, 3] }] }),
  ], expect: (r) => {
    must(r.steps[1].tree.series[0].data[0] === 6, 'series-name-with-id: the first A');
    must(r.steps[2].models.series.length === 3, 'series-name-with-id: an id never matches by name');
  } },
  { id: 'series-rename', steps: [
    set(bars({ series: [{ type: 'bar', name: 'A', data: [1, 2, 3, 4] }] })),
    set({ series: [{ name: 'Z' }] }),
    set({ series: [{ name: 'A', data: [4, 3, 2, 1] }] }),
  ], expect: (r) => {
    must(r.steps[1].models.series[0].id === '\0A\u00000' && r.steps[1].models.series[0].name === 'Z', 'series-rename: id kept');
    must(r.steps[2].models.series.length === 1, 'series-rename: back by index');
  } },
  { id: 'series-dup-names', steps: [
    set(bars({ series: [{ type: 'bar', name: 'A', data: [1, 2, 3, 4] }, { type: 'bar', name: 'A', data: [2, 3, 4, 5] }] })),
    set({ series: [{ name: 'A', data: [7, 7, 7, 7] }, { name: 'A', data: [8, 8, 8, 8] }] }),
  ], expect: (r) => must(r.steps[0].models.series[1].id === '\0A\u00001', 'series-dup-names: ids') },
  { id: 'series-type-change', steps: [
    set(bars({ series: [{ type: 'bar', name: 'S', data: [1, 2, 3, 4], itemStyle: { color: '#123456' } }, { type: 'bar', data: [2, 2, 2, 2] }] })),
    set({ series: [{ type: 'line', data: [4, 3, 2, 1] }] }),
  ], expect: (r) => {
    const t = r.steps[1].tree.series[0];
    must(t.itemStyle === undefined && t.name === undefined, 'series-type-change: the old option is dropped');
    must(r.steps[1].models.series[0].name === 'S' && r.steps[1].models.series[0].id === '\0S\u00000', 'series-type-change: id and name kept');
    must(r.steps[1].views[0] !== r.steps[0].views[0], 'series-type-change: a new view');
  } },
  { id: 'series-same-type-written', steps: [
    set(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4], itemStyle: { color: '#123456' } }] })),
    set({ series: [{ type: 'bar', data: [3, 3, 3, 3] }] }),
  ], expect: (r) => must(r.steps[1].tree.series[0].itemStyle.color === '#123456', 'series-same-type-written') },
  { id: 'series-null-entry', steps: [
    set(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4] }, { type: 'bar', data: [2, 3, 4, 5] }] })),
    set({ series: [null, { data: [9, 9, 9, 9] }] }),
  ], expect: (r) => must(r.steps[1].tree.series[0].data[0] === 9, 'series-null-entry: a null takes no index') },
  { id: 'series-bare-object', steps: [
    set(bars({ series: { type: 'bar', data: [1, 2, 3, 4] } })),
    set({ series: { data: [4, 4, 4, 4], barWidth: 20 } }),
  ] },
  { id: 'series-view-kept-on-rename', steps: [
    set(bars({ series: [{ type: 'bar', name: 'A', data: [1, 2, 3, 4] }] })),
    set({ series: [{ name: 'B', data: [2, 3, 4, 5] }] }),
    set(bars({ series: [{ type: 'bar', name: 'C', data: [2, 3, 4, 5] }] }), true),
  ], expect: (r) => {
    must(r.steps[1].views[0] === r.steps[0].views[0], 'series-view-kept-on-rename: a merge keeps the view');
    must(r.steps[2].views[0] !== r.steps[1].views[0], 'series-view-kept-on-rename: notMerge under a new name does not');
  } },
  // ---- components ----
  { id: 'xaxis-array', steps: [
    set({ animation: false, xAxis: [{ type: 'category', data: CAT }, { type: 'category', data: ['p', 'q'], position: 'top' }],
      yAxis: {}, series: [{ type: 'bar', data: [1, 2, 3, 4] }, { type: 'bar', xAxisIndex: 1, data: [5, 6] }] }),
    set({ xAxis: [{}, { name: 'second', data: ['p', 'q', 'r'] }], series: [{}, { data: [5, 6, 7] }] }),
  ] },
  { id: 'title-object-to-array', steps: [
    set(bars({ title: T({ text: 'Alpha' }), series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ title: [{ text: 'Alpha two' }, T({ text: 'Beta', top: 40 })] }),
  ] },
  { id: 'title-by-id', steps: [
    set(bars({ title: [T({ id: 't1', text: 'One' }), T({ id: 't2', text: 'Two', top: 40 })], series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ title: { id: 't2', subtext: 'two-sub' } }),
  ] },
  { id: 'title-first-seen-holes', steps: [
    set(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ title: [T({ text: 'a' }), null, T({ text: 'c', top: 40 })] }),
    set({ title: [{ subtext: 'a-sub' }] }),
    set({ title: [{}, T({ text: 'filled', top: 80 })] }),
  ], expect: (r) => {
    must(r.steps[1].tree.title[1] === null && r.steps[1].models.title[2].name === 'series\u00002', 'title-first-seen-holes: replaceAll keeps the hole');
    must(r.steps[3].tree.title[1].text === 'filled' && r.steps[3].models.title[1].id === '\0series\u00001\u00000', 'title-first-seen-holes: the hole filled');
  } },
  { id: 'legend-first-written-compacts', steps: [
    set(bars({ series: [{ type: 'bar', name: 'A', data: [1, 2, 3, 4] }] })),
    set({ legend: [{ left: 0 }, null, { top: 30 }] }),
  ], expect: (r) => must(r.steps[1].tree.legend.length === 2, 'legend-first-written-compacts: the legend was visited with the series, so a normalMerge') },
  { id: 'yaxis-type-change', steps: [
    set(bars({ yAxis: { type: 'value', name: 'Y', max: 20 }, series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ yAxis: { type: 'log' } }),
  ], expect: (r) => must(r.steps[1].tree.yAxis[0].name === undefined && r.steps[1].models.yAxis[0].sub === 'log', 'yaxis-type-change') },
  { id: 'xaxis-subtype-kept', steps: [
    set({ animation: false, xAxis: { data: CAT }, yAxis: {}, series: [{ type: 'bar', data: [1, 2, 3, 4] }] }),
    set({ xAxis: { data: ['w', 'x', 'y', 'z'] } }),
  ], expect: (r) => must(r.steps[1].models.xAxis[0].sub === 'category', 'xaxis-subtype-kept') },
  // ---- deep merge, arrays, null ----
  { id: 'deep-object', steps: [
    set(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4], itemStyle: { color: '#336699', borderWidth: 0 }, label: { show: false } }] })),
    set({ series: [{ itemStyle: { borderRadius: 4 }, label: { show: true, position: 'top' } }] }),
  ], expect: (r) => must(r.steps[1].tree.series[0].itemStyle.color === '#336699', 'deep-object') },
  { id: 'array-replace', steps: [
    set(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ xAxis: { data: ['only', 'two'] }, series: [{ data: [9, 3] }] }),
  ], expect: (r) => must(r.steps[1].tree.series[0].data.length === 2, 'array-replace') },
  { id: 'null-writes', steps: [
    set(bars({ title: T({ text: 'T', subtext: 'S' }), series: [{ type: 'bar', data: [1, 2, 3, 4], barWidth: 30 }] })),
    set({ title: { subtext: null }, series: [{ barWidth: null }] }),
  ], expect: (r) => must(r.steps[1].tree.title[0].subtext === null, 'null-writes') },
  { id: 'null-component-ignored', steps: [
    set(bars({ title: T({ text: 'T' }), backgroundColor: '#fafafa', series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ title: null, series: null, backgroundColor: null }),
    set({ title: [] }),
  ], expect: (r) => must(r.steps[1].tree.backgroundColor === '#fafafa', 'null-component-ignored') },
  { id: 'root-keys', steps: [
    set(bars({ color: ['#aa0000', '#00aa00', '#0000aa'], textStyle: { fontSize: 14 },
      series: [{ type: 'bar', data: [1, 2, 3, 4] }, { type: 'bar', data: [2, 3, 4, 5] }, { type: 'bar', data: [3, 4, 5, 6] }] })),
    set({ color: ['#123456'], textStyle: { fontWeight: 'bold' }, animationDuration: 500 }),
  ], compare: ['fill'], expect: (r) => {
    const c = r.steps[1].tree.color;
    must(c.length === 3 && c[0] === '#123456' && c[1] === '#00aa00', 'root-keys: a root array merges by index');
  } },
  // ---- box layout ----
  { id: 'title-box-ignore-size', steps: [
    set(bars({ title: T({ text: 'Boxed', left: 10 }), series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ title: { right: 20 } }),
    set({ title: { left: 'auto' } }),
  ] },
  { id: 'title-box-default-left', steps: [
    set(bars({ title: T({ text: 'Boxed', right: 30 }), series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ title: { right: null } }),
  ] },
  { id: 'legend-box', steps: [
    set(Object.assign({}, JSON.parse(S(LEGEND3)), { legend: { left: 10, top: 5 } })),
    set({ legend: { right: 10, bottom: 5 } }),
  ] },
  { id: 'grid-box-count', steps: [
    set(bars({ grid: { left: 50, width: 300 }, series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ grid: { right: 20 } }),
  ] },
  { id: 'grid-box-two-new', steps: [
    set(bars({ grid: { left: 40, right: 40 }, series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ grid: { width: 200, left: 100 } }),
    set({ grid: { top: 90 } }),
  ] },
  { id: 'grid-box-defaults', steps: [
    set(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ grid: { width: 250 } }),
  ] },
  { id: 'grid-box-untouched', steps: [
    set(bars({ grid: { left: 40 }, series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ grid: { show: true } }),
  ] },
  { id: 'visualmap-box', steps: [
    set(bars({ visualMap: { type: 'continuous', min: 0, max: 10, left: 10, calculable: true }, series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ visualMap: { right: 10, top: 20 } }),
  ] },
  { id: 'tree-series-box', steps: [
    set({ animation: false, series: [{ type: 'tree', left: '10%', width: '50%',
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }] }),
    set({ series: [{ right: '30%' }] }),
    set({ series: [{ top: 10, bottom: 10, height: 100 }] }),
  ] },
  { id: 'dataset-transform', steps: [
    set({ animation: false, xAxis: { type: 'category' }, yAxis: {},
      dataset: [{ source: [['a', 1], ['b', 5], ['c', 3]] }, { transform: { type: 'filter', config: { dimension: 1, '>': 2 } } }],
      series: [{ type: 'bar', datasetIndex: 0 }] }),
    set({ dataset: [{}, { transform: { type: 'sort', config: { dimension: 1, order: 'desc' } } }] }),
  ], expect: (r) => must(r.steps[1].tree.dataset[1].transform.config['>'] === undefined, 'dataset-transform: replaced') },
  { id: 'axispointer-preprocessed', steps: [
    set(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set({ axisPointer: { triggerTooltip: false } }),
    set({ grid: [{}, { left: 5, width: 50 }] }),
  ], expect: (r) => must(r.steps[1].models.axisPointer[0].id === ' series 0 0', 'axispointer-preprocessed') },
  { id: 'grid-preprocessed-on-merge', steps: [
    set({ animation: false, series: [{ type: 'pie', data: [{ name: 'a', value: 1 }, { name: 'b', value: 2 }] }] }),
    set({ xAxis: { type: 'category', data: CAT }, yAxis: {}, series: [{}, { type: 'bar', data: [1, 2, 3, 4] }] }),
    set({ grid: { width: 250 } }),
  ], expect: (r) => must(r.steps[2].models.grid[0].id === ' series 0 0' && r.steps[2].tree.grid[0].left === '15%',
    'grid-preprocessed-on-merge: the merge made the grid, and the next one merges into it') },
  // ---- the legend ----
  { id: 'legend-kept', steps: [
    set(LEGEND3),
    act({ type: 'legendToggleSelect', name: 'B' }),
    set({ series: [{ data: [4, 4, 4, 4] }] }),
  ], expect: (r) => must(r.steps[2].tree.legend[0].selected.B === false, 'legend-kept') },
  { id: 'legend-selected-merged', steps: [
    set(LEGEND3),
    act({ type: 'legendToggleSelect', name: 'B' }),
    set({ legend: { selected: { C: false } } }),
    set({ legend: { selected: { B: true } } }),
  ], expect: (r) => must(r.steps[2].tree.legend[0].selected.B === false && r.steps[2].tree.legend[0].selected.C === false, 'legend-selected-merged') },
  { id: 'legend-single-reresolved', steps: [
    set(Object.assign({}, JSON.parse(S(LEGEND3)), { legend: { selectedMode: 'single' } })),
    act({ type: 'legendSelect', name: 'nobody' }),
    set({ title: T({ text: 'not the legend' }) }),
    set({ series: [{ data: [3, 3, 3, 3] }] }),
  ], expect: (r) => {
    // backwardCompat writes `series: []` into EVERY option, so even a title
    // merge visits the series and, through them, the legend
    must(!r.steps[1].out.series.some(s => s.shown), 'legend-single-reresolved: the action leaves nothing shown');
    must(r.steps[2].out.series[0].shown, 'legend-single-reresolved: a title merge resolves single mode again');
  } },
  { id: 'legend-type-change', steps: [
    set(LEGEND3),
    act({ type: 'legendToggleSelect', name: 'A' }),
    set({ legend: { type: 'scroll' } }),
  ] },
  // ---- the identical text ----
  { id: 'identical-merge', steps: [
    set(LEGEND3),
    act({ type: 'legendToggleSelect', name: 'C' }),
    set(LEGEND3),
  ], expect: (r) => must(r.steps[2].tree.legend[0].selected.C === false, 'identical-merge: kept') },
  { id: 'identical-notmerge', steps: [
    set(LEGEND3),
    act({ type: 'legendToggleSelect', name: 'C' }),
    set(LEGEND3, true),
  ], expect: (r) => must(r.steps[2].tree.legend[0].selected.C === undefined, 'identical-notmerge: reset') },
  // ---- dataZoom ----
  { id: 'dz-window-kept', steps: [
    set(DZ),
    act({ type: 'dataZoom', dataZoomIndex: 0, start: 20, end: 60 }),
    set({ series: [{ data: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1] }] }),
  ] },
  { id: 'dz-value-over-percent', steps: [
    set(Object.assign({}, JSON.parse(S(DZ)), { dataZoom: [{ type: 'inside', start: 10, end: 90 }] })),
    set({ dataZoom: [{ startValue: 2 }] }),
    set({ dataZoom: [{ end: 50 }] }),
  ] },
  { id: 'dz-window-then-end', steps: [
    set(DZ),
    act({ type: 'dataZoom', dataZoomIndex: 0, start: 30, end: 70 }),
    set({ dataZoom: [{ end: 90 }] }),
  ] },
  // ---- what the series models keep ----
  { id: 'select-kept', steps: [
    set(bars({ series: [{ type: 'bar', selectedMode: 'multiple', data: [1, 2, 3, 4] }, { type: 'bar', selectedMode: 'single', data: [2, 3, 4, 5] }] })),
    act({ type: 'select', seriesIndex: 0, dataIndex: [1, 3] }),
    act({ type: 'select', seriesIndex: 1, dataIndex: 2 }),
    set({ series: [{ data: [4, 3, 2, 1] }] }),
    set({ series: [{}, { type: 'line' }] }),
  ] },
  { id: 'tree-toggle-lost', steps: [
    set({ animation: false, series: [{ type: 'tree', initialTreeDepth: 1,
      data: [{ name: 'r', children: [{ name: 'a', children: [{ name: 'a1' }] }, { name: 'b', children: [{ name: 'b1' }] }] }] }] }),
    act({ type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 2 }),
    set({ title: T({ text: 'merged' }) }),
  ], expect: (r) => {
    must(r.steps[1].out.series[0].expanded[2] === true, 'tree-toggle-lost: the action expands');
    must(r.steps[2].out.series[0].expanded[2] === false, 'tree-toggle-lost: a merge rebuilds the data');
  } },
  // ---- graph roam ----
  { id: 'graph-roam-kept', steps: [
    set(GRAPH),
    act({ type: 'graphRoam', seriesIndex: 0, dx: 30, dy: -12 }),
    set({ series: [{ label: { show: true } }] }),
    set({ series: [{ zoom: 2 }] }),
    set({ series: [{ center: [60, 60] }] }),
  ] },
  // ======== A11: replaceMerge, index holes, the options form ========
  { id: 'rm-series-by-id', steps: [
    set(LEGEND_ID3),
    setO({ series: [{ id: 'a' }, { id: 'c', data: [3, 3, 3, 3] }] }, RM(['series'])),
  ], compare: ['fill'], expect: (r) => {
    const s = r.steps[1];
    must(s.models.series[1] === null && s.models.series[2].id === 'c', 'rm-series-by-id: b removed, c keeps index 2');
    must(s.tree.series[1] === null, 'rm-series-by-id: a hole in the tree');
    must(s.out.series[2].fill === r.steps[0].out.series[1].fill, 'rm-series-by-id: c takes the second colour');
    must(S(s.out.legend[0]) === S(['A', 'C']), 'rm-series-by-id: the legend lists what is left');
    must(s.views[2] === r.steps[0].views[2], 'rm-series-by-id: c keeps its view');
  } },
  { id: 'rm-series-fill-hole', steps: [
    set(LEGEND_ID3),
    setO({ series: [{ id: 'a' }, { id: 'c' }] }, RM(['series'])),
    set({ series: [{ id: 'd', type: 'bar', name: 'D', data: [1, 3, 1, 3] }] }),
    set({ series: [{ id: 'e', type: 'bar', name: 'E', data: [2, 1, 2, 1] }] }),
  ], compare: ['fill'], expect: (r) => {
    must(r.steps[2].models.series[1].id === 'd', 'rm-series-fill-hole: an id goes to the hole');
    must(r.steps[3].models.series.length === 4 && r.steps[3].models.series[3].name === 'E',
      'rm-series-fill-hole: then appended');
  } },
  { id: 'rm-series-brand-new', steps: [
    set(bars({ series: [{ type: 'bar', name: 'A', data: [1, 2, 3, 4] }, { type: 'bar', data: [2, 3, 4, 5] }] })),
    setO({ series: [{ type: 'bar', name: 'A', data: [4, 3, 2, 1] }] }, RM('series')),
    set({ series: [{ data: [2, 2, 2, 2] }] }),
  ], expect: (r) => {
    must(r.steps[1].models.series[0].id === r.steps[0].models.series[0].id, 'rm-series-brand-new: the same id made again');
    must(r.steps[1].views[0] !== r.steps[0].views[0], 'rm-series-brand-new: a new view all the same');
    must(r.steps[2].views[0] === r.steps[1].views[0], 'rm-series-brand-new: once');
    must(r.steps[1].models.series[1] === null, 'rm-series-brand-new: the second removed');
  } },
  { id: 'rm-series-append', steps: [
    set(bars({ series: [{ id: 'a', type: 'bar', data: [1, 2, 3, 4] }, { id: 'b', type: 'bar', data: [2, 3, 4, 5] }] })),
    setO({ series: [{ id: 'x', type: 'bar', data: [1, 1, 1, 1] }, { id: 'a' }, { id: 'y', type: 'bar', data: [3, 3, 3, 3] }] }, RM(['series'])),
  ], expect: (r) => {
    const m = r.steps[1].models.series;
    must(m[0].id === 'a' && m[1].id === 'x' && m[2].id === 'y', 'rm-series-append: id first, then the removed slot, then appended');
  } },
  { id: 'rm-series-absent', steps: [
    set(LEGEND_ID3),
    setO({ title: T({ text: 'no series' }) }, RM(['series'])),
    set({ series: [{ type: 'line', data: [1, 2, 1, 2] }] }),
  ], expect: (r) => {
    must(r.steps[1].models.series.every(m => m === null) && r.steps[1].tree.series.length === 0, 'rm-series-absent: all removed');
    must(r.steps[2].models.series[0] !== null && r.steps[2].models.series.length === 3, 'rm-series-absent: the first hole filled');
  } },
  { id: 'rm-series-last-removed', steps: [
    set(LEGEND_ID3),
    setO({ series: [{ id: 'a' }, { id: 'b' }] }, RM(['series'])),
    set({ series: [{}, { data: [4, 4, 4, 4] }] }),
  ], expect: (r) => must(r.steps[1].tree.series.length === 2 && r.steps[1].models.series.length === 3,
    'rm-series-last-removed: a trailing hole is trimmed from the option, not from the models') },
  { id: 'rm-series-type-by-id', steps: [
    set(LEGEND_ID3),
    setO({ series: [{ id: 'b', type: 'line', data: [1, 4, 1, 4] }, { id: 'a' }, { id: 'c' }] }, RM(['series'])),
  ], expect: (r) => must(r.steps[1].models.series[1].sub === 'line' && r.steps[1].tree.series[1].name === undefined,
    'rm-series-type-by-id: a new class, the old option dropped') },
  { id: 'rm-series-mixed-normal', steps: [
    set(LEGEND_ID3),
    setO({ xAxis: { data: ['p', 'q', 'r', 's'] }, title: T({ text: 'T' }), series: [{ id: 'c', data: [1, 1, 1, 1] }] }, RM(['series'])),
    setO({ series: [{ id: 'c' }, { id: 'a', type: 'bar', name: 'A2', data: [2, 2, 2, 2] }] }, RM('series')),
  ], expect: (r) => {
    must(r.steps[1].tree.xAxis[0].data[0] === 'p', 'rm-series-mixed-normal: the axis normally merged');
    must(r.steps[2].models.series[0].id === 'a' && r.steps[2].models.series[2].id === 'c',
      'rm-series-mixed-normal: a new a fills the first hole');
  } },
  { id: 'rm-xaxis', steps: [
    set({ animation: false,
      xAxis: [{ id: 'x0', type: 'category', data: ['a', 'b', 'c'] }, { id: 'x1', type: 'category', data: ['p', 'q'], position: 'top' }],
      yAxis: {},
      series: [{ id: 's0', type: 'bar', data: [1, 2, 3] }, { id: 's1', type: 'bar', xAxisIndex: 1, data: [5, 6] }] }),
    setO({ xAxis: [{ id: 'x1' }], series: [{ id: 's1', data: [6, 5] }] }, RM(['xAxis', 'series'])),
    set({ xAxis: [{ type: 'category', data: ['m', 'n', 'o', 'p'] }], series: [{ type: 'bar', data: [2, 2, 2, 2] }] }),
  ], expect: (r) => {
    must(r.steps[1].models.xAxis[0] === null && r.steps[1].models.xAxis[1].id === 'x1', 'rm-xaxis: x0 removed');
    must(r.steps[2].models.xAxis[0] !== null && r.steps[2].models.series[0] !== null, 'rm-xaxis: holes refilled');
  } },
  { id: 'rm-grid', steps: [
    set({ animation: false,
      grid: [{ id: 'g0', left: 40, width: 200 }, { id: 'g1', left: 320, width: 200 }],
      xAxis: [{ id: 'x0', gridIndex: 0, type: 'category', data: ['a', 'b'] }, { id: 'x1', gridIndex: 1, type: 'category', data: ['p', 'q', 'r'] }],
      yAxis: [{ id: 'y0', gridIndex: 0 }, { id: 'y1', gridIndex: 1 }],
      series: [{ id: 's0', type: 'bar', data: [1, 2] }, { id: 's1', type: 'bar', xAxisIndex: 1, yAxisIndex: 1, data: [3, 4, 5] }] }),
    setO({ grid: [{ id: 'g1' }], xAxis: [{ id: 'x1' }], yAxis: [{ id: 'y1' }], series: [{ id: 's1' }] },
      RM(['grid', 'xAxis', 'yAxis', 'series'])),
    set({ grid: [{ left: 40, width: 150 }], xAxis: [{ gridIndex: 0, type: 'category', data: ['m', 'n'] }],
      yAxis: [{ gridIndex: 0 }], series: [{ type: 'bar', data: [7, 8] }] }),
  ], expect: (r) => {
    must(r.steps[1].out.grids[0] === null && r.steps[1].out.grids[1] !== null, 'rm-grid: grid 1 keeps its index');
    must(r.steps[2].out.grids[0] !== null, 'rm-grid: refilled');
  } },
  { id: 'rm-datazoom', steps: [
    set(Object.assign({}, JSON.parse(S(DZ)), { dataZoom: [{ id: 'z0', type: 'inside', start: 20, end: 60 }] })),
    act({ type: 'dataZoom', dataZoomIndex: 0, start: 30, end: 50 }),
    setO({ dataZoom: [{ id: 'z0' }] }, RM(['dataZoom'])),
    setO({ dataZoom: [{ id: 'z1', type: 'inside', start: 10, end: 30 }] }, RM(['dataZoom'])),
    set({ dataZoom: [{ end: 40 }] }),
  ], expect: (r) => {
    must(r.steps[2].out.dz[0][0] === 30, 'rm-datazoom: the id keeps the model and its window');
    must(r.steps[3].models.dataZoom[0].id === 'z1' && r.steps[3].out.dz[0][0] === 10, 'rm-datazoom: a new model in the slot');
  } },
  { id: 'rm-datazoom-hole-axis', steps: [
    set({ animation: false,
      xAxis: [{ id: 'x0', type: 'category', data: ['a', 'b', 'c', 'd'] }, { id: 'x1', type: 'category', data: ['p', 'q'], position: 'top' }],
      yAxis: {}, dataZoom: [{ type: 'inside', xAxisIndex: 1, start: 0, end: 50 }],
      series: [{ type: 'bar', data: [1, 2, 3, 4] }] }),
    setO({ xAxis: [{ id: 'x0' }] }, RM('xAxis')),
  ], expect: (r) => must(r.steps[1].out.dz[0] === null && r.steps[1].models.dataZoom[0] !== null,
    'rm-datazoom-hole-axis: the model stays, with no window') },
  { id: 'rm-title', steps: [
    set(bars({ title: [T({ id: 't1', text: 'One' }), T({ id: 't2', text: 'Two', top: 40 })], series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    setO({ title: { id: 't2', subtext: 'two' }, series: [{ data: [4, 3, 2, 1] }] }, RM(['title'])),
    set({ title: T({ text: 'filled', top: 80 }) }),
  ], expect: (r) => {
    must(r.steps[1].out.titles[0] === null && r.steps[1].tree.series[0].data[0] === 4, 'rm-title: t1 gone, the series merged');
    must(r.steps[2].models.title[0].name === 'series\u00000', 'rm-title: the hole filled by index');
  } },
  { id: 'rm-legend', steps: [
    set(LEGEND3),
    act({ type: 'legendToggleSelect', name: 'B' }),
    setO({ legend: [] }, RM(['legend'])),
    set({ legend: {} }),
  ], expect: (r) => {
    must(!r.steps[1].out.series[1].shown && r.steps[2].out.series[1].shown, 'rm-legend: a removed legend filters nothing');
    must(r.steps[2].out.legend[0] === null && r.steps[3].out.legend[0] !== null, 'rm-legend: the hole, then filled');
  } },
  { id: 'rm-visualmap', steps: [
    set(bars({ color: ['#aa0000', '#00aa00'],
      visualMap: { type: 'continuous', min: 0, max: 10, show: false, inRange: { color: ['#00ff00', '#ff0000'] } },
      series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    setO({}, RM(['visualMap'])),
  ], compare: ['fill'] },
  { id: 'rm-event-index', steps: [
    set(bars({ series: [{ id: 'q', type: 'bar', selectedMode: 'multiple', data: [1, 2, 3, 4] },
      { id: 'r', type: 'bar', selectedMode: 'multiple', data: [2, 3, 4, 5] },
      { id: 's', type: 'bar', name: 'S', selectedMode: 'multiple', data: [3, 4, 5, 6] }] })),
    setO({ series: [{ id: 'r' }, { id: 's' }] }, RM(['series'])),
    act({ type: 'select', seriesIndex: 2, dataIndex: 1 }),
    act({ type: 'select', seriesIndex: 0, dataIndex: 2 }),
    act({ type: 'select', seriesName: 'S', dataIndex: 3 }),
    act({ type: 'select', seriesIndex: 1, dataIndex: 0 }),
  ], expect: (r) => {
    must(S(r.steps[2].sel) === S([[{ dataIndex: [1], seriesIndex: 2 }]]),
      'rm-event-index: the index after a hole is the slot ' + S(r.steps[2].sel));
  } },
  { id: 'rm-notmerge-compacts', steps: [
    set(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    set(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4] }, null, 5, { type: 'line', data: [2, 3, 2, 3] }] }), true),
    set({ series: [{}, { data: [3, 3, 3, 3] }] }),
  ], expect: (r) => {
    must(r.steps[1].models.series.length === 2 && r.steps[1].models.series[1].name === 'series\u00001',
      'rm-notmerge-compacts: a null takes no index');
  } },
  { id: 'rm-init-compacts', steps: [
    set(bars({ series: [null, { type: 'bar', data: [1, 2, 3, 4] }, null, { type: 'bar', data: [2, 2, 2, 2] }] })),
  ], expect: (r) => must(r.steps[0].tree.series.length === 2, 'rm-init-compacts') },
  { id: 'rm-notmerge-ignores', steps: [
    set(LEGEND_ID3),
    setO(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4] }, null, { type: 'bar', data: [3, 2, 1, 0] }] }),
      { notMerge: true, replaceMerge: ['series', 'title'] }),
  ], expect: (r) => must(r.steps[1].tree.title === undefined && r.steps[1].models.series.length === 2,
    'rm-notmerge-ignores: replaceMerge is not looked at') },
  { id: 'rm-first-ignores', steps: [
    setO(bars({ series: [{ type: 'bar', data: [1, 2, 3, 4] }] }), RM(['series', 'legend'])),
    setO({ series: [{ type: 'line', data: [4, 3, 2, 1] }] }, RM(['series'])),
  ], expect: (r) => must(r.steps[0].tree.legend === undefined && r.steps[1].views[0] !== r.steps[0].views[0],
    'rm-first-ignores: the init ignores it, the next merge does not') },
  { id: 'opts-silent', steps: [
    set(LEGEND3),
    setO({ series: [{ data: [2, 2, 2, 2] }] }, { silent: true }),
    setO({ series: [{ data: [3, 3, 3, 3] }] }, {}),
    setO({ series: [{ data: [4, 3, 4, 3] }] }, { silent: false, notMerge: false }),
  ], expect: (r) => must(r.steps[0].upd === 1 && r.steps[1].upd === 0 && r.steps[2].upd === 1, 'opts-silent') },
  { id: 'opts-lazy', steps: [
    set(LEGEND3),
    setO({ series: [{ data: [2, 2, 2, 2] }] }, { lazyUpdate: true }),
    setO({ series: [{ data: [3, 1, 3, 1] }] }, { lazyUpdate: true, silent: true }),
    setO({ series: [{ type: 'bar', name: 'N', data: [1, 1, 3, 3] }] }, { lazyUpdate: true, replaceMerge: ['series'] }),
  ], expect: (r) => {
    must(r.steps[1].updNow === 0 && r.steps[1].upd === 1, 'opts-lazy: the event waits for the frame');
    must(r.steps[2].upd === 0, 'opts-lazy: a silent lazy one has none');
  } },
  { id: 'rm-title-absent', steps: [
    set(bars({ title: [T({ id: 't1', text: 'One' }), T({ id: 't2', text: 'Two', top: 40 })], series: [{ type: 'bar', data: [1, 2, 3, 4] }] })),
    setO({ series: [{ data: [2, 2, 2, 2] }] }, RM(['title'])),
  ], expect: (r) => must(r.steps[1].models.title.every(m => m === null) && r.steps[1].tree.title.length === 0,
    'rm-title-absent: a named type the option leaves out is all removed') },
  { id: 'rm-lazy-fill', steps: [
    set(bars({ series: [{ id: 'a', type: 'bar', data: [1, 2, 3, 4] }, { type: 'bar', data: [2, 3, 4, 5] }] })),
    setLazy({ series: [{ id: 'a' }] }, RM(['series'])),
    set({ series: [{ id: 'a' }, { type: 'bar', data: [4, 4, 4, 4] }] }),
  ], expect: (r) => {
    must(r.steps[1].models.series[1] === null, 'rm-lazy-fill: removed at once');
    must(r.steps[2].views[1] === r.steps[0].views[1],
      'rm-lazy-fill: no update between, so the filled slot finds the removed one\'s view');
  } },
  { id: 'rm-grid-axes-left', steps: [
    set({ animation: false, grid: [{ id: 'g0' }, { id: 'g1', left: 320 }],
      xAxis: [{ type: 'category', data: ['a'] }, { gridIndex: 1, type: 'category', data: ['b'] }],
      yAxis: [{}, { gridIndex: 1 }],
      series: [{ type: 'bar', data: [1] }, { type: 'bar', xAxisIndex: 1, yAxisIndex: 1, data: [2] }] }),
    setO({ grid: [{ id: 'g1' }] }, RM(['grid'])),
  ], expect: (r) => must(r.steps[1].out.series[0].bars[0] !== null,
    'rm-grid-axes-left: axes that name no grid go to the first there is') },
  { id: 'opts-lazy-action', steps: [
    set(LEGEND3),
    setLazy({ series: [{ data: [2, 2, 2, 2] }] }, {}),
    actF({ type: 'legendToggleSelect', name: 'A' }),
    setLazy({ series: [{ data: [3, 3, 3, 3] }] }, {}),
    actF({ type: 'select', seriesIndex: 1, dataIndex: 0 }),
  ], expect: (r) => {
    must(r.steps[2].upd === 1, 'opts-lazy-action: a legend action takes the lazy update with it');
    must(r.steps[4].upd === 2, 'opts-lazy-action: a select does not');
  } },
  { id: 'opts-actions-update', steps: [
    set(LEGEND3),
    act({ type: 'legendToggleSelect', name: 'A' }),
    act({ type: 'highlight', seriesIndex: 0, dataIndex: 1 }),
  ], expect: (r) => must(r.steps[1].upd === 1 && r.steps[2].upd === 1, 'opts-actions-update: every dispatch') },
];

function generate() {
  const recs = [];
  const tally = { byId: 0, byName: 0, append: 0, replaced: 0, hole: 0, box: 0 };
  for (const c of CASES) {
    const r = runCase(c);
    if (c.expect) c.expect(r);
    tally.box += r.stats.box;
    recs.push({ id: c.id, compare: c.compare || [], steps: r.steps.map(s => ({
      kind: s.step.kind, notMerge: s.step.notMerge, opts: s.step.opts, noFrame: !!s.step.noFrame,
      text: s.step.text, payload: s.step.payload,
      tree: s.tree, models: s.models, out: s.out, views: s.views,
      updNow: s.updNow, upd: s.upd, sel: s.sel })) });
  }
  // distinctness, coarse: each mechanism appears in at least one case
  const ids = new Set(CASES.map(c => c.id));
  for (const need of ['series-by-id', 'series-by-name', 'series-by-index', 'series-append', 'series-type-change',
    'title-first-seen-holes', 'rm-series-by-id', 'rm-series-fill-hole', 'rm-series-brand-new', 'rm-grid',
    'rm-event-index', 'rm-notmerge-compacts', 'opts-silent', 'opts-lazy', 'rm-lazy-fill', 'rm-title-absent',
    'opts-lazy-action']) must(ids.has(need), 'missing case ' + need);
  must(tally.box > 0, 'no box merge was materialised');
  return JSON.stringify({
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg), ' + W + ' x ' + H,
    mainTypes: MAIN_TYPES, deps: DEPS, subTypes: SUBTYPES,
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
  console.log(CASES.length + ' cases, ' + n + ' steps -> ' + OUT);
} catch (e) {
  console.log('FAILED: ' + (e instanceof OracleError ? e.message : e.stack));
  process.exit(1);
}
process.exit(0);
