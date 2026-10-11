// Upstream's own answers for visualMap INTERACTION (batch 116, roadmap C7):
// what a continuous visualMap does when its handles, their labels or the
// in-range bar are dragged (calculable, realtime on / off, inverse,
// horizontal / vertical), what the hover indicator shows when the pointer is
// over the bar or over a data item (hoverLink both ways), which data items the
// highlight / downplay batches reach, what a piecewise visualMap's item click
// does to `selected` (single / multiple / true / false), what the
// selectDataRange action does, and the events all of that publishes.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist by default, or
// ECHARTS_DIST) in node: echarts.init(null, null, {renderer: 'svg', ssr: true})
// and right after init chart._ssr = false (the browser's model, as
// select-legend.js / state-anim.js), echarts.env.node = false (so a COMPONENT
// model may animate: Model.isAnimationEnabled refuses under env.node), Math.random
// replaced by the port's xorshift32 (seed 2463534242, reset per case). The
// pointer goes through zrender's own Handler (handler.mousemove / mousedown /
// mouseup / click / mouseout with {zrX, zrY, which 1, preventDefault,
// stopPropagation}): findHover, the element events and their bubbling, the
// zr-level listeners (zrender's Draggable, echarts' hover emphasis, the
// visualMap's own zr.on('mouseover' / 'mouseout')) run as in a browser. An
// 'up' step is mouseup and then the browser's DOM click at the same point.
//
// TIME. The global Date is replaced before the dist loads (new Date() /
// Date.now read NOW); setTimeout / clearTimeout are a queue fired when the
// clock passes the due time (nothing in these cases arms one -- checked). The
// zrender animation loop is not started under the ssr init, so FRAMES are
// stepped by hand: zr.animation.update() steps every clip and then fires
// 'frame', which runs echarts' _onframe (applyChangedStates: the hover / blur
// flags become state lists, zrender's useStates). A step of a STATIC case
// (every case but the anim-* ones, all with option animation false) is: the
// clock advances by dt (default 300 ms), the event, a frame at NOW, a frame at
// NOW + 16, a frame at NOW + 300 (so the handle labels' 200 ms blur
// transition -- stateTransition, which runs whatever option.animation says --
// has started and ended), and NOW stays at the last frame. A step of an
// ANIMATED case is the event and one frame at NOW; a 'frame' step is only the
// frame. Then storage.getDisplayList(true) (transforms for the next hit test)
// and the record.
//
//   node tools/advchart-oracle/visualmap-interact.js
//
// writes tests/fixtures/advchart-visualmap-interact.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex    a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//          lowercase (NaN 7ff8000000000000); every hex has a readable twin
//          (field + 'Text': String(v), '-0' for negative zero).
//   colour [r, g, b, a] from zrender's color.parse of the element's fill (the
//          string as the element holds it, in 'fillText'); null when the fill
//          is not set.
//
// Top level: source, W, H, seed, clock, notes[], cases[], guards[], recipes[]
//   case: id, group, note, animated, option (as fed to setOption), seriesIds
//     (the models' ids, by series index), visualMapIds, steps[]
//   step: i, t ('init' | 'move' | 'down' | 'up' | 'out' | 'action' | 'set' |
//     'frame'), x, y (integers; null where there is no pointer), dt, now (ms
//     after the case's start), payload (action), option + notMerge (set),
//     hover (the role under the pointer BEFORE the event: handler.findHover),
//     events[], vms[], series[]
//   events: every chart event of the types highlight, downplay,
//     datarangeselected, in order:
//     {type, batch: [{s (series index of seriesId), idx (dataIndexInside, as
//       is), key (highlightKey)}] | null, plain (the payload without batch,
//       JSON with auto ids replaced, for an event that has no batch) | null,
//       vm (visualMapId -> index) | null, from (the payload had `from`),
//       selected (continuous: hex[2] + selectedText; piecewise: [[key, value]]
//       in the object's key order) | null}
//   vms[k] (every visualMap, component order):
//     subType, model: continuous {range hex[2] + rangeText (option.range)};
//       piecewise {selected [[key, value]] (option.selected, key order)}
//     continuous view: interval / handleEnds (hex[2] + Text: _dataInterval /
//       _handleEnds), dragging, hovering, firstShow (_firstShowIndicator),
//       hoverIdx [[s, [inner...]]] (_hoverLinkDataIndices, seriesId -> index),
//       group [x, y] hex + Text (view.group.x / y), inPts (inRange
//       shape.points flat, hex + Text), handles[] {x, y, scale hex + Text,
//       fill colour + fillText, hover (thumb hoverState), emph (thumb
//       currentStates includes 'emphasis'), label {text, x, y hex + Text,
//       align, blur (label hoverState === 1), opacity (style.opacity, null =
//       1)}}, indicator {invisible, x, y hex + Text, fill colour + fillText,
//       animators}, indLabel {invisible, text, x, y hex + Text, align,
//       verticalAlign}
//     piecewise view: items[] {piece (index in the model's piece list), fill
//       colour + fillText (the symbol's), labelOpacity (null: no label)}
//   series[s]: [{i (inner index), raw, hover (hoverState of the dispatcher:
//     the rect / the Symbol group), hbo (__highByOuter != 0), states
//     (currentStates of the element that draws, joined), fill colour +
//     fillText (that element's style.fill after the frame), opacity}]
//   measure[]: {string, width, height} hex + Text: echarts.format.getTextRect(string,
//     '12px sans-serif') of every text a visualMap view held at any record
//   roles: 'vm<k>.outOfRange' | 'inRange' | 'handle<i>' | 'label<i>' |
//     'indicator' | 'indLabel' | 'text<i>' | 'item<piece>.symbol' |
//     'item<piece>.label' | 'ends<i>' | 'background', 's<i>.item<inner>',
//     's<i>.label<inner>', 'other', null
//
// Self-checks (any failure: nothing is written, exit 1): the recipes (R1 the
// indicator: an '≈' label is formatValueText of linearMap of the indicator's
// y back into the extent; R2 the handle drag: sliderMove on the inverted bar
// transform of the event's delta reproduces _handleEnds, and linearMap the
// interval; R3 the first hover on the bar: the pointer through the inverted
// bar transform, the half size, the open ends and findTargetDataIndices over
// the store reproduce its highlight batch; R4 the piecewise click: the map
// after from the map before; each must run at least once); the guards
// (distinguishing counts that must each be >= 1); no \u0000 in the output;
// the JSON parses back; two generations in one process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

// ---------- the fake clock and timers (installed before the build loads) ----------
const RealDate = Date;
const CLOCK0 = 1700000000000;
let NOW = CLOCK0;
class FakeDate extends RealDate {
  constructor(...a) {
    if (a.length) super(...a);
    else super(NOW);
  }
  static now() { return NOW; }
}
global.Date = FakeDate;
let TIMERS = [];
let timerSeq = 0;
global.setTimeout = function (fn, ms) {
  const id = ++timerSeq;
  TIMERS.push({ id, due: NOW + (+ms || 0), fn });
  return id;
};
global.clearTimeout = function (id) {
  TIMERS = TIMERS.filter(t => t.id !== id);
};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
echarts.env.node = false;
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-visualmap-interact.json');

const W = 600;
const H = 400;

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
const numRec = (name, v) => ({ [name]: hex(v), [name + 'Text']: text(v) });
const arrRec = (name, a) => ({ [name]: Array.from(a, hex), [name + 'Text']: Array.from(a, text) });
function colourOf(fill) {
  if (fill == null || typeof fill !== 'string') return null;
  const c = echarts.color.parse(fill);
  return c ? [c[0], c[1], c[2], c[3]] : null;
}
const fillRec = fill => ({ fill: colourOf(fill), fillText: fill == null ? null : typeof fill === 'string' ? fill : '[object]' });

