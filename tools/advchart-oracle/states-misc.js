// F2b (fix phase, 2026-10-18): the states the shared model did not reach yet.
//
//   A. a gauge's pointer and progress arc, each its own highDownDispatcher
//      (GaugeView.ts:526-574: setStatesStylesFromModel + toggleHoverEmphasis,
//      z2EmphasisLift 0); only the pointer is the item's graphic element, so
//      the highlight action and the selection reach the pointer alone
//   B. a radar's item group (RadarView.ts:181-268): the polyline (lineStyle
//      states), the polygon (areaStyle states, an ignore per state) and the
//      symbols (itemStyle states), one dispatcher for all
//   C. the markers of a blurred series (MarkerView.toggleBlurSeries): every
//      marker element of a series blurSeries reached enters blur, allLeaveBlur
//      takes them out again
//   D. a click on a large bar or point (BarView largePathUpdateDataIndex,
//      LargeSymbolDraw): the element's ECData carries the row the last
//      mousemove found, so the click dispatches select; the large element has
//      no states
//   E. a pie's and a funnel's label hidden at rest and shown by a state
//      (labelStyle.setLabelStyle needsCreateText; pie labelLayout's
//      isLabelShown): built, laid out and ignored at rest
//   F. a pictorialBar's hit target: the glyphs (the bar rect is silent,
//      PictorialBarView.ts:692-696), clipped as drawn
//   G. [R2-B] a radar item's paint order (polyline, polygon, symbols in its
//      group), a radar item held by an action under another's focus self
//      hover, and a label riding its hovered symbol through the state
//      transition (a scatter's, a graph's, a tree's): a case with `order`
//      records each element's place in the display list (zi), one with
//      `labelPlace` a label's computed transform (tx / ty); a radar's
//      lineStyle.type (a case with `dash` records a path's dash as
//      canvas/dashStyle.ts normalizeLineDash draws it)
//   H. [R2-I1] a label's rest opacity: setLabelStyle's defaultOpacity, the
//      host's style.opacity (a scatter's 0.8 by its series default, a bar's
//      and a line's written itemStyle.opacity, an item's own; a written
//      label.opacity over it), through a hover; a radar point label's label
//      line on the item's states (setLabelLineStyle from LabelManager's
//      _updateLabelLine: hidden where its label is, or where the state's
//      labelLine.show -- the normal one by default -- is false; the state's
//      lineStyle)
//
// The harness is state-anim.js' own, copied (that script generates and exits
// on load): the replaced Date before the dist, chart._ssr = false,
// env.node = false, the seeded Math.random, hand-stepped frames. A STEP IS
// ONE FRAME: at each sample time t (ms after T1) the events of t (pointer
// moves and clicks through zr.handler, dispatchAction), then NOW = T1 + t and
// zr.animation.update() -- every clip steps, then 'frame' runs echarts'
// _onframe, whose applyChangedStates turns the flags into state lists.
//
// Recorded per sample: every element of every series view and of every
// marker view (owner 'series<i>:<type>' or '<markType>:s<i>'), with its
// transform / style / shape keys, ignore, z2, currentStates, its state
// animators and its stateTransition -- as state-anim.js; each element also
// carries `map`, the part the port keeps it as ({s, row (inner index), part})
// or null. Per sample also: the events the chart published (select,
// unselect, selectchanged, mouseover, mouseout, click, highlight, downplay)
// and every series' selectedMap and getSelectedDataIndices().
//
// Run: node tools/advchart-oracle/states-misc.js
//   -> tests/fixtures/advchart-states-misc.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-states-misc.json');

echarts.env.node = false;

const W = 400;
const H = 300;
const SAMPLES = [0, 1, 16, 50, 100, 150, 200, 250, 300, 301, 350, 400, 401, 450, 500, 501, 550, 600, 650,
  700, 750, 800, 801, 850, 900, 1000, 1100, 1200, 1201, 1500, 1600];

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
const text = v => (Object.is(v, -0) ? '-0' : String(v));

// ---------- element snapshots ----------
const TRANSFORM_KEYS = ['x', 'y', 'scaleX', 'scaleY', 'rotation'];
const STYLE_KEYS = ['opacity', 'fill', 'stroke', 'lineWidth'];
function enc(v) {
  if (typeof v === 'number') return [hex(v), text(v)];
  if (typeof v === 'string' || typeof v === 'boolean') return [v, v];
  if (v && typeof v === 'object' && v.colorStops) {
    const s = JSON.stringify(v);
    return [s, s];
  }
  return undefined;
}
let CUR_CASE = null;
// zrender canvas/dashStyle.ts normalizeLineDash, transcribed
function normalizeLineDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  lineWidth = lineWidth || 1;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
    : typeof lineType === 'number' ? [lineType]
    : Array.isArray(lineType) ? lineType : null;
}
function snap(el, zi) {
  const o = {};
  const put = (k, v) => {
    const e = enc(v);
    if (e !== undefined) o[k] = e;
  };
  for (const k of TRANSFORM_KEYS) if (typeof el[k] === 'number') put(k, el[k]);
  put('ignore', !!el.ignore);
  // [R2-B] the case's own extra records
  if (CUR_CASE && CUR_CASE.labelPlace && el.type === 'text' && el.transform) {
    put('tx', el.transform[4]);
    put('ty', el.transform[5]);
  }
  if (CUR_CASE && CUR_CASE.order && zi != null) put('zi', zi);
  if (CUR_CASE && CUR_CASE.dash && el.style && el.type !== 'text') put('dash', JSON.stringify(normalizeLineDash(el.style.lineDash, el.style.lineWidth)));
  // [R2-I3] the pen's phase as drawn (a state's dashOffset tweens)
  if (CUR_CASE && CUR_CASE.dashOff && el.style && el.type !== 'text' && el.style.lineDash) put('dashOff', el.style.lineDashOffset == null ? 0 : el.style.lineDashOffset);
  if (el.invisible != null) put('invisible', !!el.invisible);
  if (typeof el.z2 === 'number') put('z2', el.z2);
  put('states', (el.currentStates || []).join(','));
  if (el.style) for (const k of STYLE_KEYS) if (el.style[k] != null) put('style.' + k, el.style[k]);
  if (el.style && el.style.stroke === null && el.type !== 'text') put('style.stroke', 'null');
  // the shape's scalars only (a large path's points are thousands)
  if (el.shape) {
    for (const k of Object.keys(el.shape)) {
      if (typeof el.shape[k] === 'number') put('shape.' + k, el.shape[k]);
    }
  }
  return o;
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// the walk of one group: [{el, role, path}]
function walkView(root) {
  const out = [];
  const visit = (el, p) => {
    out.push({ el, role: 'el', path: p });
    const label = el.getTextContent && el.getTextContent();
    if (label) out.push({ el: label, role: 'label', path: p + '#label' });
    const guide = el.getTextGuideLine && el.getTextGuideLine();
    if (guide) out.push({ el: guide, role: 'guide', path: p + '#guide' });
    if (el.isGroup) el.childrenRef().forEach((c, i) => visit(c, p === '' ? String(i) : p + '.' + i));
  };
  visit(root, '');
  return out;
}

// getECData = makeInner() (util/innerStore.ts): an own property '__ec_inner_<n>'
function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'dataIndex' in el[k]) return el[k];
  }
  return null;
}

// THE PORT'S PARTS. A label or a label line is mapped by its host.
function seriesParts(chart) {
  const m = new Map();
  const put = (el, s, row, part) => {
    if (!el) return;
    m.set(el, { s, row, part });
    const label = el.getTextContent && el.getTextContent();
    if (label) m.set(label, { s, row, part: part === 'host' ? 'label' : part + '#label' });
    // a label line of no length draws nothing (a funnel's inside label:
    // funnelLayout gives it the label's place twice)
    const guide = el.getTextGuideLine && el.getTextGuideLine();
    const pts = guide && guide.shape.points;
    if (pts && pts.length >= 2 && pts.some(q => q[0] !== pts[0][0] || q[1] !== pts[0][1])) {
      m.set(guide, { s, row, part: part === 'host' ? 'guide' : part + '#guide' });
    }
  };
  chart.getModel().eachSeries(sm => {
    const s = sm.seriesIndex;
    const data = sm.getData();
    const view = chart.getViewOfSeriesModel(sm);
    const type = sm.subType;
    if (type === 'gauge') {
      data.each(i => put(data.getItemGraphicEl(i), s, i, 'host'));
      (view._progressEls || []).forEach((el, i) => put(el, s, i, 'peer'));
      return;
    }
    if (type === 'radar') {
      data.each(i => {
        const g = data.getItemGraphicEl(i);
        if (!g) return;
        put(g.childAt(0), s, i, 'host');
        put(g.childAt(1), s, i, 'rarea');
        g.childAt(2).eachChild(sym => put(sym, s, i, 'rsym' + sym.__dimIdx));
      });
      return;
    }
    // [R2-I3] a line's polyline, in a case that asks for the pens' phases
    if (type === 'line' && CUR_CASE && CUR_CASE.dashOff && view._polyline) put(view._polyline, s, 0, 'poly');
    if (type === 'pictorialBar') {
      data.each(i => {
        const g = data.getItemGraphicEl(i);
        if (!g) return;
        let k = 0;
        g.traverse(el => {
          if (el.isGroup || el === g.__pictorialBarRect) return;
          put(el, s, i, k === 0 ? 'host' : 'part' + (k - 1));
          k++;
        });
      });
      return;
    }
    data.each(i => {
      const el = data.getItemGraphicEl(i);
      if (!el) return;
      // a Symbol group: its path
      put(el.isGroup && el.childAt(0) ? el.childAt(0) : el, s, i, 'host');
    });
  });
  return m;
}

