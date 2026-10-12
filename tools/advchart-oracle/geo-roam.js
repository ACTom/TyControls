/*
Upstream's own answers for roadmap batch D14 GE3 [Batch 150]: roam on the
geo component -- component/helper/RoamController.ts (the press that arms,
the move that pans by the delta from the last point, the wheel's 1.1 / 1.2 /
1.4, roam true / 'move' / 'pan' / 'scale' / 'zoom', roamTrigger 'global',
the pointer checker: onIrrelevantElement, containPoint, the clip rect; the
listeners ordered by zlevel, then z, the first added winning a tie),
component/helper/roamHelper.ts updateRoamControllerSimply (the default roam
false, the payload {type: 'geoRoam', dx, dy | zoom, originX, originY,
animation, componentType: 'geo', geoId}), coord/View.ts
ownRoamModelCoordSysUpdateInAction / viewCoordSysSyncBack /
applyRoamPayloadToOverallTrans / syncBackToRoamOptionFromRoamTrans /
invertBackToCenterOption (the centre and the zoom written back into the
geo's option), component/geo/install.ts' geoRoam action (componentType or a
geo key names the geo; its event 'georoam'), GeoView / MapDraw
__updateOnOwnRoam (the transform group moves, nothing is rebuilt) and
zrender's PathProxy.rebuildPath (a later frame replays the stored path --
Float32 past 11 numbers -- folding segments under a pixel of the current
scale).

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), the recipe of
geo-interact.js (chart._ssr = false, env.node off, getDom stubbed, the
controlled clock), every option `animation: false`, a tooltip `hideDelay:
0` and `position: [5, 5]`. Pointer steps go through zrender's own Handler;
after every step the chart runs chart._onframe() and a display-list
refresh.

  node tools/advchart-oracle/geo-roam.js

writes tests/fixtures/advchart-geo-roam.json (ORACLE_OUT overrides).
Ends with process.exit().

Conventions
  hex   a double as the 16 hex digits of its IEEE-754 bits (big-endian).

Top level
  source, W, H, maps [{name, text}], notes[], cases[], guards[].

Per case
  id, note, option, steps[]: {move: [x, y]} a mousemove; {drag: [[x, y],
  ...]} mousemove to the first point, mousedown there, a mousemove to each
  further point, mouseup and click at the last; {press: [x, y], button}
  mousedown with a button (1 left, 3 right); {release: [x, y], button}
  mouseup; {wheel: [x, y, delta]} a mousewheel, delta the LCL WheelDelta
  (zrender's wheelDelta is delta / 120); {leave: true} Handler.mouseout;
  {action: payload} dispatchAction; {setOption: option, notMerge};
  {resize: [W, H]} chart.resize.
  probes[] [x, y]: findHover at each, after every state.
  states[] index-parallel to [after setOption, after step 1, ...], each:
    events[]  in firing order: a mouse event {type, componentType, name};
              an action event {type, json (JSON.stringify of the event)}
    tip       null or {text}
    hits[]    per probe: null or {geo, name}
    geos[]    per geo, component order: null when the view draws nothing,
              else {roam [x, y, scaleX, scaleY] hex (the view's roam
              transformable), group [x, y, scaleX, scaleY] hex (the
              transform group's), overall [6 hex], overallInv [6 hex],
              center (the model option's: null, or two halves {kind: num v
              | pct v str | kw str | str v str | null}), zoom (the model
              option's, hex, null when not a number), groups[] {name,
              hover, selected, paths[] {states, z2, drawn {mode 'first' |
              'replay', f32 (the replayed data is a Float32Array), scale
              [2 hex], cmds [['M'|'L', xhex, yhex] | ['Z']]}, label null |
              {ignore, text, fontSize, tx, ty (hex, null while ignored)}}}}
*/
'use strict';
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
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-geo-roam.json');

Math.random = function () { return 0; };

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const clone = v => JSON.parse(JSON.stringify(v));

const W = 600;
const H = 400;

// ---------- the chart ----------
(function enableTooltips() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk() {
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
const zr = chart => chart.getZr();
function refresh(chart) { zr(chart).storage.getDisplayList(true); }
function zev(extra) { return Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1 }, extra); }
function fire(chart, name, extra) {
  refresh(chart);
  zr(chart).handler.dispatch(name, zev(extra));
  refresh(chart);
}
function eventDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && el[k].eventData) return el[k].eventData;
  }
  return null;
}

