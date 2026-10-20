// R2-B (fix phase round 2, 2026-10-19): the markers' own states.
//
//   A markPoint is a SymbolDraw over the marker's own data (MarkPointView.ts):
//   each item a Symbol group -- a highDownDispatcher (Symbol._updateCommon:
//   toggleHoverEmphasis(this, focus, blurScope, emphasisDisabled)) whose path
//   carries emphasis / blur / select styles of the item model (item ->
//   markPoint), the emphasis scale (`_sizeX * ratio`) and the label states.
//   A markLine is a LineDraw (Line._updateCommonStl): the Line group the
//   dispatcher, its line's lineStyle states, the end symbols taking the
//   line's stroke and opacity, the label on the group. A markArea's polygon
//   is a dispatcher of no focus (toggleHoverEmphasis(polygon, null, null,
//   disabled)). The marker data's host model is the marker model, whose
//   seriesIndex is the host series' (MarkerModel._mergeOption): a hover
//   blurs by the marker's own emphasis.focus / blurScope around the HOST
//   series -- and the host's markers with it (toggleBlurSeries), the hovered
//   one too before it enters emphasis. A click dispatches select for the host
//   series' item at the marker's index; the marker elements are never
//   selected. A marker model does not animate here (isAnimationEnabled reads
//   its own `animation`, unset): no stateTransition.
//
// [R2-I1] a marker label's emphasis textConfig (setLabelStyle: the state's
// createTextConfig -- position, distance, offset, rotate where the state's
// label model says them, down the item model's chain), and a marker label
// shown only in a state (needsCreateText: built and ignored at rest; the
// state's ignore = !show where it differs from the normal one).
//
// [R2-I4] a marker label's emphasis formatter (getLabelText: each state's
// text is getFormattedLabel(idx, state, ..., the state model's formatter),
// the normal text where it answers nothing): a template, and a named handler
// ('@Name', a function here, given params.status).
//
// [R2-I5] the blur (and select) formatter the same way -- each state shows its
// own words; a label whose normal text is empty but a state has words (the
// Text is built, empty, and shows the state's words); a marker's dash written
// as a word, normalised against the width its emphasis draws.
//
// The harness is states-misc.js', copied (that script generates and exits on
// load): the replaced Date before the dist, chart._ssr = false,
// env.node = false, the seeded Math.random, hand-stepped frames, one frame a
// sample. One record more than there: a label's computed transform as tx / ty
// (where updateInnerText placed it on its host as drawn).
//
// Run: node tools/advchart-oracle/states-marks.js
//   -> tests/fixtures/advchart-states-marks.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-states-marks.json');

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
// [R2-I3] the case being run: its flags ask for extra records
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
function snap(el) {
  const o = {};
  const put = (k, v) => {
    const e = enc(v);
    if (e !== undefined) o[k] = e;
  };
  for (const k of TRANSFORM_KEYS) if (typeof el[k] === 'number') put(k, el[k]);
  put('ignore', !!el.ignore);
  // a label: where updateInnerText placed it (its computed transform)
  if (el.type === 'text' && el.transform) {
    put('tx', el.transform[4]);
    put('ty', el.transform[5]);
  }
  // [R2-I3] a text's merged style -- its size, weight, alignment -- and its
  // box through its transform (getBoundingRect: the TSpans' and the
  // backgrounds' union); every TSpan's text and place in the canvas
  if (CUR_CASE && CUR_CASE.textBox && el.type === 'text' && el.transform) {
    put('fs', el.style.fontSize == null ? -1 : Number(el.style.fontSize));
    put('fw', el.style.fontWeight == null ? '' : String(el.style.fontWeight));
    put('al', el.style.align == null ? '' : el.style.align);
    put('va', el.style.verticalAlign == null ? '' : el.style.verticalAlign);
    const r = el.getBoundingRect().clone();
    r.applyTransform(el.transform);
    put('bx', r.x);
    put('by', r.y);
    put('bw', r.width);
    put('bh', r.height);
    const spans = [];
    for (const k of el.childrenRef()) {
      if (k.type !== 'tspan') continue;
      const m = k.transform || el.transform;
      const x = m[0] * k.style.x + m[2] * k.style.y + m[4];
      const y = m[1] * k.style.x + m[3] * k.style.y + m[5];
      spans.push(k.style.text + '@' + x.toFixed(6) + ',' + y.toFixed(6) + ':' + (k.style.font || ''));
    }
    put('spans', spans.join('|'));
  }
  // [R2-I4] a text's words as its state shows them
  if (CUR_CASE && CUR_CASE.words && el.type === 'text') put('txt', el.style.text == null ? '' : String(el.style.text));
  // [R2-I3] a path's dash as drawn and its phase
  if (CUR_CASE && CUR_CASE.dash && el.style && el.type !== 'text') {
    put('dash', JSON.stringify(normalizeLineDash(el.style.lineDash, el.style.lineWidth)));
    if (el.style.lineDash) put('dashOff', el.style.lineDashOffset == null ? 0 : el.style.lineDashOffset);
  }
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
    // [R2-I5] a keepEmpty case maps an empty label too (its states have words)
    const words = label => label && label.style && label.style.text != null
      && (label.style.text !== '' || !!(CUR_CASE && CUR_CASE.keepEmpty));
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
  if (k === 'mark') {
    const parts = new Map();
    for (const mv of markerViews(chart)) markerParts(mv, parts);
    let el = null;
    for (const [e, m] of parts) if (m.s === s && m.part === pick[2]) el = e;
    must(el, 'no marker element ' + pick[2]);
    return aimAt(chart, el, pick[3]);
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
    zr.storage.getDisplayList(true);
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
        rec.snaps[si] = snap(it.el);
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
    chart.setOption(withHandlers(JSON.parse(JSON.stringify(c.option))));
    settle(chart, caseBase);
    return loopOn(chart, c, caseBase + T1_OFFSET);
  }
  finally {
    chart.dispose();
  }
}