// ---------- ECData (discovered: the inner store's key on an element) ----------
let ecKey = null;
function getECData(el) {
  return (ecKey && el && el[ecKey]) || null;
}
function newChart() {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function discoverECKey() {
  const c = newChart();
  c.setOption({ animation: false, xAxis: { type: 'category', data: ['a'] }, yAxis: {}, series: [{ type: 'bar', data: [1] }] });
  const el = c.getModel().getSeriesByIndex(0).getData().getItemGraphicEl(0);
  for (const k of Object.getOwnPropertyNames(el)) {
    const v = el[k];
    if (v && typeof v === 'object' && Object.prototype.hasOwnProperty.call(v, 'dataIndex') && v.dataIndex === 0
      && Object.prototype.hasOwnProperty.call(v, 'seriesIndex')) ecKey = k;
  }
  c.dispose();
  must(ecKey, 'the ECData key was not found');
}

// =====================================================================
// The transcription the recipes check against
// =====================================================================
function linearMap(val, domain, range, clamp) {
  const d0 = domain[0]; const d1 = domain[1]; const r0 = range[0]; const r1 = range[1];
  const subDomain = d1 - d0; const subRange = r1 - r0;
  if (subDomain === 0) return subRange === 0 ? r0 : (r0 + r1) / 2;
  if (clamp) {
    if (subDomain > 0) {
      if (val <= d0) return r0;
      else if (val >= d1) return r1;
    } else {
      if (val >= d0) return r0;
      else if (val <= d1) return r1;
    }
  } else {
    if (val === d0) return r0;
    if (val === d1) return r1;
  }
  return (val - d0) / subDomain * subRange + r0;
}
function round(x, precision) {
  if (isNaN(precision)) return +x;
  precision = Math.min(Math.max(0, precision), 20);
  return +(+x).toFixed(precision);
}
function getPrecisionSafe(val) {
  const str = val.toString().toLowerCase();
  const eIndex = str.indexOf('e');
  const exp = eIndex > 0 ? +str.slice(eIndex + 1) : 0;
  const significandPartLen = eIndex > 0 ? eIndex : str.length;
  const dotIndex = str.indexOf('.');
  const decimalPartLen = dotIndex < 0 ? 0 : significandPartLen - 1 - dotIndex;
  return Math.max(0, decimalPartLen - exp);
}
function getPrecision(val) {
  val = +val;
  if (isNaN(val)) return 0;
  if (val > 1e-14) {
    let e = 1;
    for (let i = 0; i < 15; i++, e *= 10) if (Math.round(val * e) / e === val) return i;
  }
  return getPrecisionSafe(val);
}
function addSafe(val0, val1) {
  const maxPrecision = Math.max(getPrecision(val0), getPrecision(val1));
  const sum = val0 + val1;
  return maxPrecision > 20 ? sum : round(sum, maxPrecision);
}
function restrict(value, extend) {
  return Math.min(extend[1] != null ? extend[1] : Infinity, Math.max(extend[0] != null ? extend[0] : -Infinity, value));
}
function getSpanSign(handleEnds, handleIndex) {
  const dist = handleEnds[handleIndex] - handleEnds[1 - handleIndex];
  return { span: Math.abs(dist), sign: dist > 0 ? -1 : dist < 0 ? 1 : handleIndex ? -1 : 1 };
}
function sliderMove(delta, handleEnds, extent, handleIndex, minSpan, maxSpan) {
  delta = delta || 0;
  const extentSpan = addSafe(extent[1], -extent[0]);
  if (minSpan != null) minSpan = restrict(minSpan, [0, extentSpan]);
  if (maxSpan != null) maxSpan = Math.max(maxSpan, minSpan != null ? minSpan : 0);
  if (handleIndex === 'all') {
    let handleSpan = Math.abs(addSafe(handleEnds[1], -handleEnds[0]));
    handleSpan = restrict(handleSpan, [0, extentSpan]);
    minSpan = maxSpan = restrict(handleSpan, [minSpan, maxSpan]);
    handleIndex = 0;
  }
  handleEnds[0] = restrict(handleEnds[0], extent);
  handleEnds[1] = restrict(handleEnds[1], extent);
  const originalDistSign = getSpanSign(handleEnds, handleIndex);
  handleEnds[handleIndex] += delta;
  const extentMinSpan = minSpan || 0;
  const realExtent = extent.slice();
  if (originalDistSign.sign < 0) realExtent[0] = addSafe(realExtent[0], extentMinSpan);
  else realExtent[1] = addSafe(realExtent[1], -extentMinSpan);
  handleEnds[handleIndex] = restrict(handleEnds[handleIndex], realExtent);
  let currDistSign = getSpanSign(handleEnds, handleIndex);
  if (minSpan != null && (currDistSign.sign !== originalDistSign.sign || currDistSign.span < minSpan)) {
    handleEnds[1 - handleIndex] = addSafe(handleEnds[handleIndex], originalDistSign.sign * minSpan);
  }
  currDistSign = getSpanSign(handleEnds, handleIndex);
  if (maxSpan != null && currDistSign.span > maxSpan) {
    handleEnds[1 - handleIndex] = addSafe(handleEnds[handleIndex], currDistSign.sign * maxSpan);
  }
  return handleEnds;
}
function invert(a) {
  const aa = a[0]; const ac = a[2]; const atx = a[4];
  const ab = a[1]; const ad = a[3]; const aty = a[5];
  let det = aa * ad - ab * ac;
  if (!det) return null;
  det = 1.0 / det;
  return [ad * det, -ab * det, -ac * det, aa * det, (ac * aty - ad * atx) * det, (ab * atx - aa * aty) * det];
}
function applyM(m, x, y) {
  return [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
}
// util/model compressBatches, with the keys as strings
function compressBatches(batchA, batchB) {
  const mapA = {};
  const mapB = {};
  makeMap(batchA || [], mapA);
  makeMap(batchB || [], mapB, mapA);
  return [mapToArray(mapA), mapToArray(mapB)];
  function makeMap(sourceBatch, map, otherMap) {
    for (let i = 0, len = sourceBatch.length; i < len; i++) {
      const seriesId = sourceBatch[i].seriesId;
      if (seriesId == null) return;
      const dataIndices = [].concat(sourceBatch[i].dataIndex);
      const otherDataIndices = otherMap && otherMap[seriesId];
      for (let j = 0, lenj = dataIndices.length; j < lenj; j++) {
        const dataIndex = dataIndices[j];
        if (otherDataIndices && otherDataIndices[dataIndex]) otherDataIndices[dataIndex] = null;
        else (map[seriesId] || (map[seriesId] = {}))[dataIndex] = 1;
      }
    }
  }
  function mapToArray(map, isData) {
    const result = [];
    for (const i in map) {
      if (Object.prototype.hasOwnProperty.call(map, i) && map[i] != null) {
        if (isData) result.push(+i);
        else {
          const dataIndices = mapToArray(map[i], true);
          dataIndices.length && result.push({ seriesId: i, dataIndex: dataIndices });
        }
      }
    }
    return result;
  }
}
function formatValue(model, v) {
  const precision = model.option.precision;
  const bound = model.dataBound;
  const s = v === bound[0] ? 'min' : v === bound[1] ? 'max' : (+v).toFixed(Math.min(precision, 20));
  const f = model.option.formatter;
  if (typeof f === 'string') return f.replace('{value}', s).replace('{value2}', s);
  return s;
}

// =====================================================================
// The chart under the pointer
// =====================================================================
function makeCtx(chart, def) {
  const zr = chart.getZr();
  const h = zr.handler;
  const ecModel = () => chart.getModel();
  const vmModel = k => ecModel().getComponent('visualMap', k);
  const vmView = k => chart.getViewOfComponentModel(vmModel(k));
  const ctx = { chart, zr, h, def, last: null, vmModel, vmView };
  ctx.seriesIndexOfId = id => {
    let r = null;
    ecModel().eachSeries(s => { if (s.id === id) r = s.seriesIndex; });
    return r;
  };
  ctx.vmIndexOfId = id => {
    let r = null;
    ecModel().eachComponent('visualMap', (m, k) => { if (m.id === id) r = k; });
    return r;
  };
  ctx.vmCount = () => ecModel().getComponent('visualMap', 0) ? ecModel().queryComponents({ mainType: 'visualMap' }).length : 0;
  const G = el => { zr.storage.getDisplayList(true); return el.transform || [1, 0, 0, 1, 0, 0]; };
  const rnd = p => [Math.round(p[0]), Math.round(p[1])];
  ctx.handle = (k, i) => rnd(applyM(G(vmView(k)._shapes.handleThumbs[i]), 0, 0));
  ctx.label = (k, i) => {
    const el = vmView(k)._shapes.handleLabels[i];
    const r = el.getBoundingRect();
    return rnd(applyM(G(el), r.x + r.width / 2, r.y + r.height / 2));
  };
  ctx.bar = (k, frac, across) => {
    const v = vmView(k);
    const isz = vmModel(k).itemSize;
    return rnd(applyM(G(v._shapes.mainGroup), isz[0] * (across == null ? 0.5 : across), isz[1] * frac));
  };
  ctx.item = (s, i) => {
    const el = ecModel().getSeriesByIndex(s).getData().getItemGraphicEl(i);
    if (el.type === 'rect') {
      const r = el.shape;
      return rnd(applyM(G(el), r.x + r.width / 2, r.y + r.height / 2));
    }
    return rnd(applyM(G(el), 0, 0));
  };
  ctx.piece = (k, piece, part) => {
    const v = vmView(k);
    const groups = v.group.children().filter(g => g.onclick);
    const order = v._getViewData().viewPieceList.map(x => x.indexInModelPieceList);
    const g = groups[order.indexOf(piece)];
    must(g, 'no item for piece ' + piece);
    const el = part === 'label' ? g.childAt(1) : g.childAt(0);
    const r = el.getBoundingRect();
    return rnd(applyM(G(el), r.x + r.width / 2, r.y + r.height / 2));
  };
  ctx.rel = (dx, dy) => [ctx.last[0] + dx, ctx.last[1] + dy];
  // the role of an element
  ctx.role = el => {
    if (!el) return null;
    const n = ctx.vmCount();
    for (let k = 0; k < n; k++) {
      const v = vmView(k);
      const m = vmModel(k);
      if (m.type === 'visualMap.continuous') {
        const s = v._shapes;
        if (el === s.outOfRange) return 'vm' + k + '.outOfRange';
        if (el === s.inRange) return 'vm' + k + '.inRange';
        if (el === s.indicator) return 'vm' + k + '.indicator';
        if (el === s.indicatorLabel) return 'vm' + k + '.indLabel';
        for (let i = 0; s.handleThumbs && i < 2; i++) if (el === s.handleThumbs[i]) return 'vm' + k + '.handle' + i;
        for (let i = 0; s.handleLabels && i < 2; i++) if (el === s.handleLabels[i] || el.parent === s.handleLabels[i]) return 'vm' + k + '.label' + i;
      } else {
        const groups = v.group.children().filter(g => g.onclick);
        const order = v._getViewData().viewPieceList.map(x => x.indexInModelPieceList);
        for (let j = 0; j < groups.length; j++) {
          for (let e = el; e; e = e.__hostTarget || e.parent) {
            if (e.parent === groups[j]) return 'vm' + k + '.item' + order[j] + (e === groups[j].childAt(0) ? '.symbol' : '.label');
          }
        }
      }
      for (let e = el; e; e = e.__hostTarget || e.parent) if (e === v.group) return 'vm' + k + '.other';
    }
    for (let e = el; e; e = e.__hostTarget || e.parent) {
      const d = getECData(e);
      if (d && d.dataIndex != null && d.seriesIndex != null) {
        const host = ecModel().getSeriesByIndex(d.seriesIndex).getData().getItemGraphicEl(d.dataIndex);
        let isLabel = false;
        for (let x = el; x; x = x.__hostTarget || x.parent) if (x === host) break; else if (x.type === 'text' || x.type === 'tspan') isLabel = true;
        return 's' + d.seriesIndex + (isLabel ? '.label' : '.item') + d.dataIndex;
      }
    }
    return 'other';
  };
  return ctx;
}

// ---------- text measurement (zrender's own measurer, as visualmap-view.js) ----------
// every text a visualMap view holds at a record (ends texts, handle labels, the
// indicator label, piece labels) and '国', measured by echarts.format.getTextRect
// in the views' font; the port's test measures with this table.
const FONT = '12px sans-serif';
let MEASURE = new Map();
let MEASURING = false;
function measure(string) {
  if (MEASURING || MEASURE.has(string)) return;
  MEASURING = true;
  let r;
  try {
    r = echarts.format.getTextRect(string, FONT);
  } finally {
    MEASURING = false;
  }
  MEASURE.set(string, { string, width: hex(r.width), widthText: text(r.width), height: hex(r.height), heightText: text(r.height) });
}
// every text style zrender is handed (axis labels, a label set and then put back
// by a state) is measured too: the port measures what it lays out
const TextProto = echarts.graphic.Text.prototype;
const origDirtyStyle = TextProto.dirtyStyle;
TextProto.dirtyStyle = function () {
  if (this.style && typeof this.style.text === 'string' && (this.style.fontSize == null || this.style.fontSize === 12)) measure(this.style.text);
  else if (this.style && typeof this.style.text === 'number') measure(String(this.style.text));
  return origDirtyStyle.apply(this, arguments);
};
function measureView(v) {
  v.group.traverse(el => {
    if (el.type === 'text' && el.style && el.style.text != null) {
      must(el.style.fontSize == null || el.style.fontSize === 12, 'a visualMap text not at 12px');
      measure(String(el.style.text));
    }
  });
}

// ---------- the record ----------
function orderedEntries(obj) {
  if (obj == null || typeof obj !== 'object') return null;
  return Object.keys(obj).map(k => [k, obj[k] === undefined ? null : obj[k]]);
}
function vmRecord(ctx, k) {
  const m = ctx.vmModel(k);
  const v = ctx.vmView(k);
  if (m.type === 'visualMap.continuous') {
    const s = v._shapes;
    const rec = { subType: 'continuous', model: arrRec('range', m.option.range) };
    Object.assign(rec, arrRec('interval', v._dataInterval), arrRec('handleEnds', v._handleEnds));
    rec.dragging = !!v._dragging;
    rec.hovering = !!v._hovering;
    rec.firstShow = !!v._firstShowIndicator;
    rec.hoverIdx = (v._hoverLinkDataIndices || []).map(b => [ctx.seriesIndexOfId(b.seriesId),
      [].concat(b.dataIndex != null ? b.dataIndex : b.dataIndexInside)]);
    Object.assign(rec, arrRec('group', [v.group.x, v.group.y]));
    const pts = [];
    s.inRange.shape.points.forEach(p => pts.push(p[0], p[1]));
    Object.assign(rec, arrRec('inPts', pts));
    rec.handles = (s.handleThumbs || []).map((th, i) => {
      const lb = s.handleLabels[i];
      return Object.assign({}, numRec('x', th.x), numRec('y', th.y), numRec('scale', th.scaleX), fillRec(th.style.fill), {
        hover: th.hoverState || 0,
        emph: (th.currentStates || []).indexOf('emphasis') >= 0,
        label: Object.assign({ text: lb.style.text }, numRec('x', lb.style.x), numRec('y', lb.style.y), {
          align: lb.style.align, blur: lb.hoverState === 1, opacity: lb.style.opacity == null ? null : lb.style.opacity,
        }),
      });
    });
    const ind = s.indicator;
    rec.indicator = Object.assign({ invisible: !!ind.invisible }, numRec('x', ind.x), numRec('y', ind.y), fillRec(ind.style.fill),
      { animators: ind.animators.length + (ind.style && 0) });
    const il = s.indicatorLabel;
    rec.indLabel = Object.assign({ invisible: !!il.invisible, text: il.style.text }, numRec('x', il.style.x), numRec('y', il.style.y),
      { align: il.style.align || null, verticalAlign: il.style.verticalAlign || null });
    return rec;
  }
  const rec = { subType: 'piecewise', model: { selected: orderedEntries(m.option.selected) } };
  const groups = v.group.children().filter(g => g.onclick);
  const order = v._getViewData().viewPieceList.map(x => x.indexInModelPieceList);
  rec.items = groups.map((g, j) => {
    const sym = g.childAt(0);
    const lb = g.childCount() > 1 ? g.childAt(1) : null;
    return Object.assign({ piece: order[j] }, fillRec(sym.style.fill),
      { labelOpacity: lb ? (lb.style.opacity == null ? 1 : lb.style.opacity) : null });
  });
  return rec;
}
function seriesRecord(ctx) {
  const out = [];
  ctx.chart.getModel().eachSeries(sm => {
    const data = sm.getData();
    const list = [];
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) continue;
      const draw = el.type === 'group' ? el.childAt(0) : el;
      list.push(Object.assign({ i, raw: data.getRawIndex(i), hover: el.hoverState || 0, hbo: !!(el.__highByOuter || (draw.__highByOuter)),
        states: (draw.currentStates || []).join(',') }, fillRec(draw.style.fill),
      { opacity: draw.style.opacity == null ? 1 : draw.style.opacity }));
    }
    out[sm.seriesIndex] = list;
  });
  return out;
}
function eventRecord(ctx, type, e) {
  const r = { type, batch: null, plain: null, vm: null, from: false, selected: null };
  if (type === 'datarangeselected') {
    r.vm = ctx.vmIndexOfId(e.visualMapId);
    r.from = e.from != null;
    if (Array.isArray(e.selected)) Object.assign(r, arrRec('selected', e.selected));
    else r.selected = orderedEntries(e.selected);
    return r;
  }
  if (e.batch) {
    r.batch = e.batch.map(b => ({ s: ctx.seriesIndexOfId(b.seriesId), idx: b.dataIndexInside == null ? null : [].concat(b.dataIndexInside),
      key: b.highlightKey == null ? null : b.highlightKey }));
    return r;
  }
  const p = {};
  for (const k of Object.keys(e)) {
    if (k === 'type' || e[k] === undefined) continue;
    p[k] = typeof e[k] === 'string' && e[k].includes('\u0000') ? '<auto id>' : e[k];
  }
  r.plain = JSON.stringify(p);
  return r;
}