// the marker views' groups by host series: [{owner, s, kind, group}]
function markerViews(chart) {
  const out = [];
  for (const v of chart._componentsViews) {
    if (!v || !v.markerGroupMap) continue;
    const kind = v.type;
    chart.getModel().eachSeries(sm => {
      const d = v.markerGroupMap.get(sm.id);
      if (d && d.group && d.group.parent) out.push({ owner: kind + ':s' + sm.seriesIndex, s: sm.seriesIndex, kind, group: d.group });
    });
  }
  return out;
}

// a marker element's part: markPoint mp<k> (the symbol path), markLine ml<k>
// (the line), ml<k>.from / .to (its end symbols), markArea ma<k>; labels
// '#label'
function markerParts(mv, out) {
  const tag = { markPoint: 'mp', markLine: 'ml', markArea: 'ma' }[mv.kind];
  mv.group.eachChild(item => {
    const ecd = ecDataOf(item);
    if (!ecd || ecd.dataIndex == null) return;
    const k = ecd.dataIndex;
    // a label of no text draws nothing (a markArea's without a name)
    const words = label => label && label.style && label.style.text != null && label.style.text !== '';
    const put = (el, part) => {
      if (!el) return;
      out.set(el, { s: mv.s, row: -1, part: part });
      const label = el.getTextContent && el.getTextContent();
      if (words(label)) out.set(label, { s: mv.s, row: -1, part: part + '#label' });
    };
    if (mv.kind === 'markPoint') put(item.childAt(0), tag + k);
    else if (mv.kind === 'markLine') {
      put(item.childOfName('line'), tag + k);
      put(item.childOfName('fromSymbol'), tag + k + '.from');
      put(item.childOfName('toSymbol'), tag + k + '.to');
      const label = item.getTextContent();
      if (words(label)) out.set(label, { s: mv.s, row: -1, part: tag + k + '#label' });
    }
    else put(item, tag + k);
  });
}

function clipCount(zr) {
  let n = 0;
  for (let c = zr.animation._head; c; c = c.next) n++;
  if (process.env.ORACLE_CLIPS) {
    const d = [];
    for (let c = zr.animation._head; c; c = c.next) d.push((c.loop ? 'L' : '') + c._life + '/' + c._delay + '/' + (c._startTime - T_BASE));
    if (d.length) console.log('clips', NOW - T_BASE, d.join(' '));
  }
  return n;
}

// the state animators of an element: their __fromStateTransition names
function stateAnims(el) {
  return (el.animators || []).filter(a => a.__fromStateTransition).map(a => a.__fromStateTransition + ':' + (a.targetName || ''));
}

// ---------- the timeline ----------
const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });

function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}

const T1_OFFSET = 10000;
const CASE_STRIDE = 100000;
function settle(chart, start) {
  const zr = chart.getZr();
  for (let t = 16; t <= 5000; t += 250) {
    NOW = start + t;
    zr.animation.update();
  }
  zr.storage.getDisplayList(true);
  let live = 0;
  for (let c = zr.animation._head; c; c = c.next) if (!c.loop) live++;
  must(live === 0, 'the first render did not settle');
}

// ---------- aiming ----------
function globalBox(el) {
  const r = el.getBoundingRect().clone();
  el.updateTransform();
  const m = el.getComputedTransform();
  if (m) r.applyTransform(m);
  return r;
}
// the integer point nearest the centre of APredicate's box where the hover
// target is the element itself
function aimIn(chart, box, accept) {
  const zr = chart.getZr();
  zr.storage.getDisplayList(true);
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;
  let best = null;
  let bestD = Infinity;
  for (let y = Math.floor(box.y); y <= Math.ceil(box.y + box.height); y++) {
    for (let x = Math.floor(box.x); x <= Math.ceil(box.x + box.width); x++) {
      if (x < 1 || y < 1 || x >= W - 1 || y >= H - 1) continue;
      if (!accept(x, y, zr.handler.findHover(x, y))) continue;
      const d = (x - cx) * (x - cx) + (y - cy) * (y - cy);
      if (d < bestD) { bestD = d; best = [x, y]; }
    }
  }
  must(best, 'nothing to aim at');
  return best;
}
// a point whose neighbourhood (AR pixels each way, 1 by default) hovers the
// element too: robust to a pixel of difference in an edge
function aimAt(chart, el, r) {
  const zr = chart.getZr();
  const m = r || 1;
  return aimIn(chart, globalBox(el), (x, y, h) => {
    if (h.target !== el) return false;
    for (let dy = -m; dy <= m; dy++) {
      for (let dx = -m; dx <= m; dx++) {
        if (zr.handler.findHover(x + dx, y + dy).target !== el) return false;
      }
    }
    return true;
  });
}

function itemEl(chart, s, i) {
  const sm = chart.getModel().getSeriesByIndex(s);
  return sm.getData().getItemGraphicEl(i);
}

// where an event aims: [kind, ...]
function aimOf(chart, pick) {
  const k = pick[0];
  if (k === 'xy') return [pick[1], pick[2]];
  const s = pick[1];
  const i = pick[2];
  const sm = chart.getModel().getSeriesByIndex(s);
  const view = chart.getViewOfSeriesModel(sm);
  if (k === 'gp') return aimAt(chart, itemEl(chart, s, i));
  if (k === 'gq') return aimAt(chart, view._progressEls[i]);
  if (k === 'rsym') return aimAt(chart, itemEl(chart, s, i).childAt(2).childAt(pick[3]));
  if (k === 'rline') return aimAt(chart, itemEl(chart, s, i).childAt(0));
  if (k === 'rarea') return aimAt(chart, itemEl(chart, s, i).childAt(1));
  if (k === 'item') {
    const el = itemEl(chart, s, i);
    return aimAt(chart, el.isGroup ? el.childAt(0) : el);
  }
  if (k === 'glyph') {
    // the k-th glyph of a pictorial bar
    const g = itemEl(chart, s, i);
    const paths = [];
    g.traverse(el => { if (!el.isGroup && el !== g.__pictorialBarRect) paths.push(el); });
    return aimAt(chart, paths[pick[3]], pick[4]);
  }
  if (k === 'pgap') {
    // inside the bar rect, on no glyph: nothing is hovered there
    const g = itemEl(chart, s, i);
    const rect = g.__pictorialBarRect;
    return aimIn(chart, globalBox(rect), (x, y, h) => !h.target && rect.contain(x, y));
  }
  if (k === 'pclip') {
    // on the glyph's own shape, outside its clip
    const g = itemEl(chart, s, i);
    const paths = [];
    g.traverse(el => { if (!el.isGroup && el !== g.__pictorialBarRect) paths.push(el); });
    const el = paths[pick[3]];
    // four pixels clear of the clip and of the glyph's own edge
    const zr = chart.getZr();
    return aimIn(chart, globalBox(el), (x, y, h) => {
      if (h.target) return false;
      for (let dy = -4; dy <= 4; dy++) {
        for (let dx = -4; dx <= 4; dx++) {
          if (!el.contain(x + dx, y + dy) || zr.handler.findHover(x + dx, y + dy).target) return false;
        }
      }
      return true;
    });
  }
  if (k === 'large') {
    // the middle of large bar i, or of large point i
    let large = null;
    view.group.traverse(el => { if (!large && !el.isGroup && !el.silent && el.shape && el.shape.points) large = el; });
    must(large, 'no large element');
    const p = large.shape.points;
    if (large.type === 'largeBar') {
      // a whole pixel inside the bar across its band (a large bar is often
      // under a pixel wide), the middle of its length
      const bd = large.baseDimIdx;
      const vd = 1 - bd;
      const c = [];
      const lo = p[i * 3 + bd];
      c[bd] = Math.ceil(lo);
      must(c[bd] <= lo + large.barWidth, 'large bar ' + i + ' holds no whole pixel');
      c[vd] = Math.round(p[i * 3 + vd] + p[i * 3 + 2] / 2);
      return c;
    }
    return [Math.round(p[i * 2]), Math.round(p[i * 2 + 1])];
  }
  must(false, 'unknown aim ' + k);
}

