/*
Upstream's own answers for roadmap batch D14 GE2 [Batch 148]: the geo
component's regions as things a pointer and an action reach -- the hit test
(zrender's Path.contain on a region's compound path: the stroked box, the
nonzero winding over every sub-path, the stroke within half its width; the
label a region's too; the clip path; silent), the three states and how
they are applied (util/states.ts: toggleHoverEmphasis on the region group,
enableComponentHighDownFeatures, handleGlobalMouseOverForHighDown with a
'self' focus blurring the component, allLeaveBlur, the default state
proxy's colour lift and z2 lifts, the blur's tenth; MapDraw.ts
applyOptionStyleForRegion / resetLabelForRegion / resetEventTriggerForRegion
/ resetTooltipForRegion / resetStateTriggerForRegion; labelStyle.ts
setLabelStyle with GeoModel.getFormattedLabel), the selection
(GeoModel.optionUpdated's selectedMap, select / unSelect / toggleSelected /
isSelected; GeoView._handleRegionClick and updateSelectStatus; the
geoToggleSelect / geoSelect / geoUnSelect actions of geo/install.ts and
their events), the highlight / downplay actions on a geo
(findComponentHighDownDispatchers), the region tooltip
(graphic.setTooltipConfig, TooltipView._showComponentItemTooltip,
buildTooltipModel, formatTpl) and the chart's mouse events with
componentType 'geo'.

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off and getDom stubbed on the chart prototype (the
recipe of tooltip-finish.js), so TooltipView runs with its richText content.
The clock is sunburst-treemap-interact.js': Date replaced before the dist
loads, setTimeout a queue that never runs. Every option says
`animation: false` (a state change is applied at once, no transition) and a
tooltip says `hideDelay: 0` and `position: [5, 5]` (so it hides at once and
never lies under a pointer the script moves). Pointer steps go through
zrender's own Handler with a synthetic event; after every step the chart
runs the echarts half of a frame (chart._onframe(): applyChangedStates) and
storage.getDisplayList(true), as a paint does.

  node tools/advchart-oracle/geo-interact.js

writes tests/fixtures/advchart-geo-interact.json (ORACLE_OUT overrides).
Ends with process.exit().

Conventions
  hex   a double as the 16 hex digits of its IEEE-754 bits (big-endian).
  A colour is the string zrender holds (null for none / undefined).

Top level
  source, W, H, tokens {area, border, label, highlight, labelHighlight,
  liftedArea, liftedBorder, liftedHighlight} (the default token values and
  their lifts -- where the fixture holds one of these the port holds its
  skin's ink), maps [{name, text}], notes[], cases[], guards[].

Per case
  id, note, option (as fed; '@name' a formatter this script registers),
  steps[] (as resolved: {move: [x, y]} mousemove, {click: [x, y]} mousedown
  + mouseup + click, {leave: true} Handler.mouseout (out, then globalout),
  {action: payload} dispatchAction, {setOption: option, notMerge}
  chart.setOption), probes[] {px: [x, y], hit} (the hit
  test at the start: null, or {geo, name, label (the topmost element is the
  region's text)}), states[]: index-parallel to [after setOption, after
  step 1, ...], each:
    events[]  in firing order: a mouse event {type, componentType,
              componentIndex, geoIndex, name, region (JSON text of
              params.region)}; an action event {type, json (JSON text of the
              event object)}
    tip       null, or {text} (the shown richText content)
    geos[]    one per geo, component order: null when the view draws
              nothing, else groups[] in MapDraw's order, each {name, hover,
              hbo (__highByOuter), selected, paths[]}; a path {states
              (currentStates joined), fill, stroke, lw (hex | null), op
              (hex | null), dash (JSON | null), z2, label null | {states,
              ignore, text, fill, op, z2, fontSize, fontWeight, x, y (hex:
              the text's position: innerTransformable's x and y), rot (its
              rotation), tx, ty (getLocalTransform's translation: where the
              text's own origin lands) -- the four null while it is ignored}}
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-geo-interact.json');

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
const hx = v => (v == null ? null : hex(+v));
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
  zr(chart).handler[name](zev(extra));
  refresh(chart);
}
function eventDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && el[k].eventData) return el[k].eventData;
  }
  return null;
}

// ---------- the formatter the options name ----------
const FMT = {
  geoTip: p => p.componentType + '|' + p.geoIndex + '|' + p.name + '|' + (p.seriesIndex === undefined ? 'u' : 'd'),
  geoLabel: p => '<' + p.name + ':' + p.status + '>',
};
// a function in an option as the port writes it: '@name'
function fnAsName(k, v) {
  if (typeof v !== 'function') return v;
  for (const n of Object.keys(FMT)) if (FMT[n] === v) return '@' + n;
  throw new OracleError('an unnamed function');
}
function withHandlers(v) {
  if (typeof v === 'string' && v.startsWith('@') && FMT[v.slice(1)]) return FMT[v.slice(1)];
  if (Array.isArray(v)) return v.map(withHandlers);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[k] = withHandlers(v[k]);
    return o;
  }
  return v;
}

// ---------- the maps ----------
function sq(x0, y0, x1, y1) { return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]; }
function rev(r) { return r.slice().reverse(); }
function feat(name, geometry, extra) {
  return { type: 'Feature', properties: Object.assign({ name }, extra || {}), geometry };
}
function ge2(styleB) {
  return {
    type: 'FeatureCollection',
    features: [
      feat('A', { type: 'Polygon', coordinates: [sq(0, 0, 10, 10)] }),
      feat('B', { type: 'Polygon', coordinates: [sq(10, 0, 20, 10)] }, styleB ? { echartsStyle: styleB } : null),
      feat('C', { type: 'Polygon', coordinates: [sq(0, 10, 10, 20)] }),
      // a hole, wound the other way
      feat('D', { type: 'Polygon', coordinates: [sq(10, 10, 20, 20), rev(sq(13, 13, 17, 17))] }),
      feat('E', { type: 'LineString', coordinates: [[23, 0], [23, 20]] }),
      feat('F', { type: 'MultiPolygon', coordinates: [[sq(0, 22, 4, 26)], [sq(6, 22, 10, 26)]] }),
      feat('G', { type: 'Polygon', coordinates: [sq(12, 22, 15, 25)] }),
      feat('G', { type: 'Polygon', coordinates: [sq(16, 22, 19, 25)] }),
    ],
  };
}
const MAPS = [
  { name: 'ge2', text: JSON.stringify(ge2(null)) },
  { name: 'ge2s', text: JSON.stringify(ge2({
    emphasis: { itemStyle: { areaColor: '#aa00aa' } },
    select: { label: { color: '#00ffff' } },
    silent: false,
  })) },
  // [D9-D14 survivors] a ring left open (no closing point: the closePath's
  // edge is a real one) and a sloped line (containStroke's distance branch)
  { name: 'ge2x', text: JSON.stringify({
    type: 'FeatureCollection',
    features: [
      feat('O', { type: 'Polygon', coordinates: [[[0, 0], [10, 0], [10, 10], [0, 10]]] }),
      feat('S', { type: 'LineString', coordinates: [[14, 0], [24, 10]] }),
    ],
  }) },
];
function registerMaps() {
  for (const m of MAPS) echarts.registerMap(m.name, m.text);
}

// ---------- reading the picture ----------
function colourStr(c) {
  if (c == null) return null;
  if (typeof c === 'object') return 'gradient';
  return String(c);
}
function geoModels(chart) {
  const out = [];
  chart.getModel().eachComponent('geo', g => out.push(g));
  return out;
}
function snapGeo(chart, gm) {
  const view = chart.getViewOfComponentModel(gm);
  const md = view && view._mapDraw;
  if (!md) return null;
  const groups = [];
  for (const g of md._regionsGroup.children()) {
    const ev = eventDataOf(g);
    must(ev, 'a region group without eventData');
    const rec = { name: ev.name, hover: g.hoverState || 0, hbo: g.__highByOuter || 0, selected: !!g.selected, paths: [] };
    for (const p of g.children()) {
      const r = { states: (p.currentStates || []).join(','), fill: colourStr(p.style.fill), stroke: colourStr(p.style.stroke) };
      r.lw = hx(p.style.lineWidth);
      r.op = hx(p.style.opacity);
      r.dash = p.style.lineDash == null ? null : JSON.stringify(p.style.lineDash);
      r.z2 = p.z2;
      const t = p.getTextContent();
      if (t) {
        r.label = {
          states: (t.currentStates || []).join(','),
          ignore: !!t.ignore,
          text: t.style.text == null ? null : String(t.style.text),
          fill: colourStr(t.style.fill),
          op: hx(t.style.opacity),
          z2: t.z2,
          fontSize: t.style.fontSize == null ? null : t.style.fontSize,
          fontWeight: t.style.fontWeight == null ? null : String(t.style.fontWeight),
          // updateInnerText's place (innerTransformable: the position plus
          // the offset); an ignored text is never updated, its place none
          x: t.ignore ? null : hex(t.innerTransformable.x),
          y: t.ignore ? null : hex(t.innerTransformable.y),
          rot: t.ignore ? null : hex(t.innerTransformable.rotation || 0),
          // where the text's own (0, 0) lands: getLocalTransform's translation
          tx: t.ignore ? null : hex(t.innerTransformable.getLocalTransform([])[4]),
          ty: t.ignore ? null : hex(t.innerTransformable.getLocalTransform([])[5]),
        };
      }
      else r.label = null;
      rec.paths.push(r);
    }
    groups.push(rec);
  }
  return groups;
}
function hitAt(chart, x, y) {
  refresh(chart);
  const t = zr(chart).handler.findHover(x, y).target;
  for (let el = t; el; el = el.__hostTarget || el.parent) {
    const ev = eventDataOf(el);
    // a text is drawn (and hit) as its TSpan children
    if (ev) return { geo: ev.geoIndex, name: ev.name, label: t.type === 'tspan' || t.type === 'text' };
  }
  return null;
}
function tooltipView(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  return m ? chart.getViewOfComponentModel(m) : null;
}
function tipNow(chart) {
  const view = tooltipView(chart);
  if (!view) return null;
  const c = view._tooltipContent;
  if (!c || !c.el || !c._show) return null;
  return { text: String(c.el.style.text) };
}

// ---------- points ----------
function centrePoint(chart, gi, name, k, where) {
  const gm = geoModels(chart)[gi];
  const geo = gm.coordinateSystem;
  const regs = geo.regions.filter(r => r.name === name);
  must(regs.length > (k || 0), where + ': no region ' + name);
  const c = regs[k || 0].getCenter();
  const p = geo.dataToPoint(c);
  return [Math.round(p[0]), Math.round(p[1])];
}
function geoPoint(chart, gi, lonlat) {
  const p = geoModels(chart)[gi].coordinateSystem.dataToPoint(lonlat);
  return [Math.round(p[0]), Math.round(p[1])];
}
function resolvePoint(chart, t, where) {
  if (Array.isArray(t)) return t.slice();
  if (t.region !== undefined) return centrePoint(chart, t.geo || 0, t.region, t.k, where);
  if (t.at) {
    const p = geoPoint(chart, t.geo || 0, t.at);
    return [p[0] + (t.dx || 0), p[1] + (t.dy || 0)];
  }
  throw new OracleError(where + ': an unknown target ' + JSON.stringify(t));
}

// ---------- a case ----------
const MOUSE = ['click', 'mouseover', 'mouseout', 'mousemove', 'mousedown', 'mouseup'];
const ACTION_EVENTS = ['geoselectchanged', 'geoselected', 'geounselected', 'highlight', 'downplay'];

function runCase(c) {
  registerMaps();
  const chart = mk();
  const events = [];
  for (const t of MOUSE) {
    chart.on(t, p => {
      if (p.componentType !== 'geo') {
        events.push({ type: t, componentType: p.componentType == null ? null : p.componentType });
        return;
      }
      events.push({ type: t, componentType: p.componentType, componentIndex: p.componentIndex,
        geoIndex: p.geoIndex, name: p.name, region: JSON.stringify(p.region, fnAsName) });
    });
  }
  for (const t of ACTION_EVENTS) chart.on(t, e => events.push({ type: t, json: JSON.stringify(e) }));
  const states = [];
  const steps = [];
  const snap = () => {
    chart._onframe();
    refresh(chart);
    const st = { events: events.splice(0), tip: tipNow(chart), geos: [] };
    for (const gm of geoModels(chart)) st.geos.push(snapGeo(chart, gm));
    return st;
  };
  let probes = [];
  try {
    chart.setOption(withHandlers(clone(c.option)));
    refresh(chart);
    probes = (c.probes || []).map((t, i) => {
      const p = resolvePoint(chart, t, c.id + ' probe ' + i);
      return { px: p, hit: hitAt(chart, p[0], p[1]) };
    });
    states.push(snap());
    c.steps.forEach((step, i) => {
      const where = c.id + ' step ' + i;
      let out;
      if (step.move !== undefined) {
        const p = resolvePoint(chart, step.move, where);
        fire(chart, 'mousemove', { zrX: p[0], zrY: p[1] });
        out = { move: p };
      }
      else if (step.click !== undefined) {
        const p = resolvePoint(chart, step.click, where);
        fire(chart, 'mousemove', { zrX: p[0], zrY: p[1] });
        fire(chart, 'mousedown', { zrX: p[0], zrY: p[1] });
        fire(chart, 'mouseup', { zrX: p[0], zrY: p[1] });
        fire(chart, 'click', { zrX: p[0], zrY: p[1] });
        out = { click: p };
      }
      else if (step.leave) {
        fire(chart, 'mouseout', { zrX: -1, zrY: -1 });
        out = { leave: true };
      }
      else if (step.action) {
        chart.dispatchAction(clone(step.action));
        out = { action: step.action };
      }
      else if (step.setOption) {
        chart.setOption(withHandlers(clone(step.setOption)), !!step.notMerge);
        out = { setOption: step.setOption, notMerge: !!step.notMerge };
      }
      else throw new OracleError(where + ': an unknown step ' + JSON.stringify(step));
      steps.push(out);
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
    id: 'hover-default',
    note: 'the defaults: hover a region (emphasis: the highlight fill, the lifted border, z2 10, the label shown in the primary colour), then its own label (the same region: out, over), another region, the hole of D (nothing), the line E (its stroke, 5 px wide when unfilled), a multipolygon, a name drawn twice, and leave',
    option: opt({ map: 'ge2' }, { tooltip: Object.assign({}, TIP) }),
    probes: [{ region: 'A' }, { region: 'D' }, { at: [15, 15] }, { at: [11, 11] }, { at: [23, 10] }, { at: [23, 10], dx: 2 },
      { at: [23, 10], dx: 3 }, { at: [23, 10], dx: -2 }, { at: [5, 24] }, { at: [2, 24] }, { at: [30, 30] }, { region: 'G', k: 1 },
      { at: [10, 5] }, { at: [10, 5], dx: 1 }],
    steps: [
      { move: { region: 'A' } }, { move: { region: 'A' } }, { move: { region: 'B' } }, { move: { at: [15, 15] } },
      { move: { at: [23, 10], dx: 1 } }, { move: { at: [8, 24] } }, { move: { region: 'G', k: 1 } }, { leave: true },
    ],
  },
  {
    id: 'focus-self',
    note: "emphasis.focus 'self': hovering a region blurs the whole component (paths and labels, a tenth of their opacity) and the region comes back as emphasis; leaving lifts the blur",
    option: opt({ map: 'ge2', emphasis: { focus: 'self' }, label: { show: true } }),
    steps: [{ move: { region: 'C' } }, { move: { region: 'F' } }, { move: [580, 380] }, { move: { region: 'B' } }, { leave: true }],
  },
  {
    id: 'select-single',
    note: "selectedMode 'single': a click toggles the region and takes the selection off the others; geoselectchanged fires before the click event; a click on the label counts",
    option: opt({ map: 'ge2', selectedMode: 'single' }),
    steps: [{ click: { region: 'A' } }, { click: { region: 'B' } }, { click: { region: 'B' } }, { click: { region: 'G' } },
      { click: { at: [15, 15] } }, { leave: true }],
  },
  {
    id: 'select-multiple',
    note: "selectedMode 'multiple' with regions[].selected: C starts selected; clicks add and take away",
    option: opt({ map: 'ge2', selectedMode: 'multiple', regions: [{ name: 'C', selected: true }, { name: 'E', selected: true }] }),
    steps: [{ click: { region: 'A' } }, { click: { region: 'C' } }, { click: { region: 'D' } }, { move: [590, 390] }],
  },
  {
    id: 'select-off',
    note: 'no selectedMode: a region selected by regions[].selected is shown selected, a click on it unselects it (unSelect does not look at the mode) and a click elsewhere selects nothing -- each still fires geoselectchanged',
    option: opt({ map: 'ge2', regions: [{ name: 'C', selected: true }] }),
    steps: [{ click: { region: 'A' } }, { click: { region: 'C' } }, { click: { region: 'C' } }],
  },
  {
    id: 'select-map',
    note: 'a written selectedMap wins over regions[].selected',
    option: opt({ map: 'ge2', selectedMode: 'multiple', selectedMap: { A: true, Z: true }, regions: [{ name: 'C', selected: true }] }),
    steps: [{ click: { region: 'B' } }],
  },
  {
    id: 'merge',
    note: "option.selectedMap is the model's: a merge that leaves it alone keeps the selection, one that writes it merges it in (zrUtil.merge), a notMerge setOption starts again from regions[].selected; a render makes new elements (no hover)",
    option: opt({ map: 'ge2', selectedMode: 'multiple', regions: [{ name: 'C', selected: true }] }),
    steps: [
      { click: { region: 'A' } },
      { setOption: { geo: { label: { show: true } } } },
      { setOption: { geo: { selectedMap: { B: true, C: false } } } },
      { setOption: opt({ map: 'ge2', selectedMode: 'multiple', regions: [{ name: 'D', selected: true }] }), notMerge: true },
    ],
  },
  {
    id: 'actions',
    note: 'two geos: the select actions by query (none: every geo; geoIndex), their events (selected is shared across the geos the action reached, allSelected per geo), a name left out',
    option: opt([
      { map: 'ge2', selectedMode: 'single', left: 10, width: 280 },
      { map: 'ge2', selectedMode: 'multiple', right: 10, width: 280 },
    ]),
    steps: [
      { action: { type: 'geoSelect', name: 'A' } },
      { action: { type: 'geoSelect', geoIndex: 1, name: 'B' } },
      { action: { type: 'geoToggleSelect', geoIndex: 0, name: 'B' } },
      { action: { type: 'geoUnSelect', name: 'A' } },
      { action: { type: 'geoToggleSelect', name: 'G' } },
      { action: { type: 'geoSelect', geoIndex: 1 } },
      { action: { type: 'geoUnSelect', geoIndex: [0, 1], name: 'G' } },
    ],
  },
  {
    id: 'highlight',
    note: "highlight / downplay on a geo (geoIndex and name): focus 'self' blurs the component; a region held by the action keeps its emphasis through a hover's out; a hover elsewhere blurs it again (blurComponent spares nothing); a name that is no region, no name",
    option: opt({ map: 'ge2', emphasis: { focus: 'self' } }),
    steps: [
      { action: { type: 'highlight', geoIndex: 0, name: 'B' } },
      { move: { region: 'B' } }, { move: [590, 390] },
      { move: { region: 'A' } }, { leave: true },
      { action: { type: 'downplay', geoIndex: 0, name: 'B' } },
      { action: { type: 'highlight', geoIndex: 0, name: 'Z' } },
      { action: { type: 'highlight', geoIndex: 0 } },
      { action: { type: 'highlight', geoIndex: 0, name: 'D', notBlur: true } },
      { action: { type: 'downplay', geoIndex: 0, name: 'D' } },
    ],
  },
  {
    id: 'styles',
    note: 'state styles from the geo and the regions: areaColor in emphasis, a border width, label colour / size / formatter / rotation in emphasis (the select and blur texts take the emphasis formatter too), select colour, select label hidden, blur opacity and label colour; B emphasis.disabled (no hover emphasis, still its events), C silent, D emphasis colour and areaColor null (the lift)',
    option: opt({
      map: 'ge2', selectedMode: 'multiple',
      itemStyle: { areaColor: '#ddeeff', borderColor: '#336699' },
      label: { show: true, formatter: '[{a}]', offset: [4, -6], color: '#202020' },
      emphasis: { focus: 'self', itemStyle: { areaColor: '#ff8800', borderWidth: 2 }, label: { color: '#112233', fontSize: 16, formatter: 'E:{a}', rotate: 30 } },
      select: { itemStyle: { color: '#00aa00', borderType: 'dashed' }, label: { show: false } },
      blur: { itemStyle: { opacity: 0.3 }, label: { color: '#999999' } },
      regions: [
        { name: 'B', emphasis: { disabled: true } },
        { name: 'C', silent: true },
        { name: 'D', itemStyle: { areaColor: '#123456' }, emphasis: { itemStyle: { color: null, areaColor: null } } },
        { name: 'F', label: { formatter: '@geoLabel' }, emphasis: { label: { formatter: '@geoLabel' } } },
      ],
    }, { tooltip: Object.assign({}, TIP) }),
    probes: [{ region: 'C' }, { region: 'B' }],
    steps: [
      { move: { region: 'A' } }, { move: { region: 'B' } }, { move: { region: 'C' } }, { move: { region: 'D' } },
      { click: { region: 'A' } }, { move: { region: 'F' } }, { click: { region: 'F' } }, { leave: true },
      { action: { type: 'highlight', geoIndex: 0, name: 'B' } },
    ],
  },
  {
    id: 'tooltip',
    note: "the region tooltip: the geo's formatter template ({a} the name), a region's string, a region's show: false, a region's function formatter (params: componentType, geoIndex, name, no seriesIndex), a global trigger 'axis' does not stop it",
    option: opt({
      map: 'ge2',
      tooltip: { formatter: '{a} @geo {b}' },
      regions: [
        { name: 'B', tooltip: 'B tip {a}' },
        { name: 'C', tooltip: { show: false } },
        { name: 'D', tooltip: { formatter: '@geoTip' } },
      ],
    }, { tooltip: Object.assign({ trigger: 'axis' }, TIP) }),
    steps: [{ move: { region: 'A' } }, { move: { region: 'B' } }, { move: { region: 'C' } }, { move: { at: [11, 11] } },
      { move: [590, 390] }],
  },
  {
    id: 'lift',
    note: "nothing declares an emphasis fill (the geo's written null, no root): the proxy lifts the rest fill; a region whose fill is 'none' gets its stroke lifted instead; a written 'inherit' keeps the rest fill",
    option: opt({
      map: 'ge2', itemStyle: { areaColor: '#88aacc' }, emphasis: { itemStyle: { color: null } },
      regions: [{ name: 'B', itemStyle: { areaColor: 'none' } }, { name: 'C', emphasis: { itemStyle: { areaColor: 'inherit' } } }],
    }),
    steps: [{ move: { region: 'A' } }, { move: { at: [15, 0] } }, { move: { region: 'C' } }, { leave: true }],
  },
  {
    id: 'tooltip-none',
    note: 'no tooltip component: no tooltip over a region',
    option: opt({ map: 'ge2', tooltip: { show: true } }),
    steps: [{ move: { region: 'A' } }],
  },
  {
    id: 'clip-zoom',
    note: 'clip with a zoom: what the view rect cuts away is not hit; silent on the whole geo in a second one',
    option: opt([
      { map: 'ge2', clip: true, zoom: 3, center: [5, 5], left: 20, top: 20, width: 200, height: 200 },
      { map: 'ge2', silent: true, left: 320, top: 20, width: 200, height: 200 },
    ]),
    probes: [{ region: 'A' }, { region: 'B' }, { at: [9, 9] }, { region: 'A', geo: 1 }, { region: 'D', geo: 1 }],
    steps: [{ move: { region: 'A' } }, { move: { region: 'B' } }, { move: { region: 'A', geo: 1 } }],
  },
  {
    id: 'root-styles',
    note: "the root option's emphasis / itemStyle / label are the region model's grandparent: a geo emphasis colour written null climbs to the root's, the root's border colour for emphasis, the root's item opacity",
    option: opt({ map: 'ge2', emphasis: { itemStyle: { color: null } } }, {
      emphasis: { itemStyle: { borderColor: '#ff0000', color: '#00ff00' }, label: { color: '#0000ff' } },
      itemStyle: { opacity: 0.8 },
      select: { itemStyle: { borderWidth: 3 } },
    }),
    steps: [{ move: { region: 'A' } }, { action: { type: 'geoSelect', name: 'A' } }, { leave: true }],
  },
  {
    id: 'echarts-style',
    note: "a region's echartsStyle reaches its states: emphasis areaColor, select label colour",
    option: opt({ map: 'ge2s', selectedMode: true }),
    steps: [{ move: { region: 'B' } }, { click: { region: 'B' } }, { leave: true }],
  },
  // [D9-D14 survivors]
  {
    id: 'open-ring',
    note: 'borderWidth 8: a ring with no closing point is hit 3 px off the edge its closePath draws; a sloped line is hit within half its width (4) of the line, not at 5.2 to 6 px',
    option: opt({ map: 'ge2x', itemStyle: { borderWidth: 8 } }),
    probes: [{ at: [0, 5], dx: -3 }, { at: [10, 5], dx: 3 }, { at: [19, 5], dx: 4 }, { at: [19, 5], dx: 7 }, { at: [19, 5], dx: -7 }],
    steps: [{ move: { at: [0, 5], dx: -3 } }, { leave: true }],
  },
  {
    id: 'gradient',
    note: "a region's gradient areaColor: drawn while no state sets the fill; the emphasis' highlight fill replaces it and the rest brings it back",
    option: opt({ map: 'ge2', regions: [{ name: 'A', itemStyle: { areaColor: { type: 'linear', x: 0, y: 0, x2: 1, y2: 0,
      colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } } }] }),
    steps: [{ move: { region: 'A' } }, { leave: true }],
  },
];

// ---------- guards ----------
function guards(out) {
  const g = [];
  const C = id => out.find(c => c.id === id);
  const add = (id, ok, detail) => g.push({ id, ok: !!ok, detail });
  const grp = (st, gi, name) => st.geos[gi].find(x => x.name === name);
  const tok = TOKENS;
  let c = C('hover-default');
  add('hole-misses', c.probes[2].hit === null, 'the hole of D is not D');
  add('ring-hits', c.probes[3].hit && c.probes[3].hit.name === 'D', 'inside D, off the hole');
  add('line-stroke', c.probes[4].hit && c.probes[4].hit.name === 'E' && c.probes[5].hit && !c.probes[6].hit,
    'the line hits within 2.5 px (max(0.5, 5) / 2) and not at 3');
  let s = c.states[1];
  let a = grp(s, 0, 'A');
  add('emphasis-fill', a.paths[0].fill === tok.highlight && a.paths[0].stroke === tok.liftedBorder && a.paths[0].z2 === 10,
    'emphasis: the highlight token, the lifted border, z2 10');
  add('emphasis-label', a.paths[0].label.ignore === false && a.paths[0].label.fill === tok.labelHighlight && a.paths[0].label.z2 === 12,
    'the emphasis label shows, primary, z2 2 + 10');
  add('label-hit', s.events.map(e => e.type).join(',') === 'mousemove,mouseover', 'the first move: move then over');
  s = c.states[2];
  add('label-is-region', s.events.map(e => e.type).join(',') === 'mouseout,mousemove,mouseover' && s.events[2].name === 'A',
    'the second move lands on the label: out and over within the region');
  s = c.states[3];
  add('tip-name', s.tip && s.tip.text === 'B', 'the tooltip is the region name');
  s = c.states[4];
  add('hole-out', s.events.length === 1 && s.events[0].type === 'mouseout' && s.tip === null, 'the hole: out, no tooltip');
  c = C('focus-self');
  s = c.states[1];
  const bl = grp(s, 0, 'A');
  add('blur', bl.paths[0].states === 'blur' && bl.paths[0].op === hex(0.1) && bl.paths[0].label.op === hex(0.1), 'blur is a tenth');
  add('blur-hovered', grp(s, 0, 'C').paths[0].states === 'emphasis', 'the hovered region is emphasis');
  add('blur-lifted', c.states[3].geos[0].every(x => x.paths.every(p => p.states === '')), 'out of the regions: no blur');
  c = C('select-single');
  s = c.states[1];
  add('click-order', s.events.findIndex(e => e.type === 'geoselectchanged') < s.events.findIndex(e => e.type === 'click'),
    'geoselectchanged before the click event');
  a = grp(s, 0, 'A');
  add('select-z2', a.paths[0].states === 'select,emphasis' && a.paths[0].z2 === 10, 'select then emphasis: both lifts from z2 0, the later wins');
  add('z2-creep', grp(c.states[3], 0, 'B').paths[0].z2 === 20, 'a list that keeps emphasis lifts again from the current z2');
  s = c.states[2];
  add('single', !grp(s, 0, 'A').selected && grp(s, 0, 'B').selected, 'single: the other goes');
  add('toggle-off', !grp(c.states[3], 0, 'B').selected, 'a second click unselects');
  c = C('select-off');
  add('preset', grp(c.states[0], 0, 'C').paths[0].states === 'select', 'regions[].selected shows');
  add('off-unselects', !grp(c.states[2], 0, 'C').selected, 'with no selectedMode a click unselects');
  add('off-no-select', !grp(c.states[1], 0, 'A').selected, 'with no selectedMode a click selects nothing');
  c = C('select-map');
  add('selected-map', grp(c.states[0], 0, 'A').selected && !grp(c.states[0], 0, 'C').selected, 'selectedMap wins');
  c = C('merge');
  add('merge-keeps', grp(c.states[2], 0, 'A').selected && grp(c.states[2], 0, 'C').selected, 'a merge keeps the selection');
  add('merge-map', grp(c.states[3], 0, 'B').selected && !grp(c.states[3], 0, 'C').selected && grp(c.states[3], 0, 'A').selected,
    'a written selectedMap merges in');
  add('not-merge', !grp(c.states[4], 0, 'A').selected && grp(c.states[4], 0, 'D').selected, 'notMerge: regions[].selected again');
  add('rerender-hover', grp(c.states[2], 0, 'A').hover === 0, 'a render: new elements, no hover');
  c = C('actions');
  add('two-geos', c.states[1].events.length === 1 && grp(c.states[1], 0, 'A').selected && grp(c.states[1], 1, 'A').selected,
    'one event, both geos');
  c = C('highlight');
  s = c.states[1];
  add('hl-held', grp(s, 0, 'B').hbo === 1 && grp(s, 0, 'B').paths[0].states === 'emphasis' && grp(s, 0, 'A').paths[0].states === 'blur',
    'highlight: held, the rest blurred');
  add('hl-blurred', grp(c.states[2], 0, 'B').paths[0].states === 'blur' && grp(c.states[2], 0, 'B').hbo === 1,
    "hovering the held region under 'self': blurComponent blurs it and the hover may not lift it");
  add('hl-out', grp(c.states[3], 0, 'B').paths[0].states === '' && grp(c.states[3], 0, 'B').hbo === 1,
    'its out: allLeaveBlur puts it to normal, still held');
  c = C('styles');
  add('silent-region', c.probes[0].hit === null, 'a silent region is not hit');
  add('disabled', grp(c.states[2], 0, 'B').paths[0].states === '' && c.states[2].events.some(e => e.type === 'mouseover' && e.name === 'B'),
    'emphasis.disabled: no state, the events still');
  const d = grp(c.states[4], 0, 'D').paths[0];
  add('null-climbs', d.states === 'emphasis' && d.fill === '#ff8800', "D: a region's null climbs to the geo's areaColor");
  add('fn-label', grp(c.states[6], 0, 'F').paths[0].label.text === '<F:emphasis>' && grp(c.states[8], 0, 'F').paths[0].label.text === '<F:select>',
    'a function formatter is called with the state');
  c = C('tooltip');
  add('tip-tpl', c.states[1].tip && c.states[1].tip.text === 'A @geo {b}', 'the geo template');
  add('tip-region', c.states[2].tip && c.states[2].tip.text === 'B tip B', "the region's string");
  add('tip-hidden', c.states[3].tip && c.states[3].tip.text === 'B tip B', 'show false: the box up stays as it was');
  add('tip-fn', c.states[4].tip && c.states[4].tip.text === 'geo|0|D|u', 'the function');
  c = C('lift');
  add('lift-fill', grp(c.states[1], 0, 'A').paths[0].fill === echarts.color.lift('#88aacc', -0.1), 'the rest fill lifted');
  add('lift-stroke', grp(c.states[2], 0, 'B').paths[0].fill === 'none' && grp(c.states[2], 0, 'B').paths[0].stroke === TOKENS.liftedBorder,
    "fill 'none': the stroke lifted");
  add('inherit', grp(c.states[3], 0, 'C').paths[0].fill === '#88aacc', "'inherit': the rest fill");
  c = C('tooltip-none');
  add('no-component', c.states[1].tip === null, 'no component, no tooltip');
  c = C('clip-zoom');
  add('clip', c.probes[0].hit && c.probes[1].hit === null, 'the clip cuts the hit');
  add('silent-geo', c.probes[3].hit === null, 'a silent geo is not hit');
  c = C('root-styles');
  a = grp(c.states[1], 0, 'A').paths[0];
  add('root-climb', a.fill === '#00ff00' && a.stroke === '#ff0000' && a.op === hex(0.8), 'the root reached');
  c = C('echarts-style');
  add('echarts-style', grp(c.states[1], 0, 'B').paths[0].fill === '#aa00aa', 'echartsStyle in emphasis');
  // [D9-D14 survivors]
  c = C('open-ring');
  add('open-ring-close', c.probes[0].hit && c.probes[0].hit.name === 'O' && c.probes[1].hit && c.probes[1].hit.name === 'O',
    'the closing edge of an open ring is stroked like the others');
  add('slope-half-width', c.probes[2].hit && c.probes[2].hit.name === 'S' && c.probes[3].hit === null && c.probes[4].hit === null,
    'a sloped line: within half the width (perpendicular 3.2) a hit, 5.6 not');
  add('open-ring-hover', grp(c.states[1], 0, 'O').paths[0].states === 'emphasis', 'the closing edge takes the hover');
  c = C('gradient');
  add('gradient-states', grp(c.states[0], 0, 'A').paths[0].fill === 'gradient' && grp(c.states[1], 0, 'A').paths[0].fill === tok.highlight
    && grp(c.states[2], 0, 'A').paths[0].fill === 'gradient', 'the gradient at rest, the highlight in emphasis, the gradient again');
  return g;
}

// ---------- the tokens ----------
const TOKENS = (() => {
  registerMaps();
  const chart = mk();
  chart.setOption({ animation: false, geo: { map: 'ge2' } });
  const o = chart.getModel().getComponent('geo', 0).option;
  const lift = c => echarts.color.lift(c, -0.1);
  const t = {
    area: o.itemStyle.color, border: o.itemStyle.borderColor, label: o.label.color,
    highlight: o.emphasis.itemStyle.color, labelHighlight: o.emphasis.label.color,
  };
  t.liftedArea = lift(t.area);
  t.liftedBorder = lift(t.border);
  t.liftedHighlight = lift(t.highlight);
  must(o.select.itemStyle.color === t.highlight && o.select.label.color === t.labelHighlight, 'select takes the emphasis tokens');
  chart.dispose();
  return t;
})();

function generate() {
  const out = CASES.map(runCase);
  const g = guards(out);
  const doc = {
    source: 'tools/advchart-oracle/geo-interact.js against ' + path.basename(DIST) + ' (ECharts 6.1)',
    W, H,
    tokens: TOKENS,
    maps: MAPS,
    notes: [
      'Every case is a new chart, the maps registered afresh; animation false; a tooltip hides at once and sits at [5, 5].',
      'A click is mousemove, mousedown, mouseup, click at one point; leave is Handler.mouseout.',
      'Points named by a region are its centre through dataToPoint, rounded.',
      'After every step: chart._onframe() (applyChangedStates) and a display-list refresh.',
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
  const textA = JSON.stringify(a.doc, null, 1);
  const b = generate();
  const textB = JSON.stringify(b.doc, null, 1);
  must(textA === textB, 'two generations differ');
  must(!textA.includes('\\u0000'), 'a \\u0000 in the output');
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
