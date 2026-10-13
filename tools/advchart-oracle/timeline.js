/*
Upstream's own answers for roadmap C21, batch 129: the TIMELINE component --
the slider view (SliderTimelineView: _layout, _createAxis, the axis line and
the progress line, the tick symbols, the labels, the control buttons, the
checkpoint, _position), its handlers (a tick's and a label's onclick, the
prev / next / play buttons, the checkpoint's drift and dragend with realtime
on and off), the play timer (_doPlayStop: setTimeout(playInterval) at every
render, _changeTimeline(current +/- 1)), the two actions (timelineChange:
setCurrentIndex with loop / clamp, the stop at the end without a loop, and
resetOption('timeline') with the timeline's replaceMerge; timelinePlayChange)
and their events, the frames (`options`) merged over the base by
OptionManager (getTimelineOption at every setOption, after the base and
before the media; replaced only by a non-empty list), the preprocessor
(compatibleEC2), the checkpoint's animation (300 ms quinticInOut, the
progress line with it), the hover emphasis with the component's state
transition, and the series' update animation after a change.

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist, or ECHARTS_DIST)
in node's server-side mode (SVG renderer) at 600 x 400 unless a case says,
chart._ssr = false and echarts.env.node = false (so a component may animate
its states), Math.random the port's xorshift32, process.env.TZ = 'UTC',
zrender's width table measuring every string (no canvas).

THE CLOCK (as animation.js): the global Date is replaced BEFORE the dist
loads; setTimeout / clearTimeout are a queue the clock fires in due order
(requestAnimationFrame's are dropped -- no frame runs by itself). A step
first advances the clock by its dt: every timer due by then fires at its due
time, each followed by a FRAME at that instant; then the step runs at the
new time and a FRAME follows. A frame is zr.animation.update() (the clips
stepped, then the 'frame' event: echarts' _onframe applies the hover states,
whose transitions are new clips) and zr.animation.update(true) at the same
instant (the new clips take their start there), then the display list
refreshed. So every animation a step starts begins at the step's instant --
the port renders and steps its clock there.

POINTER EVENTS go through zrender's own Handler (handler.mousemove /
mousedown / mouseup / click with {zrX, zrY, which 1}); zrender's Draggable
drives the checkpoint. Every coordinate is an integer CSS px (the port's
mouse events are integer device px at 96 PPI).

  node tools/advchart-oracle/timeline.js

writes tests/fixtures/advchart-timeline.json (ORACLE_OUT overrides). Ends
with process.exit().

-----------------------------------------------------------------------------
Numbers that are positions are the 16 lowercase hex digits of the IEEE
double (big-endian; NaN 7ff8000000000000).

Top level: source, version, seed, clock {T0}, measure {firstCode, ratio[]},
notes[], cases[], guards[].

A case: id, group, note, W, H, colours (true when every colour the timeline
draws is written by the option -- only then are colours comparable: the
port's defaults are the skin's), option (the first setOption), steps[],
states[] (index-parallel to [after the first setOption, after each step]).

A step: {kind: 'set', option, opts | null} (setOption; opts the second
argument), {kind: 'action', payload}, {kind: 'move' | 'down', x, y} (one Handler call), {kind: 'up', x, y}
(mouseup, then the DOM click a browser sends after it), {kind: 'tap', x, y}
(mousedown, mouseup and click at the point), {kind: 'leave'} (handler.mouseout),
{kind: 'resize', w, h}, {kind: 'wait'}; every step has dt (ms the clock
runs before it).

A state:
  t        NOW - T0 after the step
  fired[]  the play timers that fired during the advance, as their due
           instants (- T0), in order
  model    the timeline model's {currentIndex, autoPlay} (null without one)
  timer    the view's pending play timer's due instant (- T0), or null
  events[] every timelinechanged / timelineplaychanged since the last state:
           {type, payload} -- the event object as JSON text, a `from` that is
           the view's uid written "@view"
  tree     the raw merge layer (what the port's GetOptionJson must give;
           media.js's recording, plus the timeline model's setCurrentIndex /
           setPlayState written into it)
  view     null (no timeline view, or it shows nothing) or
           {main, label: the two groups' {x, y, rotation, originX, originY}
           (hex), els[]}
  bars[]   by seriesIndex: null (a hole, or no bar series), or each data
           item's bar shape [x, y, width, height] (hex; null where the item
           has no element)
  titles[] each title's text as its model holds it

An element (els[], in display order -- zlevel, z, z2, then the tree order):
  role     'line' | 'progress' | 'tick:<dataIndex>' | 'label:<dataIndex>' |
           'next' | 'prev' | 'play' | 'stop' | 'pointer'
  type     zrender's ('line', 'path', 'text', ...)
  z, z2, silent
  t        {x, y, rotation, scaleX, scaleY, originX, originY} (hex)
  m        the global transform (6 hex) or null
  states   currentStates; hover: hoverState (0 normal, 1 blur, 2 emphasis)
  rect     getBoundingRect() (4 hex) -- in its own frame
  path     a path's PathProxy data (hex) -- a line's: its shape {x1, y1, x2,
           y2} instead
  style    {fill, stroke, lineWidth (hex), opacity (hex), text, align,
           verticalAlign, font (a text's TSpan font)}

Guards (any failure: nothing is written, exit 1): the raw layer is a subset
of getOption() at every state; every timer that fired was the timeline
view's; named facts per case; the whole fixture generated twice,
byte-identical; no \u0000; it parses back.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

// ---------- the controlled clock (must precede loading the dist) ----------
const RealDate = Date;
const T0 = 1700000000000;
let NOW = T0;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;
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
function dropFrames() {
  TIMERS = TIMERS.filter(t => String(t.fn).indexOf('requestAnimationFrame') < 0 && String(t.fn).indexOf('rAF') < 0
    && !t.fn.__frame);
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-timeline.json');

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
const hexN = v => (v == null ? null : hex(+v));
const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};

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

// ---------- the environment ----------
(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

const zrUtil = echarts.zrUtil;
const CM = echarts.ComponentModel;
const MAIN_TYPES = CM.getAllClassMainTypes().slice();
const IS_CMPT = new Set(MAIN_TYPES);

// ---------- the raw-layer hooks (as media.js) ----------
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
// the timeline model writes its index and its play state into its option:
// the raw layer takes them where they are (in place, or appended)
let TL_PROTO = null;
for (const C of CM.getClassesByMainType('timeline')) {
  for (let p = C.prototype; p && p !== Object.prototype; p = Object.getPrototypeOf(p)) {
    if (has(p, 'setCurrentIndex') && !p.setCurrentIndex.__h) {
      TL_PROTO = p;
      const sci = p.setCurrentIndex;
      p.setCurrentIndex = function () {
        const r = sci.apply(this, arguments);
        if (this.__raw) this.__raw.currentIndex = this.option.currentIndex;
        return r;
      };
      p.setCurrentIndex.__h = true;
      const sps = p.setPlayState;
      p.setPlayState = function () {
        const r = sps.apply(this, arguments);
        if (this.__raw) this.__raw.autoPlay = this.option.autoPlay;
        return r;
      };
    }
  }
}
must(TL_PROTO, 'no TimelineModel.setCurrentIndex');
const HV = [['width', 'left', 'right'], ['height', 'top', 'bottom']];
function layoutModeOf(model) {
  return model.layoutMode || model.constructor.layoutMode;
}

// ---------- the option manager, hooked once ----------
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

// ---------- the script's own copies of what the manager keeps ----------
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
        sub(o, b[i], where + ': ' + k + '[' + i + ']');
      });
    } else sub(tree[k], full[k], where + ': ' + k);
  }
}
function mergeRoot(rootRaw, written, opt) {
  if (!opt || typeof opt !== 'object') return;
  for (const k of Object.keys(opt)) {
    const v = opt[k];
    if (v == null) continue;
    if (IS_CMPT.has(k)) {
      written.add(k);
      continue;
    }
    rootRaw[k] = rootRaw[k] == null ? zrUtil.clone(v) : zrUtil.merge(rootRaw[k], zrUtil.clone(v), true);
  }
}

// ---------- the chart ----------
const W = 600;
const H = 400;
function mk(w, h) {
  rngState = SEED;
  NOW = T0;
  TIMERS = [];
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: w, height: h });
  chart._ssr = false;
  return chart;
}
const zrOf = chart => chart.getZr();
function frame(chart) {
  const zr = zrOf(chart);
  dropFrames();
  zr.animation.update();
  zr.animation.update(true);
  dropFrames();
  zr.storage.getDisplayList(true);
}
const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });

function tlModel(chart) {
  return chart.getModel().getComponent('timeline') || null;
}
function tlView(chart) {
  const m = tlModel(chart);
  return m ? chart.getViewOfComponentModel(m) : null;
}

// ---------- reading the view ----------
const TKEYS = ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'originX', 'originY'];
const opac = st => (st.opacity == null ? 1 : st.opacity);
const strOrNull = v => (v == null ? null : String(v));
function groupRec(g) {
  const o = {};
  for (const k of TKEYS) o[k] = hex(g[k]);
  return o;
}
// the roles of the view's elements, by identity
function rolesOf(view) {
  const roles = new Map();
  const main = view._mainGroup;
  if (!main) return roles;
  const model = view.model;
  const data = model.getData();
  const ticks = view._tickSymbols || [];
  ticks.forEach((el, i) => roles.set(el, 'tick:' + i));
  if (view._currentPointer) roles.set(view._currentPointer, 'pointer');
  if (view._progressLine && view._progressLine.parent === main) roles.set(view._progressLine, 'progress');
  const lines = main.childrenRef().filter(el => el.type === 'line' && el !== view._progressLine);
  if (lines.length) roles.set(lines[0], 'line');
  // the buttons, in makeBtn's order: next, prev, play
  const lay = view._layout(model, view.api);
  const order = [];
  if (lay.nextBtnPosition) order.push('next');
  if (lay.prevBtnPosition) order.push('prev');
  if (lay.playPosition) order.push(model.getPlayState() ? 'stop' : 'play');
  const btns = main.childrenRef().filter(el => !roles.has(el) && el.type !== 'line');
  must(btns.length === order.length, 'buttons ' + btns.length + ' for ' + order.join());
  btns.forEach((el, i) => roles.set(el, order[i]));
  // a label's data index: its tick's place along the axis
  // (NaN places -- a time axis over strings -- match in order: Object.is)
  const usedLabel = new Set();
  (view._tickLabels || []).forEach(el => {
    let k = -1;
    data.each(['value'], (v, di) => {
      if (k < 0 && !usedLabel.has(di) && Object.is(view._axis.dataToCoord(v), el.x)) k = di;
    });
    usedLabel.add(k);
    must(k >= 0, 'a label at no tick');
    roles.set(el, 'label:' + k);
  });
  return roles;
}
function elRec(el, role) {
  const r = { role, type: el.type, z: el.z, z2: el.z2, silent: !!el.silent };
  r.t = {};
  for (const k of TKEYS) r.t[k] = hex(el[k]);
  r.m = el.transform ? Array.from(el.transform).map(hex) : null;
  r.states = (el.currentStates || []).slice();
  r.hover = el.hoverState || 0;
  const rc = el.getBoundingRect();
  r.rect = [rc.x, rc.y, rc.width, rc.height].map(hex);
  const s = el.style;
  r.style = { fill: strOrNull(s.fill), stroke: strOrNull(s.stroke), lineWidth: hexN(s.lineWidth), opacity: hex(opac(s)) };
  if (el.type === 'text') {
    r.style.text = s.text == null ? null : String(s.text);
    r.style.align = s.align == null ? null : s.align;
    r.style.verticalAlign = s.verticalAlign == null ? null : s.verticalAlign;
    const span = el.childrenRef()[0];
    r.style.font = span ? span.style.font : null;
  }
  else if (el.type === 'line') {
    r.shape = { x1: hex(el.shape.x1), y1: hex(el.shape.y1), x2: hex(el.shape.x2), y2: hex(el.shape.y2) };
  }
  else {
    must(el.path, role + ': no path proxy');
    r.path = Array.from(el.path.data).slice(0, el.path.len()).map(hex);
  }
  return r;
}
function viewRec(chart) {
  const view = tlView(chart);
  if (!view || !view._mainGroup || view.group.childCount() === 0) return null;
  const roles = rolesOf(view);
  const els = [];
  zrOf(chart).storage.getDisplayList(true).forEach(d => {
    let e = d;
    // a text's spans answer for the text
    if (e.parent && e.parent.type === 'text') e = e.parent;
    const role = roles.get(e);
    if (role === undefined) return;
    if (els.length && els[els.length - 1].role === role) return;
    els.push(elRec(e, role));
  });
  return { main: groupRec(view._mainGroup), label: groupRec(view._labelGroup), els };
}
// the centre of an element as the pointer must hit it, an integer point
function centreOf(chart, role) {
  const view = tlView(chart);
  const roles = rolesOf(view);
  let el = null;
  roles.forEach((r, e) => { if (r === role) el = e; });
  must(el, 'no element ' + role);
  zrOf(chart).storage.getDisplayList(true);
  const rc = el.getBoundingRect();
  const m = el.transform || [1, 0, 0, 1, 0, 0];
  const cx = rc.x + rc.width / 2;
  const cy = rc.y + rc.height / 2;
  return [Math.round(m[0] * cx + m[2] * cy + m[4]), Math.round(m[1] * cx + m[3] * cy + m[5])];
}

// ---------- one case ----------
let EVENTS = [];
function runCase(c) {
  const cw = c.W || W;
  const ch = c.H || H;
  const chart = mk(cw, ch);
  const states = [];
  const fails = [];
  let rootRaw = {};
  let written = new Set();
  let frames = [];
  let units = { list: [], def: null };
  let first = true;
  EVENTS = [];
  const evRec = e => {
    const view = tlView(chart);
    const o = JSON.parse(JSON.stringify(e));
    if (has(o, 'from') && view && o.from === view.uid) o.from = '@view';
    return { type: e.type, payload: JSON.stringify(o) };
  };
  chart.on('timelinechanged', e => EVENTS.push(evRec(e)));
  chart.on('timelineplaychanged', e => EVENTS.push(evRec(e)));

  // what a hook log says was merged, into the script's root copy
  const absorb = (replace, stepKind) => {
    const log = OM_LOG;
    OM_LOG = null;
    for (const e of log) {
      if (e.kind === 'timeline') {
        if (!e.returned) continue;
        mergeRoot(rootRaw, written, frames[e.index]);
        for (const t of replace) written.add(t);
      } else {
        if (!e.returned) continue;
        for (const i of e.indices) {
          const u = i === -1 ? units.def : units.list[i];
          must(u, c.id + ': no unit ' + i);
          mergeRoot(rootRaw, written, u.option);
        }
        if (stepKind === 'set' || stepKind === 'action') for (const t of replace) written.add(t);
      }
    }
    const hl = HOOK_LOG;
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
    const fresh = notMerge || first;
    let replace = [];
    if (opts && opts.replaceMerge != null) {
      replace = (Array.isArray(opts.replaceMerge) ? opts.replaceMerge : [opts.replaceMerge]).filter(t => IS_CMPT.has(t));
    }
    if (fresh) {
      rootRaw = {};
      written = new Set();
      units = { list: [], def: null };
      frames = [];
    } else for (const t of replace) written.add(t);
    const rawCopy = JSON.parse(text);
    const nu = unitsOf(JSON.parse(text));
    if (nu.list.length) units.list = nu.list;
    if (nu.def) units.def = nu.def;
    if (Array.isArray(rawCopy.options) && rawCopy.options.length) frames = JSON.parse(text).options;
    mergeRoot(rootRaw, written, parseRaw(rawCopy));
    HOOK_LOG = [];
    OM_LOG = [];
    quiet(() => (opts ? chart.setOption(JSON.parse(text), opts) : chart.setOption(JSON.parse(text))));
    first = false;
    absorb(replace, 'set');
  };
  const record = fired => {
    const m = tlModel(chart);
    const view = tlView(chart);
    let timer = null;
    if (view && view._timer) {
      const t = TIMERS.find(q => q.id === view._timer);
      must(t, c.id + ': the view keeps a timer the queue lost');
      timer = t.due - T0;
    }
    const st = {
      t: NOW - T0, fired,
      model: m ? { currentIndex: m.option.currentIndex, autoPlay: m.option.autoPlay } : null,
      timer, events: EVENTS, tree: treeOf(chart, rootRaw, written), view: viewRec(chart),
      bars: (() => {
        // by seriesIndex: a replaceMerge hole is null
        const all = [];
        chart.getModel().getSeries().forEach(s => {
          while (all.length < s.seriesIndex) all.push(null);
          if (s.subType !== 'bar') {
            all[s.seriesIndex] = null;
            return;
          }
          const d = s.getData();
          const out = [];
          for (let i = 0; i < d.count(); i++) {
            const el = d.getItemGraphicEl(i);
            out.push(el && el.shape ? [el.shape.x, el.shape.y, el.shape.width, el.shape.height].map(hex) : null);
          }
          all[s.seriesIndex] = out;
        });
        return all;
      })(),
      titles: (chart.getModel()._componentsMap.get('title') || []).map(t => (t ? t.option.text : null)),
    };
    EVENTS = [];
    try {
      checkSubset(st.tree, chart.getOption(), c.id + ' state ' + states.length);
    } catch (e) {
      if (!(e instanceof OracleError)) throw e;
      fails.push(e.message);
    }
    states.push(st);
  };
  const advance = dt => {
    const fired = [];
    const target = NOW + dt;
    for (;;) {
      dropFrames();
      TIMERS.sort((a, b) => a.due - b.due || a.id - b.id);
      if (!TIMERS.length || TIMERS[0].due > target) break;
      const t = TIMERS.shift();
      const view = tlView(chart);
      must(view && view._timer === t.id, c.id + ': a timer that is not the timeline view\'s fired');
      NOW = t.due;
      HOOK_LOG = [];
      OM_LOG = [];
      t.fn();
      absorb(replaceOf(), 'action');
      frame(chart);
      fired.push(NOW - T0);
    }
    NOW = target;
    return fired;
  };
  const replaceOf = () => {
    const m = tlModel(chart);
    const r = m ? m.get('replaceMerge', true) : null;
    if (r == null) return [];
    return (Array.isArray(r) ? r : [r]).filter(t => IS_CMPT.has(t));
  };

  try {
    doSet(c.option, null);
    frame(chart);
    record([]);
    const resolved = [];
    for (const st0 of c.steps) {
      const st = Object.assign({}, st0);
      const fired = advance(st.dt || 0);
      // a step aimed at an element: its centre, an integer point
      if (st.at) {
        const p = centreOf(chart, st.at);
        st.x = p[0] + (st.dx || 0);
        st.y = p[1] + (st.dy || 0);
      }
      const h = zrOf(chart).handler;
      HOOK_LOG = [];
      OM_LOG = [];
      switch (st.kind) {
        case 'set':
          OM_LOG = null;
          HOOK_LOG = null;
          doSet(st.option, st.opts || null);
          break;
        case 'action':
          chart.dispatchAction(JSON.parse(JSON.stringify(st.payload)));
          absorb(replaceOf(), 'action');
          break;
        case 'move': h.mousemove(raw(st.x, st.y)); absorb([], 'ptr'); break;
        case 'down': h.mousedown(raw(st.x, st.y)); absorb([], 'ptr'); break;
        case 'up':
          // a browser's DOM click follows every mouseup; zrender's Handler
          // decides whether it reaches an element (the same one pressed,
          // within 4 px)
          h.mouseup(raw(st.x, st.y));
          h.click(raw(st.x, st.y));
          absorb(replaceOf(), 'action');
          break;
        case 'tap':
          h.mousedown(raw(st.x, st.y));
          h.mouseup(raw(st.x, st.y));
          h.click(raw(st.x, st.y));
          absorb(replaceOf(), 'action');
          break;
        case 'leave': h.mouseout(raw(-1, -1)); absorb([], 'ptr'); break;
        case 'resize':
          chart.resize({ width: st.w, height: st.h });
          absorb([], 'resize');
          break;
        case 'wait': absorb([], 'wait'); break;
        default: throw new OracleError('a step of no kind ' + st.kind);
      }
      frame(chart);
      record(fired);
      const rs = { kind: st.kind, dt: st.dt || 0 };
      if (st.kind === 'set') {
        rs.option = st.option;
        rs.opts = st.opts || null;
      }
      if (st.kind === 'action') rs.payload = st.payload;
      if (st.x != null) {
        rs.x = st.x;
        rs.y = st.y;
      }
      if (st.kind === 'resize') {
        rs.w = st.w;
        rs.h = st.h;
      }
      if (st.at) rs.at = st.at;
      resolved.push(rs);
    }
    return { id: c.id, group: c.group, note: c.note, W: cw, H: ch, colours: !!c.colours, option: c.option,
      steps: resolved, states, fails };
  } catch (e) {
    if (process.env.ORACLE_DEBUG) {
      console.log('case ' + c.id + ' failed after ' + states.length + ' states');
      states.forEach((q, i) => console.log('  ' + i + ' t=' + q.t + ' model=' + JSON.stringify(q.model) + ' timer=' + q.timer
        + ' fired=' + JSON.stringify(q.fired) + ' ev=' + JSON.stringify(q.events.map(x => x.payload))
        + ' roles=' + (q.view ? q.view.els.map(x => x.role).join(',') : '-')));
    }
    throw e;
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CAT = ['A', 'B', 'C', 'D'];
const LETTERS = ['2002', '2003', '2004', '2005'];
const GRID = { left: 60, right: 40, top: 40, bottom: 90 };
function framesOf(n, f) {
  const out = [];
  for (let i = 0; i < n; i++) out.push(f(i));
  return out;
}
const barFrame = i => ({ title: { text: 'F' + i }, series: [{ data: [1 + i, 4 - (i % 3), 2 + (i * 7) % 5, 3] }] });
// the base form: a root key beside baseOption is never read (parseRawOption),
// so whatever the base needs goes into it (baseExtra); rootExtra is for the
// keys the root does carry (options, media)
function bars(tl, rootExtra, baseExtra) {
  return Object.assign({
    baseOption: Object.assign({
      timeline: tl,
      title: { text: 'base' },
      grid: GRID,
      xAxis: { type: 'category', data: CAT },
      yAxis: { type: 'value', max: 8 },
      series: [{ type: 'bar', data: [1, 1, 1, 1] }],
    }, baseExtra || {}),
    options: framesOf(Array.isArray(tl.data) ? tl.data.length : 4, barFrame),
  }, rootExtra || {});
}
const tlCat = o => Object.assign({ axisType: 'category', data: LETTERS }, o);
const UTC = (y, m, d) => Date.UTC(y, m, d);

const CASES = [
  // ---------------- layout ----------------
  { id: 'cat-h', group: 'layout', note: 'a horizontal category timeline, the defaults', option: bars(tlCat({})), steps: [] },
  { id: 'cat-v', group: 'layout', note: 'vertical, on the right', option: bars(tlCat({ orient: 'vertical', left: null, right: 0, top: 20, bottom: 20, width: 60, height: null })), steps: [] },
  { id: 'cat-v-left', group: 'layout', note: 'vertical on the left half: the labels go right', option: bars(tlCat({ orient: 'vertical', left: 10, right: null, top: 30, bottom: 30, width: 70, height: null, currentIndex: 2 })), steps: [] },
  { id: 'cat-top', group: 'layout', note: 'horizontal in the upper half: the labels go above', option: bars(tlCat({ top: 10, bottom: null, height: 50 })), steps: [] },
  { id: 'time-h', group: 'layout', note: 'a time axis, a string formatter, UTC', option: bars({ axisType: 'time', data: [UTC(2002, 0, 1), UTC(2003, 0, 1), UTC(2004, 6, 1), UTC(2005, 0, 1)], label: { formatter: '{yyyy}-{MM}' } }, null, { useUTC: true }), steps: [] },
  { id: 'time-dict', group: 'layout', note: 'a time axis, the default dictionary: a year, a month, a day, an hour', option: bars({ axisType: 'time', data: [UTC(2002, 0, 1), UTC(2002, 3, 1), UTC(2002, 3, 9), UTC(2002, 3, 9) + 3600000 * 5] }, null, { useUTC: true }), steps: [] },
  { id: 'time-strings', group: 'layout', note: "the default axisType 'time' over data that are not dates: every value NaN, the extent empty", option: bars({ data: ['a', 'b', 'c', 'd'] }),
    steps: [{ kind: 'tap', at: 'next' }, { kind: 'tap', at: 'play', dt: 400 }, { kind: 'wait', dt: 2000 }] },
  { id: 'value-h', group: 'layout', note: 'a value axis, uneven values, a {value} template', option: bars({ axisType: 'value', data: [0, 1.5, 4, 10], label: { formatter: '{value} km' } }), steps: [] },
  { id: 'value-default', group: 'layout', note: 'a value axis with the default label (getPrecision, addCommas)', option: bars({ axisType: 'value', data: [1200, 1250.5, 3000, 12345.25] }), steps: [] },
  { id: 'cat-template', group: 'layout', note: 'a category {value} template, a rotated label and its own size', option: bars(tlCat({ label: { formatter: 'Y{value}', rotate: 30, fontSize: 14 } })), steps: [] },
  { id: 'ctrl-right', group: 'control', note: 'controlPosition right (the preprocessor moves it)', option: bars(tlCat({ controlPosition: 'right' })), steps: [] },
  { id: 'ctrl-top', group: 'control', note: 'controlStyle.position top', option: bars(tlCat({ controlStyle: { position: 'top' } })), steps: [] },
  { id: 'ctrl-bottom', group: 'control', note: 'controlStyle.position bottom', option: bars(tlCat({ controlStyle: { position: 'bottom' } })), steps: [] },
  { id: 'ctrl-none', group: 'control', note: "controlPosition 'none': show false", option: bars(tlCat({ controlPosition: 'none' })), steps: [] },
  { id: 'ctrl-partial', group: 'control', note: 'no prev button, a bigger item, a percent play size', option: bars(tlCat({ controlStyle: { showPrevBtn: false, itemSize: 30, itemGap: 6, playBtnSize: '50%', nextBtnSize: 20 } })), steps: [] },
  { id: 'ctrl-v-right', group: 'control', note: 'vertical with the controls at the far end', option: bars(tlCat({ orient: 'vertical', left: null, right: 0, top: 20, bottom: 20, width: 60, height: null, controlStyle: { position: 'right' } })), steps: [] },
  { id: 'label-num', group: 'label', note: 'label.position a number', option: bars(tlCat({ label: { position: 12 } })), steps: [] },
  { id: 'label-neg', group: 'label', note: 'label.position a negative number, vertical', option: bars(tlCat({ orient: 'vertical', left: null, right: 0, top: 20, bottom: 20, width: 60, height: null, label: { position: -14 } })), steps: [] },
  { id: 'label-top', group: 'label', note: "label.position 'top' on a horizontal timeline", option: bars(tlCat({ label: { position: 'top' } })), steps: [] },
  { id: 'label-left-h', group: 'label', note: "label.position 'left' on a horizontal timeline: undefined", option: bars(tlCat({ label: { position: 'left' } })), steps: [] },
  { id: 'label-hidden', group: 'label', note: 'label.show false; lineStyle.show false', option: bars(tlCat({ label: { show: false }, lineStyle: { show: false } })), steps: [] },
  { id: 'cat-many', group: 'label', note: 'twenty-four long categories: the auto interval', option: bars(tlCat({ data: framesOf(24, i => 'Month ' + (i + 1)) })),
    steps: [{ kind: 'tap', at: 'label:7' }] },
  { id: 'ec2', group: 'label', note: "the preprocessor: type 'number', items with a name only, label.normal, itemStyle.emphasis", option: bars({ type: 'number', data: [{ name: 3 }, { name: 5, label: { color: '#123456' } }, 7, { value: 9, itemStyle: { color: '#654321' } }], label: { show: true } }), steps: [] },
  { id: 'inverse', group: 'control', note: 'inverse: next goes back', option: bars(tlCat({ inverse: true, currentIndex: 1 })),
    steps: [{ kind: 'tap', at: 'next' }, { kind: 'wait', dt: 400 }, { kind: 'tap', at: 'prev' }, { kind: 'wait', dt: 400 }] },
  { id: 'symbols', group: 'layout', note: 'item symbols: emptyCircle, a rect item, sizes, an offset and a rotation; the checkpoint a diamond', option: bars(tlCat({ symbol: 'emptyCircle', symbolSize: 10, data: ['a', { value: 'b', symbol: 'rect', symbolSize: [14, 8], symbolRotate: 45 }, { value: 'c', symbolOffset: [0, 3] }, 'd'], checkpointStyle: { symbol: 'diamond', symbolSize: 18 } })), steps: [] },
  // ---------------- clicks ----------------
  { id: 'click', group: 'click', note: 'a tick, a label, next, prev, play and stop', option: bars(tlCat({ playInterval: 1500 })),
    steps: [
      { kind: 'move', at: 'tick:2' }, { kind: 'down', at: 'tick:2' }, { kind: 'up', at: 'tick:2' },
      { kind: 'wait', dt: 120 }, { kind: 'wait', dt: 200 },
      { kind: 'tap', at: 'label:1', dt: 100 },
      { kind: 'tap', at: 'next', dt: 400 },
      { kind: 'tap', at: 'next', dt: 400 }, { kind: 'tap', at: 'next', dt: 400 },
      { kind: 'tap', at: 'prev', dt: 400 },
      { kind: 'tap', at: 'play', dt: 400 }, { kind: 'wait', dt: 1500 }, { kind: 'tap', at: 'stop', dt: 300 }, { kind: 'wait', dt: 2000 },
    ] },
  { id: 'click-noloop', group: 'click', note: 'next at the end without a loop: clamped, no change of play', option: bars(tlCat({ loop: false, currentIndex: 3 })),
    steps: [{ kind: 'tap', at: 'next' }, { kind: 'tap', at: 'prev', dt: 400 }] },
  // ---------------- drag ----------------
  { id: 'drag-rt', group: 'drag', note: 'the checkpoint dragged, realtime: a change at each new nearest tick', option: bars(tlCat({})),
    steps: [
      { kind: 'move', at: 'pointer' }, { kind: 'down', at: 'pointer' },
      { kind: 'move', at: 'pointer', dx: 20, dt: 30 }, { kind: 'move', at: 'pointer', dx: 40, dt: 30 },
      { kind: 'move', at: 'tick:1', dx: 15, dt: 30 }, { kind: 'move', at: 'tick:2', dx: -20, dt: 30 },
      { kind: 'move', at: 'tick:2', dx: -5, dy: 40, dt: 30 },
      { kind: 'up', at: 'tick:2', dx: -5, dy: 40, dt: 30 },
      { kind: 'wait', dt: 150 }, { kind: 'wait', dt: 200 },
    ] },
  { id: 'drag-nrt', group: 'drag', note: 'realtime false: only the release changes', option: bars(tlCat({ realtime: false, currentIndex: 3 })),
    steps: [
      { kind: 'down', at: 'pointer' },
      { kind: 'move', at: 'tick:2', dt: 30 }, { kind: 'move', at: 'tick:1', dx: 7, dt: 30 },
      { kind: 'move', at: 'tick:0', dx: -300, dt: 30 },
      { kind: 'up', at: 'tick:0', dx: 30, dt: 30 },
      { kind: 'wait', dt: 150 }, { kind: 'wait', dt: 300 },
    ] },
  { id: 'drag-v', group: 'drag', note: 'a vertical timeline dragged', option: bars(tlCat({ orient: 'vertical', left: null, right: 0, top: 20, bottom: 20, width: 60, height: null })),
    steps: [
      { kind: 'down', at: 'pointer' }, { kind: 'move', at: 'tick:2', dx: 4, dy: 6, dt: 30 },
      { kind: 'up', at: 'tick:2', dx: 4, dy: 6, dt: 30 }, { kind: 'wait', dt: 300 },
    ] },
  // ---------------- hover ----------------
  { id: 'hover', group: 'hover', note: 'the emphasis on a tick, a label and a button, with the state transition', option: bars(tlCat({ currentIndex: 2 })),
    steps: [
      { kind: 'move', at: 'tick:1' }, { kind: 'wait', dt: 150 }, { kind: 'wait', dt: 200 },
      { kind: 'move', at: 'label:3' }, { kind: 'wait', dt: 350 },
      { kind: 'move', at: 'next' }, { kind: 'wait', dt: 350 },
      { kind: 'move', x: 300, y: 100 }, { kind: 'wait', dt: 350 },
    ] },
  { id: 'colours', group: 'hover', colours: true, note: 'every colour written: the progress and the emphasis states', option: bars(tlCat({
    currentIndex: 2,
    lineStyle: { color: '#aabbcc', width: 3 }, itemStyle: { color: '#336699', borderColor: '#000000', borderWidth: 1 },
    checkpointStyle: { color: '#ff0000', borderColor: '#00ff00', borderWidth: 2 },
    controlStyle: { color: '#123123', borderColor: '#321321' }, label: { color: '#777777' },
    emphasis: { itemStyle: { color: '#ff8800', borderColor: '#884400' }, label: { color: '#0000ff' }, controlStyle: { color: '#00ffff', borderColor: '#008888' } },
    progress: { lineStyle: { color: '#444444' }, itemStyle: { color: '#999999' }, label: { color: '#bb0000' } },
  })),
    steps: [{ kind: 'move', at: 'tick:0' }, { kind: 'wait', dt: 350 }, { kind: 'move', at: 'label:3' }, { kind: 'wait', dt: 350 },
      { kind: 'move', at: 'play' }, { kind: 'wait', dt: 350 }, { kind: 'leave' }, { kind: 'wait', dt: 350 }] },
  // ---------------- play ----------------
  { id: 'play-loop', group: 'play', note: 'autoPlay with a loop, wrapping round', option: bars(tlCat({ autoPlay: true, playInterval: 1000 })),
    steps: [
      { kind: 'wait', dt: 1000 }, { kind: 'wait', dt: 150 }, { kind: 'wait', dt: 850 },
      { kind: 'wait', dt: 1000 }, { kind: 'wait', dt: 1000 }, { kind: 'wait', dt: 100 }, { kind: 'wait', dt: 900 },
    ] },
  { id: 'play-noloop', group: 'play', note: 'autoPlay without a loop: the stop at the end, and its event', option: bars(tlCat({ autoPlay: true, loop: false, playInterval: 700, currentIndex: 1 })),
    steps: [{ kind: 'wait', dt: 700 }, { kind: 'wait', dt: 700 }, { kind: 'wait', dt: 1400 }] },
  { id: 'play-rewind', group: 'play', note: 'rewind with a loop', option: bars(tlCat({ autoPlay: true, rewind: true, playInterval: 500, currentIndex: 1 })),
    steps: [{ kind: 'wait', dt: 500 }, { kind: 'wait', dt: 500 }, { kind: 'wait', dt: 500 }] },
  { id: 'play-rewind-noloop', group: 'play', note: 'rewind without a loop: held at the first', option: bars(tlCat({ autoPlay: true, rewind: true, loop: false, playInterval: 500, currentIndex: 1 })),
    steps: [{ kind: 'wait', dt: 500 }, { kind: 'wait', dt: 500 }, { kind: 'wait', dt: 500 }] },
  { id: 'play-interrupt', group: 'play', note: 'a click while playing: the timer starts over at its render; a drag stops it', option: bars(tlCat({ autoPlay: true, playInterval: 1000 })),
    steps: [{ kind: 'wait', dt: 600 }, { kind: 'tap', at: 'tick:3' }, { kind: 'wait', dt: 600 }, { kind: 'wait', dt: 400 },
      { kind: 'down', at: 'pointer', dt: 100 }, { kind: 'move', at: 'tick:2', dt: 50 }, { kind: 'wait', dt: 1500 }, { kind: 'up', at: 'tick:2', dt: 50 },
      { kind: 'wait', dt: 1000 }] },
  // ---------------- actions ----------------
  { id: 'actions', group: 'action', note: 'the actions by hand', option: bars(tlCat({})),
    steps: [
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: 5 } },
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: -1 }, dt: 600 },
      { kind: 'action', payload: { type: 'timelineChange' }, dt: 600 },
      { kind: 'action', payload: { type: 'timelinePlayChange', playState: true }, dt: 600 },
      { kind: 'wait', dt: 2000 },
      { kind: 'action', payload: { type: 'timelinePlayChange', playState: false }, dt: 100 },
      { kind: 'action', payload: { type: 'timelinePlayChange' }, dt: 100 },
      { kind: 'wait', dt: 3000 },
    ] },
  { id: 'actions-noloop', group: 'action', note: 'without a loop: clamped; the end stops a play', option: bars(tlCat({ loop: false, autoPlay: true, playInterval: 5000 })),
    steps: [
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: 9 } },
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: -4 }, dt: 600 },
      { kind: 'action', payload: { type: 'timelinePlayChange', playState: true }, dt: 600 },
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: 3 }, dt: 600 },
    ] },
  // ---------------- option ----------------
  { id: 'merge', group: 'option', note: 'merges: the frames replaced by a non-empty list, the frame merged again, a notMerge', option: bars(tlCat({ currentIndex: 1 })),
    steps: [
      { kind: 'set', option: { title: { text: 'merged' } } },
      { kind: 'set', option: { timeline: { currentIndex: 2 }, options: [{ title: { text: 'N0' } }, { title: { text: 'N1' } }, { title: { text: 'N2' }, series: [{ data: [7, 7, 7, 7] }] }] } },
      { kind: 'set', option: { options: [] } },
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: 0 } },
      { kind: 'set', option: { title: { text: 'plain' }, xAxis: { type: 'category', data: CAT }, yAxis: {}, series: [{ type: 'bar', data: [2, 2, 2, 2] }] }, opts: { notMerge: true } },
      { kind: 'set', option: bars(tlCat({ currentIndex: 3 })), opts: { notMerge: true } },
    ] },
  { id: 'root-form', group: 'option', note: 'the root form: timeline and options beside the rest; an index past the last frame merges nothing', option: {
    animation: false, timeline: tlCat({}), grid: GRID, xAxis: { type: 'category', data: CAT }, yAxis: { max: 8 },
    series: [{ type: 'bar', data: [1, 1, 1, 1] }], options: [barFrame(0), {}, barFrame(2)] },
    steps: [{ kind: 'action', payload: { type: 'timelineChange', currentIndex: 1 } }, { kind: 'action', payload: { type: 'timelineChange', currentIndex: 3 } },
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: 2 } }] },
  { id: 'replace', group: 'option', note: "timeline.replaceMerge ['series']: a frame's series replace the others", option: bars(tlCat({ replaceMerge: ['series'] }), {
    options: [
      { series: [{ id: 'a', type: 'bar', data: [1, 2, 3, 4] }, { id: 'b', type: 'bar', data: [4, 3, 2, 1] }] },
      { series: [{ id: 'b', type: 'bar', data: [2, 2, 2, 2] }] },
      { series: [{ id: 'c', type: 'bar', data: [3, 1, 3, 1] }, { id: 'a', type: 'bar', data: [1, 1, 1, 1] }] },
      { title: { text: 'only a title' } }] }),
    steps: [{ kind: 'action', payload: { type: 'timelineChange', currentIndex: 1 } }, { kind: 'action', payload: { type: 'timelineChange', currentIndex: 2 } },
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: 3 } }] },
  { id: 'media', group: 'option', note: 'media and a timeline: the frame before the units; a resize merges the units only', W: 700, H: 400,
    option: {
      animation: false,
      baseOption: { timeline: tlCat({}), title: { text: 'base' }, grid: GRID, xAxis: { type: 'category', data: CAT }, yAxis: { max: 8 }, series: [{ type: 'bar', data: [1, 1, 1, 1] }] },
      options: [
        { title: { text: 'F0' }, series: [{ data: [1, 2, 3, 4] }] },
        { title: { text: 'F1' }, series: [{ data: [4, 3, 2, 1] }], grid: { left: 100 } },
        { title: { text: 'F2' }, series: [{ data: [2, 4, 2, 4] }] },
        { title: { text: 'F3' }, series: [{ data: [3, 3, 3, 3] }] }],
      media: [
        { query: { maxWidth: 600 }, option: { timeline: { orient: 'vertical', left: null, right: 0, top: 20, bottom: 20, width: 60, height: null }, grid: { right: 90, bottom: 40 }, title: { text: 'narrow' } } },
        { option: { timeline: { left: '10%', right: '10%' }, grid: { left: 50 } } }],
    },
    steps: [
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: 1 } },
      { kind: 'resize', w: 560, h: 400 },
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: 2 } },
      { kind: 'tap', at: 'tick:3' },
      { kind: 'resize', w: 700, h: 400 },
      { kind: 'set', option: { timeline: { currentIndex: 0 } } },
    ] },
  // ---------------- animation ----------------
  { id: 'anim', group: 'anim', note: 'the series update and the checkpoint after a change', option: bars(tlCat({}), null, { animationDurationUpdate: 1000, animationEasingUpdate: 'linear' }),
    steps: [
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: 2 }, dt: 2000 },
      { kind: 'wait', dt: 100 }, { kind: 'wait', dt: 100 }, { kind: 'wait', dt: 150 }, { kind: 'wait', dt: 300 }, { kind: 'wait', dt: 400 },
      { kind: 'tap', at: 'tick:1' }, { kind: 'wait', dt: 120 },
      { kind: 'tap', at: 'tick:3', dt: 60 }, { kind: 'wait', dt: 80 }, { kind: 'wait', dt: 400 }, { kind: 'wait', dt: 1000 },
    ] },
  { id: 'anim-none', group: 'anim', note: "the base's animation false: the series jump, the checkpoint still slides (its own option), the hover still has no transition", option: bars(tlCat({}), null, { animation: false }),
    steps: [{ kind: 'action', payload: { type: 'timelineChange', currentIndex: 2 } }, { kind: 'wait', dt: 150 }, { kind: 'move', at: 'tick:1' }, { kind: 'wait', dt: 150 }] },
  { id: 'anim-off', group: 'anim', note: 'checkpointStyle animation false: no slide; a custom duration and easing on another', option: bars(tlCat({ checkpointStyle: { animation: false } })),
    steps: [{ kind: 'action', payload: { type: 'timelineChange', currentIndex: 3 } }, { kind: 'wait', dt: 100 },
      { kind: 'set', option: { timeline: { checkpointStyle: { animation: true, animationDuration: 800, animationEasing: 'linear' } } } },
      { kind: 'action', payload: { type: 'timelineChange', currentIndex: 0 }, dt: 50 }, { kind: 'wait', dt: 200 }, { kind: 'wait', dt: 400 }, { kind: 'wait', dt: 400 }] },
];

// ---------------------------------------------------------------------------
// guards
// ---------------------------------------------------------------------------
function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => {
    const c = out.cases.find(q => q.id === id);
    must(c, 'no case ' + id);
    return c;
  };
  const el = (st, role) => st.view && st.view.els.find(e => e.role === role);
  const num = h => {
    const b = Buffer.from(h, 'hex');
    return b.readDoubleBE(0);
  };
  out.cases.forEach(c => guard(c.id + ': the raw layer is a subset of getOption everywhere', c.fails.length === 0));
  // layout
  const ch = cs('cat-h').states[0];
  guard('cat-h: the play button sits at the start of the main group', num(el(ch, 'play').t.x) === 0);
  guard('cat-h: the checkpoint at the first tick', num(el(ch, 'pointer').t.x) === num(el(ch, 'tick:0').t.x));
  guard('cat-h: four labels', ch.view.els.filter(e => e.role.startsWith('label:')).length === 4);
  guard('cat-h: the labels below the axis', num(ch.view.label.y) > num(ch.view.main.y));
  const cv = cs('cat-v').states[0];
  guard('cat-v: the groups turned a quarter', num(cv.view.main.rotation) === Math.PI / 2);
  guard('cat-v: the labels to the left', el(cv, 'label:0').style.align === 'right');
  guard('cat-v-left: the labels to the right', el(cs('cat-v-left').states[0], 'label:0').style.align === 'left');
  guard('cat-top: the labels above', el(cs('cat-top').states[0], 'label:0').style.verticalAlign === 'bottom');
  guard('time-h: the template', el(cs('time-h').states[0], 'label:2').style.text === '2004-07');
  const td = cs('time-dict').states[0];
  guard('time-dict: a year, a month, a day, an hour', ['label:0', 'label:1', 'label:2', 'label:3'].map(r => el(td, r).style.text).join('|') === '2002|Apr|9|05:00');
  guard('value-h: uneven ticks', num(el(cs('value-h').states[0], 'tick:1').t.x) - num(el(cs('value-h').states[0], 'tick:0').t.x)
    < num(el(cs('value-h').states[0], 'tick:2').t.x) - num(el(cs('value-h').states[0], 'tick:1').t.x));
  guard('value-h: the template', el(cs('value-h').states[0], 'label:1').style.text === '1.5 km');
  guard('value-default: commas', el(cs('value-default').states[0], 'label:3').style.text === '12,345.25');
  guard('ctrl-right: play at the far end', num(el(cs('ctrl-right').states[0], 'play').t.x) > num(el(cs('ctrl-right').states[0], 'next').t.x));
  guard('ctrl-none: no buttons', !el(cs('ctrl-none').states[0], 'play') && !el(cs('ctrl-none').states[0], 'next'));
  guard('ctrl-partial: no prev', !el(cs('ctrl-partial').states[0], 'prev') && !!el(cs('ctrl-partial').states[0], 'next'));
  guard('label-hidden: no labels, no lines', !cs('label-hidden').states[0].view.els.some(e => e.role.startsWith('label:') || e.role === 'line'));
  const many = cs('cat-many').states[0];
  const nLab = many.view.els.filter(e => e.role.startsWith('label:')).length;
  guard('cat-many: the auto interval drops labels', nLab > 1 && nLab < 24);
  guard('cat-many: a label click changes', cs('cat-many').states[1].model.currentIndex === 7);
  guard('ec2: type number is a value axis', num(el(cs('ec2').states[0], 'tick:1').t.x) - num(el(cs('ec2').states[0], 'tick:0').t.x)
    === num(el(cs('ec2').states[0], 'tick:2').t.x) - num(el(cs('ec2').states[0], 'tick:1').t.x));
  guard('ec2: the label normal copy', JSON.stringify(cs('ec2').states[0].tree.timeline[0].label.normal) === '{"show":true}');
  guard('inverse: next goes back', cs('inverse').states[1].model.currentIndex === 0 && cs('inverse').states[3].model.currentIndex === 1);
  // clicks
  const cl = cs('click').states;
  guard('click: the tick changes the index', cl[3].model.currentIndex === 2 && cl[3].events.length === 1);
  guard('click: the event is the action\'s', JSON.parse(cl[3].events[0].payload).from === '@view' && JSON.parse(cl[3].events[0].payload).currentIndex === 2);
  guard('click: the label changes the index', cl[6].model.currentIndex === 1);
  guard('click: next three times wraps', cl[9].model.currentIndex === 0);
  guard('click: play starts the timer', cl[11].model.autoPlay === true && cl[11].timer !== null);
  guard('click: the timer fires', cl[12].fired.length === 1);
  guard('click: stop ends it', cl[13].model.autoPlay === false && cl[13].timer === null && cl[14].fired.length === 0);
  guard('click-noloop: clamped', cs('click-noloop').states[1].model.currentIndex === 3);
  // drag
  const dr = cs('drag-rt').states;
  guard('drag-rt: changes while dragging', dr.slice(3, 7).some(s => s.events.length > 0));
  guard('drag-rt: the release dispatches', dr[8].events.length === 1);
  const dn = cs('drag-nrt').states;
  guard('drag-nrt: nothing while dragging', dn.slice(1, 5).every(s => s.events.length === 0));
  guard('drag-nrt: the release changes to the nearest', dn[5].model.currentIndex === 0 && dn[5].events.length === 1);
  // hover
  const hv = cs('hover').states;
  guard('hover: the tick emphasised', el(hv[1], 'tick:1').states.join() === 'progress,emphasis' && el(hv[1], 'tick:1').hover === 2);
  guard('hover: the transition runs', el(hv[2], 'tick:1').style.fill !== el(hv[3], 'tick:1').style.fill || el(hv[1], 'tick:1').style.fill !== el(hv[3], 'tick:1').style.fill);
  // play
  const pl = cs('play-loop').states;
  guard('play-loop: one change a second', pl[1].fired.length === 1 && pl[1].model.currentIndex === 1);
  guard('play-loop: wraps round', pl[5].model.currentIndex === 0);
  const pn = cs('play-noloop').states;
  guard('play-noloop: stops at the end', pn[2].model.autoPlay === false && pn[2].events.map(e => e.type).join() === 'timelinechanged,timelineplaychanged');
  guard('play-noloop: no timer after', pn[3].fired.length === 0 && pn[3].timer === null);
  guard('play-rewind: wraps backwards', cs('play-rewind').states.map(s => s.model.currentIndex).join() === '1,0,3,2');
  guard('play-rewind-noloop: held at 0', cs('play-rewind-noloop').states.map(s => s.model.currentIndex).join() === '1,0,0,0');
  // actions
  const ac = cs('actions').states;
  guard('actions: 5 wraps to 1', ac[1].model.currentIndex === 1);
  guard('actions: -1 wraps to 3', ac[2].model.currentIndex === 3);
  guard('actions: no index still an event', ac[3].events.length === 1 && JSON.parse(ac[3].events[0].payload).currentIndex === 3);
  const an = cs('actions-noloop').states;
  guard('actions-noloop: clamped high', an[1].model.currentIndex === 3);
  guard('actions-noloop: clamped low', an[2].model.currentIndex === 0);
  guard('actions-noloop: the end stops the play', an[4].model.autoPlay === false && an[4].events.length === 2);
  // option
  const mg = cs('merge').states;
  guard('merge: the frame merged again after a merge', mg[1].titles[0] === 'F1');
  guard('merge: new frames', mg[2].titles[0] === 'N2');
  guard('merge: an empty list keeps the frames', mg[3].titles[0] === 'N2');
  guard('merge: notMerge forgets the timeline', mg[5].model === null && mg[5].view === null);
  guard('root-form: an empty frame merges nothing', cs('root-form').states[1].titles[0] === 'F0');
  guard('root-form: no frame past the last', cs('root-form').states[2].titles[0] === 'F0' && cs('root-form').states[2].model.currentIndex === 3);
  const rp = cs('replace').states;
  guard('replace: one series left', rp[1].bars.filter(b => b).length === 1);
  guard('replace: a new id takes the first hole', rp[2].tree.series.map(q => q && q.id).join() === 'c,a' && rp[3].tree.series.length === 0);
  const md = cs('media').states;
  guard('media: the default unit wins over the frame', md[0].tree.grid[0].left === 50);
  guard('media: a resize to the narrow unit', md[2].titles[0] === 'narrow' && md[2].view.main.rotation === hex(Math.PI / 2));
  guard('media: a change after the resize keeps the unit', md[3].titles[0] === 'F2');
  // animation
  const am = cs('anim').states;
  guard('anim: the checkpoint slides', el(am[2], 'pointer').t.x !== el(am[1], 'pointer').t.x && el(am[2], 'pointer').t.x !== el(am[6], 'pointer').t.x);
  guard('anim: the bars move', JSON.stringify(am[2].bars) !== JSON.stringify(am[1].bars) && JSON.stringify(am[2].bars) !== JSON.stringify(am[6].bars));
  const ao = cs('anim-off').states;
  guard('anim-off: a jump', el(ao[1], 'pointer').t.x === el(ao[2], 'pointer').t.x);
  return g;
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED, clock: { T0 },
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: chart._ssr false, env.node off, 600 x 400 unless the case says; animation false unless the case says.',
      'a step: the clock advanced by dt (the play timers fire at their due instants, each followed by a frame), the step, a frame.',
      'a frame: zr.animation.update(), zr.animation.update(true) at the same instant, the display list refreshed.',
      'TZ=UTC; a time case writes useUTC and epoch-ms data.',
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
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : '')
  + '; ' + warnings + ' warnings');
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