// ---------- the published events ----------
const EVENT_TYPES = ['select', 'unselect', 'selectchanged', 'mouseover', 'mouseout', 'click', 'highlight', 'downplay'];
function eventRec(type, e) {
  const o = { type };
  if (type === 'selectchanged') {
    o.selected = JSON.parse(JSON.stringify(e.selected));
    o.isFromClick = e.isFromClick;
    o.fromAction = e.fromAction;
    return o;
  }
  if (type === 'mouseover' || type === 'mouseout' || type === 'click') {
    o.componentType = e.componentType;
    o.seriesIndex = e.seriesIndex == null ? null : e.seriesIndex;
    o.dataIndex = e.dataIndex == null ? null : e.dataIndex;
    return o;
  }
  // an action's own, not refined
  o.seriesIndex = e.seriesIndex == null ? null : e.seriesIndex;
  o.dataIndex = e.dataIndex == null ? null : e.dataIndex;
  if (e.dataIndexInside != null) o.dataIndexInside = e.dataIndexInside;
  if (e.isFromClick) o.isFromClick = true;
  return o;
}

function selectionOf(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    const map = sm.option.selectedMap;
    // an item of no name and no id is keyed 'e\0\0' + its raw index:
    // written '<0>' for the NULs (fpjson drops a \u0000)
    const m = map == null || typeof map !== 'object' ? map
      : Object.fromEntries(Object.keys(map).map(k => [k.replace(/\u0000/g, '<0>'), map[k]]));
    out.push({ s: sm.seriesIndex, map: m == null ? null : JSON.parse(JSON.stringify(m)),
      indices: sm.getSelectedDataIndices().slice() });
  });
  return out;
}

// summarize the per-sample records into fixture elements
function summarize(recs) {
  const seen = new Map();
  const elements = [];
  for (const rec of recs) {
    const presentIdx = [];
    rec.snaps.forEach((s, i) => { if (s) presentIdx.push(i); });
    const keys = new Set();
    presentIdx.forEach(i => Object.keys(rec.snaps[i]).forEach(k => keys.add(k)));
    const lastI = presentIdx[presentIdx.length - 1];
    const final = {};
    const finalText = {};
    const track = {};
    const trackText = {};
    for (const k of [...keys].sort()) {
      const vals = presentIdx.map(i => rec.snaps[i][k]);
      const constant = vals.every(v => v !== undefined && same(v[0], vals[0][0]));
      const last = rec.snaps[lastI][k];
      if (last !== undefined) {
        final[k] = last[0];
        finalText[k] = last[1];
      }
      if (!constant) {
        track[k] = rec.snaps.map(s => (s && s[k] !== undefined ? s[k][0] : null));
        trackText[k] = rec.snaps.map(s => (s && s[k] !== undefined ? s[k][1] : null));
      }
    }
    let id = rec.id;
    const n = seen.get(id) || 0;
    seen.set(id, n + 1);
    if (n) id += '~' + n;
    const everAnim = rec.anim.some(x => x > 0);
    const everState = rec.stateAnim.some(x => x !== '');
    const everStates = rec.snaps.some(s => s && s.states && s.states[0] !== '');
    elements.push({
      id, owner: rec.owner, role: rec.role, type: rec.type, dataIndex: rec.dataIndex, map: rec.map,
      hasEmphasis: rec.hasEmphasis, everStates,
      present: presentIdx.length === SAMPLES.length ? null : presentIdx,
      final, finalText,
      track: Object.keys(track).length ? track : null,
      trackText: Object.keys(track).length ? trackText : null,
      animators: everAnim ? rec.anim : null,
      stateAnimators: everState ? rec.stateAnim : null,
      transition: rec.transition.some(x => x !== '') ? rec.transition : null,
    });
  }
  return elements;
}

// the frame loop: at each sample, its events, then one frame, then the record
function loopOn(chart, c, t1) {
  const zr = chart.getZr();
  const h = zr.handler;
  const events = c.events.map(e => Object.assign({}, e));
  const ids = new Map();
  const recs = [];
  const clips = [];
  const published = [];
  const selection = [];
  let at = 0;
  for (const type of EVENT_TYPES) {
    chart.on(type, e => published.push(Object.assign({ at }, eventRec(type, e))));
  }
  SAMPLES.forEach((t, si) => {
    NOW = t1 + t;
    at = t;
    for (const e of events) {
      if (e.at !== t) continue;
      if (e.type === 'move' || e.type === 'click') {
        const [x, y] = aimOf(chart, e.pick);
        e.x = x;
        e.y = y;
        h.mousemove(raw(x, y));
        if (e.type === 'click') {
          h.mousedown(raw(x, y));
          h.mouseup(raw(x, y));
          h.click(raw(x, y));
        }
      }
      else if (e.type === 'out') {
        e.x = 3;
        e.y = 3;
        h.mousemove(raw(e.x, e.y));
      }
      else if (e.type === 'action') chart.dispatchAction(JSON.parse(JSON.stringify(e.payload)));
      else must(false, 'unknown event ' + e.type);
    }
    zr.animation.update();
    const zList = zr.storage.getDisplayList(true);
    const zIndex = new Map();
    zList.forEach((el, i) => zIndex.set(el, i));
    clips.push(clipCount(zr));
    selection.push(selectionOf(chart));
    const parts = seriesParts(chart);
    const groups = [];
    chart.getModel().eachSeries(sm => {
      const v = chart.getViewOfSeriesModel(sm);
      if (v) groups.push({ owner: 'series' + sm.seriesIndex + ':' + sm.subType, group: v.group });
    });
    for (const mv of markerViews(chart)) {
      markerParts(mv, parts);
      groups.push({ owner: mv.owner, group: mv.group });
    }
    for (const v of groups) {
      for (const it of walkView(v.group)) {
        if (it.el.isGroup) continue;
        let rec = ids.get(it.el);
        if (!rec) {
          const ecd = ecDataOf(it.el);
          rec = {
            id: v.owner + '/' + (it.path === '' ? 'root' : it.path),
            owner: v.owner, role: it.role, type: it.el.type,
            dataIndex: ecd && ecd.dataIndex != null ? ecd.dataIndex : null,
            map: parts.get(it.el) || null,
            hasEmphasis: !!(it.el.states && it.el.states.emphasis),
            snaps: new Array(SAMPLES.length).fill(null),
            anim: new Array(SAMPLES.length).fill(0),
            stateAnim: new Array(SAMPLES.length).fill(''),
            transition: new Array(SAMPLES.length).fill(''),
          };
          ids.set(it.el, rec);
          recs.push(rec);
        }
        rec.snaps[si] = snap(it.el, zIndex.get(it.el));
        rec.anim[si] = it.el.animators ? it.el.animators.length : 0;
        rec.stateAnim[si] = stateAnims(it.el).join(' ');
        const st = it.el.stateTransition;
        rec.transition[si] = st ? st.duration + '/' + st.easing + '/' + (st.delay == null ? '' : st.delay) : '';
      }
    }
  });
  const evOut = events.map(e => {
    const o = { at: e.at, type: e.type };
    if (e.x != null) { o.x = e.x; o.y = e.y; }
    if (e.pick) o.pick = e.pick;
    if (e.payload) o.payload = e.payload;
    return o;
  });
  // a selection that never changes is written once
  const selOut = selection.every(x => same(x, selection[0])) ? [selection[0]] : selection;
  return { clips, elements: summarize(recs), events: evOut, published, selection: selOut };
}

// EVERY CASE ON ITS OWN STRETCH OF THE CLOCK, later than the last one's --
// across both generations: zrender's throttle (the large bar's dataIndex
// handler) is module-wide, and a clock going back would leave its call
// waiting on a timer that never runs
let caseBase = T_BASE;
function runCase(c) {
  CUR_CASE = c;
  caseBase += CASE_STRIDE;
  NOW = caseBase;
  rngState = SEED;
  const chart = newChart();
  try {
    chart.setOption(JSON.parse(JSON.stringify(c.option)));
    settle(chart, caseBase);
    return loopOn(chart, c, caseBase + T1_OFFSET);
  }
  finally {
    chart.dispose();
  }
}

// ---------- the cases ----------
const C0 = '#5470c6';
const C1 = '#91cc75';
const C2 = '#fac858';
const C3 = '#ee6666';
const CATS = ['A', 'B', 'C', 'D', 'E'];
const over = (at, pick) => ({ at, type: 'move', pick });
const out = at => ({ at, type: 'out' });
const click = (at, pick) => ({ at, type: 'click', pick });
const act = (at, payload) => ({ at, type: 'action', payload });