// ---------- the map ----------
function sq(x0, y0, x1, y1) { return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]; }
function rev(r) { return r.slice().reverse(); }
function feat(name, geometry) {
  return { type: 'Feature', properties: { name }, geometry };
}
// a ring of many short sides: folded under a pixel at rest, drawn out when
// zoomed in
function circle(cx, cy, r, n) {
  const pts = [];
  for (let i = 0; i < n; i++) {
    const a = 2 * Math.PI * i / n;
    // six decimals, so the text holds the number exactly as written
    pts.push([+(cx + r * Math.cos(a)).toFixed(6), +(cy + r * Math.sin(a)).toFixed(6)]);
  }
  pts.push(pts[0].slice());
  return pts;
}
function ge3() {
  return {
    type: 'FeatureCollection',
    features: [
      feat('A', { type: 'Polygon', coordinates: [sq(0, 0, 10, 10)] }),
      feat('B', { type: 'Polygon', coordinates: [sq(10, 0, 20, 10)] }),
      feat('C', { type: 'Polygon', coordinates: [sq(0, 10, 10, 20)] }),
      feat('D', { type: 'Polygon', coordinates: [sq(10, 10, 20, 20), rev(sq(13, 13, 17, 17))] }),
      feat('E', { type: 'LineString', coordinates: [[23, 0], [23, 20]] }),
      feat('R', { type: 'Polygon', coordinates: [circle(30, 10, 4, 360)] }),
    ],
  };
}
const MAPS = [{ name: 'ge3', text: JSON.stringify(ge3()) }];
function registerMaps() {
  for (const m of MAPS) echarts.registerMap(m.name, m.text);
}

// ---------- reading the picture ----------
function geoModels(chart) {
  const out = [];
  chart.getModel().eachComponent('geo', g => out.push(g));
  return out;
}
function isPct(v) { return typeof v === 'string' && /%$/.test(v.trim()); }
function classifyCentre(c) {
  if (c == null) return null;
  must(Array.isArray(c), 'a centre that is not an array: ' + JSON.stringify(c));
  return [0, 1].map(i => {
    const v = c[i];
    if (v == null) return { kind: 'null' };
    if (typeof v === 'number') return { kind: 'num', v: hex(v) };
    if (typeof v === 'string') {
      if (isPct(v)) return { kind: 'pct', v: hex(parseFloat(v)), str: v };
      if (['center', 'middle', 'left', 'top', 'right', 'bottom'].includes(v)) return { kind: 'kw', str: v };
      return { kind: 'str', v: hex(parseFloat(v)), str: v };
    }
    throw new OracleError('a centre dim of type ' + typeof v);
  });
}
function recorder() {
  const cmds = [];
  return {
    cmds,
    moveTo(x, y) { cmds.push(['M', hex(x), hex(y)]); },
    lineTo(x, y) { cmds.push(['L', hex(x), hex(y)]); },
    closePath() { cmds.push(['Z']); },
    bezierCurveTo() { throw new OracleError('a curve in a map path'); },
    quadraticCurveTo() { throw new OracleError('a curve in a map path'); },
    arc() { throw new OracleError('an arc in a map path'); },
    rect() { throw new OracleError('a rect in a map path'); },
  };
}
// what the canvas is handed for a path: on its first frame the direct
// build (double, folded at that frame's scale -- geo.js' recipe); on any
// later one the stored data replayed (rebuildPath at the current scale)
function drawnOf(el, seen) {
  if (!el.path) el.getBoundingRect();
  const PathProxy = el.path.constructor;
  const gs = el.getGlobalScale();
  const rec = recorder();
  const pp = new PathProxy();
  pp.setDPR(1);
  let mode;
  if (seen) {
    pp.reset();
    el.buildPath(pp, el.shape, false);
    pp.toStatic();
    pp.setScale(gs[0], gs[1], el.segmentIgnoreThreshold);
    pp.rebuildPath(rec, 1);
    mode = 'replay';
  }
  else {
    pp.setScale(gs[0], gs[1], el.segmentIgnoreThreshold);
    pp.setContext(rec);
    pp.reset();
    el.buildPath(pp, el.shape, false);
    mode = 'first';
  }
  return { mode, f32: pp.data instanceof Float32Array, scale: [hex(gs[0]), hex(gs[1])], cmds: rec.cmds };
}
function snapGeo(chart, gm, seenSet, nowSet) {
  const view = chart.getViewOfComponentModel(gm);
  const md = view && view._mapDraw;
  if (!md) return null;
  const v = gm.coordinateSystem.view;
  const rt = v.trans[1];
  const tg = md._transformGroup;
  const o = { roam: [rt.x, rt.y, rt.scaleX, rt.scaleY].map(hex), group: [tg.x, tg.y, tg.scaleX, tg.scaleY].map(hex),
    overall: Array.from(v.mtOverall).map(hex), overallInv: Array.from(v.mtOverallInv).map(hex),
    center: classifyCentre(gm.option.center),
    zoom: typeof gm.option.zoom === 'number' ? hex(gm.option.zoom) : null, groups: [] };
  for (const g of md._regionsGroup.children()) {
    const ev = eventDataOf(g);
    must(ev, 'a region group without eventData');
    const rec = { name: ev.name, hover: g.hoverState || 0, selected: !!g.selected, paths: [] };
    for (const p of g.children()) {
      nowSet.add(p);
      const r = { states: (p.currentStates || []).join(','), z2: p.z2, drawn: drawnOf(p, seenSet.has(p)) };
      const t = p.getTextContent();
      if (t) {
        r.label = {
          ignore: !!t.ignore,
          text: t.style.text == null ? null : String(t.style.text),
          fontSize: t.style.fontSize == null ? null : t.style.fontSize,
          tx: t.ignore ? null : hex(t.innerTransformable.getLocalTransform([])[4]),
          ty: t.ignore ? null : hex(t.innerTransformable.getLocalTransform([])[5]),
        };
      }
      else r.label = null;
      rec.paths.push(r);
    }
    o.groups.push(rec);
  }
  return o;
}
function hitAt(chart, x, y) {
  refresh(chart);
  const t = zr(chart).handler.findHover(x, y).target;
  for (let el = t; el; el = el.__hostTarget || el.parent) {
    const ev = eventDataOf(el);
    if (ev) return { geo: ev.geoIndex, name: ev.name };
  }
  return null;
}
function tipNow(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  const view = m ? chart.getViewOfComponentModel(m) : null;
  if (!view) return null;
  const c = view._tooltipContent;
  if (!c || !c.el || !c._show) return null;
  return { text: String(c.el.style.text) };
}