// [R2-I4] the named handlers an option may say ('@Name'): the port's test
// registers the same
const FMT = {
  mkWords: p => p.componentType + ':' + p.name + ':' + p.status + ':' + p.dataIndex,
};
function withHandlers(v) {
  if (typeof v === 'string' && v.startsWith('@') && FMT[v.slice(1)]) return FMT[v.slice(1)];
  if (Array.isArray(v)) return v.map(x => withHandlers(x));
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[k] = withHandlers(v[k]);
    return o;
  }
  return v;
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
const mark = (s, part) => ['mark', s, part];

// two bar series on one grid; the first carries the markers it is given
const bars = (s0, s1, extra) => Object.assign({
  color: [C0, C1], xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40 },
  series: [Object.assign({ type: 'bar', data: [5, 20, 36, 10, 18] }, s0 || {}),
    Object.assign({ type: 'bar', data: [8, 12, 6, 30, 4] }, s1 || {})],
}, extra || {});
const MP = (extra, data) => Object.assign({ data: data || [{ type: 'max', name: 'max' }] }, extra || {});
const ML = (extra, data) => Object.assign({ data: data || [{ type: 'average', name: 'avg' }] }, extra || {});
const MA = (extra, data) => Object.assign({ data: data || [[{ xAxis: 'A' }, { xAxis: 'B' }]] }, extra || {});

const HOVER = [
  { id: 'mp-hover', note: 'hover the markPoint pin at 0: the path\'s fill lifts (no emphasis declared), z2 + 10, the scale '
    + '_sizeX * 1.1; its inside label (40 % down the pin) rides the scaled pin; out at 500',
    option: bars({ markPoint: MP() }), events: [over(0, mark(0, 'mp0')), out(500)] },
  { id: 'mp-hover-item', note: 'item-level emphasis over the markPoint\'s: item 0 a colour and border of its own and a label '
    + 'colour, item 1 (symbolSize 30, a right label) emphasis.scale 1.5; the markPoint\'s emphasis border width 4; hover '
    + 'mp0 at 0, mp1 at 400, out at 800',
    option: bars({ markPoint: MP({ emphasis: { itemStyle: { borderWidth: 4 } } }, [
      { type: 'max', name: 'max', itemStyle: { color: C3 },
        emphasis: { itemStyle: { color: '#123456', borderColor: '#000000' }, label: { color: '#ff0000' } } },
      { type: 'min', name: 'min', symbol: 'circle', symbolSize: 30, label: { position: 'right' }, emphasis: { scale: 1.5 } }]) }),
    events: [over(0, mark(0, 'mp0')), over(400, mark(0, 'mp1')), out(800)] },
  { id: 'mp-label-follows', note: 'circle markPoints of size 16 with labels top / right / bottom: hovering each, its label '
    + 'moves out with the scaled circle (ratio max(1.1, 3 / 8)); scale false on the third keeps it',
    option: bars({ markPoint: MP({ symbol: 'circle', symbolSize: 16 }, [
      { type: 'max', name: 'max', label: { position: 'top' } },
      { type: 'min', name: 'min', label: { position: 'right' } },
      { coord: ['C', 30], name: 'c', value: 30, label: { position: 'bottom' }, emphasis: { scale: false } }]) }),
    events: [over(0, mark(0, 'mp0')), over(300, mark(0, 'mp1')), over(600, mark(0, 'mp2')), out(900)] },
  { id: 'ml-hover', note: 'hover the markLine (average) at 0: the line\'s width 3 (the model\'s default emphasis), its stroke '
    + 'lifted, the end symbols\' fill lifted, every z2 + 10, the label in emphasis; the max line at 500; out at 1000',
    option: bars({ markLine: ML({}, [{ type: 'average', name: 'avg' }, { type: 'max', name: 'max' }]) }),
    events: [over(0, mark(0, 'ml0')), over(500, mark(0, 'ml1')), out(1000)] },
  { id: 'ml-hover-item', note: 'markLine items with emphasis of their own over the markLine\'s width 5: item 0 a lineStyle '
    + 'colour and width (the end symbols take the colour as their fill), item 1 a label colour, item 2 emphasis disabled '
    + '(no dispatcher: no hover at all); hover each',
    option: bars({ markLine: ML({ emphasis: { lineStyle: { width: 5 } } }, [
      { type: 'average', name: 'avg', emphasis: { lineStyle: { color: C3, width: 2 } } },
      { type: 'max', name: 'max', emphasis: { label: { color: '#ff0000' } } },
      { type: 'min', name: 'min', emphasis: { disabled: true } }]) }),
    events: [over(0, mark(0, 'ml0')), over(400, mark(0, 'ml1')), over(800, mark(0, 'ml2')), out(1200)] },
  { id: 'ma-hover', note: 'hover two markAreas: the first lifts (fill), the second has an item emphasis colour; out',
    option: bars({ markArea: MA({ itemStyle: { color: 'rgba(84,112,198,0.3)' } }, [
      [{ xAxis: 'A', name: 'one' }, { xAxis: 'B' }],
      [{ xAxis: 'D', name: 'two', emphasis: { itemStyle: { color: C3 } } }, { xAxis: 'E' }]]) }),
    events: [over(0, mark(0, 'ma0')), over(400, mark(0, 'ma1')), out(800)] },
];