// A. gauge
const gauge = (s, extra) => Object.assign({ color: [C0, C1, C2] }, extra || {}, {
  series: [Object.assign({ type: 'gauge', radius: '80%', progress: { show: true, width: 14 },
    pointer: { width: 10 }, detail: { show: false }, title: { show: false },
    data: [{ value: 60, name: 'a' }] }, s || {})],
});
const GAUGE = [
  { id: 'gauge-hover-pointer', note: 'hover the pointer at 0: its fill lifts (z2EmphasisLift 0: no z2 change), the progress '
    + 'arc is another dispatcher and stays; out at 500',
    option: gauge(), events: [over(0, ['gp', 0, 0]), out(500)] },
  { id: 'gauge-hover-progress', note: 'hover the progress arc at 0: it lifts alone, the pointer stays; out at 500',
    option: gauge(), events: [over(0, ['gq', 0, 0]), out(500)] },
  { id: 'gauge-action', note: 'highlight dataIndex 0 at 0: the item graphic element is the pointer, the arc does not '
    + 'change; downplay at 500',
    option: gauge(), events: [act(0, { type: 'highlight', seriesIndex: 0, dataIndex: 0 }),
      act(500, { type: 'downplay', seriesIndex: 0, dataIndex: 0 })] },
  { id: 'gauge-focus', note: 'two items, emphasis.focus self, titles and readings shown: hovering the second pointer blurs '
    + 'every other pointer and arc of the series (the texts have no states); out at 500',
    option: gauge({ emphasis: { focus: 'self' }, progress: { show: true, width: 10 },
      title: { show: true, offsetCenter: [0, '30%'] }, detail: { show: true, offsetCenter: [0, '55%'], fontSize: 14 },
      data: [{ value: 40, name: 'a', title: { offsetCenter: ['-30%', '30%'] }, detail: { offsetCenter: ['-30%', '55%'] } },
        { value: 75, name: 'b', title: { offsetCenter: ['30%', '30%'] }, detail: { offsetCenter: ['30%', '55%'] } }] }),
    events: [over(0, ['gp', 0, 1]), out(500)] },
  { id: 'gauge-select', note: 'selectedMode single and a select colour: a click on the pointer selects (z2 + 9), a click on '
    + 'the arc dispatches select again (the arc is never flagged selected), a click on the pointer unselects',
    option: gauge({ selectedMode: 'single', select: { itemStyle: { color: C3 } } }),
    events: [click(0, ['gp', 0, 0]), out(300), click(500, ['gq', 0, 0]), out(700), click(900, ['gp', 0, 0]), out(1200)] },
  { id: 'gauge-no-pointer', note: 'pointer.show false: highlight finds no item graphic element (nothing changes); the arc '
    + 'is still hovered at 400; out at 800',
    option: gauge({ pointer: { show: false } }),
    events: [act(0, { type: 'highlight', seriesIndex: 0, dataIndex: 0 }), act(200, { type: 'downplay', seriesIndex: 0, dataIndex: 0 }),
      over(400, ['gq', 0, 0]), out(800)] },
  { id: 'gauge-emphasis-declared', note: 'emphasis.itemStyle colour and border on both: hover the pointer, then the arc',
    option: gauge({ emphasis: { itemStyle: { color: C3, borderColor: '#333333', borderWidth: 2 } } }),
    events: [over(0, ['gp', 0, 0]), over(500, ['gq', 0, 0]), out(1000)] },
];

// B. radar
const radar = (s, extra) => Object.assign({ color: [C0, C1, C2] }, {
  radar: { radius: '65%', indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 },
    { name: 'd', max: 10 }, { name: 'e', max: 10 }] },
  series: [Object.assign({ type: 'radar', symbolSize: 10,
    data: [{ value: [6, 8, 4, 7, 5], name: 'p' }, { value: [3, 4, 9, 2, 8], name: 'q' }] }, s || {})],
}, extra || {});
const RADAR = [
  { id: 'radar-hover', note: 'hover a symbol of the first item at 0: the whole item group enters emphasis -- the polyline\'s '
    + 'stroke lifts, the symbols\' fill (white, an emptyCircle) lifts, every z2 + 10; out at 500',
    option: radar(), events: [over(0, ['rsym', 0, 0, 1]), out(500)] },
  { id: 'radar-hover-line', note: 'hover the second item\'s polyline at 0; out at 500',
    option: radar(), events: [over(0, ['rline', 0, 1]), out(500)] },
  { id: 'radar-area', note: 'areaStyle {}: the polygon shows (opacity 0.7); hover it at 0 (its fill lifts); out at 500',
    option: radar({ areaStyle: {} }), events: [over(0, ['rarea', 0, 1]), out(500)] },
  { id: 'radar-focus-self', note: 'emphasis.focus self: hovering the first item blurs the second, whole; out at 500',
    option: radar({ emphasis: { focus: 'self' } }), events: [over(0, ['rsym', 0, 0, 2]), out(500)] },
  { id: 'radar-action', note: 'highlight dataIndex 1 at 0, downplay at 500',
    option: radar(), events: [act(0, { type: 'highlight', seriesIndex: 0, dataIndex: 1 }),
      act(500, { type: 'downplay', seriesIndex: 0, dataIndex: 1 })] },
  { id: 'radar-select', note: 'selectedMode single, select.lineStyle colour and width: a click on a symbol selects the item '
    + '(z2 + 9), a second click unselects',
    option: radar({ selectedMode: 'single', select: { lineStyle: { color: C3, width: 4 } } }),
    events: [click(0, ['rsym', 0, 0, 0]), out(300), click(500, ['rsym', 0, 0, 0]), out(800)] },
  { id: 'radar-emphasis-area', note: 'no areaStyle but emphasis.areaStyle: the polygon is ignored at rest and shows in emphasis',
    option: radar({ emphasis: { areaStyle: { color: C3 } } }), events: [over(0, ['rsym', 0, 0, 3]), out(500)] },
  { id: 'radar-two-series', note: 'two radar series, the second with focus series: hovering it blurs the first (one radar '
    + 'coordinate system)',
    option: { color: [C0, C1], radar: { radius: '65%', indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 },
      { name: 'c', max: 10 }, { name: 'd', max: 10 }] },
    series: [{ type: 'radar', symbolSize: 8, data: [{ value: [6, 8, 4, 7], name: 'p' }] },
      { type: 'radar', symbolSize: 8, emphasis: { focus: 'series' }, data: [{ value: [3, 4, 9, 2], name: 'q' }] }] },
    events: [over(0, ['rsym', 1, 0, 2]), out(500)] },
];

// C. the markers of a blurred series
const marked = (s0, s1) => ({
  color: [C0, C1], xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40 },
  series: [Object.assign({ type: 'bar', data: [5, 20, 36, 10, 18],
    markPoint: { data: [{ type: 'max', name: 'max' }] },
    markLine: { data: [{ type: 'average', name: 'avg' }] },
    markArea: { data: [[{ xAxis: 'A' }, { xAxis: 'B' }]] } }, s0 || {}),
  Object.assign({ type: 'bar', data: [8, 12, 6, 30, 4], emphasis: { focus: 'series' } }, s1 || {})],
});
const MARKERS = [
  { id: 'markers-blur', note: 'hover the second series (focus series) at 0: the first is blurred and its markPoint, markLine '
    + '(line, end symbols, label) and markArea fade with it; out at 500',
    option: marked(), events: [over(0, ['item', 1, 3]), out(500)] },
  { id: 'markers-self', note: 'focus self on the first series: hovering its bar blurs the series itself, its markers too, '
    + 'and the second series (one grid); out at 500',
    option: marked({ emphasis: { focus: 'self' } }), events: [over(0, ['item', 0, 1]), out(500)] },
  { id: 'markers-action', note: 'highlight the second series\' item 2 by action at 0 (focus series): the first and its '
    + 'markers blur; downplay at 500',
    option: marked(), events: [act(0, { type: 'highlight', seriesIndex: 1, dataIndex: 2 }),
      act(500, { type: 'downplay', seriesIndex: 1, dataIndex: 2 })] },
  { id: 'markers-declared', note: 'a declared blur opacity on the markPoint (0.5) and the markLine (0.4); the markArea has '
    + 'emphasis disabled (no state proxy: its blur state is empty and changes nothing)',
    option: marked({ markPoint: { data: [{ type: 'max', name: 'max' }], blur: { itemStyle: { opacity: 0.5 } } },
      markLine: { data: [{ type: 'average', name: 'avg' }], blur: { lineStyle: { opacity: 0.4 } } },
      markArea: { data: [[{ xAxis: 'A' }, { xAxis: 'B' }]], emphasis: { disabled: true } } }),
    events: [over(0, ['item', 1, 3]), out(500)] },
];

