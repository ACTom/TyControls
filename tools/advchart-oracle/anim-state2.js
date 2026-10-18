// F3a (fix phase, 2026-10-18): the STATE TRANSITIONS of the series the
// fix phase moved onto the shared state model (F2), against the clock:
//
//   A. a gauge's pointer and arc, a radar's polyline and polygon, hovered
//      WHILE THEY ENTER -- the state runs on the same element as the enter
//      animation, so saveCurrentToNormalState saves the enter's end values
//      into the normal state and the way back tweens them (Element.ts
//      saveCurrentToNormalState / Animator.saveTo)
//   B. a graph's node (a Symbol: emphasis scaleX = _sizeX * ratio, an
//      absolute scale), its edges (Line), focus adjacency; and while its
//      symbols pop in
//   C. a tree's node and its edge, focus descendant, and while it enters
//   D. a treemap's rects (getStateItemStyle), focus descendant
//   E. a sankey's node rects and bands (lineStyle states), focus adjacency,
//      and the selectchanged of a clicked node and band: one entry per data
//      (node, edge) of the series
//
// The harness is states-misc.js' own, copied (that script generates and
// exits on load): the replaced Date before the dist, chart._ssr = false,
// env.node = false, the seeded Math.random, hand-stepped frames, every case
// on its own stretch of the clock, the elements mapped to the port's parts.
// A LIVE case sets its option at T1 (sample 0 is the setOption's flush) and
// is not settled first.
//
// Run: node tools/advchart-oracle/anim-state2.js
//   -> tests/fixtures/advchart-anim-state2.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-anim-state2.json');

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
function flatNums(v, o) {
  for (const e of v) {
    if (e != null && typeof e === 'object' && e.length != null) flatNums(e, o);
    else o.push(typeof e === 'number' ? e : NaN);
  }
  return o;
}
function enc(v) {
  if (typeof v === 'number') return [hex(v), text(v)];
  if (typeof v === 'string' || typeof v === 'boolean') return [v, v];
  if (v && typeof v === 'object' && v.length != null) {
    const f = flatNums(v, []);
    return [f.map(hex), f.map(text)];
  }
  if (v && typeof v === 'object' && v.colorStops) {
    const s = JSON.stringify(v);
    return [s, s];
  }
  return undefined;
}
function snap(el) {
  const o = {};
  const put = (k, v) => {
    const e = enc(v);
    if (e !== undefined) o[k] = e;
  };
  for (const k of TRANSFORM_KEYS) if (typeof el[k] === 'number') put(k, el[k]);
  put('ignore', !!el.ignore);
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
    // a radar's polyline and polygon: their few points
    if ((el.type === 'polyline' || el.type === 'polygon') && el.shape.points && el.shape.points.length <= 16) {
      put('shape.points', el.shape.points);
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
    // a label of no words draws nothing, and the port builds none (a treemap
    // root's upper label) [F3a]
    const label = el.getTextContent && el.getTextContent();
    if (label && label.style && label.style.text != null && label.style.text !== '') {
      m.set(label, { s, row, part: part === 'host' ? 'label' : part + '#label' });
    }
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
    // [F3a] a graph's node is its Symbol's path, an edge its Line group's line,
    // the end symbols the parts in their order, the group's text the edge's label
    if (type === 'graph') {
      data.each(i => {
        const g = data.getItemGraphicEl(i);
        if (g) put(g.childAt(0), s, i, 'host');
      });
      const ed = sm.getEdgeData();
      ed.each(e => {
        const g = ed.getItemGraphicEl(e);
        if (!g) return;
        m.set(g.childOfName('line'), { s, row: e, part: 'edge' });
        let k = 0;
        for (const n of ['fromSymbol', 'toSymbol']) {
          const sym = g.childOfName(n);
          if (sym) m.set(sym, { s, row: e, part: 'edgepart' + k++ });
        }
        const lab = g.getTextContent();
        if (lab && lab.style && lab.style.text) m.set(lab, { s, row: e, part: 'edgelabel' });
      });
      return;
    }
    // a tree's node its Symbol's path, its edge (symbolEl.__edge) the second row
    if (type === 'tree') {
      data.each(i => {
        const g = data.getItemGraphicEl(i);
        if (!g) return;
        put(g.childAt(0), s, i, 'host');
        if (g.__edge) m.set(g.__edge, { s, row: i, part: 'edge' });
      });
      return;
    }
    // a treemap leaf: its group's content the host, its background part0; a
    // parent's background the host (its upper label the label)
    if (type === 'treemap') {
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        if (el.isGroup) {
          const bg = el.childAt(0);
          const content = el.childAt(1);
          if (content) {
            put(content, s, i, 'host');
            m.set(bg, { s, row: i, part: 'part0' });
          }
          else put(bg, s, i, 'host');
        }
        else put(el, s, i, 'host');
      });
      return;
    }
    // a sankey's node rect, and its bands the second row
    if (type === 'sankey') {
      data.each(i => put(data.getItemGraphicEl(i), s, i, 'host'));
      const ed = sm.getEdgeData();
      ed.each(e => {
        const el = ed.getItemGraphicEl(e);
        if (!el) return;
        m.set(el, { s, row: e, part: 'edge' });
        const lab = el.getTextContent();
        if (lab && lab.style && lab.style.text) m.set(lab, { s, row: e, part: 'edgelabel' });
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
  // [F3a] or its label, which hovers it as well (a label over a symbol
  // still popping in)
  const label = el.getTextContent && el.getTextContent();
  const mine = t => t === el || (label && t && (t === label || t.parent === label));
  return aimIn(chart, globalBox(el), (x, y, h) => {
    if (!mine(h.target)) return false;
    for (let dy = -m; dy <= m; dy++) {
      for (let dx = -m; dx <= m; dx++) {
        if (!mine(zr.handler.findHover(x + dx, y + dy).target)) return false;
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
  // [F3a] a graph edge's line; a sankey band; a treemap leaf's content, a
  // node's background
  if (k === 'gedge') return aimAt(chart, sm.getEdgeData().getItemGraphicEl(i).childOfName('line'));
  if (k === 'sedge') return aimAt(chart, sm.getEdgeData().getItemGraphicEl(i));
  if (k === 'tmc') return aimAt(chart, itemEl(chart, s, i).childAt(1));
  if (k === 'tmbg') {
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
    // A LIVE CASE sets its option here: the setOption flushes (its clips
    // start at once) and the sample makes no further frame [F3a]
    let flushed = false;
    if (c.live && si === 0) {
      chart.setOption(JSON.parse(JSON.stringify(c.option)));
      flushed = true;
    }
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
      // [F3a] a treemap's pan as its view dispatches it: the root's layout
      // moved by (dx, dy) -- written as the action it is
      else if (e.type === 'tmmove') {
        const sm = chart.getModel().getSeriesByIndex(e.s);
        const L = sm.getData().tree.root.getLayout();
        e.payload = { type: 'treemapMove', seriesIndex: e.s,
          rootRect: { x: L.x + e.dx, y: L.y + e.dy, width: L.width, height: L.height } };
        e.type = 'action';
        chart.dispatchAction(JSON.parse(JSON.stringify(e.payload)));
      }
      else must(false, 'unknown event ' + e.type);
    }
    if (!flushed) zr.animation.update();
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
  caseBase += CASE_STRIDE;
  NOW = caseBase;
  rngState = SEED;
  const chart = newChart();
  try {
    if (!c.live) {
      chart.setOption(JSON.parse(JSON.stringify(c.option)));
      settle(chart, caseBase);
    }
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
const over = (at, pick) => ({ at, type: 'move', pick });
const out = at => ({ at, type: 'out' });
const click = (at, pick) => ({ at, type: 'click', pick });
const act = (at, payload) => ({ at, type: 'action', payload });

const GRAPH_NODES = [{ name: 'a', x: 10, y: 10 }, { name: 'b', x: 100, y: 50 }, { name: 'c', x: 50, y: 100 },
  { name: 'd', x: 120, y: 120 }];
const GRAPH_LINKS = [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }, { source: 'c', target: 'd' }];
const graph = s => ({ color: [C0, C1, C2, C3], series: [Object.assign({ type: 'graph', layout: 'none', symbolSize: 20,
  label: { show: true }, edgeSymbol: ['none', 'arrow'], edgeLabel: { show: true, formatter: 'e' },
  data: GRAPH_NODES, links: GRAPH_LINKS }, s || {})] });
const TREE = [{ name: 'root', children: [
  { name: 'a', children: [{ name: 'a1' }, { name: 'a2' }] },
  { name: 'b', children: [{ name: 'b1' }] },
  { name: 'c' }] }];
const tree = s => ({ color: [C0, C1], series: [Object.assign({ type: 'tree', symbolSize: 12, data: TREE }, s || {})] });
const HIER = [
  { name: 'a', value: 10, children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 6 }] },
  { name: 'b', value: 5, children: [{ name: 'b1', value: 5 }] },
  { name: 'c', value: 3 }];
const treemap = s => ({ color: [C0, C1, C2], series: [Object.assign({ type: 'treemap', breadcrumb: { show: false },
  roam: false, nodeClick: false, data: HIER }, s || {})] });
const SANKEY_NODES = [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }];
const SANKEY_LINKS = [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 3 },
  { source: 'b', target: 'd', value: 4 }, { source: 'c', target: 'd', value: 2 }];
const sankey = s => ({ color: [C0, C1, C2, C3], series: [Object.assign({ type: 'sankey', draggable: false,
  data: SANKEY_NODES, links: SANKEY_LINKS }, s || {})] });
const gauge = s => ({ color: [C0, C1, C2], series: [Object.assign({ type: 'gauge', radius: '80%',
  progress: { show: true, width: 14 }, pointer: { width: 10 }, detail: { show: false }, title: { show: false },
  data: [{ value: 60, name: 'a' }] }, s || {})] });
const radar = s => ({ color: [C0, C1, C2], radar: { radius: '65%', indicator: [{ name: 'a', max: 10 },
  { name: 'b', max: 10 }, { name: 'c', max: 10 }, { name: 'd', max: 10 }, { name: 'e', max: 10 }] },
  series: [Object.assign({ type: 'radar', symbolSize: 10,
    data: [{ value: [6, 8, 4, 7, 5], name: 'p' }, { value: [3, 4, 9, 2, 8], name: 'q' }] }, s || {})] });

const CASES = [
  // ---- the gauge and the radar while they enter: the same element animates ----
  { id: 'gauge-enter-hover', live: true,
    note: 'the option set at T1 (the enter running: the pointer turns, the arc grows); hover the pointer at 100 -- '
      + 'saveCurrentToNormalState saves the rotation\'s end into the normal state; out at 300 -- the way back to '
      + 'normal tweens the rotation from where it is (the enter\'s track stopped)',
    option: gauge(), events: [over(100, ['gp', 0, 0]), out(300)] },
  { id: 'gauge-enter-hover-arc', live: true,
    note: 'the same on the progress arc: its endAngle is saved and tweened back',
    option: gauge(), events: [over(400, ['gq', 0, 0]), out(650)] },
  { id: 'radar-enter-hover', live: true,
    note: 'a radar entering (its points out of the centre): hover a symbol at 150, out at 400 -- the polyline\'s and '
      + 'the polygon\'s points saved and tweened back',
    option: radar({ areaStyle: {} }), events: [over(150, ['rsym', 0, 0, 1]), out(400)] },
  // ---- graph ----
  { id: 'graph-hover', note: 'hover node b at 0: its path scales to _sizeX * 1.1 (absolute), the fill lifts, the label '
      + 'stays; hover the edge b-c at 500 (the line\'s stroke lifts, its arrow and label with it); out at 1000',
    option: graph(), events: [over(0, ['item', 0, 1]), over(500, ['gedge', 0, 1]), out(1000)] },
  { id: 'graph-scale', note: 'emphasis.scale 1.6 on an oblong symbol ([24, 12]): scaleX 12 * 1.6, scaleY 6 * 1.6',
    option: graph({ symbolSize: [24, 12], emphasis: { scale: 1.6 } }), events: [over(0, ['item', 0, 2]), out(500)] },
  { id: 'graph-adjacency', note: 'focus adjacency: hovering c keeps b, d and the two edges, the rest blurs (opacity 0.1 '
      + 'of each); out at 500',
    option: graph({ emphasis: { focus: 'adjacency' } }), events: [over(0, ['item', 0, 2]), out(500)] },
  { id: 'graph-enter-hover', live: true,
    note: 'the option set at T1 (the symbols popping in): hover node a at 500 -- saveTo puts the pop-in\'s scale end into '
      + 'the normal state, emphasis scales from where it is; out at 700',
    option: graph(), events: [over(500, ['item', 0, 0]), out(700)] },
  // ---- tree ----
  { id: 'tree-hover', note: 'hover node a at 0: its path to 6 * 1.1, the fill lifts; out at 500',
    option: tree(), events: [over(0, ['item', 0, 2]), out(500)] },
  { id: 'tree-descendant', note: 'focus descendant: hovering a blurs root, b, b1, c and their edges; out at 500',
    option: tree({ emphasis: { focus: 'descendant' } }), events: [over(0, ['item', 0, 2]), out(500)] },
  { id: 'tree-enter-hover', live: true,
    note: 'the option set at T1: hover node a at 550 (its group has arrived at 500, its symbol still pops in -- '
      + 'linear 700); out at 800',
    option: tree(), events: [over(550, ['item', 0, 2]), out(800)] },
  // ---- treemap ----
  { id: 'treemap-hover', note: 'hover leaf a1 at 0 (its content and background lift), then leaf c at 500; out at 1000',
    option: treemap(), events: [over(0, ['tmc', 0, 2]), over(500, ['tmc', 0, 6]), out(1000)] },
  { id: 'treemap-descendant', note: 'focus descendant on a parent: hovering a\'s background keeps a1, a2, the rest blurs '
      + '(the blur colour); out at 500',
    option: treemap({ upperLabel: { show: true }, emphasis: { focus: 'descendant' } }),
    events: [over(0, ['tmbg', 0, 1]), out(500)] },
  { id: 'treemap-move-hover', note: 'roam: hover leaf a1 at 0, the view pans (treemapMove, the root moved 20 px right) at '
      + '150 while the lift runs -- the render keeps the elements and their states; out at 700',
    option: treemap({ roam: true }), events: [over(0, ['tmc', 0, 2]), { at: 150, type: 'tmmove', s: 0, dx: 20, dy: 0 },
      out(700)] },
  // ---- sankey ----
  { id: 'sankey-hover', note: 'hover node b at 0 (its fill lifts), then the band a-c at 500 (its opacity to 0.5, the '
      + 'fill lifts); out at 1000',
    option: sankey(), events: [over(0, ['item', 0, 1]), over(500, ['sedge', 0, 1]), out(1000)] },
  { id: 'sankey-adjacency', note: 'focus adjacency: hovering b keeps a, d and the bands a-b, b-d; the rest blurs; out at 500',
    option: sankey({ emphasis: { focus: 'adjacency' } }), events: [over(0, ['item', 0, 1]), out(500)] },
  { id: 'sankey-select', note: 'selectedMode multiple: click node a at 0, the band b-d at 400, node a again at 800 -- '
      + 'selectchanged lists every data (node and edge) of the series',
    option: sankey({ selectedMode: 'multiple', select: { itemStyle: { color: C3 }, lineStyle: { color: C3 } } }),
    events: [click(0, ['item', 0, 0]), out(200), click(400, ['sedge', 0, 2]), out(600), click(800, ['item', 0, 0]),
      out(1000)] },
];

// ---------- the writer ----------
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
const elRow = (c, s, row, part) => c.elements.find(e => e.map && e.map.s === s && e.map.row === row && e.map.part === part);
const valAt = (el, key, ms) => {
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
  // the enter and the state on the same element: the way back tweens a key
  // the state never set (saveTo put the enter's end into the normal state)
  {
    // the pointer: the rotation's end saved into the normal state, so even
    // entering emphasis tweens the rotation there (a root-key animator)
    const p = elRow(byId(cases, 'gauge-enter-hover'), 0, 0, 'host');
    const has = (el, name) => el.stateAnimators && el.stateAnimators.some(x => x.split(' ').indexOf(name) >= 0);
    g('gauge-rotation-saved', has(p, 'emphasis:') && has(p, '__zr_normal__:'), JSON.stringify(p.stateAnimators));
    // the arc and the radar's rings: a state's shape is a new object, the
    // enter's shape tween goes on
    const q = elRow(byId(cases, 'gauge-enter-hover-arc'), 0, 0, 'peer');
    g('gauge-arc-shape-goes-on', q.stateAnimators && !q.stateAnimators.some(x => x.indexOf(':shape') >= 0),
      JSON.stringify(q.stateAnimators));
    const r = elRow(byId(cases, 'radar-enter-hover'), 0, 0, 'host');
    g('radar-points-go-on', r.stateAnimators && !r.stateAnimators.some(x => x.indexOf(':shape') >= 0),
      JSON.stringify(r.stateAnimators));
  }
  // the graph's and the tree's scale is absolute: _sizeX * ratio
  {
    const p = elRow(byId(cases, 'graph-hover'), 0, 1, 'host');
    g('graph-scale-absolute', valAt(p, 'scaleX', 450) === String(10 * 1.1), valAt(p, 'scaleX', 450));
    const q = elRow(byId(cases, 'graph-scale'), 0, 2, 'host');
    g('graph-scale-oblong', valAt(q, 'scaleX', 450) === String(12 * 1.6) && valAt(q, 'scaleY', 450) === String(6 * 1.6),
      valAt(q, 'scaleX', 450) + ' ' + valAt(q, 'scaleY', 450));
    const t = elRow(byId(cases, 'tree-hover'), 0, 2, 'host');
    g('tree-scale-absolute', valAt(t, 'scaleX', 450) === String(6 * 1.1), valAt(t, 'scaleX', 450));
  }
  // the treemap and the sankey transition at all
  {
    const c = byId(cases, 'treemap-hover');
    g('treemap-transitions', c.elements.some(e => e.stateAnimators), 'treemap');
    const s = byId(cases, 'sankey-hover');
    const e = elRow(s, 0, 1, 'edge');
    g('sankey-band-transitions', e && e.stateAnimators && e.stateAnimators.some(x => x.indexOf('emphasis') === 0),
      JSON.stringify(e && e.stateAnimators));
  }
  // a sankey's selectchanged lists the node data and the edge data
  {
    const c = byId(cases, 'sankey-select');
    const sc = c.published.filter(e => e.type === 'selectchanged');
    g('sankey-selectchanged-two', sc.length === 3 && sc.every(e => e.selected.length === 2
      && e.selected[0].dataType === 'node' && e.selected[1].dataType === 'edge'), JSON.stringify(sc));
  }
  for (const c of cases) {
    g('settled:' + c.id, c.clips[SAMPLES.length - 1] === 0, c.id + ' ' + c.clips[SAMPLES.length - 1]);
  }
  return out;
}

function generate() {
  const cases = [];
  for (const c of CASES) {
    if (process.env.ORACLE_CASE && !process.env.ORACLE_CASE.split('|').some(p => c.id.startsWith(p))) continue;
    const r = runCase(c);
    cases.push({ id: c.id, note: c.note, live: !!c.live, option: c.option, events: r.events, published: r.published,
      selection: r.selection, clips: r.clips, elements: r.elements });
  }
  const gs = process.env.ORACLE_CASE ? [] : guards(cases);
  for (const c of cases) c.elements = c.elements.filter(e => e.map || e.everStates);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'F3a: the state transitions of the gauge and the radar during their enter, the graph, the tree, the treemap '
      + 'and the sankey, and the sankey\'s selectchanged. A case sets `option` at T0 and settles -- a live one sets it '
      + 'at T1 instead (sample 0 is that setOption\'s flush, no further frame) -- then at each sample t of samplesMs: '
      + 'the events at t (move: handler.mousemove at x,y; click: mousemove, mousedown, mouseup, click at x,y; out: '
      + 'mousemove at 3,3; action: dispatchAction), then NOW = T1 + t and one zr.animation.update(), then the record. '
      + 'Element keys as advchart-states-misc.json (plus a radar polyline\'s / polygon\'s shape.points, flat); map: the '
      + 'port\'s part {s, row (inner index), part}: host, label, peer, rarea, rsym<j>, part<k>, edge, edgepart<k>, '
      + 'edgelabel. published: the chart\'s events per sample; selection as states-misc.',
    W, H, seed: SEED,
    clock: { T1Offset: T1_OFFSET, note: 'each case on a clock of its own, later than every earlier one (the generation runs twice): '
      + 'only times relative to its t0 are written; T1 = t0 + T1Offset' },
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
