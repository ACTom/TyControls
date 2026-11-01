/*
Upstream's own answers for the fix phase, round 6, batch R6-B: what a geo
view's roam tween does to the map's content.

  MapDraw.draw (component/helper/MapDraw.ts) on a render that is not the
  view's first and has no payload (an animated merge writing center / zoom)
  calls applyViewCoordSysTransToElement(transformGroup,
  VIEW_COORD_SYS_TRANS_ROAM, view, model) (coord/View.ts): an updateProps of
  the transform group to viewCoordSysCopyTrans(ROAM) -- copyTransform of all
  eleven transformable props, but viewCoordSysUpdateRoamTrans only ever
  writes x, y and scaleX = scaleY = zoom on a fresh transformable, so the
  roam has no rotation, no skew and no origin (VIEW_COORD_SYS_ANIMATION_
  PROPS_CONSTRAINT). Whatever turns or skews in a map -- an SVG's own
  transform attributes, under the svg group's RAW transform -- is the
  content's, and rides the group as it is.

  The strokes: applyOptionStyleForRegion sets style.strokeNoScale on every
  GeoJSON region's compound path and on every NAMED SVG element of a styled
  tag (rect, circle, line, ellipse, polygon, polyline, path; a child of a
  named group is named from it). zrender's canvas brush draws a stroke
  lineWidth / el.getLineScale() wide (and its dash and dash offset over the
  same), getLineScale being sqrt|det| of the element's GLOBAL transform
  (1 when m[0] or m[3] is within 1e-10 of 1, or there is none) -- a fixed
  width on the screen. Every other stroke (an unnamed SVG shape, an SVG
  text) is drawn lineWidth wide in the element's own units: it grows and
  shrinks with the group, frame by frame. A TSpan's glyphs and an image
  scale the same way; a region's label is a non-local text content (its
  innerTransformable has no parent): it is moved, never scaled.

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr false,
echarts.env.node off, the clock of animation.js (the global Date replaced
BEFORE the dist loads; setTimeout a queue that never runs), Math.random the
port's xorshift32, zrender's width table measuring text, jsdom's DOMParser
for the SVG maps (JSDOM from D:/Projects/xterm.js/node_modules, or
JSDOM_PATH).

  node tools/advchart-oracle/geo-roam-tween.js

writes tests/fixtures/advchart-geo-roam-tween.json (ORACLE_OUT overrides).
Ends with process.exit().

-----------------------------------------------------------------------------
Numbers are the 16 lowercase hex digits of the IEEE double (big-endian; NaN
7ff8000000000000); strings, booleans and counts are plain JSON.

Top level: source, version, seed, measure {firstCode, ratio[] (hex)}, clock
{T0}, maps [{name, text, svg}] (svg: registered as {svg: text}), notes[],
cases[], guards[].

A case: id, note, W, H, option, events[]. The first setOption is at T0. An
event, in order, at t ms after T0:
  {t, do: 'sample', rec}   zr.animation.update(), the display list
                           refreshed (every global transform updated), then
                           the record
  {t, do: 'merge', option} setOption(option)
  {t, do: 'action', action} dispatchAction(action)
A sample's rec has, per map view ('geo<g>' a geo component's, 'map<s>' a
map series' own):
  '<view>/group' {x, y, scaleX, scaleY, rotation, skewX, skewY, originX,
     originY, n (its animators with a clip)} -- MapDraw's transform group;
  '<view>/els' [...] every displayable under it (preorder; groups and text
     contents skipped) that draws a stroke, a text or an image:
     {key, type, gm [6] (its global transform; the identity when it has
      none), nsc (style.strokeNoScale), ls (getLineScale, 1 without
      strokeNoScale), sw (the stroke as the screen sees it: lineWidth / ls
      * sqrt|det gm|; null with no stroke), dash (normalizeLineDash over
      ls, times sqrt|det gm|; null), doff (the offset the same way; null
      without a dash), bb [minX, minY, maxX, maxY] (a rect's corners, a
      polygon's or a polyline's points, a compound path's sub-polygons'
      points, through gm; null for others), fs (a tspan's font px times
      sqrt|det gm|), img [x, y, width, height] (an image's style box)}.
     key: a GeoJSON region's path 'r:<name>:<i>' (i its place in the
     region's group); an SVG shape 's:<stroke>'; a tspan 't:<fill>'; an
     image 'img'. stale: true on a leftover -- a GeoJSON region's path
     while the map is an SVG, or an SVG element while it is a GeoJSON (a
     map switched by a merge: _buildSVG never clears the regions group,
     _buildGeoJSON never the svg group).

Guards (any failure: nothing is written, exit 1): named discriminating
facts, and the whole fixture generated twice, byte-identical.
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
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

// ---------- a DOMParser for parseXML ----------
const JSDOM_PATH = process.env.JSDOM_PATH || 'D:/Projects/xterm.js/node_modules/jsdom';
const { JSDOM } = require(JSDOM_PATH);
global.DOMParser = new JSDOM('').window.DOMParser;

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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-geo-roam-tween.json');

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
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const hx = v => hex(typeof v === 'number' ? v : NaN);
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};
const nClip = el => (el && el.animators ? el.animators.filter(a => a.getClip()).length : 0);

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

// ---------- the maps ----------
function sq(x0, y0, x1, y1) { return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]; }
// a GeoJSON map: two polygons and a line string
const GJ = JSON.stringify({ type: 'FeatureCollection', features: [
  { type: 'Feature', properties: { name: 'A' }, geometry: { type: 'Polygon', coordinates: [sq(0, 0, 10, 10)] } },
  { type: 'Feature', properties: { name: 'B' }, geometry: { type: 'Polygon', coordinates: [sq(10, 0, 20, 10)] } },
  { type: 'Feature', properties: { name: 'L' }, geometry: { type: 'LineString', coordinates: [[0, 14], [10, 12], [20, 16]] } }] });
// an SVG map whose content turns and skews: a named rect (option-styled:
// strokeNoScale), an unnamed dashed rect, an unnamed polyline, a polygon
// named from its group, a text under the skew (no similarity: drawn
// through the whole map), a text that only turns, an image
const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const SVG_TURN = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="200" height="100" viewBox="0 0 200 100">
  <g transform="rotate(20 100 50) skewX(15)">
    <rect name="A" x="20" y="20" width="40" height="30" fill="#ddeeff" stroke="#777777" stroke-width="1"/>
    <rect x="80" y="20" width="40" height="30" fill="none" stroke="#002200" stroke-width="3" stroke-dasharray="6 3" stroke-dashoffset="2"/>
    <polyline points="10,80 60,70 110,90" fill="none" stroke="#000033" stroke-width="1.5"/>
    <g name="G"><polygon points="140,20 180,30 160,60" fill="#ccffcc" stroke="#888888" stroke-width="1"/></g>
    <text x="130" y="85" font-size="12" fill="#550000" stroke="#005500" stroke-width="0.5">Hi</text>
    <image x="5" y="5" width="16" height="12" xlink:href="${PNG}"/>
  </g>
  <text x="150" y="95" font-size="10" fill="#660000" stroke="#007700" stroke-width="0.4" transform="rotate(-10 150 95)">Up</text>
</svg>`;
// [R6-B gradients] an SVG map with its own userSpaceOnUse gradients (global:
// in the element's own units, under its transform) and a named rect the
// option paints with a global gradient, all under the same turn and skew
const SVG_GRAD = `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
  <defs>
    <linearGradient id="gu" gradientUnits="userSpaceOnUse" x1="20" y1="0" x2="120" y2="10"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient>
    <radialGradient id="gr" gradientUnits="userSpaceOnUse" cx="150" cy="50" r="30"><stop offset="0" stop-color="#ffff00"/><stop offset="1" stop-color="#00ff00"/></radialGradient>
  </defs>
  <g transform="rotate(20 100 50) skewX(15)">
    <rect x="20" y="20" width="100" height="40" fill="url(#gu)" stroke="#003300" stroke-width="1"/>
    <circle cx="150" cy="50" r="25" fill="url(#gr)" stroke="#000044" stroke-width="1"/>
    <rect name="N" x="40" y="65" width="60" height="25" fill="#cccccc" stroke="#777777" stroke-width="1"/>
  </g>
</svg>`;
const MAPS = [{ name: 'r6gj', text: GJ, svg: false }, { name: 'r6svg', text: SVG_TURN, svg: true },
  { name: 'r6svgu', text: SVG_GRAD, svg: true }];
function registerMaps() {
  for (const m of MAPS) {
    if (m.svg) echarts.registerMap(m.name, { svg: m.text });
    else echarts.registerMap(m.name, m.text);
  }
}

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
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
const zr = chart => chart.getZr();
function refresh(chart) { zr(chart).storage.getDisplayList(true); }

// ---------------------------------------------------------------------------
// the probe
// ---------------------------------------------------------------------------
const ID = [1, 0, 0, 1, 0, 0];
const detOf = m => Math.sqrt(Math.abs(m[0] * m[3] - m[2] * m[1]));
// canvas/dashStyle.ts normalizeLineDash
function normalizeLineDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
      : typeof lineType === 'number' ? [lineType] : Array.isArray(lineType) ? lineType : null;
}
function pointsOf(el) {
  const s = el.shape || {};
  switch (el.type) {
    case 'rect': return [[s.x, s.y], [s.x + s.width, s.y], [s.x + s.width, s.y + s.height], [s.x, s.y + s.height]];
    case 'polygon':
    case 'polyline': return s.points || [];
    case 'compound': return [].concat(...(s.paths || []).map(p => (p.shape && p.shape.points) || []));
    default: return null;
  }
}
function bbOf(el, m) {
  const pts = pointsOf(el);
  if (!pts || !pts.length) return null;
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const p of pts) {
    const x = m[0] * p[0] + m[2] * p[1] + m[4];
    const y = m[1] * p[0] + m[3] * p[1] + m[5];
    x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
  }
  return [x0, y0, x1, y1].map(hex);
}
function elRec(el, key) {
  const s = el.style || {};
  const m = el.transform ? Array.from(el.transform) : ID;
  const d = detOf(m);
  const nsc = !!s.strokeNoScale;
  const ls = nsc ? el.getLineScale() : 1;
  const hasStroke = el.hasStroke ? el.hasStroke() : (s.stroke != null && s.stroke !== 'none' && s.lineWidth > 0);
  const r = { key, type: el.type, gm: m.map(hex), nsc, ls: hex(ls), sw: null, dash: null, doff: null, bb: bbOf(el, m) };
  if (hasStroke) r.sw = hex(s.lineWidth / ls * d);
  const dash = s.lineDash && s.lineWidth > 0 && normalizeLineDash(s.lineDash, s.lineWidth);
  if (dash && hasStroke) {
    const k = (ls && ls !== 1) ? ls : 1;
    r.dash = dash.map(v => hex(v / k * d));
    r.doff = hex((s.lineDashOffset || 0) / k * d);
  }
  if (el.type === 'tspan') {
    const px = /([\d.]+)px/.exec(String(s.font));
    must(px, 'a tspan with no px font: ' + s.font);
    r.fs = hex(parseFloat(px[1]) * d);
  }
  if (el.type === 'image') r.img = [s.x || 0, s.y || 0, s.width, s.height].map(hex);
  // [R6-B gradients] a gradient fill as zrender holds it: global ones are in
  // the element's own units (the canvas draws them under gm)
  const f = s.fill;
  if (f && typeof f === 'object' && f.colorStops) {
    r.grad = { type: String(f.type), global: !!f.global, v: [f.x, f.y, f.x2, f.y2, f.r].map(hx) };
  }
  return r;
}
function drawRec(md, rec, prefix, resType) {
  const tg = md._transformGroup;
  rec[prefix + '/group'] = { x: hex(tg.x), y: hex(tg.y), scaleX: hex(tg.scaleX), scaleY: hex(tg.scaleY),
    rotation: hex(tg.rotation), skewX: hex(tg.skewX), skewY: hex(tg.skewY), originX: hex(tg.originX),
    originY: hex(tg.originY), n: nClip(tg) };
  const els = [];
  // a GeoJSON region's paths by its name
  const byEl = new Map();
  if (md._regionsGroupByName) {
    md._regionsGroupByName.each((g, name) => {
      let i = 0;
      g.eachChild(c => { byEl.set(c, 'r:' + name + ':' + (i++)); });
    });
  }
  tg.traverse(el => {
    if (el.isGroup || el.ignore) return;
    let key = byEl.get(el);
    if (!key) {
      const s = el.style || {};
      if (el.type === 'tspan') key = 't:' + String(s.fill);
      else if (el.type === 'image') key = 'img';
      else if (s.stroke != null && s.stroke !== 'none') key = 's:' + String(s.stroke);
      else return;
    }
    const r = elRec(el, key);
    // a leftover: the other resource's graphic, kept from an earlier draw
    if ((key.startsWith('r:')) !== (resType === 'geoJSON')) r.stale = true;
    els.push(r);
  });
  rec[prefix + '/els'] = els;
}
function readRec(chart) {
  const rec = {};
  let g = 0;
  chart.getModel().eachComponent('geo', gm => {
    const view = chart.getViewOfComponentModel(gm);
    const md = view && view._mapDraw;
    if (md) drawRec(md, rec, 'geo' + g, gm.coordinateSystem.resourceType);
    g++;
  });
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'map') return;
    const md = chart.getViewOfSeriesModel(sm)._mapDraw;
    if (md) drawRec(md, rec, 'map' + sm.seriesIndex, sm.coordinateSystem.resourceType);
  });
  return rec;
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
function add(id, note, option, events, more) {
  CASES.push(Object.assign({ id, note, W: 400, H: 300, option, events }, more));
}
const T1 = 3000;
const after = (ts, from) => ts.map(t => ({ t: from + t, do: 'sample' }));
const LIN = { animationDurationUpdate: 1000, animationEasingUpdate: 'linear' };
const S_LIN = [0, 1, 100, 250, 500, 750, 999, 1000, 1001];
const REGIONS = [{ name: 'A', itemStyle: { borderColor: '#110000', borderWidth: 2 } },
  { name: 'G', itemStyle: { borderColor: '#440000', borderWidth: 2.5 } }];

add('svg-geo-zoom', "a geo component on an SVG map whose content turns and skews: a merge writes zoom 2 and a centre -- MapDraw's isFirstDraw is !regionsGroup.childAt(0) || payload, and an SVG map puts nothing in the regions group (its graphic goes in the svg group): every draw of it is a first draw, the transform group is SET to the new roam, no tween",
  Object.assign({ animation: true, geo: { map: 'r6svg', roam: true, regions: REGIONS } }, LIN),
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { geo: { zoom: 2, center: [100, 50] } } }, ...after([0, 1, 500], T1)]);
add('svg-map-out', "a map series drawing its own SVG map (800 ms linear on the series): a merge writes zoom 0.5 -- the same: set at once",
  { animation: true, series: [{ type: 'map', map: 'r6svg', roam: true, animationDurationUpdate: 800, animationEasingUpdate: 'linear',
    data: [{ name: 'A', value: 1, itemStyle: { borderColor: '#110000', borderWidth: 2 } },
      { name: 'G', value: 2, itemStyle: { borderColor: '#440000', borderWidth: 2.5 } }] }] },
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ zoom: 0.5, center: [60, 40] }] } }, ...after([0, 1, 400], T1)]);
add('gj-geo-zoom', "a geo component on a GeoJSON map (two polygons and a line string, a dashed border 2 px wide): a merge writes zoom 3 -- the transform group tweens; every region is strokeNoScale: its stroke and its dash keep their screen size through the tween",
  Object.assign({ animation: true, geo: { map: 'r6gj', roam: true, itemStyle: { borderWidth: 2, borderType: 'dashed', borderColor: '#223344' } } }, LIN),
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { geo: { zoom: 3, center: [10, 8] } } }, ...after(S_LIN, T1)]);
add('gj-to-svg', "a geo component on the GeoJSON map: a merge switches it to the SVG map whose content turns and skews, with zoom 2 and a centre -- the regions group still holds the GeoJSON's regions (_buildSVG never clears it; they stay drawn, frozen: upstream's leftover), so this draw is no first draw and the transform group tweens: the SVG content rides it as it is (no turn or skew in the group, the content's own), the named shapes keep their screen width (strokeNoScale), the unnamed ones' strokes and dashes, the texts and the image grow with the group",
  Object.assign({ animation: true, geo: { map: 'r6gj', roam: true, regions: REGIONS } }, LIN),
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { geo: { map: 'r6svg', zoom: 2, center: [100, 50] } } }, ...after(S_LIN, T1)]);
add('gj-to-svg-midway', "the same switch, and 300 ms in a second merge writes zoom 0.75 and another centre on the SVG map: the regions group still holds the old regions, so the group tweens on from where it is -- the strokes follow it both ways",
  Object.assign({ animation: true, geo: { map: 'r6gj', roam: true, regions: REGIONS } }, LIN),
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { geo: { map: 'r6svg', zoom: 2, center: [100, 50] } } }, ...after([0, 300], T1),
    { t: T1 + 300, do: 'merge', option: { geo: { zoom: 0.75, center: [80, 40] } } },
    ...after([300, 301, 500, 800, 1299, 1300, 1301], T1)]);
add('gj-to-svg-flip', "the switch with zoom -1.5 (no scaleLimit: the zoom stays negative): the group's scaleX and scaleY tween from 1 through 0 to -1.5 -- an unnamed stroke is lineWidth * sqrt|det| on the screen, thin to nothing and wide again, never negative",
  Object.assign({ animation: true, geo: { map: 'r6gj', roam: true, regions: REGIONS } }, LIN),
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { geo: { map: 'r6svg', zoom: -1.5, center: [100, 50] } } }, ...after([0, 1, 200, 600, 999, 1000], T1)]);
add('svg-to-gj', "a geo component on the SVG map: a merge switches it to the GeoJSON map with zoom 2 -- the regions group is empty when the draw asks (it is filled after): a first draw, set at once (the SVG's graphic stays in the svg group: upstream's leftover)",
  Object.assign({ animation: true, geo: { map: 'r6svg', roam: true, regions: REGIONS } }, LIN),
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { geo: { map: 'r6gj', zoom: 2, center: [10, 8] } } }, ...after([0, 1, 500], T1)]);

add('gj-hide-svg', "a geo component on the GeoJSON map: a merge hides it (GeoView.render removes its MapDraw), and a merge shows it again on the SVG map with zoom 2 -- a new MapDraw, its regions group empty: set at once",
  Object.assign({ animation: true, geo: { map: 'r6gj', roam: true, regions: REGIONS } }, LIN),
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { geo: { show: false } } }, ...after([1], T1),
    { t: T1 + 10, do: 'merge', option: { geo: { show: true, map: 'r6svg', zoom: 2, center: [100, 50] } } },
    ...after([10, 11, 500], T1)]);
add('map-legend-gone', "a map series on the GeoJSON map: the legend hides it (MapView.remove clears its MapDraw), a merge switches it to the SVG map while hidden, the legend shows it (a new MapDraw on the SVG: its regions group empty), and a merge writes zoom 2 -- a first draw, set at once",
  { animation: true, legend: { data: ['m'] }, series: [{ type: 'map', name: 'm', map: 'r6gj', roam: true, animationDurationUpdate: 800, animationEasingUpdate: 'linear',
    data: [{ name: 'A', value: 1, itemStyle: { borderColor: '#110000', borderWidth: 2 } },
      { name: 'G', value: 2, itemStyle: { borderColor: '#440000', borderWidth: 2.5 } }] }] },
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'legendUnSelect', name: 'm' } }, ...after([1], T1),
    { t: T1 + 10, do: 'merge', option: { series: [{ map: 'r6svg' }] } }, ...after([11], T1),
    { t: T1 + 20, do: 'action', action: { type: 'legendSelect', name: 'm' } }, ...after([21], T1),
    { t: T1 + 100, do: 'merge', option: { series: [{ zoom: 2, center: [100, 50] }] } }, ...after([100, 101, 500], T1)]);

// [R6-B gradients]
const GLIN = { type: 'linear', x: 0, y: 0, x2: 300, y2: 40, global: true,
  colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] };
const GRAD = { type: 'radial', x: 200, y: 150, r: 80, global: true,
  colorStops: [{ offset: 0, color: '#ffff00' }, { offset: 1, color: '#00ff00' }] };
add('gj-grad', "a GeoJSON geo at zoom 2 whose areaColor is a global linear gradient, region B's a global radial one: the gradient is in the region path's own units (after the raw transform), the canvas draws it under the roam group -- at rest already through zoom 2; a merge writes zoom 3 and the gradient tweens with the group",
  Object.assign({ animation: true, geo: { map: 'r6gj', roam: true, zoom: 2, center: [10, 8], itemStyle: { areaColor: GLIN, borderColor: '#223344', borderWidth: 1 },
    regions: [{ name: 'B', itemStyle: { areaColor: GRAD } }] } }, LIN),
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { geo: { zoom: 3, center: [12, 6] } } }, ...after([0, 1, 250, 500, 999, 1000], T1)]);
add('gj-to-svgu', "a GeoJSON geo switched to the SVG map with its own userSpaceOnUse gradients and a named rect painted with a global gradient by the option, zoom 2: the group tweens and every global gradient rides it (under gm, through the content's own turn and skew)",
  Object.assign({ animation: true, geo: { map: 'r6gj', roam: true,
    regions: [{ name: 'N', itemStyle: { areaColor: GLIN, borderColor: '#550055', borderWidth: 1 } }] } }, LIN),
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { geo: { map: 'r6svgu', zoom: 2, center: [100, 50] } } }, ...after([0, 1, 250, 500, 999, 1000], T1)]);

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function runCase(c) {
  registerMaps();
  const chart = mk(c.W, c.H);
  try {
    const out = { id: c.id, note: c.note, W: c.W, H: c.H, option: clone(c.option), events: [] };
    quiet(() => chart.setOption(clone(c.option)));
    c.events.forEach(ev => {
      NOW = T0 + ev.t;
      const o = clone(ev);
      if (ev.do === 'sample') {
        zr(chart).animation.update();
        refresh(chart);
        o.rec = readRec(chart);
      }
      else if (ev.do === 'merge') quiet(() => chart.setOption(clone(ev.option)));
      else if (ev.do === 'action') quiet(() => chart.dispatchAction(clone(ev.action)));
      else must(false, 'an event it does not know: ' + ev.do);
      out.events.push(o);
    });
    return out;
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
  const rec = (id, t, key) => {
    const smp = cs(id).events.filter(q => q.do === 'sample' && q.t === t).pop();
    must(smp, id + ': no sample at ' + t);
    return smp.rec[key];
  };
  const el = (id, t, view, key) => (rec(id, t, view + '/els') || []).find(e => e.key === key && !e.stale);
  const n = num;
  const samples = [];
  out.cases.forEach(c => c.events.forEach(e => { if (e.do === 'sample') samples.push(e.rec); }));
  guard('the transform group never turns, skews or takes an origin', samples.every(r => Object.keys(r)
    .filter(k => k.endsWith('/group')).every(k => ['rotation', 'skewX', 'skewY', 'originX', 'originY']
      .every(p => n(r[k][p]) === 0))));
  guard('an SVG map is set at once (no tween)', rec('svg-geo-zoom', T1, 'geo0/group').n === 0
    && n(rec('svg-geo-zoom', T1, 'geo0/group').scaleX) === 2 && rec('svg-map-out', T1, 'map0/group').n === 0
    && n(rec('svg-map-out', T1, 'map0/group').scaleX) === 0.5 && rec('svg-to-gj', T1, 'geo0/group').n === 0
    && n(rec('svg-to-gj', T1, 'geo0/group').scaleX) === 2);
  guard('a GeoJSON map tweens, and so does the switch to SVG', rec('gj-geo-zoom', T1 + 500, 'geo0/group').n === 1
    && rec('gj-to-svg', T1 + 500, 'geo0/group').n === 1 && n(rec('gj-to-svg', T1 + 500, 'geo0/group').scaleX) === 1.5);
  guard('the views made anew are set at once', rec('gj-hide-svg', T1 + 10, 'geo0/group').n === 0
    && n(rec('gj-hide-svg', T1 + 10, 'geo0/group').scaleX) === 2 && rec('map-legend-gone', T1 + 100, 'map0/group').n === 0
    && n(rec('map-legend-gone', T1 + 100, 'map0/group').scaleX) === 2 && !rec('map-legend-gone', T1 + 1, 'map0/group'));
  guard('the switch leaves the old regions drawn', rec('gj-to-svg', T1 + 500, 'geo0/els').some(e => e.stale && e.key.startsWith('r:')));
  guard('the SVG content turns and skews (its own transform)', (() => {
    const e = el('gj-to-svg', T1 + 1000, 'geo0', 's:#002200');
    return e && n(e.gm[1]) !== 0 && n(e.gm[2]) !== 0;
  })());
  guard('every element rides the group: gm now = (group now / group at the end) * gm at the end', (() => {
    const a = rec('gj-to-svg', T1 + 500, 'geo0/group');
    const b = rec('gj-to-svg', T1 + 1000, 'geo0/group');
    const ea = rec('gj-to-svg', T1 + 500, 'geo0/els').filter(e => !e.stale);
    const eb = rec('gj-to-svg', T1 + 1000, 'geo0/els').filter(e => !e.stale);
    const f = n(a.scaleX) / n(b.scaleX);
    return ea.length === eb.length && ea.length >= 7 && ea.every((e, i) => {
      const m = e.gm.map(n);
      const m1 = eb[i].gm.map(n);
      const want = [m1[0] * f, m1[1] * f, m1[2] * f, m1[3] * f,
        n(a.x) + (m1[4] - n(b.x)) * f, n(a.y) + (m1[5] - n(b.y)) * f];
      return m.every((v, k) => Math.abs(v - want[k]) < 1e-9);
    });
  })());
  guard('a named shape keeps its screen width; an unnamed one grows', (() => {
    const a0 = el('gj-to-svg', T1 + 1000, 'geo0', 's:#110000');
    const a1 = el('gj-to-svg', T1 + 500, 'geo0', 's:#110000');
    const u0 = el('gj-to-svg', T1 + 1000, 'geo0', 's:#002200');
    const u1 = el('gj-to-svg', T1 + 500, 'geo0', 's:#002200');
    return a0.nsc && !u0.nsc && Math.abs(n(a0.sw) - 2) < 1e-12 && Math.abs(n(a1.sw) - 2) < 1e-12
      && n(u1.sw) < n(u0.sw) * 0.8 && n(u1.dash[0]) < n(u0.dash[0]) * 0.8;
  })());
  guard('the polygon named from its group is strokeNoScale', el('gj-to-svg', T1 + 500, 'geo0', 's:#440000').nsc);
  guard('a GeoJSON region keeps its screen width and dash', (() => {
    const all = [T1 - 1, T1 + 1, T1 + 500, T1 + 1000].map(t => rec('gj-geo-zoom', t, 'geo0/els'));
    return all.every(es => es.length === 3 && es.every(e => e.nsc && Math.abs(n(e.sw) - 2) < 1e-12
      && Math.abs(n(e.dash[0]) - 8) < 1e-12 && Math.abs(n(e.dash[1]) - 4) < 1e-12));
  })());
  guard('the texts scale with the group', n(el('gj-to-svg', T1 + 500, 'geo0', 't:#660000').fs)
    < n(el('gj-to-svg', T1 + 1000, 'geo0', 't:#660000').fs) * 0.8);
  guard('midway: the second tween starts where the first was', (() => {
    const s = cs('gj-to-svg-midway').events.filter(q => q.do === 'sample' && q.t === T1 + 300);
    return s.length === 2 && s[1].rec['geo0/group'].scaleX === s[0].rec['geo0/group'].scaleX
      && s[1].rec['geo0/group'].n === 1;
  })());
  // [R6-B gradients]
  guard('a global gradient rides gm: GeoJSON regions and the switched SVG', (() => {
    const a = el('gj-grad', T1 - 1, 'geo0', 'r:A:0');
    const b = el('gj-grad', T1 - 1, 'geo0', 'r:B:0');
    const s = el('gj-to-svgu', T1 + 500, 'geo0', 's:#003300');
    const c = el('gj-to-svgu', T1 + 500, 'geo0', 's:#000044');
    const nn = el('gj-to-svgu', T1 + 500, 'geo0', 's:#550055');
    return a && a.grad && a.grad.global && a.grad.type === 'linear' && n(a.gm[0]) === 2
      && b && b.grad && b.grad.type === 'radial' && s && s.grad && s.grad.global
      && c && c.grad && c.grad.type === 'radial' && c.grad.global && nn && nn.grad && nn.grad.global
      && n(s.gm[2]) !== 0 && rec('gj-to-svgu', T1 + 500, 'geo0/group').n === 1;
  })());
  return g;
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    clock: { T0 },
    maps: MAPS,
    notes: [
      'every chart: chart._ssr false, env.node off, 400 x 300; the first setOption at T0.',
      'events in order at T0 + t; a sample is zr.animation.update(), a refresh of the display list, and the record.',
      'the roam is x / y / scaleX = scaleY = zoom only (viewCoordSysUpdateRoamTrans); MapDraw tweens it on the transform group.',
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
if (process.env.ORACLE_DUMP) fs.writeFileSync(process.env.ORACLE_DUMP, json1);
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
const deterministic = json1 === json2;
const nul = json1.indexOf('\\u0000') >= 0;
let parses = true;
try { JSON.parse(json1); } catch (e) { parses = false; }
let nSamples = 0;
out1.cases.forEach(q => q.events.forEach(e => { if (e.do === 'sample') nSamples++; }));
console.log(out1.cases.length + ' cases; ' + nSamples + ' samples; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : '')
  + '; ' + warnings + ' warnings');
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