// D. a click on a large element
const lv = n => Array.from({ length: n }, (_, i) => 10 + ((i * 37) % 80));
const LARGE = [
  { id: 'large-bar-click', note: '450 large bars, selectedMode single: a click on bar 100 dispatches select (the path is '
    + 'never flagged selected: a second click selects again); no state changes on the large path',
    option: { animation: false, xAxis: { type: 'category', data: lv(450).map((_, i) => 'c' + i) }, yAxis: { type: 'value' },
      series: [{ type: 'bar', large: true, selectedMode: 'single', data: lv(450) }] },
    events: [click(0, ['large', 0, 100]), click(400, ['large', 0, 100]), click(800, ['large', 0, 300])] },
  { id: 'large-bar-click-nomode', note: 'no selectedMode: the click still dispatches select, selectchanged has nothing',
    option: { animation: false, xAxis: { type: 'category', data: lv(450).map((_, i) => 'c' + i) }, yAxis: { type: 'value' },
      series: [{ type: 'bar', large: true, data: lv(450) }] },
    events: [click(0, ['large', 0, 200])] },
  { id: 'large-scatter-click', note: 'a large scatter (threshold 20), selectedMode multiple: clicks on points 5 and 9',
    option: { animation: false, xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value', min: 0, max: 100 },
      series: [{ type: 'scatter', large: true, largeThreshold: 20, symbolSize: 10, selectedMode: 'multiple',
        data: Array.from({ length: 30 }, (_, i) => [3 + i * 3, 10 + ((i * 29) % 80)]) }] },
    events: [click(0, ['large', 0, 5]), click(400, ['large', 0, 9])] },
  { id: 'large-held-blur', note: 'a large bar series under two scatters: highlighting scatter 1 (focus series) by action at 0 '
    + 'blurs scatter 2; the pointer over a large bar at 400 and off it at 800 -- the large path is no highDownDispatcher, '
    + 'so its mouseover / mouseout leave the blur alone; downplay at 1200',
    option: { animation: false, xAxis: { type: 'category', data: lv(450).map((_, i) => 'c' + i) },
      yAxis: { type: 'value', max: 100 },
      series: [{ type: 'bar', large: true, data: lv(450) },
        { type: 'scatter', symbolSize: 10, emphasis: { focus: 'series' }, data: [[20, 95], [220, 95], [420, 95]] },
        { type: 'scatter', symbolSize: 10, data: [[40, 95], [240, 95], [440, 95]] }] },
    events: [act(0, { type: 'highlight', seriesIndex: 1, dataIndex: 0 }), over(400, ['large', 0, 100]), out(800),
      act(1200, { type: 'downplay', seriesIndex: 1, dataIndex: 0 })] },
];

// E. a label hidden at rest
const pie = s => ({
  color: [C0, C1, C2, C3],
  series: [Object.assign({ type: 'pie', radius: '50%',
    data: [{ name: 'a', value: 10 }, { name: 'b', value: 20 }, { name: 'c', value: 30 }, { name: 'd', value: 15 }] }, s || {})],
});
const funnel = s => ({
  color: [C0, C1, C2, C3],
  series: [Object.assign({ type: 'funnel', left: 60, right: 120,
    data: [{ name: 'a', value: 60 }, { name: 'b', value: 40 }, { name: 'c', value: 20 }, { name: 'd', value: 80 }] }, s || {})],
});
const LABELS = [
  { id: 'pie-label-emphasis', note: 'label.show false, emphasis.label.show true: the label is built and laid out, ignored at '
    + 'rest; hovering slice b at 0 shows it and its label line; out at 500',
    option: pie({ label: { show: false }, emphasis: { label: { show: true } } }), events: [over(0, ['item', 0, 1]), out(500)] },
  { id: 'pie-label-select', note: 'label.show false, select.label.show true, selectedMode single: select b at 0 (the label '
    + 'shows, moved with the slice), unselect at 500',
    option: pie({ selectedMode: 'single', label: { show: false }, select: { label: { show: true } } }),
    events: [act(0, { type: 'select', seriesIndex: 0, dataIndex: 1 }), act(500, { type: 'unselect', seriesIndex: 0, dataIndex: 1 })] },
  { id: 'pie-label-inside', note: 'label.show false, position inside, emphasis shows it: hover slice c at 0; out at 500',
    option: pie({ label: { show: false, position: 'inside' }, emphasis: { label: { show: true } } }),
    events: [over(0, ['item', 0, 2]), out(500)] },
  { id: 'funnel-label-emphasis', note: 'a funnel\'s label.show false: its default emphasis.label.show true shows the label and '
    + 'its line under the hover; hover band b at 0, out at 500',
    option: funnel({ label: { show: false } }), events: [over(0, ['item', 0, 1]), out(500)] },
  { id: 'funnel-label-inside', note: 'a funnel\'s inside label hidden at rest, shown under the hover of band d',
    option: funnel({ label: { show: false, position: 'inside' } }), events: [over(0, ['item', 0, 3]), out(500)] },
  { id: 'bar-item-label-emphasis', note: 'a bar series whose emphasis hides its labels; bar 1 writes label.show of its own, which '
    + 'fillDataTextStyle copies to its emphasis.label.show (defaultEmphasis on the data item): hovering bar 1 at 0 keeps '
    + 'its label, hovering bar 0 at 800 hides bar 0\'s',
    option: { animation: false, color: [C0], xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'bar', label: { show: true, position: 'top' }, emphasis: { label: { show: false } },
        data: [5, { value: 20, label: { show: true } }, 36] }] },
    events: [over(0, ['item', 0, 1]), out(500), over(800, ['item', 0, 0]), out(1200)] },
];

// F. a pictorial bar's hit target
const PICTORIAL = [
  { id: 'pictorial-hit', note: 'repeated circles with margins: the glyph is hovered (emphasis, mouseover); the margin '
    + 'between two glyphs, inside the bar rect, hovers nothing (mouseout); the glyph again; out',
    option: { color: [C0], xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'pictorialBar', symbol: 'circle', symbolRepeat: true, symbolSize: [14, 14], symbolMargin: '80%',
        data: [5, 20, 36, 10, 18] }] },
    events: [over(0, ['glyph', 0, 2, 1]), over(400, ['pgap', 0, 2]), over(800, ['glyph', 0, 2, 0]), out(1200)] },
  { id: 'pictorial-clip', note: 'symbolClip: the rect glyph is as long as symbolBoundingData and clipped at the value; a '
    + 'point on the glyph past the clip hovers nothing, one inside it hovers the bar',
    option: { color: [C0], xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'pictorialBar', symbol: 'rect', symbolClip: true, symbolBoundingData: 40, symbolSize: ['60%', '100%'],
        data: [5, 20, 30, 10, 18] }] },
    events: [over(0, ['pclip', 0, 1, 0]), over(400, ['glyph', 0, 1, 0, 4]), out(800)] },
];

// G. [R2-B]
const R2B = [
  { id: 'radar-order', order: true, note: 'a radar item\'s group is polyline, polygon, symbols: at one z2 the polygon (areaStyle, '
    + 'opaque) is painted over the polyline -- at rest and lifted together under the hover of item 1 at 0; out at 500',
    option: radar({ areaStyle: { opacity: 1 }, lineStyle: { width: 4 } }), events: [over(0, ['rsym', 0, 1, 2]), out(500)] },
  { id: 'radar-held-self', note: 'emphasis.focus self: item 0 highlighted by action at 0 (the others blur, its group holds the '
    + 'bit); hovering item 1 at 300 runs blurSeries again -- it spares only an element that holds the bit itself, so item 0\'s '
    + 'polyline, polygon and symbols enter blur under the held group; out at 700 (allLeaveBlur: they go to normal, the group '
    + 'still held); downplay at 1100',
    option: radar({ emphasis: { focus: 'self' }, areaStyle: {},
      data: [{ value: [6, 8, 4, 7, 5], name: 'p' }, { value: [3, 4, 9, 2, 8], name: 'q' }, { value: [8, 2, 6, 5, 3], name: 'r' }] }),
    events: [act(0, { type: 'highlight', seriesIndex: 0, dataIndex: 0 }), over(300, ['rsym', 0, 1, 0]), out(700),
      act(1100, { type: 'downplay', seriesIndex: 0, dataIndex: 0 })] },
  { id: 'scatter-label-follows', labelPlace: true, note: 'a scatter\'s top label rides its symbol as the hover scales it '
    + '(updateInnerText every frame on the path as drawn): over point 1 at 0, out at 500',
    option: { color: [C0], xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'scatter', symbolSize: 20, itemStyle: { opacity: 1 }, label: { show: true, position: 'top', formatter: 'p{c}' },
        data: [[2, 3], [5, 6], [8, 4]] }] },
    events: [over(0, ['item', 0, 1]), out(500)] },
  { id: 'graph-label-follows', labelPlace: true, note: 'a graph node\'s right label rides the node\'s emphasis scale (the '
    + 'state runs on the symbol\'s own proxy) through the transition and at rest: over node 1 at 0, out at 500',
    option: { color: [C0], series: [{ type: 'graph', layout: 'none', symbolSize: 30, label: { show: true, position: 'right' },
      left: 60, top: 60, width: 280, height: 180,
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 50 }, { name: 'c', x: 200, y: 0 }],
      links: [{ source: 'a', target: 'b' }] }] },
    events: [over(0, ['item', 0, 1]), out(500)] },
  { id: 'radial-label-follows', labelPlace: true, note: 'a radial tree\'s turned label rides its hovered node (the box '
    + 'scaled about its centre, the turn kept): over A at 0, out at 500',
    option: { series: [{ type: 'tree', layout: 'radial', left: 60, top: 40, bottom: 40, right: 60, symbolSize: 14,
      expandAndCollapse: false, label: { show: true },
      data: [{ name: 'root', children: [{ name: 'A', children: [{ name: 'A1' }, { name: 'A2' }] }, { name: 'B' }, { name: 'C' }] }] }] },
    events: [over(0, ['item', 0, 2]), out(500)] },
  { id: 'radar-dash', dash: true, note: 'lineStyle.type: the series\' dashed, an item\'s own dotted at width 3, an item\'s '
    + 'own [6, 3] array; hovering the dotted one keeps its dash (the emphasis states write no type)',
    option: radar({ lineStyle: { type: 'dashed', width: 2 },
      data: [{ value: [6, 8, 4, 7, 5], name: 'p' }, { value: [3, 4, 9, 2, 8], name: 'q', lineStyle: { type: 'dotted', width: 3 } },
        { value: [8, 2, 6, 5, 3], name: 'r', lineStyle: { type: [6, 3] } }] }),
    events: [over(0, ['rline', 0, 1]), out(500)] },
  { id: 'tree-label-follows', labelPlace: true, note: 'a tree node\'s label rides its scaled symbol (its own label box): '
    + 'over A at 0, out at 500',
    option: { series: [{ type: 'tree', left: 40, top: 30, bottom: 30, right: 120, symbolSize: 16, expandAndCollapse: false,
      label: { show: true, position: 'left' }, leaves: { label: { position: 'right' } },
      data: [{ name: 'root', children: [{ name: 'A', children: [{ name: 'A1' }] }, { name: 'B' }] }] }] },
    events: [over(0, ['item', 0, 2]), out(500)] },
];