// ---------- one case ----------
const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });
function frame(ctx) {
  ctx.zr.animation.update();
}
const LOOP = fn => /self\._running/.test(String(fn)) && /requestAnimationFrame/.test(String(fn));
function fireTimers() {
  TIMERS = TIMERS.filter(t => !LOOP(t.fn));
  for (;;) {
    const due = TIMERS.filter(t => t.due <= NOW).sort((a, b) => a.due - b.due || a.id - b.id);
    if (!due.length) break;
    TIMERS = TIMERS.filter(t => t !== due[0]);
    due[0].fn();
  }
}
function recordCase(def) {
  NOW = CLOCK0;
  TIMERS = [];
  const chart = newChart();
  const ctx = makeCtx(chart, def);
  const LOG = { events: null };
  for (const t of ['highlight', 'downplay', 'datarangeselected']) {
    chart.on(t, e => { if (LOG.events) LOG.events.push(eventRecord(ctx, t, e)); });
  }
  try {
    LOG.events = [];
    chart.setOption(JSON.parse(JSON.stringify(def.option)));
    // settle what the first render started (the enter animation of an animated case)
    for (let t = 16; t <= 3000; t += 250) { NOW = CLOCK0 + t; frame(ctx); }
    NOW = CLOCK0 + 3000;
    frame(ctx);
    ctx.zr.storage.getDisplayList(true);
    ctx.zr.animation.stop();
    TIMERS = TIMERS.filter(t => !LOOP(t.fn));
    const steps = [];
    const seriesIds = [];
    chart.getModel().eachSeries(s => { seriesIds[s.seriesIndex] = s.id.includes('\u0000') ? null : s.id; });
    const pushRec = (st, i, x, y, dt, hover) => {
      const n = chart.getModel().queryComponents({ mainType: 'visualMap' }).length;
      const vms = [];
      for (let k = 0; k < n; k++) {
        vms.push(vmRecord(ctx, k));
        measureView(ctx.vmView(k));
      }
      const rec = { i, t: st.t, x, y, dt, now: NOW - CLOCK0 - 3000 };
      if (st.t === 'action') rec.payload = st.payload;
      if (st.t === 'set') { rec.option = st.option; rec.notMerge = !!st.notMerge; }
      rec.hover = hover;
      rec.events = LOG.events;
      rec.vms = vms;
      rec.series = seriesRecord(ctx);
      steps.push(rec);
    };
    pushRec({ t: 'init' }, 0, null, null, 0, null);
    def.steps.forEach((st, si) => {
      const dt = st.dt != null ? st.dt : (def.animated ? 16 : 300);
      NOW += dt;
      fireTimers();
      LOG.events = [];
      let x = null;
      let y = null;
      let hover = null;
      if (st.t === 'move' || st.t === 'down' || st.t === 'up' || st.t === 'out') {
        const p = st.at(ctx);
        x = p[0];
        y = p[1];
        ctx.last = p;
        hover = ctx.role(ctx.h.findHover(x, y).target);
        if (st.t === 'move') ctx.h.mousemove(raw(x, y));
        else if (st.t === 'down') ctx.h.mousedown(raw(x, y));
        else if (st.t === 'up') { ctx.h.mouseup(raw(x, y)); ctx.h.click(raw(x, y)); }
        else ctx.h.mouseout(raw(x, y));
      } else if (st.t === 'action') {
        chart.dispatchAction(JSON.parse(JSON.stringify(st.payload)));
      } else if (st.t === 'set') {
        chart.setOption(JSON.parse(JSON.stringify(st.option)), !!st.notMerge);
      } else must(st.t === 'frame', 'unknown step ' + st.t);
      frame(ctx);
      if (!def.animated) {
        NOW += 16; frame(ctx);
        NOW += 284; frame(ctx);
      }
      ctx.zr.storage.getDisplayList(true);
      // the animation loop a wakeUp started (rAF = setTimeout 16 under node): frames are stepped by hand
      ctx.zr.animation.stop();
      TIMERS = TIMERS.filter(t => !LOOP(t.fn));
      must(TIMERS.length === 0, def.id + " step " + (si + 1) + ": a timer was armed " + TIMERS.map(t => (t.due - NOW) + ":" + String(t.fn).slice(0, 300)).join("|"));
      pushRec(st, si + 1, x, y, dt, hover);
      LOG.events = null;
    });
    const visualMapIds = chart.getModel().queryComponents({ mainType: 'visualMap' }).map(m => (m.id.includes('\u0000') ? null : m.id));
    return { id: def.id, group: def.group, note: def.note, animated: !!def.animated, option: def.option, seriesIds, visualMapIds, steps };
  } finally {
    LOG.events = null;
    chart.dispose();
  }
}