// ---------- points ----------
// a point named by a region (its centre through dataToPoint) or a
// coordinate pair of a geo, plus an offset, rounded; an array is itself
function resolvePoint(chart, t, where) {
  if (Array.isArray(t)) return t.slice();
  const gm = geoModels(chart)[t.geo || 0];
  must(gm, where + ': no geo ' + (t.geo || 0));
  const geo = gm.coordinateSystem;
  let p;
  if (t.region !== undefined) {
    const regs = geo.regions.filter(r => r.name === t.region);
    must(regs.length > 0, where + ': no region ' + t.region);
    p = geo.dataToPoint(regs[0].getCenter());
  }
  else if (t.at) p = geo.dataToPoint(t.at);
  else throw new OracleError(where + ': an unknown target ' + JSON.stringify(t));
  return [Math.round(p[0]) + (t.dx || 0), Math.round(p[1]) + (t.dy || 0)];
}
function resolveStep(chart, step, where) {
  const r = Object.assign({}, step);
  if (step.move) r.move = resolvePoint(chart, step.move, where);
  if (step.drag) r.drag = step.drag.map(t => resolvePoint(chart, t, where));
  if (step.press) r.press = resolvePoint(chart, step.press, where);
  if (step.release) r.release = resolvePoint(chart, step.release, where);
  if (step.wheel) {
    const q = resolvePoint(chart, Array.isArray(step.wheel) ? step.wheel.slice(0, 2) : step.wheel.at, where);
    r.wheel = [q[0], q[1], Array.isArray(step.wheel) ? step.wheel[2] : step.wheel.delta];
  }
  return r;
}

// ---------- a case ----------
const MOUSE = ['click', 'mouseover', 'mouseout', 'mousemove', 'mousedown', 'mouseup'];
const ACTION_EVENTS = ['georoam', 'geoselectchanged'];

function runCase(c) {
  registerMaps();
  const chart = mk();
  const events = [];
  for (const t of MOUSE) {
    chart.on(t, p => {
      events.push({ type: t, componentType: p.componentType == null ? null : p.componentType,
        name: p.name == null ? null : String(p.name) });
    });
  }
  for (const t of ACTION_EVENTS) chart.on(t, e => events.push({ type: t, json: JSON.stringify(e) }));
  const states = [];
  const steps = [];
  let seen = new Set();
  let probes = [];
  const snap = () => {
    chart._onframe();
    refresh(chart);
    const now = new Set();
    const st = { events: events.splice(0), tip: tipNow(chart), hits: [], geos: [] };
    for (const gm of geoModels(chart)) st.geos.push(snapGeo(chart, gm, seen, now));
    st.hits = probes.map(p => hitAt(chart, p[0], p[1]));
    seen = now;
    return st;
  };
  try {
    chart.setOption(clone(c.option));
    refresh(chart);
    probes = (c.probes || []).map((t, i) => resolvePoint(chart, t, c.id + ' probe ' + i));
    states.push(snap());
    c.steps.forEach((step0, i) => {
      const where = c.id + ' step ' + i;
      const step = resolveStep(chart, step0, where);
      if (step.move) fire(chart, 'mousemove', { zrX: step.move[0], zrY: step.move[1] });
      else if (step.drag) {
        const pts = step.drag;
        fire(chart, 'mousemove', { zrX: pts[0][0], zrY: pts[0][1] });
        fire(chart, 'mousedown', { zrX: pts[0][0], zrY: pts[0][1] });
        for (let k = 1; k < pts.length; k++) fire(chart, 'mousemove', { zrX: pts[k][0], zrY: pts[k][1] });
        const last = pts[pts.length - 1];
        fire(chart, 'mouseup', { zrX: last[0], zrY: last[1] });
        fire(chart, 'click', { zrX: last[0], zrY: last[1] });
      }
      else if (step.press) fire(chart, 'mousedown', { zrX: step.press[0], zrY: step.press[1], which: step.button });
      else if (step.release) fire(chart, 'mouseup', { zrX: step.release[0], zrY: step.release[1], which: step.button });
      else if (step.wheel) fire(chart, 'mousewheel', { zrX: step.wheel[0], zrY: step.wheel[1], zrDelta: step.wheel[2] / 120 });
      else if (step.leave) fire(chart, 'mouseout', { zrX: -1, zrY: -1 });
      else if (step.action) chart.dispatchAction(clone(step.action));
      else if (step.setOption) chart.setOption(clone(step.setOption), !!step.notMerge);
      else if (step.resize) chart.resize({ width: step.resize[0], height: step.resize[1] });
      else throw new OracleError(where + ': an unknown step ' + JSON.stringify(step));
      steps.push(step);
      states.push(snap());
    });
  } finally {
    chart.dispose();
  }
  return { id: c.id, note: c.note, option: c.option, steps, probes, states };
}