// H. [R2-I1]
const R2I1 = [
  { id: 'scatter-label-opacity', note: 'a scatter\'s label at its symbol\'s 0.8 (ScatterSeries itemStyle.opacity, handed '
    + 'over as defaultOpacity): at rest, through a hover of point 1 at 0 and out at 500 (the emphasis style has no opacity)',
    option: { color: [C0], xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'scatter', symbolSize: 20, label: { show: true, position: 'top', formatter: 'p{c}' },
        data: [[2, 3], [5, 6], [8, 4]] }] },
    events: [over(0, ['item', 0, 1]), out(500)] },
  { id: 'bar-label-opacity', note: 'a bar series\' itemStyle.opacity 0.5, item 1 its own 0.3, item 2 a label.opacity 0.9 of '
    + 'its own: the labels at 0.5, 0.3, 0.9; hover item 1 at 0, out at 500',
    option: { color: [C0], xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'bar', itemStyle: { opacity: 0.5 }, label: { show: true, position: 'top' },
        data: [10, { value: 20, itemStyle: { opacity: 0.3 } }, { value: 30, label: { opacity: 0.9 } }] }] },
    events: [over(0, ['item', 0, 1]), out(500)] },
  { id: 'line-label-opacity', note: 'a line\'s symbols at itemStyle.opacity 0.6: their labels at 0.6; hover point 2 at 0, '
    + 'out at 500',
    option: { color: [C0], xAxis: { type: 'category', data: ['A', 'B', 'C', 'D'] }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'line', symbolSize: 10, itemStyle: { opacity: 0.6 }, label: { show: true },
        data: [10, 25, 18, 30] }] },
    events: [over(0, ['item', 0, 2]), out(500)] },
  { id: 'pie-label-opacity', note: 'a pie\'s itemStyle.opacity 0.5, slice b its own 0.3, slice c a label.opacity 0.9 of its '
    + 'own (PieView: defaultOpacity the visual opacity); the label lines go with the slices\' style; hover b at 0, out at 500',
    option: pie({ itemStyle: { opacity: 0.5 }, data: [{ name: 'a', value: 10 }, { name: 'b', value: 20, itemStyle: { opacity: 0.3 } },
      { name: 'c', value: 30, label: { opacity: 0.9 } }, { name: 'd', value: 15 }] }),
    events: [over(0, ['item', 0, 1]), out(500)] },
  { id: 'funnel-label-opacity', note: 'a funnel\'s itemStyle.opacity 0.6, item c a label.opacity 0.25 (FunnelView: '
    + 'defaultOpacity the polygon\'s style.opacity); hover b at 0, out at 500',
    option: funnel({ itemStyle: { opacity: 0.6 }, data: [{ name: 'a', value: 60 }, { name: 'b', value: 40 },
      { name: 'c', value: 20, label: { opacity: 0.25 } }, { name: 'd', value: 80 }] }),
    events: [over(0, ['item', 0, 1]), out(500)] },
  { id: 'global-text-opacity', note: 'the root textStyle.opacity 0.7 under every label without one of its own (createTextStyle\'s '
    + 'globalTextStyle, before defaultOpacity): a bar series at itemStyle.opacity 0.5, item 1 a label.opacity 0.2; hover bar 0 '
    + 'at 0, out at 500',
    option: { color: [C0, C1, C2, C3], textStyle: { opacity: 0.7 },
      xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'bar', itemStyle: { opacity: 0.5 }, label: { show: true, position: 'top' },
        data: [10, { value: 20, label: { opacity: 0.2 } }, 30] }] },
    events: [over(0, ['item', 0, 0]), out(500)] },
  { id: 'pie-global-text-opacity', note: 'a pie under the root textStyle.opacity 0.7, slice b a label.opacity 0.2 of its own; '
    + 'hover a at 0, out at 500',
    option: Object.assign(pie({ data: [{ name: 'a', value: 10 }, { name: 'b', value: 20, label: { opacity: 0.2 } },
      { name: 'c', value: 30 }] }), { textStyle: { opacity: 0.7 } }),
    events: [over(0, ['item', 0, 0]), out(500)] },
  { id: 'radar-label-line-states', note: 'radar point labels with label lines (labelLine.show, labelLayout dy -14 so the '
    + 'line has a length), focus self: emphasis.labelLine a colour and width 3, blur.labelLine.show false; item q\'s '
    + 'emphasis.label.show false (its lines go with its labels). Hover p at 0 (p emphasis, q blur), out at 500; hover q at '
    + '800, out at 1200',
    option: radar({ emphasis: { focus: 'self', labelLine: { lineStyle: { color: C3, width: 3 } } },
      blur: { labelLine: { show: false } },
      label: { show: true, position: 'right', distance: 12 }, labelLine: { show: true, lineStyle: { width: 1 } },
      labelLayout: { dy: -14 },
      data: [{ value: [6, 8, 4, 7, 5], name: 'p' }, { value: [3, 4, 9, 2, 8], name: 'q', emphasis: { label: { show: false } } }] }),
    events: [over(0, ['rsym', 0, 0, 1]), out(500), over(800, ['rsym', 0, 1, 2]), out(1200)] },
];

// [R2-I3] the leftovers: a pie beside a bar (its squeezed label), states' dashes
const R2I3 = [
  { id: 'bar-pie-label', note: '[R2-I3] a bar and a pie in one chart (R2-I1 split them): the pie at 30% beside the bars, '
    + 'itemStyle.opacity 0.5, slice b a label.opacity 0.2 of its own -- avoidOverlap leaves b\'s label a width of 3, so its '
    + 'truncated text is empty and the Text is there all the same; hover slice b at 0, out at 500',
    option: { color: [C0, C1, C2, C3], xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value', max: 40 },
      grid: { left: 40, width: 150 },
      series: [{ type: 'bar', label: { show: true, position: 'top' }, data: [10, 20, 30] },
        { type: 'pie', radius: '30%', center: ['75%', '50%'], itemStyle: { opacity: 0.5 },
          data: [{ name: 'a', value: 10 }, { name: 'b', value: 20, label: { opacity: 0.2 } }, { name: 'c', value: 30 }] }] },
    events: [over(0, ['item', 1, 1]), out(500)] },
  { id: 'bar-state-dash', dash: true, dashOff: true, note: '[R2-I3] a state\'s borderType (lineDash: no animation prop, set '
    + 'at once) and borderDashOffset (lineDashOffset: tweened): bars bordered #000 at 2, emphasis [6, 3] at 4, bar 1 its own '
    + 'emphasis borderDashOffset 9; select dotted in #000 (selectedMode single; no theme colour). Hover bar 0 at 0, out at 500, click bar 1 at 800, out '
    + 'at 1200',
    option: { color: [C0], xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'bar', selectedMode: 'single', itemStyle: { borderColor: '#000', borderWidth: 2 },
        emphasis: { itemStyle: { borderType: [6, 3], borderDashOffset: 4 } }, select: { itemStyle: { borderType: 'dotted', borderColor: '#000' } },
        data: [10, { value: 20, emphasis: { itemStyle: { borderDashOffset: 9 } } }, 30] }] },
    events: [over(0, ['item', 0, 0]), out(500), click(800, ['item', 0, 1]), out(1200)] },
  { id: 'line-state-dash', dash: true, dashOff: true, note: '[R2-I3] a line\'s emphasis lineStyle: type [3, 3] and dashOffset '
    + '6 over its dashed at 2 (emphasis width bolder); highlight the series by action at 0, downplay at 500',
    option: { color: [C0], xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'line', lineStyle: { type: 'dashed', width: 2 }, emphasis: { lineStyle: { type: [3, 3], dashOffset: 6 } },
        data: [10, 20, 30] }] },
    events: [act(0, { type: 'highlight', seriesIndex: 0 }), act(500, { type: 'downplay', seriesIndex: 0 })] },
  { id: 'radar-state-dash', dash: true, dashOff: true, note: '[R2-I3] a radar ring\'s emphasis lineStyle: type dotted and '
    + 'dashOffset 2 (R2-B: the states\' type was not read); hover a symbol of p at 0, out at 500',
    option: radar({ lineStyle: { width: 2 }, emphasis: { lineStyle: { type: 'dotted', dashOffset: 2 } } }),
    events: [over(0, ['rsym', 0, 0, 1]), out(500)] },
];