// =====================================================================
// The cases
// =====================================================================
const VALS = [5, 12, 23, 31, 38, 46, 55, 63, 71, 80, 88, 97];
const CATS = VALS.map((_, i) => 'c' + i);
const GRID = { left: 60, right: 140, top: 40, bottom: 70 };
// the colours pinned: the port's defaults are its skin's, not upstream's theme
const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d'];
const GRADIENT = ['#d4dcf7', '#5070dd'];
const VMCOL = { contentColor: '#5070dd', inactiveColor: '#cfd2d7' };
function barChart(vm, extra) {
  return Object.assign({ animation: false, color: PALETTE, gradientColor: GRADIENT, grid: GRID, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: VALS }], visualMap: vm }, extra || {});
}
const VM_V = o => Object.assign({ type: 'continuous', min: 0, max: 100, calculable: true, right: 20, top: 'middle', precision: 1 }, VMCOL, o || {});
const VM_H = o => Object.assign({ type: 'continuous', min: 0, max: 100, calculable: true, orient: 'horizontal', left: 'center', bottom: 10, precision: 1 }, VMCOL, o || {});
const mv = at => ({ t: 'move', at });
const dn = at => ({ t: 'down', at });
const up = at => ({ t: 'up', at });
const here = c => c.last;
// a drag of a handle / label / the bar: press at `from`, moves by the deltas, release where the last move ended
function drag(from, deltas, opt) {
  const o = opt || {};
  const st = [mv(from), dn(here)];
  for (const d of deltas) st.push(mv(c => c.rel(d[0], d[1])));
  st.push(up(here));
  if (o.leave) st.push(mv(o.leave));
  return st;
}
const CASES = [];
const add = (id, group, note, option, steps, extra) => CASES.push(Object.assign({ id, group, note, option, steps }, extra || {}));

