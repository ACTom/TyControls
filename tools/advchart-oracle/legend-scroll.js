/*
Upstream's own answers for the legend's SELECTOR BUTTONS and the SCROLLING
legend (`type: 'scroll'`) -- roadmap B4, batch 98.

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node, SVG renderer, 600 x 400, `animation: false` on every
case (the scroll's own animationDurationUpdate is then never used: updateProps
sets the content position at once). Like select-legend.js the chart is created
with ssr: true and then chart._ssr = false BEFORE setOption (the browser's
model), pointer events go straight to zrender's Handler with integer
{zrX, zrY}, and after every step chart._onframe() + chart.renderToSVGString().

Text is measured by zrender's SSR width table (node has no canvas); the Pascal
side reads the same table from tests/fixtures/advchart-text-style.json.

  node tools/advchart-oracle/legend-scroll.js

writes tests/fixtures/advchart-legend-scroll.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Per case: id, note, option, steps[]. Step 0 is {type: 'init'}; then
  {type: 'action', payload}            chart.dispatchAction(payload)
  {type: 'click', at, x, y, hit}       mousemove + mousedown + mouseup + click
  {type: 'move', at, x, y, hit}        mousemove
  {type: 'wheel', at, x, y, hit}       mousemove + mousewheel (zrDelta -1)
  at  = {pager: 'prev'|'next'} | {selector: n} | {item: name} | {pt: [x, y]}
  hit = what zrender finds at (x, y) before the step: 'pager:prev',
        'pager:next', 'selector:<n>', 'item:<dataIndex>' or 'none'
Each step records:
  events[]  {type, payload} for every published event (legendscroll, the five
            legend selection events, highlight, downplay); auto ids written
            '<auto id>'
  state     the legend as drawn after the step's frame:
    type     'legend.scroll' | 'legend.plain'
    group    [x, y] the view group's position (= its global transform)
    mainRect {x, y, width, height}: what layoutInner returned (group-local)
    bg       the background rect's shape (group-local; makeBackground)
    items[]  per content child in order: {i (__legendDataIndex), name,
             t [tx, ty] (the item group's GLOBAL transform), r [x, y, w, h]
             (its local bounding rect)}
    selector[]  per button: {type, title, t, r, fill (the Text's fill now),
             st (currentStates)}
    ctl      scroll only: {show (showController), prev, text, next}: each
             {t, r, fill, invisible}; text also {text}
    clip     scroll only: {t (the container's global transform), w, h} or
             null (no controller: no clip)
    page     scroll only: _getPageInfo(): {index, count, prev, next}
    scrollDataIndex, selected
  Numbers are the 16 hex digits of the IEEE double (big-endian); a global
  transform is read from the element's own transform after updateTransform
  has been run down its parent chain (zrender's own composition, incl. its
  isNotAroundZero skip).

Guards (any failure: nothing is written, exit 1):
  1. explicit expectations read off the source (selectorPosition auto per
     orient, pageButtonGap falling back to itemGap, the 'xx/xx' placeholder
     sizing the controller, pageFormatter null leaving the placeholder, the
     strict scrollDataIndex match, a button's box left/top aligned);
  2. the whole fixture is generated twice (byte-identical).
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-legend-scroll.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
Math.random = function () { return 0; };

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hexArr = a => a.map(hex);
const rectArr = r => [r.x, r.y, r.width, r.height].map(hex);
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

// ============================================================================
// Cases
// ============================================================================
const CAT = ['a', 'b'];
function seriesOf(names) {
  return names.map(n => ({ type: 'bar', name: n, data: [1, 2] }));
}
const NAMES12 = Array.from({ length: 12 }, (_, i) => 'Series ' + i);
const NAMES20 = Array.from({ length: 20 }, (_, i) => 'Item ' + i);
const UNIQ12 = Array.from({ length: 12 }, (_, i) => 'Item ' + String.fromCharCode(65 + i));
const LONG = ['A', 'Quarterly revenue (adjusted)', 'B2', 'Operating cost', 'Gross margin per unit',
  'X', 'Net income after tax and extras', 'Cash', 'Depreciation and amortisation', 'Q'];
function opt(legend, names, extra) {
  return Object.assign({ animation: false, legend, xAxis: { type: 'category', data: CAT }, yAxis: {},
    series: seriesOf(names) }, extra || {});
}
// a handler named '@PageFmt' in the Pascal replay is this function upstream
const HANDLERS = {
  '@PageFmt': p => 'P' + p.current + '|T' + p.total,
};

const CASES = [
  // ---- the scroll legend, horizontal ----
  { id: 'h-basic', note: '12 series, scroll, the defaults', option: opt({ type: 'scroll' }, NAMES12) },
  { id: 'h-start', note: "pageButtonPosition 'start'", option: opt({ type: 'scroll', pageButtonPosition: 'start' }, NAMES12) },
  { id: 'h-fits', note: 'three series: no controller (still sized into mainRect)', option: opt({ type: 'scroll' }, ['A', 'B', 'C']) },
  { id: 'h-sdi5', note: 'scrollDataIndex 5 at load', option: opt({ type: 'scroll', scrollDataIndex: 5 }, NAMES12) },
  { id: 'h-sdi3', note: 'scrollDataIndex 3 (the middle of page 1)', option: opt({ type: 'scroll', scrollDataIndex: 3 }, NAMES12) },
  { id: 'h-sdi-bad', note: 'scrollDataIndex 99 and "2": the first item', option: opt({ type: 'scroll', scrollDataIndex: 99 }, NAMES12) },
  { id: 'h-sdi-str', note: "scrollDataIndex '4' (a string never matches)", option: opt({ type: 'scroll', scrollDataIndex: '4' }, NAMES12) },
  { id: 'h-long', note: 'long names of mixed widths, left 10 right 10', option: opt({ type: 'scroll', left: 10, right: 10 }, LONG) },
  { id: 'h-narrow', note: 'a window narrower than an item', option: opt({ type: 'scroll', left: 200, right: 200 }, LONG) },
  { id: 'h-gaps', note: 'pageButtonGap 20, pageButtonItemGap 10', option: opt({ type: 'scroll', pageButtonGap: 20, pageButtonItemGap: 10 }, NAMES12) },
  { id: 'h-itemgap', note: 'itemGap 20: pageButtonGap falls back to it', option: opt({ type: 'scroll', itemGap: 20 }, NAMES12) },
  { id: 'h-fmt', note: "pageFormatter '{current} of {total}'", option: opt({ type: 'scroll', pageFormatter: '{current} of {total}' }, NAMES12) },
  { id: 'h-fmt-once', note: "pageFormatter '{current}/{current}-{total}': each replaced once", option: opt({ type: 'scroll', pageFormatter: '{current}/{current}-{total}' }, NAMES12) },
  { id: 'h-fmt-null', note: 'pageFormatter null: the placeholder stays', option: opt({ type: 'scroll', pageFormatter: null }, NAMES12) },
  { id: 'h-fmt-handler', note: 'pageFormatter a handler', option: opt({ type: 'scroll', pageFormatter: '@PageFmt' }, NAMES12) },
  { id: 'h-icons', note: 'custom pageIcons (path:// and raw, a curve, Float32)', option: opt({ type: 'scroll', pageIcons: { horizontal: ['path://M0,0L10,0L10,10L0,10Z', 'M2,2C8,0,8,12,2,10L1,9L0,8L1,6Z'] } }, NAMES12) },
  { id: 'h-icon-style', note: 'pageIconSize [10, 20], icon colours, pageTextStyle', option: opt({ type: 'scroll', pageIconSize: [10, 20], pageIconColor: '#ff0000', pageIconInactiveColor: '#00ff00', pageTextStyle: { color: '#0000ff', fontSize: 16 } }, NAMES12) },
  { id: 'h-tall-items', note: 'itemHeight 30: content taller than the controller', option: opt({ type: 'scroll', itemHeight: 30 }, NAMES12) },
  { id: 'h-short-items', note: 'itemHeight 8: the controller taller than the content', option: opt({ type: 'scroll', itemHeight: 8, top: 10 }, NAMES12) },
  // [added for surviving mutants] the target is the first item while the
  // pager is hidden, whatever scrollDataIndex says
  { id: 'h-fits-sdi', note: 'everything fits, scrollDataIndex 2: still the first item', option: opt({ type: 'scroll', scrollDataIndex: 2 }, ['A', 'B', 'C']) },
  // the window ends EXACTLY where item 4 starts (itemGap 0, no pageButtonGap):
  // intersect's `s <= winStart + size` keeps item 4 on page one's edge
  { id: 'h-window-exact', note: 'a window exactly as long as four items', option: opt({ type: 'scroll', itemGap: 0, pageButtonGap: 0, left: 0, width: 315.76 }, UNIQ12),
    steps: [{ type: 'click', at: { pager: 'next' } }, { type: 'click', at: { pager: 'next' } }, { type: 'click', at: { pager: 'prev' } }] },
  // ---- the scroll legend, vertical ----
  { id: 'v-basic', note: 'vertical, right 10, top 20, bottom 20, 20 items', option: opt({ type: 'scroll', orient: 'vertical', right: 10, top: 20, bottom: 20 }, NAMES20) },
  { id: 'v-start', note: "vertical, pageButtonPosition 'start'", option: opt({ type: 'scroll', orient: 'vertical', left: 10, top: 40, bottom: 40, pageButtonPosition: 'start' }, NAMES20) },
  { id: 'v-sdi', note: 'vertical, scrollDataIndex 10', option: opt({ type: 'scroll', orient: 'vertical', right: 10, top: 20, bottom: 20, scrollDataIndex: 10 }, NAMES20) },
  // ---- the selector, plain legend ----
  { id: 'sel-h', note: 'selector true, horizontal: auto is end', option: opt({ selector: true }, ['A', 'Bb', 'Ccc']) },
  { id: 'sel-h-start', note: "selector, horizontal, 'start'", option: opt({ selector: true, selectorPosition: 'start' }, ['A', 'Bb', 'Ccc']) },
  { id: 'sel-v', note: 'selector, vertical: auto is start', option: opt({ selector: true, orient: 'vertical', left: 10, top: 30 }, ['A', 'Bb', 'Ccc']) },
  { id: 'sel-v-end', note: "selector, vertical, 'end'", option: opt({ selector: true, orient: 'vertical', right: 10, top: 'middle', selectorPosition: 'end' }, ['A', 'Bb', 'Ccc']) },
  { id: 'sel-titles', note: 'titled buttons, selectorItemGap 15, selectorButtonGap 4', option: opt({ selector: [{ type: 'all', title: 'Select all' }, { type: 'inverse', title: 'Invert' }], selectorItemGap: 15, selectorButtonGap: 4 }, ['A', 'Bb', 'Ccc']) },
  { id: 'sel-styled', note: "['inverse'] alone, selectorLabel styled, emphasis colour", option: opt({ selector: ['inverse'], selectorLabel: { fontSize: 14, padding: 6, borderRadius: 2, color: '#333333', borderColor: '#999999' }, emphasis: { selectorLabel: { color: '#ff0000' } } }, ['A', 'Bb', 'Ccc']) },
  { id: 'sel-wrap', note: 'selector beside a legend wrapped onto two rows', option: opt({ selector: true, left: 20, right: 300 }, NAMES12) },
  { id: 'sel-big', note: 'selector taller than the items (fontSize 20)', option: opt({ selector: true, selectorLabel: { fontSize: 20 }, top: 10 }, ['A', 'Bb']) },
  // ---- the selector on a scroll legend ----
  { id: 'scroll-sel', note: 'scroll + selector, horizontal (end)', option: opt({ type: 'scroll', selector: true }, NAMES12) },
  { id: 'scroll-sel-start', note: "scroll + selector, horizontal 'start'", option: opt({ type: 'scroll', selector: true, selectorPosition: 'start', pageButtonPosition: 'start' }, NAMES12) },
  { id: 'scroll-sel-v', note: 'scroll + selector, vertical (start)', option: opt({ type: 'scroll', selector: true, orient: 'vertical', right: 10, top: 20, bottom: 20 }, NAMES20) },
  { id: 'scroll-sel-v-end', note: "scroll + selector, vertical 'end', buttons 'start'", option: opt({ type: 'scroll', selector: true, selectorPosition: 'end', pageButtonPosition: 'start', orient: 'vertical', left: 10, top: 20, bottom: 60 }, NAMES20) },
  { id: 'scroll-sel-fits', note: 'scroll + selector, everything fits', option: opt({ type: 'scroll', selector: true }, ['A', 'B']) },
];

// ---- interaction sequences (cases with steps) ----
const SEQ = [
  { id: 'seq-actions', note: 'legendScroll actions: by index, by id miss, without scrollDataIndex, to the end',
    option: opt({ type: 'scroll' }, NAMES12),
    steps: [
      { type: 'action', payload: { type: 'legendScroll', scrollDataIndex: 5 } },
      { type: 'action', payload: { type: 'legendScroll', scrollDataIndex: 9, legendIndex: 0 } },
      { type: 'action', payload: { type: 'legendScroll', scrollDataIndex: 2, legendId: 'nope' } },
      { type: 'action', payload: { type: 'legendScroll' } },
      { type: 'action', payload: { type: 'legendScroll', scrollDataIndex: 11 } },
      { type: 'action', payload: { type: 'legendScroll', scrollDataIndex: 0, legendName: 'nope' } },
    ] },
  { id: 'seq-pager', note: 'page buttons: next, next, next (none), prev, prev, prev (none)',
    option: opt({ type: 'scroll' }, NAMES12),
    steps: [
      { type: 'click', at: { pager: 'next' } }, { type: 'click', at: { pager: 'next' } },
      { type: 'click', at: { pager: 'next' } }, { type: 'click', at: { pager: 'prev' } },
      { type: 'click', at: { pager: 'prev' } }, { type: 'click', at: { pager: 'prev' } },
    ] },
  { id: 'seq-pager-v', note: 'vertical page buttons, start',
    option: opt({ type: 'scroll', orient: 'vertical', left: 10, top: 40, bottom: 40, pageButtonPosition: 'start' }, NAMES20),
    steps: [
      { type: 'click', at: { pager: 'next' } }, { type: 'click', at: { pager: 'next' } },
      { type: 'click', at: { pager: 'prev' } },
    ] },
  { id: 'seq-pager-long', note: 'page buttons over long names',
    option: opt({ type: 'scroll', left: 10, right: 10 }, LONG),
    steps: [
      { type: 'click', at: { pager: 'next' } }, { type: 'click', at: { pager: 'next' } },
      { type: 'click', at: { pager: 'prev' } },
    ] },
  { id: 'seq-pager-narrow', note: 'page buttons on a window narrower than an item',
    option: opt({ type: 'scroll', left: 200, right: 200 }, LONG),
    steps: [
      { type: 'click', at: { pager: 'next' } }, { type: 'click', at: { pager: 'next' } },
      { type: 'click', at: { pager: 'prev' } },
    ] },
  { id: 'seq-selector', note: 'selector clicks: Inv, All, Inv; an item toggle between',
    option: opt({ selector: true }, ['A', 'Bb', 'Ccc']),
    steps: [
      { type: 'click', at: { selector: 1 } }, { type: 'click', at: { selector: 0 } },
      { type: 'click', at: { item: 'Bb' } }, { type: 'click', at: { selector: 1 } },
    ] },
  { id: 'seq-selector-hover', note: 'hover a button (emphasis), off, back on, click (re-render: normal), off, on',
    option: opt({ selector: true, emphasis: { selectorLabel: { color: '#ff0000' } } }, ['A', 'Bb', 'Ccc']),
    steps: [
      { type: 'move', at: { selector: 0 } }, { type: 'move', at: { pt: [5, 5] } },
      { type: 'move', at: { selector: 1 } }, { type: 'click', at: { selector: 1 } },
      { type: 'move', at: { pt: [5, 5] } }, { type: 'move', at: { selector: 1 } },
    ] },
  { id: 'seq-scroll-sel', note: 'scroll + selector: inverse, next page, all, item toggle on page 2',
    option: opt({ type: 'scroll', selector: true }, NAMES12),
    steps: [
      { type: 'click', at: { selector: 1 } }, { type: 'click', at: { pager: 'next' } },
      { type: 'click', at: { selector: 0 } }, { type: 'click', at: { item: 'Series 6' } },
    ] },
  { id: 'seq-wheel', note: 'the wheel over a scroll legend does nothing',
    option: opt({ type: 'scroll' }, NAMES12),
    steps: [
      { type: 'wheel', at: { item: 'Series 1' } }, { type: 'wheel', at: { pager: 'next' } },
    ] },
  { id: 'seq-single', note: 'selectedMode single + selector: All and Inv',
    option: opt({ selector: true, selectedMode: 'single' }, ['A', 'Bb', 'Ccc']),
    steps: [
      { type: 'click', at: { selector: 0 } }, { type: 'click', at: { selector: 1 } },
    ] },
];

// ============================================================================
// Driving
// ============================================================================
let captured = null;
function patch() {
  for (const type of ['plain', 'scroll']) {
    const chart = newChart();
    let proto;
    try {
      chart.setOption({ animation: false, legend: { type }, series: [] });
      const view = chart.getViewOfComponentModel(chart.getModel().getComponent('legend', 0));
      proto = Object.getPrototypeOf(view);
      while (proto && !Object.prototype.hasOwnProperty.call(proto, 'layoutInner')) proto = Object.getPrototypeOf(proto);
      must(proto, type + ' legend: no layoutInner on the view chain');
    } finally {
      chart.dispose();
    }
    if (Object.prototype.hasOwnProperty.call(proto, '__b4Patched')) continue;
    const orig = proto.layoutInner;
    proto.layoutInner = function () {
      const r = orig.apply(this, arguments);
      captured = { x: r.x, y: r.y, width: r.width, height: r.height };
      return r;
    };
    proto.__b4Patched = true;
  }
}

function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function frame(chart) {
  chart._onframe();
  chart.renderToSVGString();
}
function globalT(el) {
  const chain = [];
  for (let e = el; e; e = e.parent) chain.unshift(e);
  chain.forEach(e => e.updateTransform());
  const t = el.transform;
  return t ? [t[4], t[5]] : [0, 0];
}
const isAuto = s => typeof s === 'string' && s.charCodeAt(0) === 0;
function plain(v) {
  if (v === undefined) return undefined;
  if (v === null || typeof v !== 'object') return isAuto(v) ? '<auto id>' : v;
  if (Array.isArray(v)) return v.map(plain);
  const o = {};
  for (const k of Object.keys(v)) {
    const p = plain(v[k]);
    if (p !== undefined) o[k] = p;
  }
  return o;
}
function withHandlers(option) {
  const o = clone(option);
  if (o.legend && typeof o.legend.pageFormatter === 'string' && HANDLERS[o.legend.pageFormatter]) {
    o.legend.pageFormatter = HANDLERS[o.legend.pageFormatter];
  }
  return o;
}

const EVENT_TYPES = ['legendscroll', 'legendselectchanged', 'legendselected', 'legendunselected',
  'legendselectall', 'legendinverseselect', 'highlight', 'downplay'];

function stateOf(chart) {
  const model = chart.getModel().getComponent('legend', 0);
  const view = chart.getViewOfComponentModel(model);
  const scroll = model.type === 'legend.scroll';
  const g = view.group;
  const st = { type: model.type, orient: model.get('orient') };
  st.group = hexArr(globalT(g));
  must(captured, 'layoutInner was not called');
  st.mainRect = rectArr(captured);
  const bg = view._backgroundEl;
  st.bg = rectArr(bg.shape);
  st.items = view.getContentGroup().children().map(it => {
    const te = it.children().filter(k => k.type === 'text');
    return { i: it.__legendDataIndex, name: te.length ? te[0].style.text : null,
      t: hexArr(globalT(it)), r: rectArr(it.getBoundingRect()) };
  });
  const selOpt = model.get('selector', true);
  st.selector = view.getSelectorGroup().children().map((b, k) => ({
    type: selOpt[k].type, title: b.style.text, t: hexArr(globalT(b)), r: rectArr(b.getBoundingRect()),
    fill: b.style.fill, st: b.currentStates.slice(),
  }));
  if (scroll) {
    const ctl = view._controllerGroup;
    const one = name => {
      const c = ctl.childOfName(name);
      if (!c) return null;
      const o = { t: hexArr(globalT(c)), r: rectArr(c.getBoundingRect()), fill: c.style.fill, invisible: !!c.invisible };
      if (name === 'pageText') o.text = c.style.text;
      return o;
    };
    st.ctl = { show: view._showController, prev: one('pagePrev'), text: one('pageText'), next: one('pageNext') };
    const cg = view._containerGroup;
    const cp = cg.getClipPath();
    st.clip = cp ? { t: hexArr(globalT(cg)), w: hex(cp.shape.width), h: hex(cp.shape.height) } : null;
    const pi = view._getPageInfo(model);
    st.page = { index: pi.pageIndex, count: pi.pageCount, prev: pi.pagePrevDataIndex, next: pi.pageNextDataIndex };
    st.scrollDataIndex = model.option.scrollDataIndex;
  }
  st.selected = clone(model.option.selected);
  return st;
}

function runCase(def) {
  const chart = newChart();
  const events = [];
  try {
    captured = null;
    chart.setOption(withHandlers(def.option));
    frame(chart);
    for (const t of EVENT_TYPES) chart.on(t, p => events.push({ type: t, payload: plain(p) }));
    const hd = () => chart.getZr().handler;
    const model = () => chart.getModel().getComponent('legend', 0);
    const view = () => chart.getViewOfComponentModel(model());
    const hitName = (x, y) => {
      const t = hd().findHover(x, y).target;
      if (!t) return 'none';
      for (let e = t; e; e = e.__hostTarget || e.parent) {
        if (e.name === 'pagePrev') return 'pager:prev';
        if (e.name === 'pagePrev' || e.name === 'pageNext') return 'pager:next';
        if (e.parent === view().getSelectorGroup()) return 'selector:' + view().getSelectorGroup().children().indexOf(e);
        if (e.__legendDataIndex != null) return 'item:' + e.__legendDataIndex;
      }
      return 'other';
    };
    const aim = at => {
      let el = null;
      let want = '';
      if (at.pt) return { x: at.pt[0], y: at.pt[1] };
      if (at.pager) {
        el = view()._controllerGroup.childOfName(at.pager === 'prev' ? 'pagePrev' : 'pageNext');
        want = 'pager:' + at.pager;
      } else if (at.selector != null) {
        el = view().getSelectorGroup().childAt(at.selector);
        // the words: the box's padding is hollow upstream (only the glyphs
        // and the 1px ring hit)
        el = el._children.find(k => k.type === 'tspan');
        want = 'selector:' + at.selector;
      } else if (at.item) {
        const it = view().getContentGroup().children().find(c =>
          c.children().some(k => k.type === 'text' && k.style.text === at.item));
        must(it, def.id + ': no item ' + at.item);
        el = it.children().find(k => k.type === 'text');
        want = 'item:' + it.__legendDataIndex;
      }
      must(el, def.id + ': nothing to aim at ' + JSON.stringify(at));
      const t = globalT(el);
      const r = el.getBoundingRect();
      const x = Math.round(t[0] + r.x + r.width / 2);
      const y = Math.round(t[1] + r.y + r.height / 2);
      must(hitName(x, y) === want, def.id + ': (' + x + ', ' + y + ') hits ' + hitName(x, y) + ', not ' + want);
      return { x, y };
    };
    const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, zrDelta: -1, wheelDelta: -120, preventDefault() {}, stopPropagation() {} });
    const out = [];
    out.push({ type: 'init', events: [], state: stateOf(chart) });
    for (const s of def.steps || []) {
      events.length = 0;
      const rec = { type: s.type };
      if (s.type === 'action') {
        rec.payload = s.payload;
        chart.dispatchAction(clone(s.payload));
      } else {
        const p = aim(s.at);
        rec.at = s.at;
        rec.x = p.x;
        rec.y = p.y;
        rec.hit = hitName(p.x, p.y);
        hd().mousemove(raw(p.x, p.y));
        if (s.type === 'click') {
          hd().mousedown(raw(p.x, p.y));
          hd().mouseup(raw(p.x, p.y));
          hd().click(raw(p.x, p.y));
        } else if (s.type === 'wheel') {
          hd().mousewheel(raw(p.x, p.y));
        }
      }
      frame(chart);
      rec.events = events.slice();
      rec.state = stateOf(chart);
      out.push(rec);
    }
    const option = clone(def.option);
    return { id: def.id, note: def.note, option, steps: out };
  } finally {
    chart.dispose();
  }
}

// ============================================================================
// Guards: expectations read off the source
// ============================================================================
function guards(cases) {
  const by = id => cases.find(c => c.id === id);
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const n = h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); };
  // LegendView.render: selectorPosition 'auto' -> horizontal end, vertical start
  const selH = by('sel-h').steps[0].state;
  guard('auto horizontal selector sits after the items',
    n(selH.selector[0].t[0]) > Math.max(...selH.items.map(it => n(it.t[0]))));
  const selV = by('sel-v').steps[0].state;
  guard('auto vertical selector sits above the items',
    n(selV.selector[0].t[1]) < Math.min(...selV.items.map(it => n(it.t[1]))));
  // a button's box is left/top aligned: setLabelStyle drops align/verticalAlign
  guard('a button box starts half its border out', n(selH.selector[0].r[0]) === -0.5 && n(selH.selector[0].r[1]) === -0.5);
  // retrieve2(pageButtonGap, itemGap)
  const ig = by('h-itemgap').steps[0].state;
  const ctlLeft = n(ig.ctl.prev.t[0]) + n(ig.ctl.prev.r[0]);
  const clipW = n(ig.clip.w);
  guard('pageButtonGap falls back to itemGap (end: clip + gap + controller = window)',
    Math.abs(clipW + 20 - (ctlLeft - n(ig.clip.t[0]))) < 1e-9);
  // the placeholder sizes the controller; pageFormatter null keeps it
  guard('pageFormatter null leaves the placeholder', by('h-fmt-null').steps[0].state.ctl.text.text === 'xx/xx');
  const b = by('h-basic').steps[0].state;
  guard('the placeholder sizes the controller: next sits past the real text',
    n(b.ctl.next.t[0]) - n(b.ctl.text.t[0]) > n(b.ctl.text.r[2]) / 2 + 5);
  // _findTargetItemIndex: a strict match; else the first item
  guard('a string scrollDataIndex matches nothing', by('h-sdi-str').steps[0].state.page.index === 0);
  guard('an unknown scrollDataIndex is the first item', by('h-sdi-bad').steps[0].state.page.index === 0);
  guard('scrollDataIndex 5 is page 2', by('h-sdi5').steps[0].state.page.index === 1);
  // no controller: invisible but sized in
  const fits = by('h-fits').steps[0].state;
  guard('no controller: invisible, no clip, mainRect as tall as the icon', !fits.ctl.show && fits.ctl.prev.invisible
    && fits.clip === null && n(fits.mainRect[3]) === 15);
  // the wheel does nothing
  const wh = by('seq-wheel');
  guard('the wheel publishes nothing and leaves scrollDataIndex',
    wh.steps.slice(1).every(s => s.events.filter(e => e.type === 'legendscroll').length === 0 && s.state.scrollDataIndex === 0));
  // a page click publishes legendscroll with the legend's id
  const pg = by('seq-pager');
  guard('a page click publishes legendscroll {type, scrollDataIndex, legendId}',
    pg.steps[1].events.length === 1 && pg.steps[1].events[0].type === 'legendscroll'
    && JSON.stringify(Object.keys(pg.steps[1].events[0].payload)) === '["type","scrollDataIndex","legendId"]');
  guard('an inactive page button dispatches nothing', pg.steps[3].events.length === 0);
  // a button click re-renders: the new text is in no state
  const sh = by('seq-selector-hover');
  guard('hover emphasis then the re-render clears it', sh.steps[1].state.selector[0].st.join() === 'emphasis'
    && sh.steps[4].state.selector[1].st.length === 0 && sh.steps[6].state.selector[1].st.join() === 'emphasis');
  return g;
}

// ============================================================================
// Output
// ============================================================================
function generate() {
  patch();
  const cases = CASES.concat(SEQ).map(runCase);
  return { source: DIST, version: echarts.version, W, H, cases, guards: guards(cases) };
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
const bad = out1.guards.filter(g => !g.ok);
out1.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.name));
const deterministic = json1 === json2;
const steps = out1.cases.reduce((a, c) => a + c.steps.length, 0);
const evs = out1.cases.reduce((a, c) => a + c.steps.reduce((b, s) => b + s.events.length, 0), 0);
console.log(out1.cases.length + ' cases, ' + steps + ' steps, ' + evs + ' events; '
  + (out1.guards.length - bad.length) + '/' + out1.guards.length + ' guards; two runs '
  + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