const FOCUS = [
  { id: 'mp-focus-series', note: 'the markPoint\'s emphasis.focus series: hovering it blurs the other series (one grid) and '
    + 'its markPoint, not the host; out at 500',
    option: bars({ markPoint: MP({ emphasis: { focus: 'series' } }) }, { markPoint: MP() }),
    events: [over(0, mark(0, 'mp0')), out(500)] },
  { id: 'mp-focus-self', note: 'an item\'s emphasis.focus self: hovering it blurs both series, the host\'s other markers and '
    + 'the other\'s; the hovered pin blurs and then enters emphasis; out at 500',
    option: bars({ markPoint: MP({}, [{ type: 'max', name: 'max', emphasis: { focus: 'self' } }, { type: 'min', name: 'min' }]),
      markLine: ML() }, { markPoint: MP() }),
    events: [over(0, mark(0, 'mp0')), out(500)] },
  { id: 'ml-focus-scope', note: 'the markLine\'s emphasis focus self, blurScope series: only the host series and its markers '
    + 'blur; out at 500',
    option: bars({ markLine: ML({ emphasis: { focus: 'self', blurScope: 'series' } }), markPoint: MP() }, { markPoint: MP() }),
    events: [over(0, mark(0, 'ml0')), out(500)] },
  { id: 'ma-focus-ignored', note: 'a markArea\'s emphasis.focus series is never read (toggleHoverEmphasis(polygon, null)): '
    + 'hovering it blurs nothing',
    option: bars({ markArea: MA({ emphasis: { focus: 'series' } }) }, { markPoint: MP() }),
    events: [over(0, mark(0, 'ma0')), out(500)] },
  { id: 'mark-disabled', note: 'the markPoint\'s emphasis disabled: no hover state, and under the other series\' focus its '
    + 'blur is the declared one alone (none: no change)',
    option: bars({ markPoint: MP({ emphasis: { disabled: true } }) }, { emphasis: { focus: 'series' } }),
    events: [over(0, mark(0, 'mp0')), out(300), over(500, ['item', 1, 3]), out(900)] },
  { id: 'mark-hover-held-blur', note: 'hovering a markPoint, then a highlight by action of the other series (focus series) '
    + 'blurs the host and the hovered pin with it; the downplay takes the blur off and the pin is normal under the pointer',
    option: bars({ markPoint: MP() }, { emphasis: { focus: 'series' } }),
    events: [over(0, mark(0, 'mp0')), act(300, { type: 'highlight', seriesIndex: 1, dataIndex: 3 }),
      act(600, { type: 'downplay', seriesIndex: 1, dataIndex: 3 }), out(900)] },
];

const ITEMBLUR = [
  { id: 'item-blur', note: 'the other series\' focus series blurs the host: the markers\' data items\' own blur styles over '
    + 'the component\'s -- a markPoint item opacity 0.5 (the other item takes the markPoint\'s 0.3), a markLine item\'s '
    + 'lineStyle colour and opacity (its end symbols take both), a markArea item\'s opacity, a label\'s opacity',
    option: bars({
      markPoint: MP({ blur: { itemStyle: { opacity: 0.3 } } }, [
        { type: 'max', name: 'max', blur: { itemStyle: { opacity: 0.5 }, label: { opacity: 0.2 } } }, { type: 'min', name: 'min' }]),
      markLine: ML({}, [{ type: 'average', name: 'avg', blur: { lineStyle: { color: C3, opacity: 0.6 } } }, { type: 'max', name: 'max' }]),
      markArea: MA({}, [[{ xAxis: 'A', blur: { itemStyle: { opacity: 0.05 } } }, { xAxis: 'B' }], [{ xAxis: 'D' }, { xAxis: 'E' }]]),
    }, { emphasis: { focus: 'series' } }),
    events: [over(0, ['item', 1, 3]), out(500)] },
  { id: 'item-emphasis-blur-scope', note: 'an item emphasis.focus on a markLine data item (series), the markLine\'s own focus '
    + 'none: hovering item 1 blurs the other series; item 0 blurs nothing',
    option: bars({ markLine: ML({}, [{ type: 'average', name: 'avg' }, { type: 'max', name: 'max', emphasis: { focus: 'series' } }]) },
      { markPoint: MP() }),
    events: [over(0, mark(0, 'ml0')), out(300), over(500, mark(0, 'ml1')), out(900)] },
];

const SELECT = [
  { id: 'mark-click-select', note: 'the host selectedMode single: a click on mp0 (the max, data index 0 of the marker) '
    + 'selects the host\'s item 0 -- the marker is never selected, so the second click selects again; select.itemStyle on '
    + 'the markPoint changes nothing',
    option: bars({ selectedMode: 'single', markPoint: MP({ select: { itemStyle: { color: '#000000' } } }) }),
    events: [click(0, mark(0, 'mp0')), out(300), click(500, mark(0, 'mp0')), out(800)] },
];