// ---- continuous: handle drags ----
add('drag-v-rt', 'drag', 'vertical, realtime: the top handle down, the bottom one up; every move dispatches selectDataRange, hoverLink on the handle highlights',
  barChart(VM_V()), drag(c => c.handle(0, 1), [[0, 7], [0, 13], [0, 20]], { leave: c => [300, 380] })
    .concat(drag(c => c.handle(0, 0), [[0, -15], [0, -30]], { leave: c => [300, 380] })));
add('drag-v-nrt', 'drag', 'vertical, realtime false: no dispatch until the release (one there, even unmoved), no hoverLink on the handle',
  barChart(VM_V({ realtime: false })), drag(c => c.handle(0, 1), [[0, 10], [0, 25]], { leave: c => [300, 380] })
    .concat(drag(c => c.handle(0, 0), [], {})));
add('drag-v-inverse', 'drag', 'vertical inverse: the bar group is not flipped, a downward move raises the value of handle 0',
  barChart(VM_V({ inverse: true })), drag(c => c.handle(0, 0), [[0, 12], [0, 18]]).concat(drag(c => c.handle(0, 1), [[0, -9]])));
add('drag-h', 'drag', 'horizontal: the bar is rotated pi/2, the drag reads dx through the inverted transform',
  barChart(VM_H()), drag(c => c.handle(0, 0), [[15, 0], [30, 3]]).concat(drag(c => c.handle(0, 1), [[-20, 0]]))
    .concat([{ t: 'set', option: { grid: GRID } }]));
add('drag-h-inverse', 'drag', 'horizontal inverse (rotation -pi/2)',
  barChart(VM_H({ inverse: true, realtime: false })), drag(c => c.handle(0, 1), [[25, -2], [10, 0]]));
add('drag-clamp-cross', 'drag', 'a handle dragged past the other (cross is forbidden: they meet) and past the end of the bar (clamped)',
  barChart(VM_V({ range: [30, 70] })), drag(c => c.handle(0, 1), [[0, 40], [0, 60]]).concat(drag(c => c.handle(0, 0), [[0, 200]])));
add('drag-label', 'drag', 'a drag by the handle label moves its handle',
  barChart(VM_V({ range: [20, 80] })), drag(c => c.label(0, 1), [[0, 9], [0, 9]]));
add('drag-range', 'drag', 'the in-range bar dragged moves both ends ("all"); the dist reads _handleEnds["all"] for the hoverLink, NaN: every highlight goes',
  barChart(VM_V({ range: [30, 60] })), [mv(c => c.bar(0, 0.45))].concat(drag(c => c.bar(0, 0.45), [[0, -10], [0, -25]], { leave: c => [300, 380] })));
add('drag-range-nrt', 'drag', 'the in-range bar dragged, realtime false',
  barChart(VM_V({ range: [30, 60], realtime: false })), drag(c => c.bar(0, 0.45), [[0, 12]]));
add('drag-hover-on-handle', 'drag', 'hoverLinkOnHandle true with realtime false: the drag highlights the handle\'s neighbourhood',
  barChart(VM_V({ realtime: false, hoverLinkOnHandle: true })), drag(c => c.handle(0, 1), [[0, 16], [0, 16]], { leave: c => [300, 380] }));
add('drag-no-hover-on-handle', 'drag', 'hoverLinkOnHandle false with realtime true: dispatches, no hoverLink from the handle',
  barChart(VM_V({ hoverLinkOnHandle: false })), drag(c => c.handle(0, 1), [[0, 16]]));
add('drag-not-calculable', 'drag', 'calculable false: no handles, the bar is not draggable; hover still links',
  barChart(VM_V({ calculable: false })), [mv(c => c.bar(0, 0.5)), dn(here), mv(c => c.rel(0, 10)), up(here), mv(c => [300, 380])]);
add('drag-formatter', 'drag', 'formatter and precision 0 on the handle labels and the indicator',
  barChart(VM_V({ precision: 0, formatter: '{value} pts' })), drag(c => c.handle(0, 0), [[0, -11]]).concat([mv(c => c.bar(0, 0.3))]));

// ---- continuous: hover ----
add('hover-bar', 'hover', 'the pointer over the bar: the indicator with ≈, < and > near the ends, the highlight batches, the handle labels blurred; off the bar',
  barChart(VM_V()), [mv(c => c.bar(0, 0.5)), mv(c => c.bar(0, 0.52)), mv(c => c.bar(0, 0.02)), mv(c => c.bar(0, 0.98)),
    mv(c => c.bar(0, 0.6, 0.9)), mv(c => [300, 380]), mv(c => c.bar(0, 0.3)), { t: 'out', at: c => c.bar(0, 0.3) }]);
add('hover-bar-range', 'hover', 'a partial range: over the in-range and the out-of-range parts (each crossing is an out and an over: downplay all, highlight all)',
  barChart(VM_V({ range: [40, 70] })), [mv(c => c.bar(0, 0.55)), mv(c => c.bar(0, 0.2)), mv(c => c.bar(0, 0.56)), mv(c => [300, 380])]);