// ---------- the cases ----------
const TIP = { hideDelay: 0, position: [5, 5] };
function opt(geo, extra) {
  return Object.assign({ animation: false, geo: geo }, extra || {});
}
const CASES = [
  {
    id: 'drag',
    note: 'roam true: a left drag pans by the delta from the last point (one georoam per move, also off the canvas); the hovered region stays hovered and the tooltip up; the release then a click 40 px from the press is no click; a hover afterwards finds the regions where they went',
    option: opt({ map: 'ge3', roam: true }, { tooltip: Object.assign({}, TIP) }),
    probes: [[150, 150], [300, 200], [450, 250]],
    steps: [
      { move: [200, 200] },
      { drag: [[200, 200], [210, 205], [230, 190], [240, 190], [-20, 150], [160, 220]] },
      { move: [161, 221] },
      { move: [400, 120] },
    ],
  },
  {
    id: 'wheel',
    note: 'the wheel: delta 120 is 1.1, 240 1.2, 480 1.4, the other way the inverse; about the pointer; a wheel off the map (outside containPoint) is not taken',
    option: opt({ map: 'ge3', roam: true }),
    probes: [[200, 200], [350, 150]],
    steps: [
      { wheel: [200, 200, 120] }, { wheel: [220, 210, 240] }, { wheel: [300, 180, 480] },
      { wheel: [300, 180, -120] }, { wheel: [250, 200, -360] }, { wheel: [5, 5, 120] }, { wheel: [250, 200, 600] },
    ],
  },
  {
    id: 'scale-limit',
    note: 'scaleLimit {min 0.8, max 2}: the wheel stops at the limits (the zoom written back is the clamped one); zoom 3 in the option is clamped to 2 at the start',
    option: opt({ map: 'ge3', roam: true, zoom: 3, scaleLimit: { min: 0.8, max: 2 } }),
    probes: [[300, 200]],
    steps: [
      { wheel: [300, 200, 480] }, { wheel: [280, 190, -480] }, { wheel: [280, 190, -480] }, { wheel: [280, 190, -480] },
      { wheel: [280, 190, -120] }, { wheel: [320, 210, 240] },
    ],
  },
  {
    id: 'scale-only',
    note: "roam 'scale': a drag does nothing (no event), the wheel zooms; 'zoom' is the same word",
    option: opt([{ map: 'ge3', roam: 'scale', left: 10, width: 280 }, { map: 'ge3', roam: 'zoom', right: 10, width: 280 }]),
    steps: [
      { drag: [[150, 200], [170, 210], [190, 230]] }, { wheel: [150, 200, 240] },
      { drag: [[450, 200], [430, 190]] }, { wheel: [450, 200, -240] },
    ],
  },
  {
    id: 'move-only',
    note: "roam 'move': the wheel does nothing, a drag pans; 'pan' is the same word; a right press does not arm",
    option: opt([{ map: 'ge3', roam: 'move', left: 10, width: 280 }, { map: 'ge3', roam: 'pan', right: 10, width: 280 }]),
    steps: [
      { wheel: [150, 200, 240] }, { drag: [[150, 200], [170, 210], [175, 230]] },
      { drag: [[450, 200], [420, 190]] },
      { press: [450, 200], button: 3 }, { move: [470, 220] }, { release: [470, 220], button: 3 },
    ],
  },
  {
    id: 'roam-off',
    note: 'no roam on the geo nor at the root: no gesture; a written null at the geo climbs to the root, also nothing there',
    option: opt([{ map: 'ge3', left: 10, width: 280 }, { map: 'ge3', roam: null, right: 10, width: 280 }]),
    steps: [{ drag: [[150, 200], [170, 210]] }, { wheel: [150, 200, 120] }, { drag: [[450, 200], [470, 210]] }, { wheel: [450, 200, 120] }],
  },
  {
    id: 'roam-root',
    note: "the geo's roam left out climbs to the root option (GeoModel has no roam default): root roam true makes it roam; one geo saying false does not",
    option: opt([{ map: 'ge3', left: 10, width: 280 }, { map: 'ge3', roam: false, right: 10, width: 280 }], { roam: true }),
    steps: [{ drag: [[150, 200], [170, 210]] }, { wheel: [150, 200, 120] }, { drag: [[450, 200], [470, 210]] }, { wheel: [450, 200, 120] }],
  },
  {
    id: 'actions',
    note: "geoRoam by hand, roam off (an action is not gated by roam): by geoIndex a pan and a zoom about a point; componentType 'geo' with no query moves every geo; no geo key and no componentType is the map series' (nothing here, the event still fires); geoName; a pan with dy missing is no pan; geoIndex as an array",
    option: opt([{ map: 'ge3', name: 'g0', left: 10, width: 280 }, { map: 'ge3', name: 'g1', right: 10, width: 280 }]),
    steps: [
      { action: { type: 'geoRoam', geoIndex: 0, dx: 30, dy: -10 } },
      { action: { type: 'geoRoam', geoIndex: 1, zoom: 2, originX: 450, originY: 200 } },
      { action: { type: 'geoRoam', componentType: 'geo', zoom: 0.5, originX: 100, originY: 100 } },
      { action: { type: 'geoRoam', dx: 5, dy: 5 } },
      { action: { type: 'geoRoam', geoName: 'g1', dx: -12.5, dy: 7.25 } },
      { action: { type: 'geoRoam', geoIndex: 0, dx: 5 } },
      { action: { type: 'geoRoam', geoIndex: [0, 1], dx: 1, dy: 2, zoom: 1.5, originX: 300, originY: 200 } },
    ],
  },
  {
    id: 'two-geos',
    note: 'two geos side by side, both roaming: only the one under the pointer pans or zooms',
    option: opt([{ map: 'ge3', roam: true, left: 10, width: 280 }, { map: 'ge3', roam: true, right: 10, width: 280 }]),
    probes: [[150, 200], [450, 200]],
    steps: [{ drag: [[450, 200], [460, 210], [470, 215]] }, { wheel: [150, 200, 240] }, { wheel: [450, 200, -120] }],
  },
  {
    id: 'overlap',
    note: 'two geos over each other: the higher z takes the gesture; on a tie the first geo (its controller was added first); a geo above with no roam makes the one under it irrelevant where its element is the top target (onIrrelevantElement) but not where the pointer is on nothing of it',
    option: opt([
      { map: 'ge3', roam: true, z: 1 },
      { map: 'ge3', roam: true, left: 100, z: 0 },
    ]),
    steps: [
      { drag: [[300, 200], [310, 205]] }, { wheel: [300, 200, 120] },
      { setOption: opt([{ map: 'ge3', roam: true, z: 0 }, { map: 'ge3', roam: true, left: 100, z: 0 }]), notMerge: true },
      { drag: [[300, 200], [290, 195]] }, { wheel: [300, 200, -120] },
      { setOption: opt([{ map: 'ge3', roam: true, z: 0 }, { map: 'ge3', roam: false, left: 140, top: 20, z: 5 }]), notMerge: true },
      { drag: [{ region: 'A', geo: 1 }, { region: 'A', geo: 1, dx: 5 }] }, { drag: [{ at: [15, 15], geo: 1 }, { at: [15, 15], geo: 1, dx: 10, dy: -10 }] },
      { wheel: { at: { region: 'B', geo: 1 }, delta: 120 } }, { wheel: { at: { at: [15, 15], geo: 1 }, delta: 120 } },
    ],
  },
  {
    id: 'hover-select',
    note: "states through a roam: hover A, a drag (A stays emphasised, the tooltip stays), a select by click, a wheel; a 3 px drag ends in a click (it selects), a 6 px one does not; focus 'self' blur survives",
    option: opt({ map: 'ge3', roam: true, selectedMode: 'multiple', emphasis: { focus: 'self' } }, { tooltip: Object.assign({}, TIP) }),
    probes: [[200, 200], { region: 'B' }],
    steps: [
      { move: { region: 'A' } }, { drag: [{ region: 'A' }, { region: 'A', dx: 3, dy: 2 }, { region: 'A', dx: 8, dy: 1 }] },
      { move: { region: 'A', dx: 1 } },
      { drag: [{ region: 'B' }, { region: 'B', dx: 2, dy: 2 }] }, { wheel: { at: { region: 'B' }, delta: 240 } },
      { drag: [{ region: 'B' }, { region: 'B', dx: 3, dy: 2 }] },
      { drag: [{ region: 'C' }, { region: 'C', dx: 6 }] }, { leave: true },
    ],
  },
  {
    id: 'clip',
    note: "clip with a zoom: a press outside the view rect does not arm the first geo (isInClip), inside it does; the second geo, roamTrigger 'global' and no clip, takes whatever the first does not -- a wheel below the first's clip, a drag in a corner -- and loses a tie on the first's map",
    option: opt([
      { map: 'ge3', roam: true, clip: true, zoom: 2, left: 20, top: 20, width: 260, height: 200 },
      { map: 'ge3', roam: true, roamTrigger: 'global', left: 320, top: 20, width: 260, height: 300 },
    ]),
    probes: [[100, 100], [400, 100]],
    steps: [
      { drag: [[150, 300], [160, 290]] }, { drag: [[150, 120], [160, 125]] }, { wheel: [150, 350, 120] }, { wheel: [150, 120, 120] },
      { drag: [[595, 395], [590, 380]] }, { drag: [{ region: 'B', geo: 1 }, { region: 'B', geo: 1, dx: -4, dy: 3 }] },
    ],
  },
  {
    id: 'layout',
    note: "layoutCenter / layoutSize and boundingCoords with a percentage centre: the write-back keeps a percent half a percent (of the data rect) and a number half a number; preserveAspect cover on the second geo",
    option: opt([
      { map: 'ge3', roam: true, layoutCenter: ['25%', '50%'], layoutSize: 250, center: ['40%', 12], zoom: 1.5 },
      { map: 'ge3', roam: true, boundingCoords: [[-5, 30], [40, -5]], left: 320, top: 30, width: 250, height: 300, preserveAspect: 'cover',
        center: ['50%', '25%'] },
    ]),
    probes: [[150, 200], [450, 200]],
    steps: [
      { drag: [[150, 200], [140, 190], [130, 195]] }, { wheel: [150, 200, 240] },
      { drag: [[450, 200], [455, 230]] }, { wheel: [430, 180, -120] },
    ],
  },
  {
    id: 'merge',
    note: 'after a roam a merge that leaves center and zoom alone keeps them; one writing zoom replaces the zoom and keeps the centre; one writing center replaces it; a resize keeps both; notMerge starts again',
    option: opt({ map: 'ge3', roam: true }),
    probes: [[300, 200]],
    steps: [
      { drag: [[300, 200], [320, 215]] }, { wheel: [320, 215, 240] },
      { setOption: { geo: { label: { show: true } } } },
      { setOption: { geo: { zoom: 3 } } },
      { drag: [[300, 200], [290, 190]] },
      { setOption: { geo: { center: [10, 10] } } },
      { resize: [500, 360] },
      { wheel: [250, 180, -120] },
      { setOption: opt({ map: 'ge3', roam: true }), notMerge: true },
    ],
  },
  {
    id: 'labels',
    note: 'labels shown: they follow the regions and keep their size; a zoom far in draws the ring R out of more segments',
    option: opt({ map: 'ge3', roam: true, label: { show: true, fontSize: 14 } }),
    steps: [{ wheel: [450, 200, 480] }, { wheel: [450, 200, 480] }, { wheel: [450, 200, 480] }, { drag: [[450, 200], [300, 220]] }],
  },
];