// [R2-I1]
const R2I1 = [
  { id: 'mp-emph-position', note: 'emphasis textConfig: the markPoint\'s emphasis.label.position top over the pin\'s inside '
    + 'label; item 1 (a circle of 20, a right label at rest) its own emphasis label at the bottom, distance 8, offset [3, 2]; '
    + 'item 2 (a circle) an emphasis rotate of 30; hover mp0 at 0, mp1 at 400, mp2 at 800, out at 1200',
    option: bars({ markPoint: MP({ emphasis: { label: { position: 'top' } } }, [
      { type: 'max', name: 'max' },
      { type: 'min', name: 'min', symbol: 'circle', symbolSize: 20, label: { position: 'right' },
        emphasis: { label: { position: 'bottom', distance: 8, offset: [3, 2] } } },
      { coord: ['C', 30], name: 'c', value: 30, symbol: 'circle', symbolSize: 20, label: { position: 'left' },
        emphasis: { label: { position: 'right', rotate: 30 } } }]) }),
    events: [over(0, mark(0, 'mp0')), over(400, mark(0, 'mp1')), over(800, mark(0, 'mp2')), out(1200)] },
  { id: 'mp-label-state-only', note: 'a markPoint label hidden at rest (label.show false) and shown by a state: the '
    + 'markPoint\'s emphasis.label.show (at the top) on hover; item 1\'s blur.label.show under the other series\' focus; '
    + 'hover mp0 at 0, out at 300, the other series at 500, out at 900',
    option: bars({ markPoint: MP({ label: { show: false }, emphasis: { label: { show: true, position: 'top' } } }, [
      { type: 'max', name: 'max' }, { type: 'min', name: 'min', blur: { label: { show: true } } }]) },
      { emphasis: { focus: 'series' } }),
    events: [over(0, mark(0, 'mp0')), out(300), over(500, ['item', 1, 3]), out(900)] },
  { id: 'ml-label-state-only', note: 'a markLine label hidden at rest and shown in emphasis (the markLine\'s '
    + 'emphasis.label.show): hover ml0 at 0, out at 500',
    option: bars({ markLine: ML({ label: { show: false }, emphasis: { label: { show: true } } }) }),
    events: [over(0, mark(0, 'ml0')), out(500)] },
  { id: 'ma-label-state-only', note: 'markArea labels: the first hidden at rest and shown in emphasis; the second shown at '
    + 'rest (top) and moved to insideBottom by its emphasis.label.position; hover ma0 at 0, ma1 at 400, out at 800',
    option: bars({ markArea: MA({ label: { show: false }, emphasis: { label: { show: true } } }, [
      [{ xAxis: 'A', name: 'one' }, { xAxis: 'B' }],
      [{ xAxis: 'D', name: 'two', label: { show: true }, emphasis: { label: { position: 'insideBottom' } } }, { xAxis: 'E' }]]) }),
    events: [over(0, mark(0, 'ma0')), over(400, mark(0, 'ma1')), out(800)] },
];

// [R2-I3] the emphasis label's text style, laid out again; rich markers; a
// markLine label under an emphasis position; the states' dashes
const R2I3 = [
  { id: 'mp-emph-font', textBox: true, note: '[R2-I3] the emphasis label\'s text style merged over the normal one and laid '
    + 'out again (setLabelStyle\'s state style): mp0 (a circle of 20, its label at the top) emphasis fontSize 20, bold, '
    + '#cc0000; mp1 its own emphasis fontSize 16 at the right (normal left); emphasis.scale false. Hover mp0 at 0, mp1 at 400, '
    + 'out at 800',
    option: bars({ markPoint: MP({ symbol: 'circle', symbolSize: 20, label: { position: 'top' },
      emphasis: { scale: false, label: { fontSize: 20, fontWeight: 'bold', color: '#cc0000' } } }, [
      { type: 'max', name: 'max' },
      { type: 'min', name: 'min', label: { position: 'left' }, emphasis: { label: { fontSize: 16, position: 'right' } } }]) }),
    events: [over(0, mark(0, 'mp0')), over(400, mark(0, 'mp1')), out(800)] },
  { id: 'mp-emph-rich', textBox: true, note: '[R2-I3] a rich markPoint label in emphasis: {a|A}{b|B} with a 14 and b 10 and blue at '
    + 'the right; the emphasis position left and a rich of its own, a 18 -- the state style\'s rich replaces the normal one '
    + '(b loses its 10 and its blue: the 12 of the block); hover mp0 at 0, out at 500',
    option: bars({ markPoint: MP({ symbol: 'circle', symbolSize: 20,
      label: { position: 'right', formatter: '{a|A}{b|B}', rich: { a: { fontSize: 14 }, b: { fontSize: 10, color: '#0000ff' } } },
      emphasis: { scale: false, label: { position: 'left', rich: { a: { fontSize: 18 } } } } }) }),
    events: [over(0, mark(0, 'mp0')), out(500)] },
  { id: 'ml-emph-position', textBox: true, note: '[R2-I3] a markLine label under an emphasis position: the Line group\'s '
    + 'emphasis textConfig puts it by calculateTextPosition on the group\'s own box (the line grown by max(3, 5), the end '
    + 'symbols) after Line.beforeUpdate -- ml0 inside (and fontSize 16), ml1 a markLine word, start (the box\'s corner); '
    + 'hover ml0 at 0, ml1 at 400, out at 800',
    option: bars({ markLine: ML({ emphasis: { label: { position: 'inside', fontSize: 16 } } }, [
      { type: 'average', name: 'avg' },
      { yAxis: 30, name: 'thirty', emphasis: { label: { position: 'start', distance: 9 } } }]) }),
    events: [over(0, mark(0, 'ml0')), over(400, mark(0, 'ml1')), out(800)] },
  { id: 'ma-emph-font', textBox: true, note: '[R2-I3] a markArea label\'s emphasis fontSize 18 (its default emphasis position '
    + 'top); hover ma0 at 0, out at 500',
    option: bars({ markArea: MA({ emphasis: { label: { fontSize: 18 } } }, [[{ xAxis: 'A', name: 'area' }, { xAxis: 'B' }]]) }),
    events: [over(0, mark(0, 'ma0')), out(500)] },
  { id: 'marks-state-dash', dash: true, note: '[R2-I3] the markers\' states\' dashes, set at once (a marker does not animate): '
    + 'the markLine\'s emphasis lineStyle [8, 2] at 5 over its dashed; a pin\'s emphasis borderType dotted at 3; hover ml0 '
    + 'at 0, mp0 at 400, out at 800',
    option: bars({ markLine: ML({ emphasis: { lineStyle: { type: [8, 2], dashOffset: 5 } } }),
      markPoint: MP({ itemStyle: { borderColor: '#000000', borderWidth: 2 },
        emphasis: { scale: false, itemStyle: { borderType: 'dotted', borderDashOffset: 3 } } }) }),
    events: [over(0, mark(0, 'ml0')), over(400, mark(0, 'mp0')), out(800)] },
];