add('hover-bar-h', 'hover', 'horizontal: the indicator label above / below by the bar align',
  barChart(VM_H()), [mv(c => c.bar(0, 0.5)), mv(c => c.bar(0, 0.1)), mv(c => [300, 200])]);
add('hover-datasize', 'hover', 'hoverLinkDataSize 20: the link spans 20 data units',
  barChart(VM_V({ hoverLinkDataSize: 20 })), [mv(c => c.bar(0, 0.5)), mv(c => c.bar(0, 0.95)), mv(c => [300, 380])]);
add('hover-handle', 'hover', 'over a handle (outside the bar width): no indicator; with realtime the handle links',
  barChart(VM_V()), [mv(c => c.bar(0, 0.5)), mv(c => c.handle(0, 1)), mv(c => c.label(0, 1)), mv(c => [300, 380])]);
add('hover-from-series', 'hover', 'hoverLink from the series: over a bar the indicator shows its value; leaving hides it',
  barChart(VM_V()), [mv(c => c.item(0, 3)), mv(c => c.item(0, 9)), mv(c => [300, 30]), mv(c => c.item(0, 0))]);
add('hover-from-series-target', 'hover', 'a series the visualMap does not target: no indicator; the targeted one: the indicator',
  Object.assign(barChart(VM_V({ seriesIndex: 1 })), { series: [{ type: 'bar', data: VALS }, { type: 'bar', data: VALS.map(v => 100 - v) }] }),
  [mv(c => c.item(0, 2)), mv(c => c.item(1, 2)), mv(c => [300, 30])]);
add('hover-off', 'hover', 'hoverLink false: no indicator, no batches either way',
  barChart(VM_V({ hoverLink: false })), [mv(c => c.bar(0, 0.5)), mv(c => c.item(0, 4)), mv(c => [300, 380])]);
add('hover-scatter-zoom', 'hover', 'a scatter behind a dataZoom window: the batch indices are the inner ones',
  {
    animation: false, color: PALETTE, gradientColor: GRADIENT, grid: GRID, xAxis: { type: 'value' }, yAxis: { type: 'value' },
    dataZoom: [{ type: 'inside', xAxisIndex: 0, startValue: 3, endValue: 9 }],
    series: [{ type: 'scatter', data: VALS.map((v, i) => [i, v]), symbolSize: 14 }],
    visualMap: VM_V({ dimension: 1 }),
  }, [mv(c => c.bar(0, 0.6)), mv(c => c.item(0, 2)), mv(c => [300, 380])]);
add('hover-focus', 'hover', 'a series with emphasis.focus series: the highlight blurs the other series',
  Object.assign(barChart(VM_V({ seriesIndex: 0 })), {
    series: [{ type: 'bar', data: VALS, emphasis: { focus: 'series' } }, { type: 'bar', data: VALS.map(v => v / 2) }],
  }), [mv(c => c.bar(0, 0.5)), mv(c => [300, 380])]);
add('two-visualmaps', 'hover', 'two visualMaps on one series: two highlight keys; downplay by one keeps what the other holds',
  barChart([VM_V({ right: 20 }), VM_V({ right: 90, calculable: false })]),
  [mv(c => c.bar(0, 0.5)), mv(c => c.bar(1, 0.52)), mv(c => [300, 380]), mv(c => c.bar(1, 0.5))]);

// ---- continuous: the action ----
add('action-continuous', 'action', 'selectDataRange from outside: the range (reversed, clamped), the view rebuilt, the event without from',
  barChart(VM_V()), [
    { t: 'action', payload: { type: 'selectDataRange', visualMapIndex: 0, selected: [80, 25] } },
    { t: 'action', payload: { type: 'selectDataRange', selected: [-20, 140] } },
    mv(c => c.bar(0, 0.5)),
    { t: 'action', payload: { type: 'selectDataRange', visualMapIndex: 0, selected: [10, 30] } },
    mv(c => c.bar(0, 0.52)),
  ]);
add('merge-after-drag', 'action', 'a merge after a drag keeps the dragged range; a merge writing range replaces it; notMerge forgets',
  barChart(VM_V()), drag(c => c.handle(0, 1), [[0, 30]]).concat([
    { t: 'set', option: { grid: GRID } },
    { t: 'set', option: { visualMap: [{ range: [20, 50] }] } },
    { t: 'set', option: barChart(VM_V()), notMerge: true },
  ]));

// ---- piecewise ----
const PW = o => Object.assign({ type: 'piecewise', min: 0, max: 100, splitNumber: 5, right: 20, top: 'middle' }, VMCOL, o || {});
add('pw-multiple', 'piecewise', 'multiple (the default): each click toggles its piece; hovering an item highlights its data',
  barChart(PW()), [mv(c => c.piece(0, 1, 'symbol')), dn(here), up(here), dn(here), up(here), mv(c => c.piece(0, 1, 'label')), dn(here), up(here),
    mv(c => c.piece(0, 3, 'symbol')), dn(here), up(here), up(here), mv(c => [300, 380])]);
add('pw-single', 'piecewise', 'single: a click selects only its piece',
  barChart(PW({ selectedMode: 'single' })), [mv(c => c.piece(0, 2, 'symbol')), dn(here), up(here), mv(c => c.piece(0, 4, 'symbol')), dn(here), up(here)]);
add('pw-true', 'piecewise', 'selectedMode true acts as single',
  barChart(PW({ selectedMode: true })), [mv(c => c.piece(0, 0, 'symbol')), dn(here), up(here)]);
add('pw-off', 'piecewise', 'selectedMode false: the items are silent -- no click, no hover link',
  barChart(PW({ selectedMode: false })), [mv(c => c.piece(0, 2, 'symbol')), dn(here), up(here), mv(c => [300, 380])]);
add('pw-pieces', 'piecewise', 'pieces with an open end; a click on the open piece',
  barChart(PW({ splitNumber: undefined, pieces: [{ lt: 20 }, { gte: 20, lt: 50 }, { gte: 50, lte: 80 }, { gt: 80 }] })),
  [mv(c => c.piece(0, 0, 'symbol')), dn(here), up(here), mv(c => c.piece(0, 3, 'symbol')), dn(here), up(here), mv(c => [300, 380])]);
add('pw-categories', 'piecewise', 'categories: the key is the category',
  {
    animation: false, color: PALETTE, gradientColor: GRADIENT, grid: GRID, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: VALS.map((v, i) => ({ value: [i, v, ['lo', 'mid', 'hi'][i % 3]] })), encode: { x: 0, y: 1 } }],
    visualMap: Object.assign({ type: 'piecewise', categories: ['lo', 'mid', 'hi'], dimension: 2, right: 20, top: 'middle' }, VMCOL),
  }, [mv(c => c.piece(0, 1, 'symbol')), dn(here), up(here), mv(c => [300, 380])]);
add('pw-action', 'piecewise', 'selectDataRange with a partial map: unnamed pieces are unselected (setSelected does not complete it); a merge resets',
  barChart(PW()), [
    { t: 'action', payload: { type: 'selectDataRange', visualMapIndex: 0, selected: { 1: true, 3: true } } },
    mv(c => c.piece(0, 2, 'symbol')), dn(here), up(here),
    { t: 'set', option: { grid: GRID } },
    { t: 'set', option: { visualMap: { selected: { 0: false } } } },
  ]);