// ---------- guards ----------
function guards(out) {
  const g = [];
  const C = id => out.find(c => c.id === id);
  const add = (id, ok, detail) => g.push({ id, ok: !!ok, detail });
  const roamEvs = st => st.events.filter(e => e.type === 'georoam').map(e => JSON.parse(e.json));
  let c = C('drag');
  let evs = roamEvs(c.states[2]);
  add('one-per-move', evs.length === 5 && evs[0].dx === 10 && evs[0].dy === 5 && evs[3].dx === -260,
    'one georoam per move, the delta from the last point, off the canvas too');
  add('payload', evs[0].componentType === 'geo' && typeof evs[0].geoId === 'string' && evs[0].animation && evs[0].animation.duration === 0,
    "the gesture's payload: componentType 'geo', geoId, animation duration 0");
  add('key-order', Object.keys(evs[0]).join(',') === 'type,dx,dy,animation,componentType,geoId', 'the event keys in order');
  add('no-click', !c.states[2].events.some(e => e.type === 'click'), 'a long drag is no click');
  add('hover-moves', c.states[2].events.filter(e => e.type === 'mouseover').length >= 2,
    'the hover is found on the picture before each pan: it changes under a long drag');
  add('roam-before-move', c.states[2].events.map(e => e.type).slice(2, 5).join(',') === 'mouseout,georoam,mousemove',
    "the out, the roam's listener, then echarts' own mousemove (zrEventfulCallAtLast)");
  add('centre-written', c.states[2].geos[0].center && c.states[2].geos[0].center[0].kind === 'num', 'the centre written back as numbers');
  c = C('wheel');
  evs = roamEvs(c.states[1]);
  add('wheel-1.1', evs.length === 1 && evs[0].zoom === 1.1 && evs[0].originX === 200, 'delta 120: 1.1 about the pointer');
  add('wheel-1.2', roamEvs(c.states[2])[0].zoom === 1.2, 'delta 240: 1.2');
  add('wheel-1.4', roamEvs(c.states[3])[0].zoom === 1.4, 'delta 480: 1.4');
  add('wheel-inv', roamEvs(c.states[4])[0].zoom === 1 / 1.1 && roamEvs(c.states[5])[0].zoom === 1 / 1.2, 'the other way: the inverse');
  add('wheel-off', roamEvs(c.states[6]).length === 0, 'a wheel off the map is not taken');
  c = C('scale-limit');
  add('limit-start', c.states[0].geos[0].roam[2] === hex(2), 'zoom 3 starts at the limit 2');
  add('limit-max', c.states[1].geos[0].zoom === hex(2), 'the wheel stops at max (written back clamped)');
  c = C('scale-only');
  add('scale-no-drag', roamEvs(c.states[1]).length === 0 && roamEvs(c.states[2]).length === 1, "'scale': no drag, a wheel");
  add('zoom-word', roamEvs(c.states[3]).length === 0 && roamEvs(c.states[4]).length === 1, "'zoom': no drag, a wheel");
  c = C('move-only');
  add('move-no-wheel', roamEvs(c.states[1]).length === 0 && roamEvs(c.states[2]).length === 2, "'move': no wheel, a drag");
  add('pan-word', roamEvs(c.states[3]).length === 1, "'pan': a drag");
  add('right-no-arm', roamEvs(c.states[5]).length === 0, 'a right press does not arm');
  c = C('roam-off');
  add('off', c.states.every(s => roamEvs(s).length === 0), 'no roam, no gesture');
  c = C('roam-root');
  add('root-climbs', roamEvs(c.states[1]).length === 1 && roamEvs(c.states[2]).length === 1, 'the root roam reached');
  add('false-stays', roamEvs(c.states[3]).length === 0 && roamEvs(c.states[4]).length === 0, 'a written false');
  c = C('actions');
  const z0 = c.states[0].geos[0].roam;
  add('action-pan', c.states[1].geos[0].roam[0] !== z0[0] && c.states[1].geos[1].roam[0] === c.states[0].geos[1].roam[0], 'geoIndex 0 only');
  add('action-all', c.states[3].geos[0].zoom !== c.states[2].geos[0].zoom && c.states[3].geos[1].zoom !== c.states[2].geos[1].zoom,
    "componentType 'geo': every geo");
  add('action-series', JSON.stringify(c.states[4].geos) === JSON.stringify(c.states[3].geos) && roamEvs(c.states[4]).length === 1,
    'no geo key: the map series, nothing moves, the event fires');
  add('action-no-anim', !('animation' in roamEvs(c.states[4])[0]), 'no geo reached: no animation key on the payload');
  const nb = h => Buffer.from(h, 'hex').readDoubleBE(0);
  add('half-pan', roamEvs(c.states[6]).length === 1 && Math.abs(nb(c.states[6].geos[0].roam[0]) - nb(c.states[5].geos[0].roam[0])) < 1e-9,
    'dy missing: no pan (only the round trip of the write-back)');
  c = C('two-geos');
  add('two-drag', roamEvs(c.states[1]).length === 2 && c.states[1].geos[0].roam[0] === c.states[0].geos[0].roam[0],
    'the drag on the right moves the right one only');
  c = C('overlap');
  add('higher-z', JSON.stringify(c.states[1].geos[1].roam) === JSON.stringify(c.states[0].geos[1].roam)
    && c.states[1].geos[0].roam[0] !== c.states[0].geos[0].roam[0], 'the higher z takes it');
  add('tie-first', JSON.stringify(c.states[4].geos[1].roam) === JSON.stringify(c.states[3].geos[1].roam)
    && c.states[4].geos[0].roam[0] !== c.states[3].geos[0].roam[0], 'a tie: the first geo');
  add('irrelevant', roamEvs(c.states[7]).length === 0, 'an element of a higher geo on top: the lower one does not arm');
  add('relevant-empty', roamEvs(c.states[8]).length === 1, 'nothing of the higher geo there: the lower one pans');
  c = C('hover-select');
  const hov = st => st.geos[0].groups.filter(x => x.hover === 2).map(x => x.name).join(',');
  add('hover-through', hov(c.states[2]) === 'A', 'a short drag inside A: A stays hovered');
  add('tip-through', c.states[2].tip && c.states[2].tip.text === 'A', 'the tooltip stays up');
  add('click-3px', c.states[4].events.some(e => e.type === 'geoselectchanged') && roamEvs(c.states[4]).length === 1,
    'a short drag pans and is a click');
  add('no-click-6px', !c.states[7].events.some(e => e.type === 'geoselectchanged') && roamEvs(c.states[7]).length === 1,
    'a 6 px drag is no click');
  add('select-kept', c.states[5].geos[0].groups.some(x => x.name === 'B' && x.selected)
    && c.states[6].events.some(e => e.type === 'geoselectchanged') && !c.states[6].geos[0].groups.some(x => x.selected),
    'the selection through a wheel; the next short drag on B is a click that takes it off');
  c = C('clip');
  const gid = (st, k) => roamEvs(st).map(e => e.geoId).join(',') === '\u0000series\u0000' + k + '\u00000';
  add('clip-out', gid(c.states[1], 1) && gid(c.states[2], 0), "outside the first one's clip the global second one, inside the first");
  add('clip-wheel', gid(c.states[3], 1) && gid(c.states[4], 0), 'the wheel the same');
  add('global-anywhere', gid(c.states[5], 1) && gid(c.states[6], 1), 'global: a corner of the canvas, its own map');
  c = C('layout');
  const ctr = c.states[1].geos[0].center;
  add('pct-kept', ctr && ctr[0].kind === 'pct' && ctr[1].kind === 'num', 'a percent half stays a percent, a number a number');
  c = C('merge');
  add('merge-keeps', c.states[3].geos[0].zoom === c.states[2].geos[0].zoom
    && JSON.stringify(c.states[3].geos[0].center) === JSON.stringify(c.states[2].geos[0].center), 'a merge keeps centre and zoom');
  add('merge-zoom', c.states[4].geos[0].zoom === hex(3) && JSON.stringify(c.states[4].geos[0].center) === JSON.stringify(c.states[2].geos[0].center),
    'a merge writing zoom');
  add('resize-keeps', c.states[7].geos[0].zoom === c.states[6].geos[0].zoom, 'a resize keeps');
  add('notmerge', c.states[9].geos[0].center === null && c.states[9].geos[0].zoom === hex(1), 'notMerge starts again');
  c = C('labels');
  const lab = st => st.geos[0].groups[0].paths[0].label;
  add('label-size', lab(c.states[3]).fontSize === 14, 'the label keeps its size');
  add('label-moves', lab(c.states[3]).tx !== lab(c.states[0]).tx, 'the label follows');
  const rr = st => st.geos[0].groups.find(x => x.name === 'R').paths[0].drawn;
  add('replay', rr(c.states[1]).mode === 'replay' && rr(c.states[1]).f32 && rr(c.states[0]).mode === 'first', 'a roam frame replays a Float32 path');
  add('unfold', rr(c.states[3]).cmds.length > rr(c.states[0]).cmds.length, 'zoomed in, the ring draws more segments');
  return g;
}