// [R2-I4] the emphasis formatter: each state's text is the state model's
// formatter's (getFormattedLabel), the normal text where it says none
const R2I4 = [
  { id: 'mp-emph-formatter', textBox: true, words: true, note: '[R2-I4] markPoint labels at the top of circles of 20 '
    + '(scale false) formatted {b}: {c}; mp0 its own emphasis formatter, a template; mp1 its own emphasis formatter, a named '
    + 'handler (params.status emphasis); mp2 a named handler at rest and no emphasis formatter (the normal text stays, the '
    + 'handler asked once, normal). Hover mp0 at 0, mp1 at 400, mp2 at 800, out at 1200',
    option: bars({ markPoint: MP({ symbol: 'circle', symbolSize: 20, label: { position: 'top', formatter: '{b}: {c}' },
      emphasis: { scale: false } }, [
      { type: 'max', name: 'max', emphasis: { label: { formatter: 'hi {b} ({c})' } } },
      { type: 'min', name: 'min', emphasis: { label: { formatter: '@mkWords' } } },
      { coord: ['C', 30], name: 'c', value: 30, label: { formatter: '@mkWords' } }]) }),
    events: [over(0, mark(0, 'mp0')), over(400, mark(0, 'mp1')), over(800, mark(0, 'mp2')), out(1200)] },
  { id: 'ml-emph-formatter', textBox: true, words: true, note: '[R2-I4] markLine labels: the markLine\'s emphasis formatter '
    + '{b} = {c} over the default value text; ml1 its own, a named handler; hover ml0 at 0, ml1 at 400, out at 800',
    option: bars({ markLine: ML({ emphasis: { label: { formatter: '{b} = {c}' } } }, [
      { type: 'average', name: 'avg' },
      { yAxis: 30, name: 'thirty', emphasis: { label: { formatter: '@mkWords' } } }]) }),
    events: [over(0, mark(0, 'ml0')), over(400, mark(0, 'ml1')), out(800)] },
  { id: 'ma-emph-formatter', textBox: true, words: true, note: '[R2-I4] markArea labels: the markArea\'s emphasis formatter '
    + '[{b}] over the name; ma1 its own, a named handler; hover ma0 at 0, ma1 at 400, out at 800',
    option: bars({ markArea: MA({ emphasis: { label: { formatter: '[{b}]' } } }, [
      [{ xAxis: 'A', name: 'one' }, { xAxis: 'B' }],
      [{ xAxis: 'D', name: 'two', emphasis: { label: { formatter: '@mkWords' } } }, { xAxis: 'E' }]]) }),
    events: [over(0, mark(0, 'ma0')), over(400, mark(0, 'ma1')), out(800)] },
];