add('pw-merge-selected', 'piecewise', 'a merge writing `selected` replaces the map (_resetSelected takes the new one alone); a merge without it selects every piece again',
  barChart(PW({ selected: { 1: false } })), [
    { t: 'set', option: { visualMap: { selected: { 2: false } } } },
    { t: 'set', option: { grid: GRID } },
  ]);

// ---- animated: the indicator (additive) ----
add('anim-bar', 'anim', 'animation on: the indicator slides 100 ms cubicInOut, additive, the moves 30 ms apart stack',
  Object.assign(barChart(VM_V()), { animation: true }), [
    mv(c => c.bar(0, 0.2)), { t: 'frame', dt: 16 },
    mv(c => c.bar(0, 0.5)), { t: 'frame', dt: 16 }, mv(c => c.bar(0, 0.7)), { t: 'frame', dt: 16 },
    { t: 'frame', dt: 16 }, mv(c => c.bar(0, 0.35)), { t: 'frame', dt: 20 }, { t: 'frame', dt: 30 },
    { t: 'frame', dt: 50 }, { t: 'frame', dt: 100 }, { t: 'frame', dt: 200 },
  ], { animated: true });
add('anim-series', 'anim', 'animation on: the indicator follows the hovered data (fill animates too)',
  Object.assign(barChart(VM_V({ inRange: { color: ['#0000ff', '#ff0000'] } })), { animation: true }), [
    mv(c => c.item(0, 1)), { t: 'frame', dt: 16 }, mv(c => c.item(0, 10)), { t: 'frame', dt: 16 },
    { t: 'frame', dt: 16 }, mv(c => c.item(0, 5)), { t: 'frame', dt: 16 }, { t: 'frame', dt: 30 },
    { t: 'frame', dt: 60 }, { t: 'frame', dt: 200 },
  ], { animated: true });

// =====================================================================
// Recipes and guards
// =====================================================================
const num = h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); };
function checkRecipes(cases) {
  const recipes = [];
  const r = (id, ok, detail) => { recipes.push({ id, ok, detail: detail || null }); must(ok, 'recipe ' + id + ' failed: ' + detail); };
  let n1 = 0; let n2 = 0; let n3 = 0; let n4 = 0;
  for (const cs of cases) {
    const chart = newChart();
    chart.setOption(JSON.parse(JSON.stringify(cs.option)));
    const vmModels = chart.getModel().queryComponents({ mainType: 'visualMap' });
    const view0 = vmModels.map(m => chart.getViewOfComponentModel(m));
    for (let si = 1; si < cs.steps.length; si++) {
      const st = cs.steps[si];
      const prev = cs.steps[si - 1];
      st.vms.forEach((vr, k) => {
        if (vr.subType !== 'continuous') return;
        const m = vmModels[k];
        const ext = m.getExtent();
        const isz = m.itemSize;
        // R1 the indicator: its y is linearMap of the value its text names (the ≈ case)
        if (!vr.indicator.invisible && !cs.animated && vr.indLabel.text.startsWith('≈ ') && !m.option.formatter) {
          const y = num(vr.indicator.y);
          const v = linearMap(y, [0, isz[1]], ext, true);
          r('R1', formatValue(m, v) === vr.indLabel.text.slice(2), cs.id + '/' + si + ' ' + vr.indLabel.text + ' vs ' + formatValue(m, v));
          n1++;
        }
        // R2 the drag: sliderMove of the inverted delta from the previous ends
        if (st.t === 'move' && prev.vms[k].dragging && vr.dragging && st.x != null && prev.x != null) {
          const bar = view0[k]._shapes.mainGroup;
          const L = bar.getLocalTransform();
          const iv = invert(L);
          const d = applyM(iv, st.x - prev.x, st.y - prev.y);
          const ends = prev.vms[k].handleEnds.map(num);
          const roleIdx = cs.dragRole && cs.dragRole[si];
          const idx = roleIdx != null ? roleIdx : null;
          if (idx != null) {
            sliderMove(d[1], ends, [0, isz[1]], idx, 0);
            r('R2', hex(ends[0]) === vr.handleEnds[0] && hex(ends[1]) === vr.handleEnds[1], cs.id + '/' + si);
            const iv2 = [linearMap(ends[0], [0, isz[1]], ext, true), linearMap(ends[1], [0, isz[1]], ext, true)];
            r('R2b', hex(iv2[0]) === vr.interval[0] && hex(iv2[1]) === vr.interval[1], cs.id + '/' + si);
            n2++;
          }
        }
        // R3 the first hover on the bar group: its highlight batch recomputed from the
        // pointer (the bar group's global transform of a fresh build, inverted), the
        // half size, the open ends and the store -- before any step rebuilt the view
        const untouched = cs.steps.slice(1, si).every(s => s.t !== 'action' && s.t !== 'set' && s.t !== 'down');
        if (untouched && st.t === 'move' && st.hover && /^vm\d+\.(inRange|outOfRange)$/.test(st.hover) && st.hover.startsWith('vm' + k + '.')
          && !prev.vms[k].hovering && prev.vms[k].hoverIdx.length === 0 && m.option.hoverLink && !cs.animated) {
          chart.getZr().storage.getDisplayList(true);
          const M = view0[k]._shapes.mainGroup.transform;
          const p = applyM(invert(M), st.x, st.y);
          const h = isz[1];
          const y = Math.min(Math.max(0, p[1]), h);
          const half = m.option.hoverLinkDataSize ? linearMap(m.option.hoverLinkDataSize, ext, [0, h], true) / 2 : 6;
          let v0 = linearMap(y - half, [0, h], ext, true);
          let v1 = linearMap(y + half, [0, h], ext, true);
          if (y - half < 0) v0 = -Infinity;
          if (y + half > h) v1 = Infinity;
          const want = [];
          m.eachTargetSeries(sm => {
            const data = sm.getData();
            const dim = m.getDataDimensionIndex(data);
            const idx = [];
            for (let i = 0; i < data.count(); i++) {
              const v = data.getStore().get(dim, i);
              if (v0 <= v && v <= v1) idx.push(i);
            }
            if (idx.length) want.push([sm.seriesIndex, idx]);
          });
          const hl = st.events.filter(e => e.type === 'highlight');
          const got = hl.length ? hl[hl.length - 1].batch.map(b => [b.s, b.idx]) : [];
          r('R3', JSON.stringify(got) === JSON.stringify(want), cs.id + '/' + si + ' ' + JSON.stringify(got) + ' vs ' + JSON.stringify(want));
          n3++;
        }
      });
      // R4 the piecewise click: the map after from the map before
      if (st.t === 'up' && st.hover && /^vm\d+\.item\d+\./.test(st.hover) && st.events.some(e => e.type === 'datarangeselected')) {
        const k = +st.hover.slice(2, st.hover.indexOf('.'));
        const piece = +st.hover.match(/item(\d+)/)[1];
        const m = vmModels[k];
        const mode = cs.option.visualMap.selectedMode;
        const before = {};
        for (const [kk, vv] of prev.vms[k].model.selected) before[kk] = vv;
        const pl = m.getPieceList();
        const key = m._mode === 'categories' ? pl[piece].value + '' : pl[piece].index + '';
        const obj = Object.assign({}, before);
        if (mode === 'single' || mode === true) { obj[key] = true; for (const kk of Object.keys(obj)) obj[kk] = kk === key; } else obj[key] = !obj[key];
        const after = new Map(Object.keys(obj).map(kk => [kk, obj[kk]]));
        const ev = st.events.find(e => e.type === 'datarangeselected');
        r('R4', JSON.stringify([...after]) === JSON.stringify(ev.selected), cs.id + '/' + si + ' ' + JSON.stringify([...after]) + ' vs ' + JSON.stringify(ev.selected));
        n4++;
      }
    }
    chart.dispose();
  }
  r('R-counts', n1 > 0 && n2 > 0 && n3 > 0 && n4 > 0, [n1, n2, n3, n4].join(','));
  return recipes;
}
function guards(cases) {
  const out = [];
  const g = (id, n, detail) => { out.push({ id, count: n, ok: n >= 1, detail }); if (!process.env.SOFT) must(n >= 1, 'guard ' + id + ' has no case'); };
  const allSteps = cases.flatMap(c => c.steps.map(s => ({ c, s })));
  const evs = allSteps.flatMap(({ c, s }) => s.events.map(e => ({ c, s, e })));
  g('nrt-silent-drag', allSteps.filter(({ c, s }) => c.id === 'drag-v-nrt' && s.t === 'move' && s.vms[0].dragging && !s.events.length).length, 'realtime false: a drag move dispatches nothing');
  g('nrt-release-dispatch', evs.filter(({ c, s, e }) => c.id === 'drag-v-nrt' && s.t === 'up' && e.type === 'datarangeselected' && e.from).length, 'realtime false: the release dispatches');
  g('rt-move-dispatch', evs.filter(({ c, s, e }) => c.id === 'drag-v-rt' && s.t === 'move' && e.type === 'datarangeselected').length, 'realtime: each move dispatches');
  g('prefix-lt', allSteps.filter(({ s }) => s.vms.some(v => v.indLabel && !v.indLabel.invisible && v.indLabel.text.startsWith('< '))).length, 'the < prefix');
  g('prefix-gt', allSteps.filter(({ s }) => s.vms.some(v => v.indLabel && !v.indLabel.invisible && v.indLabel.text.startsWith('> '))).length, 'the > prefix');
  g('series-indicator', allSteps.filter(({ c, s }) => c.id === 'hover-from-series' && s.vms[0].indLabel && !s.vms[0].indLabel.invisible).length, 'the indicator from a data hover');
  g('range-nan-downplay', evs.filter(({ c, s, e }) => c.id === 'drag-range' && s.t === 'move' && s.vms[0].dragging && e.type === 'downplay').length, 'the range drag downplays (NaN hoverLink)');
  g('handle-label-blur', allSteps.filter(({ s }) => s.vms.some(v => v.handles && v.handles.some(h => h.label.blur && h.label.opacity === 0.1))).length, 'a blurred handle label at 0.1');
  g('two-keys', evs.filter(({ c, e }) => c.id === 'two-visualmaps' && e.batch && e.batch.some(b => b.key === 'visualMap1')).length, 'the second key');
  g('kept-by-other', allSteps.filter(({ c, s }) => c.id === 'two-visualmaps' && s.series[0].some(x => x.hbo)).length, 'an item held');
  g('pw-single-one', allSteps.filter(({ c, s }) => c.id === 'pw-single' && s.vms[0].model.selected && s.vms[0].model.selected.filter(e => e[1] === true).length === 1).length, 'single leaves one');
  g('pw-partial-unselected', allSteps.filter(({ c, s }) => c.id === 'pw-action' && s.t === 'action' && s.vms[0].items.some(it => it.labelOpacity === 0.5)).length, 'a partial map unselects');
  g('pw-merge-replace', allSteps.filter(({ c, s }) => c.id === 'pw-merge-selected' && s.i === 1
    && s.vms[0].model.selected.some(e => e[0] === '1' && e[1] === true) && s.vms[0].model.selected.some(e => e[0] === '2' && e[1] === false)).length,
  'a merge replaces the selected map');
  g('pw-merge-reset', allSteps.filter(({ c, s, }) => c.id === 'pw-action' && s.t === 'set' && s.vms[0].model.selected.every(e => e[1] === true)).length, 'a merge resets the selection');
  g('merge-keeps-range', allSteps.filter(({ c, s }) => c.id === 'merge-after-drag' && s.t === 'set' && s.vms[0].modelText === undefined && s.vms[0].model.rangeText[1] !== '100').length, 'the dragged range survives a merge');
  g('additive-stack', allSteps.filter(({ c, s }) => c.animated && s.vms[0].indicator.animators >= 2).length, 'stacked indicator animators');
  // the group a drag leaves stands where the last build put it: the rebuild after the merge moves it
  const dh = cases.find(c => c.id === 'drag-h');
  const last = dh.steps[dh.steps.length - 1].vms[0].group[0];
  g('frozen-group', dh.steps.filter(s => s.t === 'move' && s.vms[0].dragging && s.vms[0].group[0] !== last).length, 'the group stays while dragging');
  g('handle-emph', allSteps.filter(({ s }) => s.vms.some(v => v.handles && v.handles.some(h => h.emph))).length, 'a handle in emphasis');
  g('focus-blur', allSteps.filter(({ c, s }) => c.id === 'hover-focus' && s.series[1].some(x => x.hover === 1)).length, 'the highlight blurs the other series');
  g('inner-index', evs.filter(({ c, s, e }) => c.id === 'hover-scatter-zoom' && e.batch && e.batch.some(b => b.idx && b.idx.some(ix => s.series[0].some(r => r.i === ix && r.raw !== ix)))).length, 'inner indices');
  return out;
}