// ---------- the self-check: the gestures are their actions ----------
// every case's georoam events dispatched as actions on a fresh chart leave
// the same views
function replayCheck(out) {
  for (const c of out) {
    if (!c.steps.every(s => s.drag || s.wheel || s.move || s.press || s.release || s.action || s.leave)) continue;
    registerMaps();
    const chart = mk();
    try {
      chart.setOption(clone(c.option));
      for (let k = 1; k < c.states.length; k++) {
        for (const e of c.states[k].events) {
          if (e.type !== 'georoam') continue;
          const p = JSON.parse(e.json);
          p.type = 'geoRoam';
          chart.dispatchAction(p);
        }
        refresh(chart);
        const gms = geoModels(chart);
        gms.forEach((gm, i) => {
          const v = gm.coordinateSystem.view;
          const want = c.states[k].geos[i];
          if (!want) return;
          must(JSON.stringify(Array.from(v.mtOverall).map(hex)) === JSON.stringify(want.overall),
            c.id + ' state ' + k + ' geo ' + i + ': the gesture is not its actions');
        });
      }
    } finally {
      chart.dispose();
    }
  }
}

function generate() {
  const out = CASES.map(runCase);
  const g = guards(out);
  replayCheck(out);
  const doc = {
    source: 'tools/advchart-oracle/geo-roam.js against ' + path.basename(DIST) + ' (ECharts 6.1)',
    W, H,
    maps: MAPS,
    notes: [
      'Every case is a new chart, the map registered afresh; animation false; a tooltip hides at once and sits at [5, 5].',
      'A drag is mousemove and mousedown at the first point, a mousemove to each further one, mouseup and click at the last.',
      'A wheel is zrender\'s mousewheel with wheelDelta = delta / 120.',
      'After every step: chart._onframe() and a display-list refresh.',
      'drawn: a path new in this state is its first canvas brush (double); one that was there before is the stored data replayed at the current scale (Float32 past 11 numbers).',
    ],
    cases: out,
    guards: g,
  };
  return { doc, bad: g.filter(x => !x.ok) };
}

try {
  const a = generate();
  if (a.bad.length) {
    for (const b of a.bad) console.error('GUARD FAILED: ' + b.id + ' -- ' + b.detail);
    if (process.env.ORACLE_DEBUG) fs.writeFileSync(process.env.ORACLE_DEBUG, JSON.stringify(a.doc, null, 1));
    process.exit(1);
  }
  const textA = JSON.stringify(a.doc);
  const b = generate();
  const textB = JSON.stringify(b.doc);
  must(textA === textB, 'two generations differ');
  JSON.parse(textA);
  fs.writeFileSync(OUT, textA + '\n');
  let states = 0;
  a.doc.cases.forEach(c => { states += c.states.length; });
  console.log('wrote ' + OUT + ': ' + a.doc.cases.length + ' cases, ' + states + ' states, ' + a.doc.guards.length + ' guards');
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e.stack);
  process.exit(1);
}