// [R2-I5] the blur and select formatters (getLabelText asks every special
// state); a label empty at rest that a state gives words; a marker's dash
// word against the width its emphasis draws (canvas getLineDash per brush)
const R2I5 = [
  { id: 'mk-blur-formatter', textBox: true, words: true, note: '[R2-I5] the other series\' focus series blurs the host\'s '
    + 'markers: mp0 / mp1 at the top of circles of 20 formatted {b}: {c}, the markPoint\'s blur formatter blur {b}; mp1 its '
    + 'own blur formatter, a named handler (params.status blur), and a blur fontSize 16; mp2 a select formatter (a marker '
    + 'is never selected: never shown; blurred, the markPoint\'s blur words); the markLine\'s blur formatter {b} ~ {c}; the markAreas\' blur formatter '
    + '({b}), ma1 its own handler. Hover bar 3 of series 1 at 0, out at 500',
    option: bars({ markPoint: MP({ symbol: 'circle', symbolSize: 20, label: { position: 'top', formatter: '{b}: {c}' },
      emphasis: { scale: false }, blur: { label: { formatter: 'blur {b}' } } }, [
      { type: 'max', name: 'max' },
      { type: 'min', name: 'min', blur: { label: { formatter: '@mkWords', fontSize: 16 } } },
      { coord: ['C', 30], name: 'c', value: 30, select: { label: { formatter: 'sel {b}' } } }]),
    markLine: ML({ blur: { label: { formatter: '{b} ~ {c}' } } }),
    markArea: MA({ blur: { label: { formatter: '({b})' } } }, [
      [{ xAxis: 'A', name: 'one' }, { xAxis: 'B' }],
      [{ xAxis: 'B', name: 'two', blur: { label: { formatter: '@mkWords' } } }, { xAxis: 'C' }]]) },
    { emphasis: { focus: 'series' } }),
    events: [over(0, ['item', 1, 3]), out(500)] },
  { id: 'mk-empty-normal', textBox: true, words: true, keepEmpty: true, note: '[R2-I5] labels whose normal text is empty: '
    + 'mp0 formatted \'\' with an emphasis formatter hover {b}; mp1 formatted \'\' with a blur formatter blur {c}; the '
    + 'markLine formatted \'\' with an emphasis formatter {b}!; a markArea of no name with an emphasis formatter area. The '
    + 'empty Text is there (setLabelStyle: some state shows it) and shows the state\'s words. Hover mp0 at 0, ml0 at 300, '
    + 'ma0 at 600, bar 3 of series 1 (focus series) at 900, out at 1200',
    option: bars({ markPoint: MP({ symbol: 'circle', symbolSize: 20, label: { position: 'top', formatter: '' },
      emphasis: { scale: false } }, [
      { type: 'max', name: 'max', emphasis: { label: { formatter: 'hover {b}' } } },
      { type: 'min', name: 'min', blur: { label: { formatter: 'blur {c}' } } }]),
    markLine: ML({ label: { formatter: '' }, emphasis: { label: { formatter: '{b}!' } } }),
    markArea: MA({ emphasis: { label: { formatter: 'area' } } }, [[{ xAxis: 'A' }, { xAxis: 'B' }]]) },
    { emphasis: { focus: 'series' } }),
    events: [over(0, mark(0, 'mp0')), over(300, mark(0, 'ml0')), over(600, mark(0, 'ma0')), over(900, ['item', 1, 3]),
      out(1200)] },
  { id: 'mk-dash-word', dash: true, note: '[R2-I5] markers\' dashes written as words under an emphasis width: the '
    + 'markLine dashed at 1 (its default emphasis width 3: [12, 6]); the pin\'s border dotted at 1, emphasis borderWidth 4 '
    + '([4]); the markArea\'s border dashed at 1, emphasis borderWidth 3 ([12, 6]) -- a marker does not animate: at once. '
    + 'Hover ml0 at 0, mp0 at 400, ma0 at 800, out at 1200',
    option: bars({ markLine: ML({ lineStyle: { type: 'dashed', width: 1 } }),
      markPoint: MP({ itemStyle: { borderColor: '#000000', borderWidth: 1, borderType: 'dotted' },
        emphasis: { scale: false, itemStyle: { borderWidth: 4 } } }),
      markArea: MA({ itemStyle: { borderColor: '#000000', borderWidth: 1, borderType: 'dashed' },
        emphasis: { itemStyle: { borderWidth: 3 } } }) }),
    events: [over(0, mark(0, 'ml0')), over(400, mark(0, 'mp0')), over(800, mark(0, 'ma0')), out(1200)] },
  { id: 'mk-state-pen', textBox: true, note: '[R2-I5] a state\'s pen moves the label (updateInnerText on the path as the '
    + 'state draws it, Path.getBoundingRect grown by its lineWidth): the markArea \'one\' bordered #000 at 1, emphasis '
    + 'borderWidth 11, blur borderWidth 5; a circle markPoint of 20 (scale false) with its label at the top, bordered at 1, '
    + 'emphasis borderWidth 9, blur borderWidth 3. Hover ma0 at 0, mp0 at 300, bar 3 of series 1 (focus series) at 600, '
    + 'out at 900',
    option: bars({ markArea: MA({ itemStyle: { borderColor: '#000000', borderWidth: 1 },
      emphasis: { itemStyle: { borderWidth: 11 } }, blur: { itemStyle: { borderWidth: 5 } } },
      [[{ xAxis: 'A', name: 'one' }, { xAxis: 'B' }]]),
    markPoint: MP({ symbol: 'circle', symbolSize: 20, label: { position: 'top' },
      itemStyle: { borderColor: '#000000', borderWidth: 1 },
      emphasis: { scale: false, itemStyle: { borderWidth: 9 } }, blur: { itemStyle: { borderWidth: 3 } } }) },
    { emphasis: { focus: 'series' } }),
    events: [over(0, mark(0, 'ma0')), over(300, mark(0, 'mp0')), over(600, ['item', 1, 3]), out(900)] },
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
const mk = (c, s, part) => c.elements.find(e => e.map && e.map.row === -1 && e.map.s === s && e.map.part === part);
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
  {
    const c = byId(cases, 'mp-hover');
    const p = mk(c, 0, 'mp0');
    const l = mk(c, 0, 'mp0#label');
    g('mp-emphasis', statesAt(p, 450) === 'emphasis' && statesAt(p, 1600) === ''
      && numAt(p, 'z2', 450) - numAt(p, 'z2', 1600) === 10, [statesAt(p, 450), numAt(p, 'z2', 450)].join(' '));
    g('mp-scale', Math.abs(numAt(p, 'scaleX', 450) / numAt(p, 'scaleX', 1600) - 1.1) < 1e-12, numAt(p, 'scaleX', 450));
    g('mp-label-rides', l && statesAt(l, 450) === 'emphasis' && numAt(l, 'ty', 450) !== numAt(l, 'ty', 1600), 'mp0#label');
  }
  {
    const c = byId(cases, 'mp-label-follows');
    const moved = part => numAt(mk(c, 0, part), 'tx', 1600) !== numAt(mk(c, 0, part), 'tx', 850)
      || numAt(mk(c, 0, part), 'ty', 1600) !== numAt(mk(c, 0, part), 'ty', 850);
    const at = (part, ms) => [numAt(mk(c, 0, part), 'tx', ms), numAt(mk(c, 0, part), 'ty', ms)].join(',');
    g('mp-top-label-follows', at('mp0#label', 250) !== at('mp0#label', 1600), at('mp0#label', 250));
    g('mp-right-label-follows', at('mp1#label', 550) !== at('mp1#label', 1600), at('mp1#label', 550));
    g('mp-unscaled-label-stays', at('mp2#label', 850) === at('mp2#label', 1600) && statesAt(mk(c, 0, 'mp2'), 850) === 'emphasis'
      && !moved('mp2#label'), at('mp2#label', 850));
  }
  {
    const c = byId(cases, 'ml-hover');
    const l = mk(c, 0, 'ml0');
    g('ml-width-3', statesAt(l, 450) === 'emphasis' && numAt(l, 'style.lineWidth', 450) === '3', numAt(l, 'style.lineWidth', 450));
    g('ml-ends-take-it', ['ml0.from', 'ml0.to', 'ml0#label'].every(p => statesAt(mk(c, 0, p), 450) === 'emphasis'), 'ml ends');
  }
  {
    const c = byId(cases, 'mp-focus-series');
    g('mp-focus-series', statesAt(elRow(c, 1, 0, 'host'), 450) === 'blur' && statesAt(mk(c, 1, 'mp0'), 450) === 'blur'
      && statesAt(elRow(c, 0, 0, 'host'), 450) === '' && statesAt(mk(c, 0, 'mp0'), 450) === 'emphasis', 'mp-focus-series');
  }
  {
    const c = byId(cases, 'mp-focus-self');
    g('mp-focus-self', statesAt(mk(c, 0, 'mp0'), 450) === 'emphasis' && statesAt(mk(c, 0, 'mp1'), 450) === 'blur'
      && statesAt(mk(c, 0, 'ml0'), 450) === 'blur' && statesAt(elRow(c, 0, 2, 'host'), 450) === 'blur'
      && statesAt(elRow(c, 1, 0, 'host'), 450) === 'blur' && statesAt(mk(c, 1, 'mp0'), 450) === 'blur', 'mp-focus-self');
  }
  {
    const c = byId(cases, 'ml-focus-scope');
    g('ml-focus-scope', statesAt(elRow(c, 0, 0, 'host'), 450) === 'blur' && statesAt(mk(c, 0, 'mp0'), 450) === 'blur'
      && statesAt(elRow(c, 1, 0, 'host'), 450) === '' && statesAt(mk(c, 1, 'mp0'), 450) === '', 'ml-focus-scope');
  }
  {
    const c = byId(cases, 'ma-focus-ignored');
    g('ma-focus-ignored', statesAt(mk(c, 0, 'ma0'), 450) === 'emphasis'
      && c.elements.every(e => !e.map || e.map.part === 'ma0' || e.map.part === 'ma0#label' || !e.everStates), 'ma-focus-ignored');
  }
  {
    const c = byId(cases, 'mark-disabled');
    g('mark-disabled', statesAt(mk(c, 0, 'mp0'), 250) === '' && statesAt(mk(c, 0, 'mp0'), 850) === 'blur', 'mark-disabled');
  }
  {
    const c = byId(cases, 'mark-hover-held-blur');
    const p = mk(c, 0, 'mp0');
    g('mark-hover-held-blur', statesAt(p, 250) === 'emphasis' && statesAt(p, 550) === 'blur' && statesAt(p, 850) === '',
      [statesAt(p, 250), statesAt(p, 550), statesAt(p, 850)].join(' '));
  }
  {
    const c = byId(cases, 'item-blur');
    const a = mk(c, 0, 'mp0');
    const b = mk(c, 0, 'mp1');
    g('item-blur-own', statesAt(a, 450) === 'blur' && numAt(a, 'style.opacity', 450) !== numAt(b, 'style.opacity', 450),
      [numAt(a, 'style.opacity', 450), numAt(b, 'style.opacity', 450)].join(' '));
  }
  {
    const c = byId(cases, 'item-emphasis-blur-scope');
    const h = elRow(c, 1, 0, 'host');
    g('item-focus', statesAt(h, 250) === '' && statesAt(h, 850) === 'blur', [statesAt(h, 250), statesAt(h, 850)].join(' '));
  }
  {
    const c = byId(cases, 'mark-click-select');
    const sel = c.published.filter(e => e.type === 'select' || e.type === 'unselect').map(e => e.type).join(',');
    g('mark-click-select', sel === 'select,select' && c.elements.every(e => !e.map || e.map.row >= 0
      || !((e.trackText && e.trackText.states && e.trackText.states.some(x => /select/.test(x || '')))
        || /select/.test(e.finalText.states || ''))), sel);
  }
  // [R2-I1]
  {
    const c = byId(cases, 'mp-emph-position');
    const at = (part, ms) => [numAt(mk(c, 0, part), 'tx', ms), numAt(mk(c, 0, part), 'ty', ms)].join(',');
    g('mp-emph-position-moves', at('mp0#label', 250) !== at('mp0#label', 1600) && at('mp1#label', 650) !== at('mp1#label', 1600)
      && at('mp2#label', 1000) !== at('mp2#label', 1600), [at('mp0#label', 250), at('mp0#label', 1600)].join(' '));
  }
  {
    const c = byId(cases, 'mp-label-state-only');
    const l0 = mk(c, 0, 'mp0#label');
    const l1 = mk(c, 0, 'mp1#label');
    g('mp-label-state-only', l0 && l1 && numAt(l0, 'ignore', 250) === false && numAt(l0, 'ignore', 1600) === true
      && numAt(l1, 'ignore', 650) === false && numAt(l1, 'ignore', 250) === true, 'mp-label-state-only');
  }
  {
    const c = byId(cases, 'ml-label-state-only');
    const l = mk(c, 0, 'ml0#label');
    g('ml-label-state-only', l && numAt(l, 'ignore', 250) === false && numAt(l, 'ignore', 1600) === true, 'ml-label-state-only');
  }
  {
    const c = byId(cases, 'ma-label-state-only');
    const l = mk(c, 0, 'ma0#label');
    const l1 = mk(c, 0, 'ma1#label');
    g('ma-label-state-only', l && numAt(l, 'ignore', 250) === false && numAt(l, 'ignore', 1600) === true
      && numAt(l1, 'ty', 650) !== numAt(l1, 'ty', 1600), 'ma-label-state-only');
  }
  // [R2-I4]
  {
    const c = byId(cases, 'mp-emph-formatter');
    const t = (part, ms) => numAt(mk(c, 0, part), 'txt', ms);
    g('mp-emph-formatter', t('mp0#label', 250) === 'hi max (36)' && t('mp0#label', 1600) === 'max: 36'
      && t('mp1#label', 650) === 'markPoint:min:emphasis:1' && t('mp1#label', 1600) === 'min: 5'
      && t('mp2#label', 1000) === 'markPoint:c:normal:2' && t('mp2#label', 1600) === 'markPoint:c:normal:2',
      [t('mp0#label', 250), t('mp1#label', 650), t('mp2#label', 1000)].join(' | '));
  }
  {
    const c = byId(cases, 'ml-emph-formatter');
    const t = (part, ms) => numAt(mk(c, 0, part), 'txt', ms);
    g('ml-emph-formatter', t('ml0#label', 250) !== t('ml0#label', 1600) && t('ml1#label', 650) === 'markLine:thirty:emphasis:1',
      [t('ml0#label', 250), t('ml0#label', 1600), t('ml1#label', 650)].join(' | '));
  }
  {
    const c = byId(cases, 'ma-emph-formatter');
    const t = (part, ms) => numAt(mk(c, 0, part), 'txt', ms);
    g('ma-emph-formatter', t('ma0#label', 250) === '[one]' && t('ma0#label', 1600) === 'one'
      && t('ma1#label', 650) === 'markArea:two:emphasis:1', [t('ma0#label', 250), t('ma1#label', 650)].join(' | '));
  }
  // [R2-I5]
  {
    const c = byId(cases, 'mk-blur-formatter');
    const t = (part, ms) => numAt(mk(c, 0, part), 'txt', ms);
    g('mk-blur-formatter', t('mp0#label', 250) === 'blur max' && t('mp0#label', 1600) === 'max: 36'
      && t('mp1#label', 250) === 'markPoint:min:blur:1' && t('mp2#label', 250) === 'blur c' && t('mp2#label', 1600) === 'c: 30'
      && t('ml0#label', 250) !== t('ml0#label', 1600) && t('ma0#label', 250) === '(one)'
      && t('ma1#label', 250) === 'markArea:two:blur:1',
      [t('mp0#label', 250), t('mp1#label', 250), t('mp2#label', 250), t('ml0#label', 250), t('ma0#label', 250),
        t('ma1#label', 250)].join(' | '));
  }
  {
    const c = byId(cases, 'mk-empty-normal');
    const t = (part, ms) => numAt(mk(c, 0, part), 'txt', ms);
    g('mk-empty-normal', t('mp0#label', 1600) === '' && t('mp0#label', 250) === 'hover max'
      && t('mp1#label', 1000) === 'blur 5' && t('ml0#label', 550) !== '' && t('ml0#label', 1600) === ''
      && t('ma0#label', 850) === 'area' && t('ma0#label', 1600) === '',
      [t('mp0#label', 250), t('mp1#label', 1000), t('ml0#label', 550), t('ma0#label', 850)].join(' | '));
  }
  {
    const c = byId(cases, 'mk-dash-word');
    const d = (part, ms) => numAt(mk(c, 0, part), 'dash', ms);
    g('mk-dash-word', d('ml0', 250) === '[12,6]' && d('ml0', 1600) === '[4,2]' && d('mp0', 650) === '[4]'
      && d('mp0', 1600) === '[1]' && d('ma0', 1000) === '[12,6]' && d('ma0', 1600) === '[4,2]',
      [d('ml0', 250), d('mp0', 650), d('ma0', 1000)].join(' | '));
  }
  {
    const c = byId(cases, 'mk-state-pen');
    const ty = (part, ms) => Number(numAt(mk(c, 0, part), 'ty', ms));
    g('mk-state-pen', ty('ma0#label', 250) - ty('ma0#label', 1600) === -5 && ty('ma0#label', 650) - ty('ma0#label', 1600) === -2
      && ty('mp0#label', 550) - ty('mp0#label', 1600) === -4 && ty('mp0#label', 650) - ty('mp0#label', 1600) === -1,
      [ty('ma0#label', 250), ty('ma0#label', 650), ty('mp0#label', 550), ty('mp0#label', 650), ty('mp0#label', 1600)].join(' '));
  }
  for (const c of cases) g('settled-' + c.id, c.clips[c.clips.length - 1] === 0, c.id + ' ' + c.clips.join(','));
  return out;
}

function generate() {
  const cases = [];
  for (const c of HOVER.concat(FOCUS, ITEMBLUR, SELECT, R2I1, R2I3, R2I4, R2I5)) {
    if (process.env.ORACLE_CASE && !process.env.ORACLE_CASE.split('|').some(p => c.id.startsWith(p))) continue;
    const r = runCase(c);
    cases.push({ id: c.id, note: c.note, option: c.option, events: r.events, published: r.published,
      selection: r.selection, clips: r.clips, elements: r.elements });
  }
  const gs = process.env.ORACLE_CASE ? [] : guards(cases);
  for (const c of cases) c.elements = c.elements.filter(e => e.map || e.everStates);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'R2-B: the markers\' own states -- hover emphasis, emphasis.focus / blurScope around the host series, data items\' '
      + 'own emphasis and blur, a click selecting the host\'s item. Driven and recorded as advchart-states-misc.json; a '
      + 'label also has tx / ty, its computed transform\'s translation.',
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