// [R2-I4] a dash written as a word is normalised against the width the
// frame draws (canvas getLineDash per brush): where a state tweens the width
// the dash follows it, the state's word and the rest's alike
const R2I4 = [
  { id: 'bar-dash-word-tween', dash: true, note: '[R2-I4] series 0: bars bordered #000 at 1, emphasis borderWidth 5 and '
    + 'borderType dashed (the state\'s word against the tweening width); series 1: bars bordered #000 at 1 dotted, emphasis '
    + 'borderWidth 6 alone (the rest\'s word against it). Hover bar 0 of series 0 at 0, out at 500, bar 1 of series 1 at '
    + '800, out at 1200',
    option: { color: [C0, C1], xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 1 },
        emphasis: { itemStyle: { borderWidth: 5, borderType: 'dashed' } }, data: [10, 20, 30] },
      { type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 1, borderType: 'dotted' },
        emphasis: { itemStyle: { borderWidth: 6 } }, data: [12, 22, 32] }] },
    events: [over(0, ['item', 0, 0]), out(500), over(800, ['item', 1, 1]), out(1200)] },
  { id: 'bar-dash-word-still', dash: true, note: '[R2-I4] the same with animation false (no state transition): the '
    + 'rest\'s dotted at 1 under emphasis borderWidth 6 is [6] at once; the state\'s dashed at 5 is [20, 10]. Hover bar 1 '
    + 'of series 1 at 0, out at 300, bar 0 of series 0 at 500, out at 800',
    option: { animation: false, color: [C0, C1], xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 1 },
        emphasis: { itemStyle: { borderWidth: 5, borderType: 'dashed' } }, data: [10, 20, 30] },
      { type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 1, borderType: 'dotted' },
        emphasis: { itemStyle: { borderWidth: 6 } }, data: [12, 22, 32] }] },
    events: [over(0, ['item', 1, 1]), out(300), over(500, ['item', 0, 0]), out(800)] },
];

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

// ---------- guards ----------
const byId = (cs, id) => cs.find(c => c.id === id);
const elOf = (c, part, s) => c.elements.find(e => e.map && e.map.part === part && (s == null || e.map.s === s)
  && (e.map.row === -1 || true));
