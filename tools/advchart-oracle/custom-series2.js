/*
Upstream's own answers for roadmap C15, batch 124: the CUSTOM series, second
part -- renderItem on the other coordinate systems (polar's prepareCustom:
coordSys {cx, cy, r, r0}, api.coord's [x, y, radius, angle], api.size in px
and radians; calendar's: coordSys {x, y, width, height, cellWidth,
cellHeight, rangeInfo}, api.coord of a date, api.layout's {rect,
contentRect}, no api.size; singleAxis': coordSys {x, y, width, height},
api.coord and api.size of bare values; `coordinateSystem: 'none'`: no
coordSys, no api.coord), the transitions (applyUpdateTransition with the
series as the animatable model: enterFrom with enterAnimation, the default
transition ['x', 'y'], 'all', per-prop lists at the root, in the shape and
in the style, updateAnimation; an element with a leaveTo whose item is
removed -- upstream's applyLeaveTransition reads customInnerStore(el).option,
which CustomView never sets, and throws), the root's focus / blurScope /
emphasisDisabled, an element's tooltipDisabled, and api.visual over a
continuous and a piecewise visualMap.

Every renderItem is JavaScript here and a named handler in the port: an
option says renderItem: '@name' and this script hands the series RENDER[name]
wrapped in a recorder that writes down the params, every api call with its
answer, and the element tree returned. The Pascal tests register a
transcription of each under the same name.

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off and the chart prototype's getDom answering an
empty object so TooltipView runs, with the clock of animation.js (the global
Date replaced BEFORE the dist loads; setTimeout a queue the steps settle),
Math.random the port's xorshift32 and zrender's width table measuring every
string. Every pointer step goes through zrender's own Handler; a paint
follows every step. An animation case samples the clock as graphic.js does:
NOW = the setOption instant + t, zr.animation.update(), the display list
refreshed.

  node tools/advchart-oracle/custom-series2.js

writes tests/fixtures/advchart-custom-series2.json (ORACLE_OUT overrides).
Ends with process.exit().

-----------------------------------------------------------------------------
Numbers that are positions are the 16 lowercase hex digits of the IEEE double
(big-endian; NaN 7ff8000000000000); counts, flags, strings and option values
are plain JSON. Colours of the states are [r, g, b, a] from
echarts.color.parse.

Top level: source, version, seed, clock {T0}, measure {firstCode, ratio[]
(hex)}, notes[], cases[], guards[].

A case: id, group, note, W, H, option (as run; renderItem '@name'), steps[]
(each: {move key | [x, y]} | {leave} | {merge option} | {wait ms}),
samplesMs[] (an animation case), states[] (index-parallel to [after
setOption, after each step that is not a wait]).

A state: calls[] (every renderItem call since the last state, in order: {s
seriesIndex, name (the handler), params, api[] ({fn, args, ret}), ret (the
element tree returned)}); throws (the message setOption threw, or null) and
roots (the number of item roots in the view group, when it threw); els[]
(every element of every custom series' view group, depth first: elRec; at
rest in an animation case), order[], clips[], point, hover, tooltip, st[],
legend (as custom-series.js); samples[] (an animation case: {t, els: {key:
snap}}, snap the seven transform props (hex), style.opacity / fill /
stroke / lineWidth where set, every shape key but transition / enterFrom /
leaveTo).

A value in a recorded params / api answer / element tree: a number as hex, a
string, a boolean, null (also undefined), an array or an object of those (a
Date has no own keys: {}).

elRec: key ('s<series>:<raw dataIndex>' for an item's root, '/k' per child),
type (zrender's), name, ignore, invisible, silent, z, z2, zlevel (hex; null
on a group), t {x, y, rotation, scaleX, scaleY, originX, originY} (hex),
transform (6 hex | null), shape (every key but transition / enterFrom /
leaveTo), path (PathProxy data, hex), style (paths: fill, stroke, lineWidth,
opacity, lineDash; text: text, font, fill, stroke, lineWidth, align,
verticalAlign, x, y, opacity), pieces, label, ec {seriesIndex, dataIndex},
info (JSON text | null).

Guards (any failure: nothing is written, exit 1): every case's recipe
checks (R1: an element's global transform from its props; R2: the display
list sorted by (zlevel, z, z2)); named discriminating facts; the whole
fixture generated twice, byte-identical; no \u0000; it parses back.
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
function settle(at) {
  for (;;) {
    TIMERS = TIMERS.filter(t => String(t.fn).indexOf('requestAnimationFrame') < 0);
    TIMERS.sort((a, b) => a.due - b.due || a.id - b.id);
    if (!TIMERS.length || TIMERS[0].due > at) break;
    const t = TIMERS.shift();
    if (t.due > NOW) NOW = t.due;
    t.fn();
  }
  NOW = Math.max(NOW, at);
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-custom-series2.json');

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
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const enc = id => (id == null ? null : String(id).split('\u0000').join('~'));
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};
function colourOf(c) {
  if (c == null || c === 'none') return null;
  if (typeof c !== 'string') return null;
  const p = echarts.color.parse(c);
  return p ? [p[0], p[1], p[2], p[3]] : null;
}
// a recorded value: numbers hexed, undefined as null
function rv(v) {
  if (v === undefined || v === null) return null;
  if (typeof v === 'number') return hex(v);
  if (typeof v === 'string' || typeof v === 'boolean') return v;
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v).map(rv);
  if (typeof v === 'function') return '<fn>';
  if (typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      if (v[k] === undefined) continue;
      o[k] = rv(v[k]);
    }
    return o;
  }
  throw new OracleError('an unrecordable value ' + typeof v);
}

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

// ---------- the chart ----------
(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk(W, H) {
  rngState = SEED;
  NOW = T0;
  TIMERS = [];
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
const zr = chart => chart.getZr();
function refresh(chart) { zr(chart).storage.getDisplayList(true); }
function paint(chart) {
  chart._onframe();
  refresh(chart);
  quiet(() => chart.renderToSVGString());
  refresh(chart);
}
const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });
let ecKey = null;
function ecDataOf(el) {
  if (!el) return null;
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (k.indexOf('__ec_inner_') === 0 && v && typeof v === 'object' && 'seriesIndex' in v) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}
// customInnerStore: {info, customGraphicType, ...}
function customInner(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'customGraphicType' in el[k]) return el[k];
  }
  return null;
}


// ---------------------------------------------------------------------------
// the renderItems (each mirrored in tests/test.advchart.customseries2.pas)
// ---------------------------------------------------------------------------
const RENDER = {
  // a sector per item on a polar: the radius axis' value, the angle's
  // category band (api.size in radians), barLayout (undefined off a cartesian)
  polarBar(params, api) {
    const r = api.value(0);
    const a = api.value(1);
    const p = api.coord([r, a]);
    const s = api.size([2, 1], [r, a]);
    const lay = api.barLayout({ count: 1 });
    const cs = params.coordSys;
    const c = api.visual('color');
    return { type: 'sector', shape: { cx: cs.cx, cy: cs.cy, r0: cs.r0, r: p[2], startAngle: -p[3] - s[1] / 2, endAngle: -p[3] + s[1] / 2 },
      style: { fill: c, stroke: '#fff' }, info: { band: s[0], none: lay === undefined } };
  },
  // a calendar day: its content rect (api.layout), a dot at its centre
  // (api.coord of a bare date); a date outside the range draws nothing
  calCell(params, api) {
    const t = api.value(0);
    const v = api.value(1);
    const p = api.coord(t);
    const lay = api.layout([t]);
    const cs = params.coordSys;
    const c = api.visual('color');
    if (isNaN(p[0])) return null;
    return { type: 'group', children: [
      { type: 'rect', shape: { x: lay.contentRect.x, y: lay.contentRect.y, width: lay.contentRect.width, height: lay.contentRect.height },
        style: { fill: c, opacity: v / 10 } },
      { type: 'circle', shape: { cx: p[0], cy: p[1], r: Math.min(cs.cellWidth, cs.cellHeight) / 4 }, style: { fill: '#fff' } }] };
  },
  // a dot on a single axis: api.coord and api.size of bare values
  singleDot(params, api) {
    const v = api.value(0);
    const w = api.value(1);
    const p = api.coord(v);
    const s = api.size(w, v);
    const cs = params.coordSys;
    const c = api.visual('color');
    return { type: 'circle', shape: { cx: p[0], cy: p[1], r: s / 2 }, style: { fill: c }, info: { mid: cs.y + cs.height / 2 } };
  },
  // no coordinate system: the values are pixels
  free(params, api) {
    const x = api.value(0);
    const y = api.value(1);
    const w = api.value(2);
    const h = api.getHeight();
    const c = api.visual('color');
    return { type: 'rect', shape: { x: x, y: y, width: w, height: h / 20 }, style: { fill: c },
      info: { cs: params.coordSys === undefined ? 'none' : params.coordSys.type } };
  },
  // a dot in the visualMap's colour, its size the visualMap's symbolSize
  vmDot(params, api) {
    const x = api.value(0);
    const y = api.value(1);
    const p = api.coord([x, y]);
    const c = api.visual('color');
    const sz = api.visual('symbolSize');
    const sym = api.visual('symbol');
    api.visual('opacity');
    api.visual('liftZ');
    const st = api.style();
    const el = { type: 'circle', shape: { cx: p[0], cy: p[1], r: (sz || 10) / 2 }, style: { fill: c },
      info: { sym: sym === undefined ? null : sym } };
    if (st.opacity != null) el.style.opacity = st.opacity;
    return el;
  },
  // entering: the root's and the style's enterFrom with an enterAnimation
  // of its own, a shape's enterFrom on the series' timing, a group scaled in
  enterRI(params, api) {
    const x = api.value(0);
    const y = api.value(1);
    const p = api.coord([x, y]);
    const c = api.visual('color');
    const i = params.dataIndex;
    if (i === 0) {
      return { type: 'rect', x: p[0], y: p[1], shape: { x: -15, y: -10, width: 30, height: 20 },
        style: { fill: c, enterFrom: { opacity: 0 } }, enterFrom: { y: p[1] + 80 },
        enterAnimation: { duration: 800, easing: 'linear', delay: 100 } };
    }
    if (i === 1) return { type: 'circle', shape: { cx: p[0], cy: p[1], r: 12, enterFrom: { r: 0 } }, style: { fill: c } };
    return { type: 'group', x: p[0], y: p[1], enterFrom: { scaleX: 0, scaleY: 0 }, children: [
      { type: 'rect', shape: { x: -10, y: -10, width: 20, height: 20 }, style: { fill: c, enterFrom: { opacity: 0 } } },
      { type: 'circle', shape: { cx: 0, cy: 0, r: 4 }, style: { fill: '#fff' } }] };
  },
  // updating: the third column picks the transition -- 0 the default
  // ['x', 'y'], 1 'all', 2 per-prop lists, 3 the words shape and style with
  // an updateAnimation of its own
  moveRI(params, api) {
    const x = api.value(0);
    const y = api.value(1);
    const k = api.value(2);
    const p = api.coord([x, y]);
    const c = api.visual('color');
    if (k === 0) return { type: 'rect', x: p[0], y: p[1], shape: { x: -10, y: -10, width: 20, height: 10 + y }, style: { fill: c } };
    if (k === 1) {
      return { type: 'rect', x: p[0], y: p[1], transition: 'all', shape: { x: -10, y: -10, width: 10 + y * 2, height: 20 },
        style: { fill: y > 5 ? '#ee6666' : c, opacity: 0.5 + y / 20 } };
    }
    if (k === 2) {
      return { type: 'circle', x: p[0], y: p[1], transition: ['x'], shape: { cx: 0, cy: 0, r: 5 + y, transition: ['r'] },
        style: { fill: y > 5 ? '#fac858' : c, stroke: '#333', lineWidth: y / 2, transition: ['fill'] } };
    }
    return { type: 'rect', shape: { x: p[0] - 10, y: p[1] - 10, width: 20, height: 20 }, transition: ['shape', 'style'],
      updateAnimation: { duration: 300, easing: 'linear' }, style: { fill: c, opacity: 0.3 + y / 20 } };
  },
  // a leaveTo on the last item
  leaveRI(params, api) {
    const x = api.value(0);
    const y = api.value(1);
    const p = api.coord([x, y]);
    const c = api.visual('color');
    const el = { type: 'rect', x: p[0], y: p[1], shape: { x: -10, y: -10, width: 20, height: 20 }, style: { fill: c } };
    if (params.dataIndex === 2) {
      el.leaveTo = { y: p[1] + 50 };
      el.style.leaveTo = { opacity: 0 };
    }
    return el;
  },
  // a bar per series, side by side: series 0 focuses 'self', series 1
  // 'series' over the whole chart, series 2 none -- its second item with
  // its emphasis disabled
  focusRI(params, api) {
    const v0 = api.value(0);
    const v1 = api.value(1);
    const p = api.coord([v0, v1]);
    const base = api.coord([v0, 0]);
    const c = api.visual('color');
    const s = params.seriesIndex;
    const el = { type: 'rect', shape: { x: p[0] - 15 + s * 10, y: p[1], width: 10, height: base[1] - p[1] }, style: { fill: c } };
    if (s === 0) el.focus = 'self';
    if (s === 1) {
      el.focus = 'series';
      el.blurScope = 'global';
    }
    if (s === 2 && params.dataIndex === 1) el.emphasisDisabled = true;
    return el;
  },
  // tooltipDisabled on a root, on one child of a group, on a group over its
  // child
  tipRI(params, api) {
    const x = api.value(0);
    const y = api.value(1);
    const p = api.coord([x, y]);
    const c = api.visual('color');
    const i = params.dataIndex;
    if (i === 0) return { type: 'circle', tooltipDisabled: true, shape: { cx: p[0], cy: p[1], r: 15 }, style: { fill: c } };
    if (i === 1) {
      return { type: 'group', children: [
        { type: 'rect', tooltipDisabled: true, shape: { x: p[0] - 30, y: p[1] - 10, width: 25, height: 20 }, style: { fill: c } },
        { type: 'rect', shape: { x: p[0] + 5, y: p[1] - 10, width: 25, height: 20 }, style: { fill: '#91cc75' } }] };
    }
    if (i === 3) {
      return { type: 'group', tooltipDisabled: true, children: [
        { type: 'rect', shape: { x: p[0] - 10, y: p[1] - 10, width: 20, height: 20 }, style: { fill: c } }] };
    }
    return { type: 'circle', shape: { cx: p[0], cy: p[1], r: 15 }, style: { fill: c } };
  },
};

// the recorder each '@name' becomes
let CALLS = [];
function recorder(name) {
  const fn = RENDER[name];
  must(fn, 'no renderItem ' + name);
  return function (params, api) {
    const call = { s: params.seriesIndex, name, params: null, api: [], ret: null };
    call.params = {
      dataIndex: params.dataIndex, dataIndexInside: params.dataIndexInside, dataInsideLength: params.dataInsideLength,
      actionType: params.actionType == null ? null : params.actionType, seriesId: enc(params.seriesId),
      seriesName: params.seriesName == null ? null : enc(params.seriesName), seriesIndex: params.seriesIndex,
      coordSys: rv(params.coordSys), encode: clone(params.encode), itemPayload: clone(params.itemPayload),
      context: rv(params.context) };
    const wrapped = {};
    for (const k of Object.keys(api)) {
      if (typeof api[k] !== 'function') continue;
      wrapped[k] = function () {
        const args = Array.from(arguments);
        const recArgs = rv(args);
        const ret = api[k].apply(api, args);
        call.api.push({ fn: k, args: recArgs, ret: rv(ret) });
        return ret;
      };
    }
    const ret = quiet(() => fn(params, wrapped));
    call.ret = rv(ret);
    CALLS.push(call);
    return ret;
  };
}
function materialize(v) {
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      if (k === 'renderItem' && typeof v[k] === 'string' && v[k][0] === '@') o[k] = recorder(v[k].slice(1));
      else o[k] = materialize(v[k]);
    }
    return o;
  }
  return v;
}

// ---------------------------------------------------------------------------
// reading the elements
// ---------------------------------------------------------------------------
const TKEYS = ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'originX', 'originY'];
// a dirty shape's path rebuilt first: the SVG painter writes a circle and an
// ellipse as their own elements and never rebuilds el.path for them
const pathData = el => {
  el.getBoundingRect();
  must(el.path, 'no path proxy');
  return Array.from(el.path.data).slice(0, el.path.len());
};
const opac = st => (st.opacity == null ? 1 : st.opacity);
const rectRec = r => ({ x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) });
function valRec(v) {
  if (v == null) return null;
  if (typeof v === 'number') return hex(v);
  if (typeof v === 'boolean' || typeof v === 'string') return v;
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v).map(valRec);
  return JSON.stringify(v);
}
// the transition keys an option leaves in the shape are not geometry
const SKIP_SHAPE = { transition: 1, enterFrom: 1, leaveTo: 1 };
function shapeRec(shape) {
  const o = {};
  for (const k of Object.keys(shape)) if (!SKIP_SHAPE[k]) o[k] = valRec(shape[k]);
  return o;
}
function piecesOf(textEl) {
  return textEl.childrenRef().map(c => {
    const s = c.style;
    if (c.type === 'tspan') {
      return { k: 't', text: s.text == null ? null : String(s.text), x: hexN(s.x), y: hexN(s.y), font: s.font,
        align: s.textAlign == null ? null : s.textAlign, base: s.textBaseline == null ? null : s.textBaseline,
        fill: s.fill == null ? null : String(s.fill), stroke: s.stroke == null ? null : String(s.stroke),
        lineWidth: hexN(s.lineWidth), opacity: hex(opac(s)) };
    }
    if (c.type === 'rect') {
      return { k: 'r', x: hex(c.shape.x), y: hex(c.shape.y), width: hex(c.shape.width), height: hex(c.shape.height),
        r: valRec(c.shape.r), fill: s.fill == null ? null : String(s.fill), stroke: s.stroke == null ? null : String(s.stroke),
        lineWidth: hexN(s.lineWidth) };
    }
    return { k: c.type };
  });
}
function textStyleRec(s) {
  return { text: s.text == null ? null : String(s.text), font: s.font == null ? null : s.font,
    fill: s.fill == null ? null : String(s.fill), stroke: s.stroke == null ? null : String(s.stroke),
    lineWidth: hexN(s.lineWidth), align: s.align == null ? null : s.align,
    verticalAlign: s.verticalAlign == null ? null : s.verticalAlign, x: hexN(s.x), y: hexN(s.y), opacity: hex(opac(s)) };
}
function labelRec(host) {
  const tc = host.getTextContent();
  if (!tc) return null;
  tc.getComputedTransform();
  const it = tc.innerTransformable;
  const ds = tc._defaultStyle || {};
  return { transform: tc.transform ? Array.from(tc.transform).map(hex) : null,
    inner: { x: hex(it.x), y: hex(it.y), rotation: hex(it.rotation), originX: hex(it.originX), originY: hex(it.originY) },
    def: { fill: ds.fill == null ? null : String(ds.fill), stroke: ds.stroke == null ? null : String(ds.stroke),
      autoStroke: !!ds.autoStroke, align: ds.align == null ? null : ds.align,
      verticalAlign: ds.verticalAlign == null ? null : ds.verticalAlign },
    style: textStyleRec(tc.style), pieces: piecesOf(tc),
    z: hex(tc.z), z2: hex(tc.z2), zlevel: hex(tc.zlevel), ignore: !!tc.ignore, silent: !!tc.silent };
}
function elRec(el, key) {
  const r = { key, type: el.type, name: el.name == null || el.name === '' ? null : String(el.name) };
  r.ignore = !!el.ignore;
  r.invisible = !!el.invisible;
  r.silent = !!el.silent;
  r.z = el.isGroup ? null : hex(el.z);
  r.zlevel = el.isGroup ? null : hex(el.zlevel);
  r.z2 = el.isGroup ? null : hex(el.z2);
  r.t = {};
  for (const k of TKEYS) r.t[k] = hex(el[k]);
  r.transform = el.transform ? Array.from(el.transform).map(hex) : null;
  if (el.type === 'text') {
    r.style = textStyleRec(el.style);
    r.pieces = piecesOf(el);
  }
  else if (!el.isGroup) {
    const s = el.style;
    r.shape = shapeRec(el.shape);
    r.path = pathData(el).map(hex);
    r.style = { fill: s.fill == null ? null : String(s.fill), stroke: s.stroke == null ? null : String(s.stroke),
      lineWidth: hexN(s.lineWidth), opacity: hex(opac(s)), lineDash: s.lineDash == null ? null : valRec(s.lineDash) };
  }
  r.label = el.isGroup ? null : labelRec(el);
  const ecd = ecDataOf(el);
  r.ec = ecd ? { seriesIndex: ecd.seriesIndex == null ? null : ecd.seriesIndex, dataIndex: ecd.dataIndex == null ? null : ecd.dataIndex } : null;
  const inn = customInner(el);
  r.info = inn && inn.info !== undefined ? JSON.stringify(inn.info) : null;
  return r;
}
function customSeries(chart) {
  const out = [];
  chart.getModel().eachRawSeries(s => {
    if (s.subType === 'custom') out.push(s);
  });
  return out;
}
// every element of every custom view group, depth first, keyed
function keyedTree(chart) {
  const list = [];
  customSeries(chart).forEach(s => {
    const view = chart.getViewOfSeriesModel(s);
    if (!view) return;
    const data = s.getData();
    const walk = (el, key) => {
      list.push({ el, key });
      if (el.isGroup) el.childrenRef().forEach((c, k) => walk(c, key + '/' + k));
    };
    view.group.childrenRef().forEach(el => {
      const ecd = ecDataOf(el);
      must(ecd && ecd.dataIndex != null, 'a custom root without a data index');
      walk(el, 's' + s.seriesIndex + ':' + data.getRawIndex(ecd.dataIndex));
    });
  });
  return list;
}
function readEls(chart) {
  return keyedTree(chart).map(q => elRec(q.el, q.key));
}
function keyOf(chart, target) {
  const tree = keyedTree(chart);
  for (let e = target; e; e = e.__hostTarget || e.parent) {
    const q = tree.find(t => t.el === e);
    if (q) return q.key + (e !== target && target === e.getTextContent() ? '#label' : '');
  }
  return null;
}
function readOrder(chart) {
  const tree = keyedTree(chart);
  const tags = new Map();
  tree.forEach(q => {
    tags.set(q.el, q.key);
    const tc = q.el.getTextContent && q.el.getTextContent();
    if (tc) {
      tags.set(tc, q.key + '#label');
      tc.childrenRef().forEach(c => tags.set(c, q.key + '#label'));
    }
    if (q.el.type === 'text') q.el.childrenRef().forEach(c => tags.set(c, q.key));
  });
  const out = [];
  zr(chart).storage.getDisplayList(true).forEach(d => {
    const t = tags.get(d);
    if (t !== undefined && out[out.length - 1] !== t) out.push(t);
  });
  return out;
}
function readClips(chart) {
  return customSeries(chart).map(s => {
    const view = chart.getViewOfSeriesModel(s);
    const cp = view && view.group.getClipPath();
    return { s: s.seriesIndex, rect: cp ? [cp.shape.x, cp.shape.y, cp.shape.width, cp.shape.height].map(hex) : null };
  });
}
function readSt(chart) {
  return keyedTree(chart).filter(q => !q.el.isGroup && q.el.type !== 'text').map(q => {
    const s = q.el.style;
    return { key: q.key, states: (q.el.currentStates || []).slice(), fill: colourOf(s.fill), stroke: colourOf(s.stroke),
      lineWidth: hexN(s.lineWidth), opacity: hex(opac(s)), z2: q.el.z2 };
  });
}

// ---------- transforms, recomputed (R1) ----------
function mul(m1, m2) {
  return [m1[0] * m2[0] + m1[2] * m2[1], m1[1] * m2[0] + m1[3] * m2[1], m1[0] * m2[2] + m1[2] * m2[3],
    m1[1] * m2[2] + m1[3] * m2[3], m1[0] * m2[4] + m1[2] * m2[5] + m1[4], m1[1] * m2[4] + m1[3] * m2[5] + m1[5]];
}
function localOf(t) {
  const m = [];
  const ox = t.originX || 0;
  const oy = t.originY || 0;
  const sx = t.scaleX;
  const sy = t.scaleY;
  const rotation = t.rotation || 0;
  if (ox || oy) {
    m[4] = -ox * sx;
    m[5] = -oy * sy;
  }
  else m[4] = m[5] = 0;
  m[0] = sx; m[3] = sy; m[1] = 0; m[2] = 0;
  if (rotation) {
    const aa = m[0], ac = m[2], atx = m[4], ab = m[1], ad = m[3], aty = m[5];
    const st = Math.sin(rotation);
    const ct = Math.cos(rotation);
    m[0] = aa * ct + ab * st;
    m[1] = -aa * st + ab * ct;
    m[2] = ac * ct + ad * st;
    m[3] = -ac * st + ct * ad;
    m[4] = ct * atx + st * aty;
    m[5] = ct * aty - st * atx;
  }
  m[4] += ox + t.x;
  m[5] += oy + t.y;
  return m;
}
const around = v => v > 5e-5 || v < -5e-5;
function needLocal(t) {
  return around(t.rotation) || around(t.x) || around(t.y) || around(t.scaleX - 1) || around(t.scaleY - 1);
}
function checkTransforms(chart, fails, where) {
  customSeries(chart).forEach(s => {
    const view = chart.getViewOfSeriesModel(s);
    if (!view) return;
    const walk = (g, parentM) => g.childrenRef().forEach(el => {
      const t = {};
      TKEYS.forEach(k => { t[k] = el[k]; });
      must(!el.skewX && !el.skewY && !el.anchorX && !el.anchorY, where + ': a skew or an anchor');
      let m = null;
      if (needLocal(t) || parentM) {
        m = needLocal(t) ? localOf(t) : [1, 0, 0, 1, 0, 0];
        if (parentM) m = needLocal(t) ? mul(parentM, m) : parentM.slice();
      }
      const got = el.transform ? Array.from(el.transform) : null;
      const same = (m === null && (got === null || got.join() === '1,0,0,1,0,0'))
        || (m !== null && got !== null && m.every((v, i) => Object.is(v, got[i]) || (v === 0 && got[i] === 0)));
      if (!same) fails.push(where + ': R1 the transform ' + JSON.stringify(got) + ', the recipe ' + JSON.stringify(m));
      if (el.isGroup) walk(el, got && got.join() !== '1,0,0,1,0,0' ? got : (m || null));
    });
    walk(view.group, null);
  });
}
function checkSorted(chart, fails, where) {
  const list = zr(chart).storage.getDisplayList(true);
  for (let i = 1; i < list.length; i++) {
    const a = list[i - 1];
    const b = list[i];
    const k = (a.zlevel - b.zlevel) || (a.z - b.z) || (a.z2 - b.z2);
    if (k > 0) fails.push(where + ': R2 the display list is not sorted at ' + i);
  }
}

// ---------- the pointer ----------
function hoverTarget(chart, x, y) {
  refresh(chart);
  return zr(chart).handler.findHover(x, y).target;
}
function spiral(x0, y0, ok, where) {
  for (let r = 0; r <= 24; r++) {
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        if (ok(x0 + dx, y0 + dy)) return [x0 + dx, y0 + dy];
      }
    }
  }
  throw new OracleError(where + ': no point found near ' + x0 + ',' + y0);
}
// a point the pointer finds the element of a key at
function resolvePoint(chart, t, where) {
  if (Array.isArray(t)) return t.slice();
  const q = keyedTree(chart).find(e => e.key === t);
  must(q, where + ': no element ' + t);
  const r = q.el.getBoundingRect().clone();
  q.el.getComputedTransform();
  if (q.el.transform) r.applyTransform(q.el.transform);
  return spiral(Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2),
    (x, y) => keyOf(chart, hoverTarget(chart, x, y)) === t, where);
}
function hoverRec(chart, x, y) {
  const t = hoverTarget(chart, x, y);
  if (!t) return null;
  let d = null;
  for (let e = t; e; e = e.__hostTarget || e.parent) {
    const q = ecDataOf(e);
    if (q && q.seriesIndex != null) { d = q; break; }
  }
  return { key: keyOf(chart, t), seriesIndex: d ? d.seriesIndex : null, dataIndex: d && d.dataIndex != null ? d.dataIndex : null };
}
const SEGMENT = /\{(__EC_aUTo_\d+)\|([^}]*)\}/g;
function tooltipRows(content) {
  const text = String(content.el.style.text);
  const rich = content.el.style.rich || {};
  return text.split('\n').map(line => {
    const row = { marker: null, name: null, value: null };
    SEGMENT.lastIndex = 0;
    let m;
    while ((m = SEGMENT.exec(line))) {
      const st = rich[m[1]] || {};
      // a marker is the box with a width; a value is the bold run; any other
      // run is a name
      if (st.width != null) row.marker = st.width === 10 ? 'item' : 'subItem';
      else if (st.fontWeight != null && +st.fontWeight >= 700 || st.fontWeight === 'bold') row.value = m[2];
      else row.name = m[2];
    }
    return row;
  });
}
function legendRec(chart) {
  const m = chart.getModel().getComponent('legend', 0);
  if (!m) return null;
  const v = chart.getViewOfComponentModel(m);
  const out = [];
  v.group.traverse(el => {
    if (el.type === 'text' && el.parent) {
      const icon = el.parent.childAt(0);
      if (icon && icon.shape && icon.shape.symbolType) {
        out.push({ name: String(el.style.text), selected: m.isSelected(String(el.style.text)),
          icon: icon.shape.symbolType, fill: colourOf(icon.style.fill) });
      }
    }
  });
  return out;
}


// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
const GRID = { left: 60, right: 40, top: 40, bottom: 40 };
const COLORS = ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'];
const SAMPLES = [0, 1, 50, 100, 200, 300, 350, 400, 500, 600, 700, 800, 900, 1000, 1001, 1500];
const add = (group, id, note, option, more) => CASES.push(Object.assign({ group, id, note, W: 600, H: 400,
  option: Object.assign({ animation: false, color: COLORS, grid: GRID }, option), steps: [] }, more || {}));

add('coords', 'polar', "sectors on a polar: coordSys {cx, cy, r, r0}, api.coord's [x, y, radius, angle], api.size with a data item (px on the value radius, the category band in radians), barLayout undefined; a hover",
  { polar: { radius: [20, '80%'] }, angleAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, radiusAxis: { type: 'value', min: 0, max: 10 },
    series: [{ type: 'custom', coordinateSystem: 'polar', renderItem: '@polarBar', data: [[3, 0], [7, 1], [5, 2], [9, 3]] }] },
  { steps: [{ move: 's0:1' }] });
add('coords', 'calendar', "calendar days: coordSys {x, y, width, height, cellWidth, cellHeight, rangeInfo}, api.coord of a bare date, api.layout's rect and contentRect; a date past the range is NaN and draws nothing",
  { calendar: { range: '2017-02', cellSize: [40, 30], left: 60, top: 60 },
    series: [{ type: 'custom', coordinateSystem: 'calendar', renderItem: '@calCell',
      data: [['2017-02-03', 3], ['2017-02-14', 8], ['2017-02-27', 5], ['2017-03-02', 4]] }] });
add('coords', 'single', "dots on a single axis: coordSys {x, y, width, height}, api.coord and api.size of bare values (a number back)",
  { singleAxis: { type: 'value', min: 0, max: 20, top: 100, height: 60 },
    series: [{ type: 'custom', coordinateSystem: 'singleAxis', renderItem: '@singleDot', data: [[3, 2], [9, 5], [15, 3]] }] });
add('coords', 'single-category', "dots on a CATEGORY single axis: api.size is the band width whatever the value asked (milestone C14-C22)",
  { singleAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e'], top: 100, height: 60 },
    series: [{ type: 'custom', coordinateSystem: 'singleAxis', renderItem: '@singleDot', data: [[0, 2], [2, 5], [4, 3]] }] });
add('coords', 'none', "coordinateSystem 'none': no coordSys, the dimensions x and y, the values as pixels; a hover",
  { series: [{ type: 'custom', coordinateSystem: 'none', renderItem: '@free', data: [[50, 60, 120], [200, 100, 80], [320, 240, 40]] }] },
  { steps: [{ move: 's0:1' }] });
add('visual', 'visualmap', "api.visual over a continuous visualMap (colour, symbolSize and opacity mapped; api.style's opacity) and a piecewise one (a piece's colour as written, a piece's symbol); the visuals nothing sets undefined",
  { xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
    visualMap: [{ type: 'continuous', show: false, seriesIndex: 0, dimension: 2, min: 0, max: 10,
      inRange: { color: ['#313695', '#ffffbf', '#a50026'], symbolSize: [8, 24], opacity: [0.5, 1] } },
    { type: 'piecewise', show: false, seriesIndex: 1, dimension: 2,
      pieces: [{ min: 0, max: 5, color: '#ee6666' }, { min: 5, max: 10, color: '#91cc75', symbol: 'diamond' }] }],
    series: [{ type: 'custom', renderItem: '@vmDot', data: [[1, 2, 0], [3, 5, 4], [5, 7, 7.5], [7, 3, 10]] },
      { type: 'custom', renderItem: '@vmDot', data: [[2, 8, 2], [6, 6, 8], [8, 1, 9]] }] });
add('anim', 'enter', "enter: the root's enterFrom (y) and the style's (opacity) with an enterAnimation (800 ms linear, delay 100), a shape's enterFrom (r) on the series' timing (1000 ms cubicInOut, animationDelay 40), a group scaled in with its children",
  { animation: true, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
    series: [{ type: 'custom', renderItem: '@enterRI', animationDelay: 40, data: [[2, 3], [5, 6], [8, 4]] }] },
  { samples: SAMPLES });
add('anim', 'update', "update after a data change: the default transition ['x', 'y'] (the shape jumps), 'all' (the transform, the shape, the animatable style), per-prop lists (root x, shape r, style fill), the words 'shape' and 'style' with an updateAnimation (300 ms linear), the series' animationDurationUpdate 700 and quadraticOut; a new item enters as it is; a second change removes four items at once",
  { animation: true, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
    series: [{ type: 'custom', renderItem: '@moveRI', animationDurationUpdate: 700, animationEasingUpdate: 'quadraticOut',
      data: [[1, 2, 0], [3, 4, 1], [5, 6, 2], [7, 3, 3], [9, 8, 0]] }] },
  { samples: SAMPLES, steps: [{ wait: 2000 },
    { merge: { series: [{ data: [[2, 7, 0], [3, 8, 1], [6, 2, 2], [7, 9, 3], [8, 1, 0], [4, 5, 1]] }] } },
    { wait: 2000 },
    { merge: { series: [{ data: [[1, 1, 0], [9, 9, 1]] }] } }] });
add('leave', 'leave', "a removed item whose element has a leaveTo: applyLeaveTransition reads customInnerStore(el).option, which CustomView never sets -- the render throws after updating the items before it",
  { animation: true, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
    series: [{ type: 'custom', renderItem: '@leaveRI', data: [[2, 3], [5, 6], [8, 4]] }] },
  { samples: [0, 2000], steps: [{ merge: { series: [{ data: [[2, 4], [5, 7]] }] } }] });
add('leave', 'leave-static', 'the same with the animation off: the throw does not depend on it',
  { xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
    series: [{ type: 'custom', renderItem: '@leaveRI', data: [[2, 3], [5, 6], [8, 4]] }] },
  { steps: [{ merge: { series: [{ data: [[2, 4], [5, 7]] }] } }] });
add('hover', 'focus', "the root's focus and blurScope: 'self' (the default scope, the coordinate system) blurs its own series but the hovered item and the other series of its grid, not the series on the second grid; 'series' with blurScope 'global' every other series, the second grid's too; none blurs nothing; emphasisDisabled: no hover at all",
  { grid: [{ left: 60, right: 320, top: 40, bottom: 40 }, { left: 340, right: 40, top: 40, bottom: 40 }],
    xAxis: [{ type: 'category', data: ['a', 'b', 'c'] }, { type: 'category', data: ['a', 'b', 'c'], gridIndex: 1 }],
    yAxis: [{ type: 'value', min: 0, max: 10 }, { type: 'value', min: 0, max: 10, gridIndex: 1 }],
    series: [{ type: 'custom', renderItem: '@focusRI', data: [[0, 4], [1, 6], [2, 3]] },
      { type: 'custom', renderItem: '@focusRI', data: [[0, 5], [1, 7], [2, 2]] },
      { type: 'custom', renderItem: '@focusRI', xAxisIndex: 1, yAxisIndex: 1, data: [[0, 3], [1, 8], [2, 6]] }] },
  { steps: [{ move: 's0:0' }, { move: 's1:1' }, { move: 's2:0' }, { move: 's2:1' }, { leave: true }] });
add('hover', 'tooltip', "tooltipDisabled: on a root, on one child of a group (its sibling still shows the tooltip), on a group (its child hides it)",
  { tooltip: {}, xAxis: { type: 'category', data: ['p', 'q', 'r', 's'] }, yAxis: { type: 'value', min: 0, max: 10 },
    series: [{ type: 'custom', name: 'T', renderItem: '@tipRI', data: [[0, 4], [1, 6], [2, 3], [3, 5]] }] },
  { steps: [{ move: 's0:2' }, { move: 's0:0' }, { move: 's0:1/0' }, { move: 's0:1/1' }, { move: 's0:3/0' }, { leave: true }] });
// [F4c] coordinateSystem written null (a harvested `undefined`): the merge
// keeps the key, the default 'cartesian2d' never arrives, no creator claims
// the series -- it renders with no coordSys, as 'none' does, and says nothing
add('coords', 'none-null', "coordinateSystem null: no coordSys (the key the option has keeps the default out), as 'none'; a hover",
  { series: [{ type: 'custom', coordinateSystem: null, renderItem: '@free', data: [[50, 60, 120], [200, 100, 80], [320, 240, 40]] }] },
  { steps: [{ move: 's0:1' }] });

// ---------------------------------------------------------------------------
// one case
// ---------------------------------------------------------------------------
const SNAP_STYLE = ['opacity', 'fill', 'stroke', 'lineWidth'];
function snap(el) {
  const o = {};
  for (const k of TKEYS) o[k] = hex(el[k]);
  if (el.style) for (const k of SNAP_STYLE) if (el.style[k] != null) o['style.' + k] = valRec(el.style[k]);
  if (el.shape) {
    for (const k of Object.keys(el.shape)) {
      if (SKIP_SHAPE[k] || el.shape[k] == null) continue;
      o['shape.' + k] = valRec(el.shape[k]);
    }
  }
  return o;
}
function samplesOf(chart, start, times) {
  const z = zr(chart);
  return times.map(t => {
    NOW = start + t;
    z.animation.update();
    refresh(chart);
    const els = {};
    keyedTree(chart).forEach(q => { els[q.key] = snap(q.el); });
    return { t, els };
  });
}
function rootCount(chart) {
  let n = 0;
  customSeries(chart).forEach(s => {
    const view = chart.getViewOfSeriesModel(s);
    if (view) n += view.group.childrenRef().length;
  });
  return n;
}
function runCase(c) {
  const fails = [];
  const chart = mk(c.W, c.H);
  try {
    const rec = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: clone(c.option), steps: clone(c.steps), states: [] };
    if (c.samples) rec.samplesMs = c.samples;
    const tv = () => {
      const m = chart.getModel().getComponent('tooltip', 0);
      return m ? chart.getViewOfComponentModel(m) : null;
    };
    const state = (step) => {
      const st = { calls: CALLS.splice(0), throws: null };
      const pointer = step && (step.move !== undefined || step.leave);
      if (!pointer) {
        st.els = readEls(chart);
        st.order = readOrder(chart);
        st.clips = readClips(chart);
      }
      st.st = readSt(chart);
      st.legend = legendRec(chart);
      checkTransforms(chart, fails, c.id);
      checkSorted(chart, fails, c.id);
      return st;
    };
    // an animation case: the calls, the samples from the setOption instant,
    // the elements at rest after the last
    const animState = (start) => {
      const st = { calls: CALLS.splice(0), throws: null, samples: samplesOf(chart, start, c.samples) };
      // a paint at rest: the paths are built where the props ended
      paint(chart);
      st.els = readEls(chart);
      checkTransforms(chart, fails, c.id);
      checkSorted(chart, fails, c.id);
      return st;
    };
    CALLS = [];
    let start = NOW;
    quiet(() => chart.setOption(materialize(c.option)));
    if (c.samples) rec.states.push(animState(start));
    else {
      paint(chart);
      rec.states.push(state(null));
    }
    let clock = start + (c.samples ? c.samples[c.samples.length - 1] : 0);
    c.steps.forEach((step, i) => {
      const where = c.id + ' step ' + i;
      if (step.wait !== undefined) {
        clock += step.wait;
        NOW = clock;
        zr(chart).animation.update();
        return;
      }
      if (!c.samples) settle(NOW + 500);
      let point = null;
      let threw = null;
      if (step.move !== undefined) {
        point = resolvePoint(chart, step.move, where);
        zr(chart).handler.mousemove(raw(point[0], point[1]));
      }
      else if (step.leave) zr(chart).handler.mouseout(raw(-1, -1));
      else if (step.merge) {
        if (c.samples) NOW = clock;
        start = NOW;
        try {
          quiet(() => chart.setOption(materialize(step.merge)));
        }
        catch (e) {
          threw = e.message;
        }
      }
      else throw new OracleError(where + ': an unknown step ' + JSON.stringify(step));
      if (threw !== null) {
        // what the throw left: the calls made before it and the roots in the
        // view group; nothing else is read
        rec.states.push({ calls: CALLS.splice(0), throws: threw, roots: rootCount(chart) });
        return;
      }
      if (c.samples) {
        rec.states.push(animState(start));
        clock = start + c.samples[c.samples.length - 1];
        return;
      }
      paint(chart);
      settle(NOW + 500);
      paint(chart);
      const st = state(step);
      st.point = point;
      st.hover = point ? hoverRec(chart, point[0], point[1]) : null;
      const t = tv();
      if (t) {
        const ct = t._tooltipContent;
        const vis = !!(ct && ct.el && !ct.el.ignore && !ct.el.invisible);
        st.tooltip = { shown: vis, rows: vis ? tooltipRows(ct) : null };
      }
      else st.tooltip = null;
      rec.states.push(st);
    });
    rec.fails = fails;
    return rec;
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// named guards
// ---------------------------------------------------------------------------
function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => out.cases.find(q => q.id === id);
  const num = h => {
    bits.setUint32(0, parseInt(h.slice(0, 8), 16));
    bits.setUint32(4, parseInt(h.slice(8), 16));
    return bits.getFloat64(0);
  };
  const call = (id, si, k) => cs(id).states[si].calls[k];
  const apiOf = (c, fn) => c.api.filter(a => a.fn === fn);
  const elOf = (id, si, key) => cs(id).states[si].els.find(e => e.key === key);
  const smp = (id, si, t, key) => cs(id).states[si].samples.find(q => q.t === t).els[key];
  out.cases.forEach(q => guard(q.id + ': every record matches its recipe', q.fails.length === 0));
  out.cases.forEach(q => q.states.forEach((s, i) => {
    const step = i > 0 ? q.steps.filter(x => x.wait === undefined)[i - 1] : null;
    if (step && (step.move !== undefined || step.leave)) guard(q.id + ' state ' + i + ': a pointer step renders nothing', s.calls.length === 0);
  }));
  // polar
  const p0 = call('polar', 0, 0);
  guard('polar: the coordSys is the centre and the radii', p0.params.coordSys.type === 'polar' && p0.params.coordSys.cx != null
    && p0.params.coordSys.r0 != null && p0.params.encode.radius.join() === '0' && p0.params.encode.angle.join() === '1');
  guard('polar: api.coord answers x, y, radius and the angle in radians', apiOf(p0, 'coord')[0].ret.length === 4
    && Math.abs(num(apiOf(p0, 'coord')[0].ret[3])) < 7);
  guard('polar: a category band is an angle in radians', Math.abs(num(apiOf(p0, 'size')[0].ret[1]) - Math.PI / 2) < 1e-9);
  guard('polar: barLayout is undefined off a cartesian', apiOf(p0, 'barLayout')[0].ret === null);
  guard('polar: a sector is drawn per item', elOf('polar', 0, 's0:3').type === 'sector');
  guard('polar: the hover finds the sector', cs('polar').states[1].hover.dataIndex === 1);
  // calendar
  const c0 = call('calendar', 0, 0);
  guard('calendar: the coordSys carries the cell size and the range', num(c0.params.coordSys.cellWidth) === 40
    && c0.params.coordSys.rangeInfo.dayCount === hex(28) && c0.params.coordSys.rangeInfo.start.formatedDate === '2017-02-01');
  guard('calendar: api.layout answers a rect and a content rect', apiOf(c0, 'layout')[0].ret.contentRect
    && num(apiOf(c0, 'layout')[0].ret.rect.width) === 40);
  guard('calendar: a date past the range is NaN and draws nothing', apiOf(call('calendar', 0, 3), 'coord')[0].ret[0] === '7ff8000000000000'
    && !cs('calendar').states[0].els.some(e => e.key === 's0:3'));
  guard('calendar: the encode is time and value', c0.params.encode.time.join() === '0' && c0.params.encode.value.join() === '1');
  // single
  const s0 = call('single', 0, 0);
  guard('single: the coordSys is singleAxis', s0.params.coordSys.type === 'singleAxis' && s0.params.encode.single.join() === '0');
  guard('single: api.size of a bare value is a number', typeof apiOf(s0, 'size')[0].ret === 'string');
  // none
  const n0 = call('none', 0, 0);
  guard('none: no coordSys', n0.params.coordSys === null && elOf('none', 0, 's0:0').info === JSON.stringify({ cs: 'none' }));
  guard('none: the dimensions are x and y', n0.params.encode.x.join() === '0' && n0.params.encode.y.join() === '1');
  guard('none: the hover finds the rect', cs('none').states[1].hover.dataIndex === 1);
  // visual
  const vm = cs('visualmap').states[0].calls;
  guard('visual: a continuous colour is an rgba text', /^rgba\(/.test(apiOf(vm[1], 'visual')[0].ret));
  guard('visual: the symbolSize the visualMap maps', num(apiOf(vm[0], 'visual')[1].ret) === 8 && num(apiOf(vm[3], 'visual')[1].ret) === 24);
  guard("visual: the opacity reaches api.style but not api.visual", apiOf(vm[0], 'visual')[3].ret === null
    && num(apiOf(vm[0], 'style')[0].ret.opacity) === 0.5);
  const vp = vm.filter(q => q.s === 1);
  guard("visual: a piece's colour as written", apiOf(vp[0], 'visual')[0].ret === '#ee6666');
  guard("visual: a piece's symbol, the others the default circle", apiOf(vp[1], 'visual')[2].ret === 'diamond' && apiOf(vp[0], 'visual')[2].ret === 'circle');
  // enter
  guard("enter: the root's enterFrom starts below", num(smp('enter', 0, 0, 's0:0').y) > num(elOf('enter', 0, 's0:0').t.y));
  guard('enter: the style starts transparent', num(smp('enter', 0, 0, 's0:0')['style.opacity']) === 0);
  guard('enter: an enterAnimation delay holds it', smp('enter', 0, 50, 's0:0').y === smp('enter', 0, 0, 's0:0').y);
  guard('enter: linear at 500', smp('enter', 0, 500, 's0:0').y !== smp('enter', 0, 100, 's0:0').y);
  guard('enter: the shape enterFrom grows the circle', num(smp('enter', 0, 0, 's0:1')['shape.r']) === 0
    && num(smp('enter', 0, 1500, 's0:1')['shape.r']) === 12);
  guard('enter: the series delay holds the circle at 1', num(smp('enter', 0, 1, 's0:1')['shape.r']) === 0);
  guard('enter: the group scales in', num(smp('enter', 0, 0, 's0:2').scaleX) === 0 && num(smp('enter', 0, 1500, 's0:2').scaleX) === 1);
  // update
  const u = (t, key, p) => smp('update', 1, t, key)[p];
  guard('update: the default transition moves x', num(u(350, 's0:0', 'x')) !== num(u(0, 's0:0', 'x'))
    && num(u(350, 's0:0', 'x')) !== num(u(1500, 's0:0', 'x')));
  guard('update: the default transition jumps the shape', u(0, 's0:0', 'shape.height') === u(1500, 's0:0', 'shape.height'));
  guard("update: 'all' moves the shape", u(350, 's0:1', 'shape.width') !== u(0, 's0:1', 'shape.width')
    && u(350, 's0:1', 'shape.width') !== u(1500, 's0:1', 'shape.width'));
  guard("update: 'all' moves the fill", u(350, 's0:1', 'style.fill') !== u(1500, 's0:1', 'style.fill'));
  guard("update: ['x'] jumps y", u(0, 's0:2', 'y') === u(1500, 's0:2', 'y') && u(350, 's0:2', 'x') !== u(1500, 's0:2', 'x'));
  guard("update: the shape's ['r'] moves r", u(350, 's0:2', 'shape.r') !== u(1500, 's0:2', 'shape.r'));
  guard("update: the style's ['fill'] moves the fill, not the lineWidth", u(350, 's0:2', 'style.fill') !== u(1500, 's0:2', 'style.fill')
    && u(0, 's0:2', 'style.lineWidth') === u(1500, 's0:2', 'style.lineWidth'));
  guard('update: an updateAnimation of 300 ms ends at 300, linear', u(300, 's0:3', 'shape.y') === u(1500, 's0:3', 'shape.y')
    && u(200, 's0:3', 'shape.y') !== u(1500, 's0:3', 'shape.y'));
  guard('update: the series duration 700 ends at 700', u(700, 's0:0', 'x') === u(1500, 's0:0', 'x') && u(600, 's0:0', 'x') !== u(1500, 's0:0', 'x'));
  guard('update: a new item is there at once', u(0, 's0:5', 'x') === u(1500, 's0:5', 'x'));
  guard('update: removed items go at once', Object.keys(cs('update').states[2].samples[0].els).length === 2);
  // leave
  guard('leave: the render throws on the leaveTo', /updateAnimation/.test(cs('leave').states[1].throws || ''));
  guard('leave: the items before it were updated', cs('leave').states[1].calls.length === 2);
  guard('leave: the roots stay in the group', cs('leave').states[1].roots === 3);
  guard('leave-static: it throws with the animation off too', /updateAnimation/.test(cs('leave-static').states[1].throws || ''));
  // focus
  const fo = cs('focus').states;
  const stOf = (s, key) => s.st.find(e => e.key === key);
  guard("focus 'self': the hovered item rises, its series and its grid blur", stOf(fo[1], 's0:0').states.join() === 'emphasis'
    && stOf(fo[1], 's0:1').states.join() === 'blur' && stOf(fo[1], 's1:0').states.join() === 'blur');
  guard("focus 'self': the other grid stays", stOf(fo[1], 's2:0').states.length === 0);
  guard("focus 'series': its own series stays", stOf(fo[2], 's1:0').states.length === 0 && stOf(fo[2], 's1:1').states.join() === 'emphasis'
    && stOf(fo[2], 's0:0').states.join() === 'blur' && stOf(fo[2], 's2:0').states.join() === 'blur');
  guard('no focus: nothing blurs', fo[3].st.every(e => e.key === 's2:0' ? e.states.join() === 'emphasis' : e.states.length === 0));
  guard('emphasisDisabled: no hover', fo[4].st.every(e => e.states.length === 0));
  // tooltip
  const tt = cs('tooltip').states;
  guard('tooltip: an ordinary item shows it', tt[1].tooltip.shown);
  guard('tooltip: a disabled root hides it', !tt[2].tooltip.shown);
  guard('tooltip: a disabled child hides it', !tt[3].tooltip.shown);
  guard('tooltip: its sibling shows it', tt[4].tooltip.shown);
  guard("tooltip: a disabled group hides its child's", !tt[5].tooltip.shown);
  return g;
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED, clock: { T0 },
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: chart._ssr false, env.node off, 600 x 400, the grid 60 / 40 / 40 / 40; animation false unless the case says.',
      'a static case paints (renderToSVGString) after setOption and after every step; its timers settle 500 ms before and after every step.',
      'an animation case samples the clock at samplesMs after each setOption; a {wait} step only lets the clock run.',
      'renderItem: \'@name\' is the recorder of RENDER[name]: the params, every api call and its answer, the tree returned.',
      'ids an author did not write are upstream\'s with \\0 written ~; a Date in the params is {}.',
      'TZ=UTC: the calendar\'s times are UTC midnights.',
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
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : ''));
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);

