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
  {kind: 'action', payload}      chart.dispatchAction(payload)
Per step (after it):
  tree    the raw merge, as the port's GetOptionJson must give it: every
          component main type written (non-null) since the last notMerge, as
          an array over componentIndex (null in a hole, trailing nulls
          trimmed); the other root keys merged; NaN never occurs
  models  {mainType: [null | {id, name, sub}]} for series and every main type
          in tree: the model's id (NULs kept, '\0' + name + '\0' + n), name,
          subType ('' for none)
  out     {series: [null | {count, shown, fill, sel, bars?, expanded?,
            centre?, zoom?}],
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
          getPercentRange()
  views   [view number per series]: the n-th distinct series view object
          seen in this case -- the same number across steps is the same view
          (an update), a new number a new view (an entrance)
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
  try {
    for (const st of c.steps) {
      const rec = { step: st };
      if (st.kind === 'set') {
        const opt = JSON.parse(st.text);
        if (st.notMerge || steps.length === 0) {
          rootRaw = {};
          written = new Set();
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
        chart.setOption(opt, !!st.notMerge);
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
      for (let i = 0; i < data.count(); i++) {
        const el = data.getItemGraphicEl(i);
        o.bars.push(el && el.shape ? [el.shape.x, el.shape.y, el.shape.width, el.shape.height] : null);
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
  const dz = (slotsOf(chart, 'dataZoom') || []).map(z => z ? z.getPercentRange() : null);
  return { series, grids, titles, dz };
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
const act = (p) => ({ kind: 'action', payload: p });
const LEGEND3 = bars({
  legend: {},
  series: [
    { type: 'bar', name: 'A', data: [1, 2, 3, 4] },
    { type: 'bar', name: 'B', data: [4, 3, 2, 1] },
    { type: 'bar', name: 'C', data: [2, 2, 2, 2] },
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
];

function generate() {
  const recs = [];
  const tally = { byId: 0, byName: 0, append: 0, replaced: 0, hole: 0, box: 0 };
  for (const c of CASES) {
    const r = runCase(c);
    if (c.expect) c.expect(r);
    tally.box += r.stats.box;
    recs.push({ id: c.id, compare: c.compare || [], steps: r.steps.map(s => ({
      kind: s.step.kind, notMerge: s.step.notMerge, text: s.step.text, payload: s.step.payload,
      tree: s.tree, models: s.models, out: s.out, views: s.views })) });
  }
  // distinctness, coarse: each mechanism appears in at least one case
  const ids = new Set(CASES.map(c => c.id));
  for (const need of ['series-by-id', 'series-by-name', 'series-by-index', 'series-append', 'series-type-change',
    'title-first-seen-holes']) must(ids.has(need), 'missing case ' + need);
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