const elRow = (c, s, row, part) => c.elements.find(e => e.map && e.map.s === s && e.map.row === row && e.map.part === part);
const statesAt = (el, ms) => {
  const i = SAMPLES.indexOf(ms);
  return el.trackText && el.trackText.states ? el.trackText.states[i] : el.finalText.states;
};
const numAt = (el, key, ms) => {
  const i = SAMPLES.indexOf(ms);
  return el.trackText && el.trackText[key] ? el.trackText[key][i] : el.finalText[key];
};
function guards(cases) {
  const out = [];
  const g = (name, ok, detail) => {
    if (process.env.ORACLE_LOOSE && !ok) console.log('guard ' + name + ': ' + detail);
    else must(ok, 'guard ' + name + ': ' + detail);
    out.push(name);
  };
  // A1. the pointer's hover leaves the arc alone, and its z2 does not move
  {
    const c = byId(cases, 'gauge-hover-pointer');
    const p = elRow(c, 0, 0, 'host');
    const q = elRow(c, 0, 0, 'peer');
    g('gauge-pointer-alone', statesAt(p, 450) === 'emphasis' && statesAt(q, 450) === '' && numAt(p, 'z2', 450) === numAt(p, 'z2', 0),
      [statesAt(p, 450), statesAt(q, 450), numAt(p, 'z2', 450)].join(' '));
  }
  {
    const c = byId(cases, 'gauge-hover-progress');
    const p = elRow(c, 0, 0, 'host');
    const q = elRow(c, 0, 0, 'peer');
    g('gauge-arc-alone', statesAt(q, 450) === 'emphasis' && statesAt(p, 450) === '', [statesAt(p, 450), statesAt(q, 450)].join(' '));
  }
  {
    const c = byId(cases, 'gauge-action');
    g('gauge-action-pointer-only', statesAt(elRow(c, 0, 0, 'host'), 450) === 'emphasis'
      && statesAt(elRow(c, 0, 0, 'peer'), 450) === '', 'gauge-action');
  }
  {
    const c = byId(cases, 'gauge-focus');
    g('gauge-focus-blurs-the-rest', statesAt(elRow(c, 0, 0, 'host'), 450) === 'blur' && statesAt(elRow(c, 0, 0, 'peer'), 450) === 'blur'
      && statesAt(elRow(c, 0, 1, 'peer'), 450) === 'blur' && statesAt(elRow(c, 0, 1, 'host'), 450) === 'emphasis', 'gauge-focus');
    g('gauge-texts-have-no-states', c.elements.filter(e => e.type === 'text').every(e => !e.everStates), 'gauge-focus texts');
  }
  {
    const c = byId(cases, 'gauge-select');
    const sel = c.published.filter(e => e.type === 'select' || e.type === 'unselect').map(e => e.type).join(',');
    g('gauge-arc-click-selects-again', sel === 'select,select,unselect', sel);
  }
  {
    const c = byId(cases, 'gauge-no-pointer');
    const q = elRow(c, 0, 0, 'peer');
    g('gauge-no-pointer-action-nothing', statesAt(q, 100) === '' && statesAt(q, 750) === 'emphasis', 'gauge-no-pointer');
  }
  // B. the radar item is one dispatcher
  {
    const c = byId(cases, 'radar-hover');
    g('radar-whole-item', ['host', 'rsym0', 'rsym4'].every(p => statesAt(elRow(c, 0, 0, p), 450) === 'emphasis')
      && statesAt(elRow(c, 0, 1, 'host'), 450) === '', 'radar-hover');
    const a = elRow(c, 0, 0, 'rarea');
    g('radar-polygon-ignored', numAt(a, 'ignore', 450) === true, 'radar-hover polygon');
  }
  {
    const c = byId(cases, 'radar-emphasis-area');
    const a = elRow(c, 0, 0, 'rarea');
    g('radar-emphasis-area-shows', numAt(a, 'ignore', 1600) === true && numAt(a, 'ignore', 450) === false, 'radar-emphasis-area');
  }
  {
    const c = byId(cases, 'radar-focus-self');
    g('radar-focus-blurs-item', ['host', 'rsym0'].every(p => statesAt(elRow(c, 0, 1, p), 450) === 'blur'), 'radar-focus-self');
  }
  // C. the markers fade
  {
    const c = byId(cases, 'markers-blur');
    const mk = c.elements.filter(e => e.map && e.map.row === -1 && e.map.s === 0);
    g('markers-blur', mk.length >= 6 && mk.every(e => statesAt(e, 450) === 'blur' && statesAt(e, 1000) === ''),
      mk.map(e => e.map.part + ':' + statesAt(e, 450)).join(' '));
    g('markers-fade-opacity', mk.filter(e => e.map.part.indexOf('#') < 0).every(e => numAt(e, 'style.opacity', 450) !== numAt(e, 'style.opacity', 1600)),
      mk.map(e => e.map.part + ':' + numAt(e, 'style.opacity', 450)).join(' '));
  }
  {
    const c = byId(cases, 'markers-declared');
    const ma = c.elements.find(e => e.map && e.map.part === 'ma0');
    g('markers-no-proxy-no-change', ma && statesAt(ma, 450) === 'blur' && numAt(ma, 'style.opacity', 450) === numAt(ma, 'style.opacity', 1600),
      'markers-declared');
  }
  // D. a large click
  {
    const c = byId(cases, 'large-bar-click');
    const sel = c.published.filter(e => e.type === 'select').length;
    g('large-click-selects-twice', sel === 3 && c.elements.every(e => !e.everStates), 'large-bar-click ' + sel);
    const last = c.selection[c.selection.length - 1][0];
    g('large-click-model', same(last.indices, [300]), JSON.stringify(last));
  }
  {
    const c = byId(cases, 'large-held-blur');
    const p = elRow(c, 2, 1, 'host');
    const ev = c.published.filter(e => e.type === 'mouseover' || e.type === 'mouseout').map(e => e.at + e.type).join(',');
    g('large-hover-keeps-held-blur', p && statesAt(p, 450) === 'blur' && statesAt(p, 1000) === 'blur'
      && statesAt(p, 1600) === '' && ev === '400mouseover,800mouseout', ev);
  }
  // E. a hidden label
  {
    const c = byId(cases, 'pie-label-emphasis');
    const l = elRow(c, 0, 1, 'label');
    g('pie-hidden-label-built', l && numAt(l, 'ignore', 1600) === true && numAt(l, 'ignore', 450) === false, 'pie-label-emphasis');
  }
  {
    const c = byId(cases, 'funnel-label-emphasis');
    const l = elRow(c, 0, 1, 'label');
    const gl = elRow(c, 0, 1, 'guide');
    g('funnel-default-emphasis-label', l && numAt(l, 'ignore', 1600) === true && numAt(l, 'ignore', 450) === false
      && gl && numAt(gl, 'ignore', 450) === false, 'funnel-label-emphasis');
  }
  {
    const c = byId(cases, 'bar-item-label-emphasis');
    const l1 = elRow(c, 0, 1, 'label');
    const l0 = elRow(c, 0, 0, 'label');
    g('item-label-show-is-its-emphasis', l1 && l0 && numAt(l1, 'ignore', 200) === false && numAt(l0, 'ignore', 1000) === true,
      'bar-item-label-emphasis');
  }
  // F. the glyph is the target
  {
    const c = byId(cases, 'pictorial-hit');
    const ev = c.published.filter(e => e.type === 'mouseover' || e.type === 'mouseout').map(e => e.at + e.type).join(',');
    g('pictorial-glyph-target', ev === '0mouseover,400mouseout,800mouseover,1200mouseout', ev);
  }
  {
    const c = byId(cases, 'pictorial-clip');
    const ev = c.published.filter(e => e.type === 'mouseover').map(e => e.at).join(',');
    g('pictorial-clip-target', ev === '400', ev);
  }
  // G. [R2-B]
  {
    const c = byId(cases, 'radar-order');
    const zi = (row, part, ms) => numAt(elRow(c, 0, row, part), 'zi', ms);
    g('radar-polygon-over-line', Number(zi(0, 'rarea', 1600)) > Number(zi(0, 'host', 1600))
      && Number(zi(1, 'rarea', 450)) > Number(zi(1, 'host', 450)), [zi(0, 'host', 1600), zi(0, 'rarea', 1600)].join(' '));
  }
  {
    const c = byId(cases, 'radar-held-self');
    g('radar-held-children-blur', statesAt(elRow(c, 0, 0, 'host'), 650) === 'blur', statesAt(elRow(c, 0, 0, 'host'), 650));
  }
  {
    const c = byId(cases, 'scatter-label-follows');
    const l = elRow(c, 0, 1, 'label');
    g('scatter-label-rides', l && numAt(l, 'ty', 450) !== numAt(l, 'ty', 1600) && numAt(l, 'ty', 16) !== numAt(l, 'ty', 450),
      'scatter-label-follows');
  }
  // H. [R2-I1]
  {
    const c = byId(cases, 'scatter-label-opacity');
    const l = elRow(c, 0, 1, 'label');
    g('scatter-label-at-0.8', l && numAt(l, 'style.opacity', 1600) === '0.8' && numAt(l, 'style.opacity', 450) === '0.8'
      && statesAt(l, 450) === 'emphasis', l && numAt(l, 'style.opacity', 1600));
  }
  {
    const c = byId(cases, 'bar-label-opacity');
    const op = row => numAt(elRow(c, 0, row, 'label'), 'style.opacity', 1600);
    g('bar-label-opacities', op(0) === '0.5' && op(1) === '0.3' && op(2) === '0.9', [op(0), op(1), op(2)].join(' '));
  }
  {
    const c = byId(cases, 'radar-label-line-states');
    const gl = (row, j) => elRow(c, 0, row, 'rsym' + j + '#guide');
    const p = gl(0, 1);
    const q = gl(1, 1);
    g('radar-guide-states', p && q && numAt(p, 'ignore', 1600) === false && numAt(p, 'style.lineWidth', 450) === '3'
      && numAt(q, 'ignore', 450) === true && numAt(q, 'ignore', 1000) === true && numAt(q, 'ignore', 1600) === false,
      p && q && [numAt(p, 'style.lineWidth', 450), numAt(q, 'ignore', 450), numAt(q, 'ignore', 1000)].join(' '));
  }
  // [R2-I3]
  {
    const c = byId(cases, 'bar-pie-label');
    const l = elRow(c, 1, 1, 'label');
    g('pie-squeezed-label-present', l && numAt(l, 'ignore', 1600) === false && statesAt(l, 450) === 'emphasis', 'bar-pie-label');
  }
  {
    const c = byId(cases, 'bar-state-dash');
    const b0 = elRow(c, 0, 0, 'host');
    const b1 = elRow(c, 0, 1, 'host');
    g('state-dash-set-at-once', b0 && numAt(b0, 'dash', 1) === '[6,3]' && numAt(b0, 'dash', 1600) === 'null', 'bar-state-dash');
    g('state-dash-offset-tweens', b0 && Number(numAt(b0, 'dashOff', 100)) > 0 && Number(numAt(b0, 'dashOff', 100)) < 4
      && Number(numAt(b0, 'dashOff', 450)) === 4 && b1 && Number(numAt(b1, 'dashOff', 1200)) === 9, 'bar-state-dash phases');
  }
  // [R2-I4]
  {
    const c = byId(cases, 'bar-dash-word-tween');
    const b0 = elRow(c, 0, 0, 'host');
    const b1 = elRow(c, 1, 1, 'host');
    const d = (el, ms) => numAt(el, 'dash', ms);
    g('state-dash-word-follows-width', b0 && d(b0, 450) === '[20,10]' && d(b0, 50) !== '[20,10]' && d(b0, 50) !== 'null'
      && b1 && JSON.parse(d(b1, 1100))[0] > 5.99 && JSON.parse(d(b1, 850))[0] > 1 && JSON.parse(d(b1, 850))[0] < 5,
      b0 && b1 && [d(b0, 50), d(b0, 450), d(b1, 850), d(b1, 1100)].join(' '));
  }
  {
    const c = byId(cases, 'bar-dash-word-still');
    const b0 = elRow(c, 0, 0, 'host');
    const b1 = elRow(c, 1, 1, 'host');
    g('still-dash-word-at-state-width', b1 && numAt(b1, 'dash', 1) === '[6]' && numAt(b1, 'dash', 400) === '[1]'
      && b0 && numAt(b0, 'dash', 501) === '[20,10]', b0 && b1 && [numAt(b1, 'dash', 1), numAt(b0, 'dash', 501)].join(' '));
  }
  // every case comes to rest
  for (const c of cases) g('settled-' + c.id, c.clips[c.clips.length - 1] === 0, c.id + ' ' + c.clips.join(','));
  return out;
}

function generate() {
  const cases = [];
  for (const c of GAUGE.concat(RADAR, MARKERS, LARGE, LABELS, PICTORIAL, R2B, R2I1, R2I3, R2I4)) {
    if (process.env.ORACLE_CASE && !process.env.ORACLE_CASE.split('|').some(p => c.id.startsWith(p))) continue;
    const r = runCase(c);
    cases.push({ id: c.id, note: c.note, option: c.option, events: r.events, published: r.published,
      selection: r.selection, clips: r.clips, elements: r.elements });
  }
  const gs = process.env.ORACLE_CASE ? [] : guards(cases);
  // the furniture that never takes a state (a gauge's ticks and words, an
  // axis' labels) is not written: only the mapped elements and any element
  // that held a state
  for (const c of cases) c.elements = c.elements.filter(e => e.map || e.everStates);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'F2b: gauge and radar states, the markers of a blurred series, a click on a large element, labels hidden at rest, '
      + 'the pictorial bar\'s hit target. A case sets `option` at T0 and settles; then at each sample t of samplesMs: the '
      + 'events at t (move: handler.mousemove at x,y; click: mousemove, mousedown, mouseup, click at x,y; out: mousemove '
      + 'at 3,3; action: dispatchAction), then NOW = T1 + t and one zr.animation.update(), then the record. Element keys as '
      + 'advchart-state-anim.json; map: the port\'s part {s, row (inner index, -1 for a marker), part}. published: the '
      + 'chart\'s events per sample; selection: per sample (once when it never changes) every series\' selectedMap and '
      + 'selected indices.',
    W, H, seed: SEED,
    clock: { T1Offset: T1_OFFSET, note: 'each case on a clock of its own, later than every earlier one (the generation runs twice): '
      + 'only times relative to its t0, where the option is set and the settle starts, are written; T1 = t0 + T1Offset' },
    samplesMs: SAMPLES,
    guards: gs,
    cases,
  };
}

let json1;
let json2;
try {
  json1 = fmt(generate(), '') + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  if (!process.env.ORACLE_ONCE) json2 = fmt(generate(), '') + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (json2 !== undefined && json1 !== json2) {
  console.log('FAILED: two generations differ');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT, json1.length, 'bytes');
process.exit(0);