// the drag roles of each case (which handle a move moves), for R2
function dragRoles(cs) {
  const roles = {};
  let cur = null;
  cs.steps.forEach((s, i) => {
    if (s.t === 'down') {
      const m = s.hover && s.hover.match(/^vm0\.(handle|label)(\d)$/);
      cur = m ? +m[2] : s.hover === 'vm0.inRange' ? 'all' : null;
    }
    if (s.t === 'move' && cur != null) roles[i] = cur;
    if (s.t === 'up') cur = null;
  });
  return roles;
}

function generate() {
  MEASURE = new Map();
  measure('国');
  const cases = CASES.map(recordCase);
  for (const cs of cases) cs.dragRole = dragRoles(cs);
  const recipes = checkRecipes(cases);
  for (const cs of cases) delete cs.dragRole;
  const gs = guards(cases);
  const out = {
    source: 'ECharts 6.1 dist (' + path.basename(DIST) + ') under node, ssr init then _ssr = false, env.node = false',
    W, H, seed: SEED,
    clock: { start: CLOCK0, settle: 'first render: frames to 3000 ms; static step: event, frames at NOW, NOW + 16, NOW + 300; animated step: event, frame at NOW', defaultDt: { static: 300, animated: 16 } },
    notes: [
      'An up step is handler.mouseup then handler.click at the same point.',
      'hover is the role of handler.findHover before the event.',
      'Every case but anim-* has option.animation false; the handle labels\' blur still transitions (stateTransition 200 ms) and is settled at each record.',
    ],
    measure: Array.from(MEASURE.values()).sort((a, b) => (a.string < b.string ? -1 : a.string > b.string ? 1 : 0)),
    cases, guards: gs, recipes,
  };
  return JSON.stringify(out, null, 1);
}

try {
  discoverECKey();
  const a = generate();
  const b = generate();
  must(a === b, 'two generations differ');
  must(!a.includes('\\u0000'), 'a NUL in the output');
  JSON.parse(a);
  fs.writeFileSync(OUT, a);
  console.log('wrote ' + OUT + ' (' + CASES.length + ' cases)');
  process.exit(0);
} catch (e) {
  console.error(e && e.stack || e);
  process.exit(1);
}
