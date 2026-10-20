/*
Upstream's own answers for fix-phase batch F6b: SVG maps --
echarts.registerMap(name, {svg}) (coord/geo/geoSourceManager.ts), the SVG
resource (coord/geo/GeoSVGResource.ts: _buildGraphic's bounding rect from
width / height / viewBox / the content, the viewBox transform on the parsed
root, the root clip, the named items of the region-available tags made
non-silent, the regions of the self-named ones; GeoSVGRegion.calcCenter of
Region.ts), zrender's SVG parser (tool/parseSVG.ts with tool/parseXML.ts:
the node parsers, inherited and self styles, the transform attribute, the
paint servers, text and tspan, path data through tool/path.ts), the geo of
an SVG map (Geo.ts: aspectScale 1, no y flip, a projection on an SVG map
throws in the dev build) and MapDraw._buildSVG (component/helper/MapDraw.ts:
the option's itemStyle over the SVG's own style on the named shapes, the
three states and the default state proxy, z2EmphasisLift 0, the labels of
the self-named hosts placed 'inside', the event data and tooltip of every
self-named item, the high-down dispatchers of the shapes and groups,
_enableBlurEntireSVG for focus 'self') -- and everything a GeoJSON region
takes part in: the hit test, hover, select, blur, the tooltip, the roam,
the map series' values and visualMap colours, the series on the geo
(scatter, effectScatter, lines, custom), convertToPixel / convertFromPixel.

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), the recipe of
geo-interact.js / geo-roam.js / geo-series.js (chart._ssr = false, env.node
off, getDom stubbed, the controlled clock; text measured by zrender's own
width table through a stub canvas). Node has no DOMParser: jsdom's (a
conforming XML parser, saxes) is installed as the global one parseXML uses
(JSDOM from D:/Projects/xterm.js/node_modules, or JSDOM_PATH).

  node tools/advchart-oracle/geo-svg.js

writes tests/fixtures/advchart-geo-svg.json (ORACLE_OUT overrides). Two
generations must be byte for byte the same. Ends with process.exit().

Conventions
  hex   a double as the 16 hex digits of its IEEE-754 bits (big-endian).
  pt    [hx, hy] or null.
  col   a colour as zrender holds it: the string, null (null / undefined /
        'none'), or a gradient {type, x, y, x2, y2 | r, global, stops
        [[offset hex, colour]]}.

Top level
  source, W, H, tokens (the default token values and their lifts), svgs
  [{name, text} | {name, file}] (file: the shipped SVG under the repo, read
  as UTF-8), notes[], cases[], guards[].

Per case
  id, note, W, H, option ('@name' a handler this script registers),
  maps[] (the svg names registered, as {map, svg}), throws (setOption threw,
  the message) or:
  steps[] as run ({move}, {click}, {drag}, {wheel: [x, y, delta]}, {leave},
  {action}, {setOption, notMerge}), probes[] (pixels),
  trees[] per geo draw (component geos first, then map series' own geos):
    {owner: 'geo' i | 'series' i, lite, rect [4 hex] (the resource's
    boundingRect), view {dataRect, viewRect, mtRaw, mtOverall, mtOverallInv,
    zoom}, named [{name, from (index in named, -1 for self), tag, el}],
    regions [{name, el, c: pt}] (GeoSVGRegion.getCenter, asked after the
    first frame), els[] (preorder from MapDraw's SVG root: the extra root
    group, the parsed root, then the document's elements) -- full:
      {t, p, lt [x y sx sy rot skx sky] hex, gt [6 hex] | null, sil, inv,
       ign, st, sh, br [4 hex] | null}
    lite: {t, p, gt, br, fill, stroke, lw}}
  states[] index-parallel to [after setOption, after step 1, ...]:
    events[] (mouse: {type, componentType, seriesIndex, dataIndex,
             geoIndex, name, region}; action: {type, json}),
    tip (null | {text}), hits[] per probe ({el, label, owner, name} | null),
    draws[] per tree: {roam [6 hex], clip [4 hex] | null, items[] per
      element of interest: {i, states, fill, stroke, lw, op, z2, hover,
      sel, label}} (interest: every displayable of a full tree, the named
      elements of a lite one; label: {states, ignore, text, fill, op, z2,
      x, y, tx, ty} for a label host),
    series[] per series: null | scatter {pts [pt]} | lines {pts [[pt]]} |
      custom {calls [{i, coord [pt], size [[w h] hex]}], coordSys},
    convert[] [{finder, value, px: pt | null}] / [{finder, px, data}].
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

// ---------- a DOMParser for parseXML ----------
const JSDOM_PATH = process.env.JSDOM_PATH || 'D:/Projects/xterm.js/node_modules/jsdom';
const { JSDOM } = require(JSDOM_PATH);
const DOM_WINDOW = new JSDOM('').window;
global.DOMParser = DOM_WINDOW.DOMParser;

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-geo-svg.json');
const MAPS_DIR = path.join(ROOT, 'examples', 'advchart', 'maps');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');

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
function fromHex(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const hx = v => (v == null ? null : hex(+v));
const pt = p => (p && p.length >= 2 && p[0] != null ? [hex(+p[0]), hex(+p[1])] : null);
const clone = v => JSON.parse(JSON.stringify(v));
const rectHex = r => (r ? [hex(r.x), hex(r.y), hex(r.width), hex(r.height)] : null);
const matHex = m => (m ? Array.from(m).map(v => hex(v)) : null);

// ---------- text: zrender's width table through a stub canvas ----------
const WIDTH_TABLE = (function () {
  const map = {};
  const text = '007LLmW\'55;N0500LLLLLLLLLL00NNNLzWW\\\\WQb\\0FWLg\\bWb\\WQ\\WrWWQ000CL5LLFLL0LL**F*gLLLL5F0LF\\FFF5.5N';
  for (let i = 0; i < text.length; i++) map[String.fromCharCode(i + 32)] = (text.charCodeAt(i) - 20) / 100;
  return map;
})();
function tableWidth(t, font) {
  t = t || '';
  font = font || '12px sans-serif';
  const res = /((?:\d+)?\.?\d*)px/.exec(font);
  const fontSize = (res && +res[1]) || 12;
  let w = 0;
  if (font.indexOf('mono') >= 0) w = fontSize * t.length;
  else for (let i = 0; i < t.length; i++) {
    const p = WIDTH_TABLE[t[i]];
    w += p == null ? fontSize : p * fontSize;
  }
  return { width: w };
}
class StubCanvas {
  constructor() { this.width = 300; this.height = 150; }
  getContext() {
    const self = this;
    return { font: '12px sans-serif', measureText(t) { return tableWidth(t, this.font); }, canvas: self };
  }
  toDataURL() { return 'data:,'; }
}
echarts.setPlatformAPI({ createCanvas() { return new StubCanvas(); } });

const W = 600;
const H = 400;

(function enableTooltips() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk(w, h) {
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: w || W, height: h || H });
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
function innerOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object'
      && ('dataIndex' in el[k] || 'eventData' in el[k] || 'seriesIndex' in el[k])) return el[k];
  }
  return null;
}

// ============================================================================
// the SVG maps
// ============================================================================
// Hand-written, each exercising a part of parseSVG / GeoSVGResource. The
// gallery's shipped maps are read from examples/advchart/maps.
const SV_RICH = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="300" height="200" viewBox="0 0 600 400" style="fill:#336699;stroke-width:2" fill="#ff00ff">
  <title>ignored</title>
  <metadata><foo name="nope"/></metadata>
  <defs>
    <linearGradient id="lg" x1="0" y1="0" x2="1" y2="0.5"><stop offset="0" stop-color="#ff0000"/><stop offset="50%" style="stop-color:#00ff00" stop-color="#000000" stop-opacity="0.5"/><desc>x</desc><stop offset="1" stop-color="rgba(0,0,255,0.5)" stop-opacity="0.5"/><stop/></linearGradient>
    <radialGradient id="rg" cx="50.7" cy="50" r="40" gradientUnits="userSpaceOnUse"><stop offset="0.2" stop-color="#ffffff"/><stop offset="1" stop-color="#000000"/></radialGradient>
    <rect id="inDefs" name="inDefs" x="0" y="0" width="5" height="5"/>
  </defs>
  <rect name="bg" x="0" y="0" width="600" height="400" fill="#eeeeee" stroke="none"/>
  <g name="grpA" transform="translate(20, 30)" fill="#cc3333" stroke="#000" style="stroke-width:3;opacity:0.8">
    <rect x="10" y="10" width="80" height="60"/>
    <circle cx="140" cy="40" r="30" fill="url(#lg)"/>
    <g transform="scale(1.5)"><ellipse cx="40" cy="80" rx="20" ry="10" fill-opacity="0.5" stroke-opacity="0.25"/></g>
    <text x="10" y="150" font-size="14" font-family="serif" font-weight="bold" font-style="italic">Grp <tspan dx="2" dy="-3" fill="#0000ff">A</tspan> end</text>
  </g>
  <line name="ln" x1="250" y1="20" x2="350" y2="80" stroke="#00aa00" stroke-width="4" stroke-dasharray="5,3 2" stroke-dashoffset="1" stroke-linecap="round" stroke-linejoin="bevel" stroke-miterlimit="7"/>
  <polygon name="pg" points="400,20 480,20 460,90 410,90" fill="url(#rg)" stroke="url( #missing )"/>
  <polyline name="pl" points="500 20 560 60 520 100" fill="none" stroke="#990099"/>
  <path name="pa" d="M20 200 h60 v40 H20 Z m100 0 l40 0 l0 40 z M200 200 C220 180 260 180 280 200 S 320 240 340 200 Q 360 170 380 200 T 420 200 A 30 20 30 0 1 480 220 a 20 20 0 1 0 40 0 L 520 260 z" fill="#ffcc00" stroke="#333333" stroke-width="1.5px"/>
  <path name="pa" d="M40 300 l30 0 l-15 30 z" style="fill:#123456; stroke : #00ff00" fill="#654321"/>
  <text name="tx" x="300" y="300" text-anchor="middle" alignment-baseline="central" font-size="7" fill="#000000">Small</text>
  <text name="tx2" x="300" y="330" dx="5" dy="2" text-anchor="end" alignment-baseline="hanging" font-size="16" font-family="monospace" fill="#222222" stroke="#ff0000" stroke-width="1">Mono<tspan x="350" y="345" alignment-baseline="text-before-edge">abs</tspan></text>
  <path d="M500 300 l20 0 l-10 20 z" style="fill:#123456; stroke : #00ff00" stroke="url(#missing)"/>
  <path d="M530 300 l20 0 l-10 20 z" style="fill:#123456" fill="#654321"/>
  <switch><rect name="sw" x="560" y="300" width="30" height="30" fill="#00ffff"/></switch>
  <a><rect name="inA" x="560" y="350" width="30" height="30"/></a>
  <rect name="hidden" x="10" y="350" width="20" height="20" visibility="hidden"/>
  <rect name="gone" x="40" y="350" width="20" height="20" display="none"/>
  <rect name="" x="70" y="350" width="20" height="20"/>
  <image name="img" x="100" y="340" width="40" height="30" xlink:href="data:image/png;base64,iVBORw0KGgo="/>
  <g name="grpB"><path name="inner" d="M150 360 l20 0 0 20 -20 0z" fill="#aabbcc"/><path d="M180 360 l20 0 0 20 -20 0z"/><g><circle cx="215" cy="370" r="6"/></g></g>
</svg>`;

// viewBox only: the rect is the viewBox
const SV_VB = `<svg viewBox="-50.5 -20 200 100">
  <rect name="a" x="-40" y="-10" width="60" height="40" fill="#ff8800"/>
  <circle name="b" cx="100" cy="30" r="25" fill="#0088ff" stroke="#000000" stroke-width="2"/>
</svg>`;

// neither size nor viewBox: the rect is the content's own (text included)
const SV_NONE = `<svg>
  <g transform="translate(5 7)">
    <rect name="a" x="10" y="20" width="60" height="40" fill="#448844" stroke="#000000" stroke-width="4"/>
    <text name="t" x="80" y="15" font-size="20" fill="#000000">Content</text>
  </g>
  <polyline name="pl" points="0,100 50,80" stroke="#000000"/>
</svg>`;

// a width only, and a viewBox: the y from the viewBox, the x from 0
const SV_WONLY = `<svg width="240" viewBox="10 20 120 60">
  <rect name="a" x="15" y="25" width="50" height="30" fill="#aa4444"/>
  <rect name="b" x="70" y="30" width="50" height="40" fill="#4444aa" transform="rotate(10 95 50)"/>
</svg>`;

// every kind of transform, and a viewBox of another aspect (scale by min)
const SV_TRANS = `<svg width="400" height="100" viewBox="0 0 100 100">
  <rect name="r0" x="0" y="0" width="10" height="10" transform="translate(5)" fill="#100000"/>
  <rect name="r1" x="0" y="0" width="10" height="10" transform="translate(20,5) rotate(30)" fill="#200000"/>
  <rect name="r2" x="0" y="0" width="10" height="10" transform="rotate(-45 45 15)" fill="#300000"/>
  <rect name="r3" x="0" y="0" width="10" height="10" transform="translate(60 5) skewX(20)" fill="#400000"/>
  <rect name="r4" x="0" y="0" width="10" height="10" transform="translate(80,5)skewY(-15)" fill="#500000"/>
  <rect name="r5" x="0" y="0" width="10" height="10" transform="matrix(1 0.2 -0.3 1 5 40)" fill="#600000"/>
  <rect name="r6" x="0" y="0" width="10" height="10" transform="translate(30,40) scale(2)" fill="#700000"/>
  <rect name="r7" x="0" y="0" width="10" height="10" transform="translate(60,40) scale(2,0.5) rotate(90)" fill="#800000"/>
  <g transform="translate(10,70) scale(1.25)" name="gg">
    <rect name="r8" x="0" y="0" width="10" height="10" transform="rotate(15)" fill="#900000"/>
    <g transform="matrix(0.5,0,0,0.5,20,0)"><rect name="r9" x="0" y="0" width="10" height="10" transform="scale(1e-1, 2E0)" fill="#a00000"/></g>
  </g>
  <circle name="c" cx="80" cy="80" r="8" transform="translate(-1.5e1 .5)" fill="#b00000" stroke="#000000" stroke-width="0.5"/>
</svg>`;

// a plain picture for the pointer: two shapes named B, a named group of
// two rects and a text, a named text, a stroke-only circle, a named rect in
// a named group, an unnamed background
const SV_HIT = `<svg width="400" height="300">
  <rect x="0" y="0" width="400" height="300" fill="#f0f0f0"/>
  <rect name="A" x="20" y="20" width="80" height="60" fill="#88aacc" stroke="#224466" stroke-width="2"/>
  <rect name="B" x="120" y="20" width="60" height="60" fill="#ccaa88"/>
  <rect name="B" x="200" y="20" width="60" height="60" fill="#ccaa88"/>
  <g name="G" fill="#99cc99">
    <rect x="20" y="120" width="60" height="60"/>
    <rect x="90" y="120" width="60" height="60" fill="#669966"/>
    <text x="30" y="200" font-size="12" fill="#000000">in G</text>
  </g>
  <text name="T" x="200" y="160" font-size="20" fill="#333333">Words</text>
  <circle name="C" cx="330" cy="60" r="35" fill="none" stroke="#aa0000" stroke-width="6"/>
  <g name="H">
    <rect name="N" x="280" y="140" width="50" height="50" fill="#cc66cc"/>
    <rect x="340" y="140" width="40" height="50" fill="#996699"/>
  </g>
  <path name="P" d="M40 230 C 60 200 100 200 120 230 Q 140 260 180 240 A 30 30 0 0 1 240 240 Z" fill="#6688aa"/>
</svg>`;

// width as a percentage (parseFloat reads the number), viewBox 'none'
const SV_PCT = `<svg width="50%" height="80px" viewBox="none">
  <rect name="a" x="5" y="5" width="30" height="30" fill="#557755"/>
</svg>`;

const SVGS = [
  { name: 'svRich', text: SV_RICH },
  { name: 'svVb', text: SV_VB },
  { name: 'svNone', text: SV_NONE },
  { name: 'svWonly', text: SV_WONLY },
  { name: 'svTrans', text: SV_TRANS },
  { name: 'svHit', text: SV_HIT },
  { name: 'svPct', text: SV_PCT },
  { name: 'svBad', text: '<svg><rect></svg>' },
  { name: 'svNotSvg', text: '<foo/>' },
  { name: 'Beef_cuts_France', file: 'examples/advchart/maps/Beef_cuts_France.svg' },
  { name: 'iceland_svg', file: 'examples/advchart/maps/Map_of_Iceland.svg' },
  { name: 'sicily', file: 'examples/advchart/maps/Sicily_prehellenic_topographic_map.svg' },
];
function svgText(s) {
  return s.text != null ? s.text : fs.readFileSync(path.join(ROOT, s.file), 'utf8');
}
const LITE = new Set(['Beef_cuts_France', 'iceland_svg', 'sicily']);

// register the case's maps afresh: [{map, svg}] (map: the name the option
// asks for, svg: the SVGS entry)
function registerMaps(maps) {
  const out = [];
  for (const m of maps) {
    const s = SVGS.find(x => x.name === m.svg);
    must(s, 'no svg ' + m.svg);
    let threw = null;
    try {
      echarts.registerMap(m.map, { svg: svgText(s) });
    }
    catch (e) {
      threw = String(e.message).split('\n')[0];
    }
    out.push({ map: m.map, svg: m.svg, threw: threw !== null });
  }
  return out;
}

// ---------- the handlers an option names ----------
const FMT = {
  regionTip: p => 'tip:' + p.componentType + ':' + p.name,
  regionLabel: p => '[' + p.name + '|' + p.status + ']',
};
const CU_LOG = [];
const RENDER = {
  pin(params, api) {
    const v = [api.value(0), api.value(1)];
    const c = api.coord(v);
    const s = api.size([10, 10], v);
    CU_LOG.push({ i: params.dataIndex, value: [hex(v[0]), hex(v[1])], coord: pt(c), size: [hex(s[0]), hex(s[1])],
      coordSys: { type: params.coordSys.type, x: hex(params.coordSys.x), y: hex(params.coordSys.y),
        width: hex(params.coordSys.width), height: hex(params.coordSys.height), zoom: hex(params.coordSys.zoom) } });
    return { type: 'circle', shape: { cx: c[0], cy: c[1], r: 6 }, style: { fill: '#ff0000' } };
  },
};
function withHandlers(v, key) {
  if (typeof v === 'string' && v.startsWith('@')) {
    const n = v.slice(1);
    if (key === 'renderItem' && RENDER[n]) return RENDER[n];
    if (FMT[n]) return FMT[n];
  }
  if (Array.isArray(v)) return v.map(x => withHandlers(x));
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[k] = withHandlers(v[k], k);
    return o;
  }
  return v;
}

// ============================================================================
// reading the picture
// ============================================================================
function colourOf(c) {
  if (c == null || c === 'none') return null;
  if (typeof c === 'object') {
    const g = { type: c.type, global: !!c.global, stops: (c.colorStops || []).map(s => [hex(s.offset), String(s.color)]) };
    if (c.type === 'radial') { g.x = hex(c.x); g.y = hex(c.y); g.r = hex(c.r); }
    else { g.x = hex(c.x); g.y = hex(c.y); g.x2 = hex(c.x2); g.y2 = hex(c.y2); }
    return g;
  }
  return String(c);
}
function shortColour(c) {
  const v = colourOf(c);
  return v && typeof v === 'object' ? 'gradient' : v;
}
function enumerate(root) {
  const els = [];
  const index = new Map();
  (function walk(el, parent) {
    index.set(el, els.length);
    els.push({ el, parent });
    if (el.isGroup) for (const c of el.children()) walk(c, index.get(el));
  })(root, -1);
  return { els, index };
}
function localOf(el) {
  return [el.x, el.y, el.scaleX, el.scaleY, el.rotation, el.skewX, el.skewY].map(v => hex(v || 0));
}
function styleOf(el) {
  const s = el.style;
  const r = {
    fill: colourOf(s.fill), stroke: colourOf(s.stroke), lw: hx(s.lineWidth), op: hx(s.opacity),
    fo: hx(s.fillOpacity), so: hx(s.strokeOpacity),
    dash: s.lineDash == null ? null : (Array.isArray(s.lineDash) ? s.lineDash.map(hex) : String(s.lineDash)),
    dashOff: hx(s.lineDashOffset), cap: s.lineCap == null ? null : String(s.lineCap),
    join: s.lineJoin == null ? null : String(s.lineJoin), miter: hx(s.miterLimit), noScale: !!s.strokeNoScale,
  };
  if (el.type === 'tspan') {
    r.text = s.text == null ? null : String(s.text);
    r.font = s.font == null ? null : String(s.font);
    r.fontSize = hx(s.fontSize);
    r.x = hx(s.x);
    r.y = hx(s.y);
    r.align = s.textAlign == null ? null : String(s.textAlign);
    r.base = s.textBaseline == null ? null : String(s.textBaseline);
  }
  if (el.type === 'image') {
    const img = s.image == null ? null : String(s.image);
    r.img = img == null ? null : img.length + ':' + img.slice(0, 48);
    r.ix = hx(s.x); r.iy = hx(s.y); r.iw = hx(s.width); r.ih = hx(s.height);
  }
  return r;
}
function shapeOf(el) {
  const s = el.shape || {};
  switch (el.type) {
    case 'path': {
      if (!el.path) el.getBoundingRect();
      const d = el.path.data;
      return { d: Array.from(d.slice(0, el.path.len())).map(hex), f32: d instanceof Float32Array };
    }
    case 'rect': return { v: [s.x, s.y, s.width, s.height].map(hex) };
    case 'circle': return { v: [s.cx, s.cy, s.r].map(hex) };
    case 'ellipse': return { v: [s.cx, s.cy, s.rx, s.ry].map(hex) };
    case 'line': return { v: [s.x1, s.y1, s.x2, s.y2].map(hex) };
    case 'polygon':
    case 'polyline': return { v: [].concat(...(s.points || []).map(p => [hex(p[0]), hex(p[1])])) };
    default: return null;
  }
}
function fullRecord(el, parent) {
  const r = { t: el.type, p: parent, lt: localOf(el), gt: matHex(el.transform),
    sil: !!el.silent, inv: !!el.invisible, ign: !!el.ignore };
  if (!el.isGroup) {
    r.st = styleOf(el);
    r.sh = shapeOf(el);
  }
  const br = el.getBoundingRect && el.getBoundingRect();
  r.br = br ? rectHex(br) : null;
  return r;
}
function liteRecord(el, parent) {
  const br = el.getBoundingRect && el.getBoundingRect();
  const r = { t: el.type, p: parent, gt: matHex(el.transform), br: br ? rectHex(br) : null };
  if (!el.isGroup) {
    r.fill = shortColour(el.style.fill);
    r.stroke = shortColour(el.style.stroke);
    r.lw = hx(el.style.lineWidth);
  }
  return r;
}
function viewOf(view) {
  return {
    dataRect: rectHex(view.dataRect), viewRect: rectHex(view.viewRect),
    mtRaw: matHex(view.mtRaw), mtOverall: matHex(view.mtOverall), mtOverallInv: matHex(view.mtOverallInv),
    zoom: hex(view.zoom),
  };
}
// every MapDraw drawing an SVG map: the geo components', then the map
// series' own (the main series of each group draws it)
function svgDraws(chart) {
  const out = [];
  chart.getModel().eachComponent('geo', gm => {
    const v = chart.getViewOfComponentModel(gm);
    if (v && v._mapDraw && v._mapDraw._svgGraphicRecord) out.push({ owner: 'geo', i: gm.componentIndex, md: v._mapDraw, geo: gm.coordinateSystem });
  });
  chart.getModel().eachSeriesByType('map', sm => {
    const v = chart.getViewOfSeriesModel(sm);
    if (v && v._mapDraw && v._mapDraw._svgGraphicRecord && v._mapDraw.group.parent) {
      out.push({ owner: 'series', i: sm.seriesIndex, md: v._mapDraw, geo: sm.coordinateSystem });
    }
  });
  return out;
}
function treeOf(d, mapName) {
  const lite = LITE.has(mapName);
  const rec = d.md._svgGraphicRecord;
  const en = enumerate(rec.root);
  const named = rec.named.map(n => ({ name: n.name, from: n.namedFrom ? rec.named.indexOf(n.namedFrom) : -1,
    tag: n.svgNodeTagLower, el: en.index.get(n.el) }));
  const regions = d.geo.regions.map(r => ({ name: r.name, el: en.index.get(r._elOnlyForCalculate), c: pt(r.getCenter()) }));
  const els = en.els.map(x => (lite ? liteRecord(x.el, x.parent) : fullRecord(x.el, x.parent)));
  return { owner: d.owner, i: d.i, map: mapName, lite, rect: rectHex(rec.boundingRect), view: viewOf(d.geo.view),
    named, regions, els, en };
}
function labelOf(el) {
  const t = el.getTextContent && el.getTextContent();
  if (!t) return null;
  const lt = t.ignore ? null : t.innerTransformable.getLocalTransform([]);
  return {
    states: (t.currentStates || []).join(','), ignore: !!t.ignore,
    text: t.style.text == null ? null : String(t.style.text), fill: shortColour(t.style.fill),
    op: hx(t.style.opacity), z2: t.z2,
    x: t.ignore ? null : hex(t.innerTransformable.x), y: t.ignore ? null : hex(t.innerTransformable.y),
    tx: lt ? hex(lt[4]) : null, ty: lt ? hex(lt[5]) : null,
  };
}
function drawState(tree, d) {
  const items = [];
  tree.en.els.forEach((x, i) => {
    const el = x.el;
    const isNamed = tree.named.some(n => n.el === i);
    const interest = tree.lite ? isNamed : (!el.isGroup || isNamed);
    if (!interest) return;
    const r = { i, states: (el.currentStates || []).join(','), hover: el.hoverState || 0, sel: !!el.selected };
    if (!el.isGroup) {
      r.fill = shortColour(el.style.fill);
      r.stroke = shortColour(el.style.stroke);
      r.lw = hx(el.style.lineWidth);
      r.op = hx(el.style.opacity);
      r.z2 = el.z2;
    }
    r.label = labelOf(el);
    items.push(r);
  });
  const tg = d.md._transformGroup;
  tg.updateTransform();
  return { roam: matHex(tg.transform), clip: d.md.group.getClipPath() ? rectHex(d.md.group.getClipPath().shape) : null, items };
}
// the hit test at a pixel: the element (its index in its tree) or the label
// it carries, and the event data found up the way
function hitAt(chart, trees, draws, x, y) {
  refresh(chart);
  const t = zr(chart).handler.findHover(x, y).target;
  if (!t) return null;
  const r = { el: null, label: null, owner: null, name: null, series: null, dataIndex: null };
  for (let k = 0; k < trees.length; k++) {
    let host = t;
    let isLabel = false;
    // a label is a Text whose TSpan children are hit
    for (let e = t; e; e = e.parent || e.__hostTarget) {
      if (trees[k].en.index.has(e)) { host = e; break; }
      if (e.__hostTarget) { host = e.__hostTarget; isLabel = true; break; }
    }
    if (trees[k].en.index.has(host)) {
      if (isLabel) r.label = trees[k].en.index.get(host); else r.el = trees[k].en.index.get(t);
      r.owner = trees[k].owner + trees[k].i;
      break;
    }
  }
  for (let el = t; el; el = el.__hostTarget || el.parent) {
    const inner = innerOf(el);
    if (inner && inner.eventData) { r.name = inner.eventData.name; break; }
    if (inner && inner.seriesIndex != null && inner.dataIndex != null) {
      r.series = inner.seriesIndex;
      r.dataIndex = inner.dataIndex;
      break;
    }
  }
  return r;
}
function tooltipView(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  return m ? chart.getViewOfComponentModel(m) : null;
}
const SEGMENT = /\{(__EC_aUTo_\d+)\|([^}]*)\}/g;
function tipNow(chart) {
  const view = tooltipView(chart);
  if (!view) return null;
  const c = view._tooltipContent;
  if (!c || !c.el || !c._show) return null;
  return { text: String(c.el.style.text).replace(SEGMENT, '$2') };
}
function seriesOf(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    const t = sm.subType;
    const data = sm.getData();
    // the points of a series on a geo (the cartesian ones of a gallery
    // option are not this suite's)
    const onGeo = sm.coordinateSystem && sm.coordinateSystem.type === 'geo';
    if ((t === 'scatter' || t === 'effectScatter') && !onGeo) out.push(null);
    else if (t === 'scatter' || t === 'effectScatter') {
      const pts = [];
      for (let i = 0; i < data.count(); i++) pts.push(pt(data.getItemLayout(i)));
      out.push({ type: t, pts });
    }
    else if (t === 'lines') {
      const pts = [];
      for (let i = 0; i < data.count(); i++) pts.push((data.getItemLayout(i) || []).map(pt));
      out.push({ type: t, pts });
    }
    else if (t === 'custom') out.push({ type: t, calls: CU_LOG.splice(0) });
    else out.push(null);
  });
  return out;
}

// ---------- points ----------
function treeByOwner(trees, owner) {
  const t = trees.find(x => x.owner + x.i === (owner || 'geo0'));
  must(t, 'no tree ' + owner);
  return t;
}
function resolvePoint(chart, trees, target, where) {
  if (Array.isArray(target)) return target.slice();
  const draws = svgDraws(chart);
  const d = draws.find(x => x.owner + x.i === (target.owner || 'geo0'));
  must(d, where + ': no draw ' + target.owner);
  let p;
  if (target.region !== undefined) {
    p = d.geo.dataToPoint(target.region);
    must(p, where + ': no region ' + target.region);
  }
  else if (target.at) p = d.geo.dataToPoint(target.at);
  else throw new OracleError(where + ': an unknown target ' + JSON.stringify(target));
  return [Math.round(p[0]) + (target.dx || 0), Math.round(p[1]) + (target.dy || 0)];
}
function resolveStep(chart, trees, step, where) {
  const r = Object.assign({}, step);
  if (step.move) r.move = resolvePoint(chart, trees, step.move, where);
  if (step.click) r.click = resolvePoint(chart, trees, step.click, where);
  if (step.drag) r.drag = step.drag.map(t => resolvePoint(chart, trees, t, where));
  if (step.wheel) {
    const q = resolvePoint(chart, trees, Array.isArray(step.wheel) ? step.wheel.slice(0, 2) : step.wheel.at, where);
    r.wheel = [q[0], q[1], Array.isArray(step.wheel) ? step.wheel[2] : step.wheel.delta];
  }
  return r;
}
function convertOf(chart, c) {
  const out = [];
  for (const q of c.convert || []) {
    if (q.value !== undefined) {
      const v = chart.convertToPixel(q.finder, clone(q.value));
      out.push({ finder: q.finder, value: q.value, px: v == null ? null : pt(v) });
    }
    else {
      const v = chart.convertFromPixel(q.finder, clone(q.px));
      out.push({ finder: q.finder, px: q.px, data: v == null ? null : pt(v) });
    }
  }
  return out;
}

// ---------- a case ----------
const MOUSE = ['click', 'mouseover', 'mouseout', 'mousemove'];
const ACTION_EVENTS = ['geoselectchanged', 'geoselected', 'geounselected', 'georoam', 'selectchanged'];

function runCase(c) {
  const reg = registerMaps(c.maps);
  const chart = mk(c.W, c.H);
  CU_LOG.length = 0;
  const events = [];
  for (const t of MOUSE) {
    chart.on(t, p => {
      events.push({ type: t, componentType: p.componentType == null ? null : p.componentType,
        seriesIndex: p.seriesIndex == null ? null : p.seriesIndex, dataIndex: p.dataIndex == null ? null : p.dataIndex,
        geoIndex: p.geoIndex == null ? null : p.geoIndex, name: p.name == null ? null : String(p.name),
        region: p.region === undefined ? null : JSON.stringify(p.region) });
    });
  }
  for (const t of ACTION_EVENTS) chart.on(t, e => events.push({ type: t, json: JSON.stringify(e) }));
  const out = { id: c.id, note: c.note, W: c.W || W, H: c.H || H, option: c.option, maps: c.maps,
    registered: reg.map(r => r.threw === false) };
  const states = [];
  const steps = [];
  let trees = [];
  let probes = [];
  const snap = () => {
    chart._onframe();
    refresh(chart);
    const draws = svgDraws(chart);
    const st = { events: events.splice(0), tip: tipNow(chart), hits: probes.map(p => hitAt(chart, trees, draws, p[0], p[1])), draws: [] };
    for (const d of draws) {
      const tr = trees.find(x => x.owner === d.owner && x.i === d.i);
      // a new tree when the draw is new (a notMerge setOption): read again
      if (tr && tr.root === d.md._svgGraphicRecord.root) st.draws.push(drawState(tr, d));
      else st.draws.push(null);
    }
    st.series = seriesOf(chart);
    st.convert = convertOf(chart, c);
    return st;
  };
  try {
    try {
      chart.setOption(withHandlers(clone(c.option)));
    }
    catch (e) {
      out.throws = String(e.message).split('\n')[0];
      return out;
    }
    refresh(chart);
    const optMap = d => {
      const m = d.owner === 'geo' ? chart.getModel().getComponent('geo', d.i) : chart.getModel().getSeriesByIndex(d.i);
      const name = d.owner === 'geo' ? m.get('map') : m.getMapType();
      const e = c.maps.find(x => x.map === name);
      return e ? e.svg : name;
    };
    trees = svgDraws(chart).map(d => Object.assign(treeOf(d, optMap(d)), { root: d.md._svgGraphicRecord.root }));
    probes = (c.probes || []).map((t, i) => resolvePoint(chart, trees, t, c.id + ' probe ' + i));
    states.push(snap());
    (c.steps || []).forEach((step0, i) => {
      const where = c.id + ' step ' + i;
      const step = resolveStep(chart, trees, step0, where);
      if (step.move) fire(chart, 'mousemove', { zrX: step.move[0], zrY: step.move[1] });
      else if (step.click) {
        const p = step.click;
        fire(chart, 'mousemove', { zrX: p[0], zrY: p[1] });
        fire(chart, 'mousedown', { zrX: p[0], zrY: p[1] });
        fire(chart, 'mouseup', { zrX: p[0], zrY: p[1] });
        fire(chart, 'click', { zrX: p[0], zrY: p[1] });
      }
      else if (step.drag) {
        const pts = step.drag;
        fire(chart, 'mousemove', { zrX: pts[0][0], zrY: pts[0][1] });
        fire(chart, 'mousedown', { zrX: pts[0][0], zrY: pts[0][1] });
        for (let k = 1; k < pts.length; k++) fire(chart, 'mousemove', { zrX: pts[k][0], zrY: pts[k][1] });
        const last = pts[pts.length - 1];
        fire(chart, 'mouseup', { zrX: last[0], zrY: last[1] });
        fire(chart, 'click', { zrX: last[0], zrY: last[1] });
      }
      else if (step.wheel) fire(chart, 'mousewheel', { zrX: step.wheel[0], zrY: step.wheel[1], zrDelta: step.wheel[2] / 120 });
      else if (step.leave) fire(chart, 'mouseout', { zrX: -1, zrY: -1 });
      else if (step.action) chart.dispatchAction(clone(step.action));
      else if (step.setOption) chart.setOption(withHandlers(clone(step.setOption)), !!step.notMerge);
      else throw new OracleError(where + ': an unknown step ' + JSON.stringify(step));
      steps.push(step);
      states.push(snap());
    });
  } finally {
    chart.dispose();
  }
  out.steps = steps;
  out.probes = probes;
  out.trees = trees.map(t => {
    const r = Object.assign({}, t);
    delete r.en;
    delete r.root;
    return r;
  });
  out.states = states;
  return out;
}

// ---------- the cases ----------
const TIP = { hideDelay: 0, position: [5, 5] };
function opt(geo, extra) { return Object.assign({ animation: false, geo }, extra || {}); }
const A = (x, y) => ({ at: [x, y] });
const S = (x, y) => ({ owner: 'series0', at: [x, y] });
function gallery(name) { return JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8')); }

const CASES = [
  // ---- the parse ----
  {
    id: 'parse-rich',
    note: 'parseSVG over every node parser: the root svg reads its inline style only, a title / metadata / unknown tag is skipped with its children, defs and switch are passed through (an element in defs is not drawn, a gradient anywhere is a paint server), the attributes override the inline style, the inherited style goes down (opacity too), fill none, url(#id) fills (a missing id leaves the fill undefined), path data of every command, text with tspans (dx / dy, an absolute x / y, the text-anchor of the parent, alignment-baseline of the tspan itself, a font size under 9 scaled), visibility hidden, display none, an empty name, an image, a <g name> group; the default geo style on the named shapes',
    maps: [{ map: 'svRich', svg: 'svRich' }],
    option: opt({ map: 'svRich' }),
  },
  {
    id: 'parse-rects',
    note: "GeoSVGResource's bounding rect four ways: viewBox only (the viewBox), neither size nor viewBox (the content's own rect, the text measured), a width and a viewBox (x from 0, y from the viewBox), width '50%' (parseFloat: 50) with viewBox 'none'; and every transform the attribute knows, a viewBox of another aspect",
    maps: [{ map: 'svVb', svg: 'svVb' }, { map: 'svNone', svg: 'svNone' }, { map: 'svWonly', svg: 'svWonly' },
      { map: 'svPct', svg: 'svPct' }, { map: 'svTrans', svg: 'svTrans' }],
    W: 800, H: 600,
    option: opt([
      { map: 'svVb', left: 0, top: 0, width: 400, height: 200 },
      { map: 'svNone', left: 400, top: 0, width: 400, height: 200 },
      { map: 'svWonly', left: 0, top: 200, width: 400, height: 200 },
      { map: 'svPct', left: 400, top: 200, width: 400, height: 200 },
      { map: 'svTrans', left: 0, top: 400, width: 800, height: 200, label: { show: true } },
    ]),
    convert: [
      { finder: { geoIndex: 4 }, value: 'r2' }, { finder: { geoIndex: 4 }, value: 'gg' }, { finder: { geoIndex: 4 }, value: [50, 50] },
      { finder: { geoIndex: 0 }, value: 'b' }, { finder: { geoIndex: 1 }, value: 't' },
      { finder: { geoIndex: 4 }, px: [400, 500] }, { finder: { geoIndex: 2 }, px: [100, 300] },
    ],
  },
  {
    id: 'register-errors',
    note: 'an SVG that does not parse (mismatched tags) and a document whose root is not svg: registerMap throws, the map is not there, setOption throws on it',
    maps: [{ map: 'svBad', svg: 'svBad' }, { map: 'svNotSvg', svg: 'svNotSvg' }],
    option: opt({ map: 'svBad' }),
  },
  {
    id: 'projection-throws',
    note: 'a projection written on an SVG map: the dev build drops it and then reads project off null -- setOption throws',
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: opt({ map: 'svHit', projection: { project: '@regionTip', unproject: '@regionTip' } }),
  },
  // ---- the pointer ----
  {
    id: 'hover-default',
    note: 'the defaults on SVG regions: hover a named rect (the emphasis fill, z2 not lifted: z2EmphasisLift 0), a rect named B twice (only the one under the pointer), a child of the named group G (the whole group and its label), the named text T (events, no state), the stroke of a fill-less circle, a named rect N in the named group H (N alone), the curved path P, the unnamed background (nothing: silent), and leave',
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: opt({ map: 'svHit' }, { tooltip: Object.assign({}, TIP) }),
    probes: [A(60, 50), A(150, 50), A(230, 50), A(50, 150), A(120, 150), A(40, 196), A(220, 155), A(330, 60), A(362, 60), A(330, 26), A(40, 205), A(220, 170),
      A(300, 160), A(360, 160), A(80, 225), A(210, 240), A(10, 10), A(390, 290), A(50, 245)],
    steps: [
      { move: A(60, 50) }, { move: A(150, 50) }, { move: A(230, 50) }, { move: A(50, 150) }, { move: A(120, 150) },
      { move: A(220, 155) }, { move: A(362, 60) }, { move: A(300, 160) }, { move: A(360, 160) }, { move: A(80, 225) },
      { move: A(10, 10) }, { leave: true },
    ],
  },
  {
    id: 'select',
    note: "selectedMode 'multiple': a click selects every element of the name (both B), a click in the group G selects G, a click on the named text T toggles T; geoselectchanged before click; then 'single'",
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: opt({ map: 'svHit', selectedMode: 'multiple' }),
    steps: [
      { click: A(150, 50) }, { click: A(50, 150) }, { click: A(220, 155) }, { click: A(150, 50) },
      { setOption: { geo: { selectedMode: 'single' } } }, { click: A(60, 50) }, { click: A(300, 160) }, { leave: true },
    ],
  },
  {
    id: 'focus-self',
    note: "emphasis.focus 'self': every element of the SVG gets the default proxy and a blur state (_enableBlurEntireSVG) -- hovering a region blurs the unnamed background too, the hovered region in emphasis; leaving lifts the blur",
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: opt({ map: 'svHit', emphasis: { focus: 'self' }, blur: { itemStyle: { opacity: 0.3 } } }),
    steps: [{ move: A(60, 50) }, { move: A(50, 150) }, { move: A(10, 10) }, { leave: true }],
  },
  {
    id: 'styles',
    note: 'region options on SVG regions: itemStyle over the SVG style (color replaces the fill, borderColor / borderWidth the stroke), emphasis / select / blur styles, labels shown with a formatter and a function formatter, a silent region, emphasis.disabled, areaColor over color; the geo itemStyle color on every named shape',
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: opt({
      map: 'svHit', selectedMode: 'single', itemStyle: { color: '#dddddd', borderWidth: 1 },
      label: { show: true, formatter: '<{a}>' },
      emphasis: { label: { formatter: '@regionLabel' }, itemStyle: { borderColor: '#ff0000', borderWidth: 3 } },
      regions: [
        { name: 'A', itemStyle: { color: '#00ff00', borderType: 'dashed', opacity: 0.6 }, select: { itemStyle: { color: '#0000ff' } } },
        { name: 'B', silent: true },
        { name: 'G', emphasis: { disabled: true }, itemStyle: { areaColor: '#ff00ff' } },
        { name: 'C', label: { show: false }, emphasis: { itemStyle: { color: 'inherit' } } },
        { name: 'N', blur: { itemStyle: { opacity: 0.2 } }, emphasis: { focus: 'self' } },
      ],
    }),
    probes: [A(150, 50), A(50, 150), A(330, 26)],
    steps: [{ move: A(60, 50) }, { click: A(60, 50) }, { move: A(50, 150) }, { move: A(330, 26) }, { move: A(300, 160) }, { leave: true }],
  },
  {
    id: 'tooltip-actions',
    note: "the region tooltip (the region's string, the geo's template, a function), highlight / downplay by name (both B), geoSelect / geoUnSelect / geoToggleSelect",
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: opt({ map: 'svHit', selectedMode: 'multiple', tooltip: { formatter: 'geo {a}!' },
      regions: [{ name: 'A', tooltip: { formatter: 'A says {a}' } }, { name: 'T', tooltip: { formatter: '@regionTip' } }] },
    { tooltip: Object.assign({}, TIP) }),
    steps: [
      { move: A(60, 50) }, { move: A(150, 50) }, { move: A(220, 155) }, { leave: true },
      { action: { type: 'highlight', geoIndex: 0, name: 'B' } }, { action: { type: 'downplay', geoIndex: 0, name: 'B' } },
      { action: { type: 'geoSelect', geoIndex: 0, name: 'H' } }, { action: { type: 'geoToggleSelect', geoIndex: 0, name: 'B' } },
      { action: { type: 'geoUnSelect', geoIndex: 0, name: 'H' } },
    ],
  },
  {
    id: 'roam-layout',
    note: 'the roam on an SVG geo (drag, wheel, geoRoam), the hover kept, labels following; layoutCenter / layoutSize, aspectScale default 1, a centre and zoom in the option, clip',
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: opt({ map: 'svHit', roam: true, layoutCenter: ['50%', '50%'], layoutSize: '90%', center: [150, 120], zoom: 1.2, clip: true,
      label: { show: true } }),
    probes: [[300, 200], [150, 150]],
    steps: [
      { move: { region: 'A' } }, { drag: [{ region: 'A' }, { region: 'A', dx: 20, dy: 10 }, { region: 'A', dx: 40, dy: 15 }] },
      { wheel: [300, 200, 240] }, { action: { type: 'geoRoam', geoIndex: 0, dx: -30, dy: 12 } }, { move: { region: 'C' } }, { leave: true },
    ],
    convert: [{ finder: { geoIndex: 0 }, value: 'A' }, { finder: { geoIndex: 0 }, value: [100, 100] }, { finder: { geoIndex: 0 }, px: [300, 200] }],
  },
  // ---- series ----
  {
    id: 'map-series',
    note: 'a map series on an SVG map with a continuous visualMap: the named regions coloured by value (a region without data keeps the default), the data appended for regions not in the data, the label rule, hover and select through the series, the tooltip',
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: { animation: false, tooltip: Object.assign({}, TIP),
      visualMap: { min: 0, max: 100, inRange: { color: ['#ffeeee', '#cc0000'] }, hoverLink: false },
      series: [{ type: 'map', map: 'svHit', label: { show: true },
        data: [{ name: 'A', value: 20 }, { name: 'B', value: 80 }, { name: 'G', value: 50 }, { name: 'P', value: '-' }] }] },
    // no pointer on the twice-named B: a map series hovers the element under
    // the pointer only, the port every element of the name (a deviation,
    // upstream's own FIXME in resetEventTriggerForRegion)
    probes: [S(60, 50), S(150, 50), S(50, 150), S(80, 225)],
    steps: [{ move: S(60, 50) }, { click: S(60, 50) }, { move: S(50, 150) }, { move: S(80, 225) }, { leave: true }],
  },
  {
    id: 'geo-series',
    note: 'series on an SVG geo: scatter and effectScatter at SVG coordinates, a polyline of lines, a custom series (api.coord, api.size, coordSys), convertToPixel by series',
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: opt({ map: 'svHit', roam: true }, {
      series: [
        { type: 'scatter', coordinateSystem: 'geo', data: [[60, 50], [330, 60], [200, 160]] },
        { type: 'effectScatter', coordinateSystem: 'geo', geoIndex: 0, data: [[100, 100], [380, 280]] },
        { type: 'lines', coordinateSystem: 'geo', polyline: true, data: [{ coords: [[20, 20], [200, 100], [380, 20]] }] },
        { type: 'custom', coordinateSystem: 'geo', renderItem: '@pin', data: [[150, 150], [300, 250]] },
      ],
    }),
    steps: [{ action: { type: 'geoRoam', geoIndex: 0, zoom: 1.5, originX: 300, originY: 200 } }],
    convert: [{ finder: { seriesIndex: 0 }, value: [60, 50] }, { finder: { seriesIndex: 3 }, value: [150, 150] }],
  },
  // ---- the gallery ----
  {
    id: 'gallery-beef',
    note: 'geo-beef-cuts: a map series on Beef_cuts_France.svg with a visualMap (the harvested option)',
    maps: [{ map: 'Beef_cuts_France', svg: 'Beef_cuts_France' }],
    option: Object.assign({ animation: false }, gallery('geo-beef-cuts')),
    probes: [[300, 200], [150, 150], [450, 250]],
    steps: [{ move: [300, 200] }, { move: [450, 250] }, { leave: true }],
  },
  {
    id: 'gallery-iceland',
    note: 'geo-svg-scatter-simple: an effectScatter on Map_of_Iceland.svg (no named element: no region)',
    maps: [{ map: 'iceland_svg', svg: 'iceland_svg' }],
    option: Object.assign({ animation: false }, gallery('geo-svg-scatter-simple')),
    probes: [[300, 200]],
    convert: [{ finder: { geoIndex: 0 }, px: [300, 200] }, { finder: { geoIndex: 0 }, value: [488.2358421078053, 459.70913833075736] }],
  },
  {
    id: 'gallery-sicily',
    note: 'geo-svg-map: Sicily_prehellenic_topographic_map.svg with its routes and sites as regions (the harvested option, functions dropped), a select by action',
    maps: [{ map: 'sicily', svg: 'sicily' }],
    option: Object.assign({ animation: false }, gallery('geo-svg-map')),
    probes: [[300, 200], [200, 250]],
    steps: [{ action: { type: 'geoSelect', geoIndex: 0, name: 'route1' } }, { move: [300, 200] }, { leave: true }],
  },
  // ---- [R2-B] ----
  {
    id: 'map-series-same-name',
    note: "a map series on the SVG map: each of the two rects named B is a highDownDispatcher of the item (resetEventTriggerForRegion; no component high-down by name on a series) -- hovering one lifts it alone, then the other; highlight by name reaches getItemGraphicEl, the last one registered (the second B), alone; the pointer on the first B while the second is held lifts it too, leaving takes it down (it holds nothing); downplay",
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: { animation: false, series: [{ type: 'map', map: 'svHit', data: [{ name: 'A', value: 1 }, { name: 'B', value: 2 }] }] },
    steps: [{ move: S(150, 50) }, { move: S(230, 50) }, { leave: true }, { action: { type: 'highlight', seriesIndex: 0, name: 'B' } },
      { move: S(150, 50) }, { leave: true }, { action: { type: 'downplay', seriesIndex: 0, name: 'B' } }],
  },
  // ---- [R2-I1] ----
  {
    id: 'map-series-held-move-off',
    note: "[R2-I1] the second B held by highlight; the pointer on the first B lifts it, and MOVING OFF it -- onto the unnamed background, onto A, onto the held B -- takes it down again (it holds no bits; the held one stays); downplay, the pointer still on the background; then the first B hovered BEFORE the highlight and left (the held one stays), the held one hovered and left, a downplay under the pointer on the first B (it stays lifted: its own hover); a highlight and a downplay under the pointer on the held B (the downplay takes it down, the pointer still on it), and a downplay of the hovered last B with no highlight (leaveEmphasis there too)",
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: { animation: false, series: [{ type: 'map', map: 'svHit', data: [{ name: 'A', value: 1 }, { name: 'B', value: 2 }] }] },
    steps: [{ action: { type: 'highlight', seriesIndex: 0, name: 'B' } }, { move: S(150, 50) }, { move: S(300, 250) },
      { move: S(150, 50) }, { move: S(60, 50) }, { move: S(150, 50) }, { move: S(230, 50) }, { move: S(300, 250) },
      { action: { type: 'downplay', seriesIndex: 0, name: 'B' } }, { leave: true },
      { move: S(150, 50) }, { action: { type: 'highlight', seriesIndex: 0, name: 'B' } }, { leave: true },
      { move: S(230, 50) }, { leave: true }, { move: S(150, 50) }, { action: { type: 'downplay', seriesIndex: 0, name: 'B' } },
      { move: S(300, 250) }, { move: S(230, 50) }, { action: { type: 'highlight', seriesIndex: 0, name: 'B' } },
      { action: { type: 'downplay', seriesIndex: 0, name: 'B' } }, { move: S(300, 250) }, { move: S(230, 50) },
      { action: { type: 'downplay', seriesIndex: 0, name: 'B' } }, { leave: true }],
  },
  // ---- [r2v] ----
  {
    id: 'map-series-nested',
    note: "[r2v] a map series with data for H and for N, the self-named rect inside the self-named group H: the pointer on N's rect finds the OUTERMOST dispatcher (findEventDispatcher without returnFirstMatch), H -- H lifts, its other rect with it; leave",
    maps: [{ map: 'svHit', svg: 'svHit' }],
    option: { animation: false, series: [{ type: 'map', map: 'svHit', data: [{ name: 'H', value: 1 }, { name: 'N', value: 2 }] }] },
    steps: [{ move: S(305, 165) }, { leave: true }],
  },
];

// ============================================================================
// guards
// ============================================================================
function guards(out) {
  const g = [];
  const add = (id, ok, detail) => g.push({ id, ok: !!ok, detail });
  const tryAdd = (id, f, detail) => { let ok = false; try { ok = f(); } catch (e) { ok = false; } add(id, ok, detail); };
  const C = id => { const c = out.find(x => x.id === id); must(c, 'no case ' + id); return c; };
  let c = C('parse-rich');
  let t = c.trees[0];
  const named = t.named.map(n => n.name);
  add('defs-skip', !named.includes('inDefs'), 'a named element in defs is not drawn nor named');
  add('switch-pass', named.includes('sw'), 'switch passes its children through');
  add('a-skip', !named.includes('inA'), 'an <a> is not a parser: skipped with its children');
  add('empty-name', !t.els.some((e, i) => false) && named.indexOf('') < 0, 'an empty name is no name');
  const pa = t.named.filter(n => n.name === 'pa');
  add('dup-name', pa.length === 2 && t.regions.filter(r => r.name === 'pa').length === 2, 'two elements of one name: two regions');
  const pa2 = t.els[pa[1].el];
  const ups = t.els.filter(e => e.t === 'path' && e.sh && e.sh.d && fromHex(e.sh.d[1]) >= 500);
  add('attr-over-inline', pa2.st.fill === '#654321' && ups.length === 2 && ups[1].st.fill === '#654321',
    'an attribute overrides the inline style (zrender reads the attributes after)');
  add('root-inline-only', t.els.some(e => e.t === 'rect' && e.st && e.st.fill === '#336699'), "the root's inline fill reaches the children, its fill attribute not");
  add('url-missing', ups.length === 2 && ups[0].st.stroke === null && ups[0].st.fill === '#123456', 'url(#missing) (over the inline stroke): no stroke');
  add('grad', typeof t.els.find(e => e.t === 'circle').st.fill === 'object', 'url(#lg) is the gradient');
  add('hidden', t.els[t.named.find(n => n.name === 'hidden').el].inv, 'visibility hidden: invisible');
  add('gone', t.els[t.named.find(n => n.name === 'gone').el].ign, 'display none: ignored');
  add('named-default-style', t.els[t.named.find(n => n.name === 'bg').el].st.lw === hex(0.5)
    && t.els[t.named.find(n => n.name === 'bg').el].st.noScale, "the geo's default borderWidth 0.5 on a named shape, strokeNoScale");
  add('group-children-named', t.named.filter(n => n.from === t.named.findIndex(m => m.name === 'grpA')).length >= 4, "a named group's descendants are named from it");
  add('aspect-1', fromHex(c.trees[0].view.dataRect[2]) === 300, 'the data rect is the svg width');
  c = C('parse-rects');
  add('rect-vb', c.trees[0].rect.map(fromHex).join() === '-50.5,-20,200,100', 'viewBox only: the viewBox');
  add('rect-wonly', c.trees[2].rect.map(fromHex).join() === '0,20,240,60', 'width only: x 0, the viewBox y and height');
  add('rect-pct', fromHex(c.trees[3].rect[2]) === 50 && fromHex(c.trees[3].rect[3]) === 80, "'50%' reads 50, 'none' is no viewBox");
  add('centre-quirk', (() => { const r = c.trees[4].regions.find(x => x.name === 'c'); return r && fromHex(r.c[0]) !== 80; })(), 'calcCenter applies the inverse of the transform chain');
  c = C('register-errors');
  add('bad-svg', c.registered.every(x => !x) && c.throws, 'a broken SVG is refused');
  c = C('projection-throws');
  add('proj', !!c.throws, 'a projection on an SVG map throws');
  c = C('hover-default');
  const tr = c.trees[0];
  const idx = n => tr.named.find(x => x.name === n && x.from < 0).el;
  const item = (st, i) => st.draws[0].items.find(x => x.i === i);
  add('hover-z2', item(c.states[1], idx('A')).states === 'emphasis' && item(c.states[1], idx('A')).z2 === 0, 'emphasis, no z2 lift');
  const bs = tr.named.filter(x => x.name === 'B').map(x => x.el);
  add('hover-dup', item(c.states[2], bs[0]).states === 'emphasis' && item(c.states[2], bs[1]).states === 'emphasis',
    "a component's high-down by name: every dispatcher of the name (both B)");
  add('hover-group', item(c.states[4], idx('G')).label && !item(c.states[4], idx('G')).label.ignore, "the group's label shows");
  add('bg-silent', c.probes.length && c.states[0].hits[14] === null, 'the unnamed background is silent');
  add('stroke-hit', c.states[0].hits[8] && c.states[0].hits[8].name === 'C' && c.states[0].hits[7] === null, 'a fill-less circle: its stroke');
  c = C('select');
  tryAdd('select-dup', () => { const ev = c.states[1].events.map(e => e.type); return ev.indexOf('geoselectchanged') >= 0 && ev.indexOf('geoselectchanged') < ev.indexOf('click'); },
    'geoselectchanged before the click');
  c = C('focus-self');
  add('blur-bg', c.states[1].draws[0].items.find(x => x.i === 2).states === 'blur', 'the unnamed background blurs');
  c = C('map-series');
  add('map-visual', c.states[0].draws[0].items.some(x => x.fill && x.fill.startsWith('rgba')), 'visualMap colours a region');
  c = C('geo-series');
  add('custom-calls', c.states[0].series[3].calls.length === 2, 'the custom series ran');
  c = C('gallery-beef');
  add('beef-regions', c.trees[0].regions.length === 29, 'Beef cuts: 29 regions');
  // [R2-B] a map series: the element under the pointer alone, the action's the last one
  c = C('map-series-same-name');
  const bs2 = c.trees[0].named.filter(x => x.name === 'B').map(x => x.el);
  const st2 = (k, i) => c.states[k].draws[0].items.find(x => x.i === i).states;
  add('map-dup-hover', st2(1, bs2[0]) === 'emphasis' && st2(1, bs2[1]) === '' && st2(2, bs2[1]) === 'emphasis' && st2(2, bs2[0]) === '',
    'a map series lifts the element under the pointer alone');
  add('map-dup-action', st2(4, bs2[1]) === 'emphasis' && st2(4, bs2[0]) === '', 'highlight by name: the last element registered alone');
  // [R2-I1] moving off the unheld one of the name takes it down
  c = C('map-series-held-move-off');
  const bs3 = c.trees[0].named.filter(x => x.name === 'B').map(x => x.el);
  const st3 = (k, i) => c.states[k].draws[0].items.find(x => x.i === i).states;
  add('map-held-move-off', st3(2, bs3[0]) === 'emphasis' && st3(3, bs3[0]) === '' && st3(3, bs3[1]) === 'emphasis'
    && st3(5, bs3[0]) === '' && st3(7, bs3[0]) === '' && st3(7, bs3[1]) === 'emphasis'
    && st3(17, bs3[0]) === 'emphasis' && st3(21, bs3[1]) === '' && st3(24, bs3[1]) === '',
    'the unheld B leaves emphasis when the pointer moves off; a downplay reaches the last one alone');
  // [r2v] the outermost dispatcher over the pointer
  c = C('map-series-nested');
  const hs = c.trees[0].named.filter(x => x.name === 'H').map(x => x.el);
  const st4 = (k, i) => c.states[k].draws[0].items.find(x => x.i === i).states;
  add('map-nested-outermost', hs.length === 2 && hs.every(i => st4(1, i) === 'emphasis') && hs.every(i => st4(2, i) === ''),
    'the pointer on N inside H lifts H, its other rect with it');
  return g;
}

// ---------- the tokens ----------
const TOKENS = (() => {
  registerMaps([{ map: 'svHit', svg: 'svHit' }]);
  const chart = mk();
  chart.setOption({ animation: false, geo: { map: 'svHit' } });
  const o = chart.getModel().getComponent('geo', 0).option;
  const lift = x => echarts.color.lift(x, -0.1);
  const t = { border: o.itemStyle.borderColor, label: o.label.color, highlight: o.emphasis.itemStyle.color,
    labelHighlight: o.emphasis.label.color };
  must(o.itemStyle.color === undefined, 'no colour default for an SVG map');
  t.liftedBorder = lift(t.border);
  t.liftedHighlight = lift(t.highlight);
  chart.dispose();
  chart.setOption && 0;
  const c2 = mk();
  c2.setOption({ animation: false, series: [{ type: 'map', map: 'svHit' }] });
  const so = c2.getModel().getSeriesByIndex(0).option;
  t.mapArea = so.itemStyle.areaColor;
  t.mapHighlight = so.emphasis.itemStyle.areaColor;
  c2.dispose();
  return t;
})();

function generate() {
  const out = CASES.map(runCase);
  if (process.env.ORACLE_DEBUG) fs.writeFileSync(process.env.ORACLE_DEBUG, JSON.stringify(out, null, 1));
  const g = guards(out);
  const doc = {
    source: 'tools/advchart-oracle/geo-svg.js against ' + path.basename(DIST) + ' (ECharts 6.1)',
    W, H,
    tokens: TOKENS,
    svgs: SVGS.map(s => (s.text != null ? { name: s.name, text: s.text } : { name: s.name, file: s.file })),
    notes: [
      'Every case is a new chart, its maps registered afresh as {svg: text}; animation false; a tooltip hides at once and sits at [5, 5].',
      'Text is measured with zrender\'s width table (the server-side fallback): width = sum of ratio * font size over the characters, the font size the first number before px in the font string, a font with mono in it fontSize * length.',
      'A click is mousemove, mousedown, mouseup, click; a drag moves between a press and a release, then a click; leave is the handler\'s mouseout.',
      'After every step: chart._onframe() and a display-list refresh.',
      'Region centres are asked once, after the first frame (GeoSVGRegion caches them).',
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
  JSON.parse(textA);
  fs.writeFileSync(OUT, textA + '\n');
  let states = 0;
  a.doc.cases.forEach(c => { states += (c.states || []).length; });
  console.log('wrote ' + OUT + ': ' + a.doc.cases.length + ' cases, ' + states + ' states, ' + a.doc.guards.length + ' guards, '
    + Math.round(textA.length / 1024) + ' KB');
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e.stack);
  process.exit(1);
}
