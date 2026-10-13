/*
Upstream's own answers for roadmap batch D14 GE4 [Batch 152]: the map series
and the series on a geo -- chart/map/MapSeries.ts (getInitialData's appended
regions and echartsStyle merge, getHostGeoModel, formatTooltip, the defaults,
buildAllMapSeriesGroups), chart/map/mapDataStatistic.ts (sum / average / max /
min over a group's filtered series), chart/map/mapSymbolLayout.ts (the legend
symbols' offsets and showLabel), chart/map/MapView.ts (the region picture of a
group's main series, the legend symbols and their labels),
component/helper/MapDraw.ts' series path (the data's visual fill, the label
rule isDataNaN || showLabel, the region group as the item's graphic element),
coord/geo/geoCreator.ts (the geo of a map series group: the first declared
series' layout, the group's nameMaps merged), the legacy mapToggleSelect /
mapSelect / mapUnSelect actions; and the series that sit on a geo --
scatter / effectScatter through layout/points.ts (clipped by
createCoordSysClipAreaSimply when the geo clips), lines, pie (a box layout
reference by point: createBoxLayoutReference without dataToLayout), custom
(coord/geo/prepareCustom.ts: api.coord, api.size), graph, heatmap
(HeatmapView._renderOnGeo with HeatmapLayer) and brush with geoIndex
(BrushTargetManager's geo target, the rect / polygon coordConvert); every
series on a geo laid out again after a geoRoam (updateTransform).

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), the recipe of
geo-interact.js / geo-roam.js (chart._ssr = false, env.node off, getDom
stubbed, the controlled clock), every option `animation: false`, a tooltip
`hideDelay: 0` and `position: [5, 5]`. Pointer steps go through zrender's
own Handler; after every step the chart runs chart._onframe() and a
display-list refresh. A renderItem written '@name' is RENDER[name] here and
a handler of the same arithmetic in the port.

THE HEATMAP LAYER draws on a canvas: a circle shadow-blurred into a brush
image, the brush drawn at every point with the point's alpha, the alpha
channel then coloured through the visualMap's gradient. Node has no canvas,
so this script installs one (setPlatformAPI's createCanvas) that records
every call and answers getImageData with a REFERENCE raster -- the shadow
the SVG specification's three-box approximation of a Gaussian of sigma
blurSize / 2 over the disc's pixel-centre coverage, in integers, drawn
source-over at the offset Math.round gives. The colouring that follows is
upstream's own code on those bytes; the port draws the same reference
raster and must colour it the same, byte for byte.

  node tools/advchart-oracle/geo-series.js

writes tests/fixtures/advchart-geo-series.json (ORACLE_OUT overrides).
Ends with process.exit().

Conventions
  hex   a double as the 16 hex digits of its IEEE-754 bits (big-endian).
  pt    [hx, hy] or null.

Top level
  source, maps [{name, text}], notes[], cases[], guards[].

Per case
  id, note, W, H, option, steps[] (as run, targets resolved to pixels):
  {move: [x, y]}; {click: [x, y]} (mousemove, mousedown, mouseup, click);
  {drag: [[x, y], ...]}; {wheel: [x, y, delta]} (delta the LCL WheelDelta);
  {leave: true}; {action: payload}; {setOption: option, notMerge}.
  states[] index-parallel to [after setOption, after step 1, ...]:
    events[]  mouse events {type, componentType, seriesIndex, dataIndex,
              name}; action events {type, json}
    tip       null or {text}
    draws[]   every MapDraw: {owner: 'geo' i | 'series' i, overall [6 hex],
              view [4 hex], groups[] {name, ds (the data index on the
              group: null for a geo's own), hover, selected, paths[]
              {states, fill, stroke, lw (hex), z2, label null | {ignore,
              text, fill, tx, ty (hex; null while ignored)}}}}
    series[]  per series index: null, or by type:
      map      {symbols[] {cx, cy (hex), r, fill, z2, label null |
               {ignore, text, tx, ty}}}
      scatter / effectScatter  {items[] {i, p (pt of the layout), el
               (drawn), size [w, h], fill, z2, ripples}}
      lines    {items[] {i, pts [pt...] (the layout), el}}
      pie      {items[] {i, cx, cy, r0, r, sa, ea (hex)}}
      graph    {nodes[] {i, p}}
      custom   {calls[] {i, coord: [[in], pt], size: [[in], [out]]},
               coordSys, els[] {type, shape {k: hex}}}
      heatmap  {img {x, y, w, h (hex)}, draws [[xr, yr, alpha hex]],
               px (base64 of the coloured RGBA bytes)}
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-geo-series.json');
const EXAMPLES = process.env.ECHARTS_EXAMPLES || 'D:/Projects/echarts-examples';
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
const pt = p => (p && p.length >= 2 && p[0] != null ? [hex(+p[0]), hex(+p[1])] : null);
const clone = v => JSON.parse(JSON.stringify(v));

// ---------- the heatmap canvas ----------
// Every canvas the dist asks for. measureText may take one of these (it
// caches the first context it gets): it answers with zrender's own width
// table, the fallback node takes without a canvas.
const WIDTH_TABLE = (function () {
  // zrender's DEFAULT_TEXT_WIDTH_MAP, built as the dist builds it
  const map = {};
  const text = '007LLmW\'55;N0500LLLLLLLLLL00NNNLzWW\\\\WQb\\0FWLg\\bWb\\WQ\\WrWWQ000CL5LLFLL0LL**F*gLLLL5F0LF\\FFF5.5N';
  for (let i = 0; i < text.length; i++) {
    map[String.fromCharCode(i + 32)] = (text.charCodeAt(i) - 20) / 100;
  }
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
let HM_LOG = null;
class StubCanvas {
  constructor() {
    this._w = 300;
    this._h = 150;
    this.alpha = new Float64Array(0);
    this._ctx = null;
    this.brushOf = null;
  }
  get width() { return this._w; }
  set width(v) { this._w = v | 0; this.alpha = new Float64Array(this._w * this._h); }
  get height() { return this._h; }
  set height(v) { this._h = v | 0; this.alpha = new Float64Array(this._w * this._h); }
  getContext() {
    if (!this._ctx) this._ctx = new StubCtx(this);
    return this._ctx;
  }
  toDataURL() { return 'data:,'; }
}
class StubCtx {
  constructor(canvas) {
    this.canvas = canvas;
    this.font = '12px sans-serif';
    this.globalAlpha = 1;
    this.shadowOffsetX = 0;
    this.shadowBlur = 0;
    this.shadowColor = '';
    this._arc = null;
    this.putBytes = null;
  }
  measureText(t) { return tableWidth(t, this.font); }
  clearRect() { this.canvas.alpha.fill(0); }
  beginPath() { this._arc = null; }
  arc(x, y, r) { this._arc = { x, y, r }; }
  closePath() {}
  fill() {
    // the brush: the disc's shadow, offset by shadowOffsetX, blurred
    const c = this.canvas;
    const a = this._arc;
    must(a, 'a fill without an arc');
    const cx = a.x + this.shadowOffsetX;
    const cy = a.y;
    c.brushOf = { blur: this.shadowBlur, r: a.r, cx, cy, color: this.shadowColor };
    c.alpha = referenceBrush(c._w, c._h, cx, cy, a.r, this.shadowBlur);
  }
  drawImage(img, x, y) {
    const c = this.canvas;
    const ga = this.globalAlpha;
    const ox = Math.round(x);
    const oy = Math.round(y);
    if (HM_LOG) HM_LOG.draws.push([hex(x), hex(y), hex(ga)]);
    if (Number.isNaN(ox) || Number.isNaN(oy)) return;
    const bw = img._w;
    const bh = img._h;
    for (let j = 0; j < bh; j++) {
      const ty = oy + j;
      if (ty < 0 || ty >= c._h) continue;
      for (let i = 0; i < bw; i++) {
        const tx = ox + i;
        if (tx < 0 || tx >= c._w) continue;
        const s = img.alpha[j * bw + i] * ga;
        const k = ty * c._w + tx;
        c.alpha[k] = s + c.alpha[k] * (1 - s);
      }
    }
  }
  getImageData(x, y, w, h) {
    const c = this.canvas;
    const data = new Uint8ClampedArray(w * h * 4);
    for (let k = 0; k < w * h; k++) data[k * 4 + 3] = Math.floor(c.alpha[k] * 255 + 0.5);
    return { data, width: w, height: h };
  }
  putImageData(img) {
    this.putBytes = Buffer.from(img.data.buffer, img.data.byteOffset, img.data.byteLength).toString('base64');
    if (HM_LOG) HM_LOG.px = this.putBytes;
  }
}
// THE REFERENCE SHADOW, in integers so the port can draw the same bytes:
// the disc's coverage at pixel centres (255 inside), blurred the way the SVG
// specification approximates a Gaussian of sigma blur / 2 -- three box
// blurs of d = floor(sigma * 3 * sqrt(2 pi) / 4 + 0.5) (an even d: two of d,
// one either side of the pixel, and one of d + 1) along x, then the same
// along y, each box sum rounded to a byte -- and each brush pixel's alpha
// that byte over 255.
function boxPass(src, w, h, size, off, vertical) {
  const out = new Int32Array(w * h);
  const half = Math.floor(size / 2);
  for (let j = 0; j < h; j++) {
    for (let i = 0; i < w; i++) {
      let sum = 0;
      for (let k = 0; k < size; k++) {
        if (vertical) {
          const jj = j - off + k;
          if (jj >= 0 && jj < h) sum += src[jj * w + i];
        }
        else {
          const ii = i - off + k;
          if (ii >= 0 && ii < w) sum += src[j * w + ii];
        }
      }
      out[j * w + i] = Math.floor((sum + half) / size);
    }
  }
  return out;
}
function referenceBrush(w, h, cx, cy, r, blur) {
  let cur = new Int32Array(w * h);
  for (let j = 0; j < h; j++) {
    for (let i = 0; i < w; i++) {
      const dx = i + 0.5 - cx;
      const dy = j + 0.5 - cy;
      cur[j * w + i] = dx * dx + dy * dy <= r * r ? 255 : 0;
    }
  }
  const sigma = blur / 2;
  const d = sigma > 0 ? Math.floor(sigma * 3 * Math.sqrt(2 * Math.PI) / 4 + 0.5) : 0;
  if (d >= 1) {
    const passes = d % 2 === 1
      ? [[d, (d - 1) / 2], [d, (d - 1) / 2], [d, (d - 1) / 2]]
      : [[d, d / 2], [d, d / 2 - 1], [d + 1, d / 2]];
    for (const [size, off] of passes) cur = boxPass(cur, w, h, size, off, false);
    for (const [size, off] of passes) cur = boxPass(cur, w, h, size, off, true);
  }
  const out = new Float64Array(w * h);
  for (let k = 0; k < w * h; k++) out[k] = cur[k] / 255;
  return out;
}
echarts.setPlatformAPI({ createCanvas() { return new StubCanvas(); } });

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

// ---------- the maps ----------
function sq(x0, y0, x1, y1) { return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]; }
function rev(r) { return r.slice().reverse(); }
function feat(name, geometry, extra) {
  return { type: 'Feature', properties: Object.assign({ name }, extra || {}), geometry };
}
function g4() {
  return {
    type: 'FeatureCollection',
    features: [
      feat('A', { type: 'Polygon', coordinates: [sq(0, 0, 10, 10)] }),
      feat('B', { type: 'Polygon', coordinates: [sq(10, 0, 20, 10)] }),
      feat('C', { type: 'Polygon', coordinates: [sq(0, 10, 10, 20)] }),
      feat('D', { type: 'Polygon', coordinates: [sq(10, 10, 20, 20), rev(sq(13, 13, 17, 17))] }),
      feat('E', { type: 'LineString', coordinates: [[23, 0], [23, 20]] }),
      feat('F', { type: 'MultiPolygon', coordinates: [[sq(25, 0, 30, 5)], [sq(25, 10, 30, 15)]] }),
      feat('G', { type: 'Polygon', coordinates: [sq(0, 20, 10, 25)] },
        { echartsStyle: { itemStyle: { areaColor: '#99ccff' }, label: { show: true } } }),
    ],
  };
}
function g2() {
  return {
    type: 'FeatureCollection',
    features: [
      feat('P', { type: 'Polygon', coordinates: [sq(0, 0, 8, 8)] }),
      feat('Q', { type: 'Polygon', coordinates: [sq(8, 0, 16, 8)] }),
    ],
  };
}
function readJson(p) { return JSON.parse(fs.readFileSync(p, 'utf8')); }
function box(x0, y0, x1, y1) { return [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]]; }
// geo.js' hand-made 'china'
const CHINA = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', properties: { name: '北京' }, geometry: { type: 'Polygon', coordinates: box(115.5, 39.5, 117.3, 41) } },
    { type: 'Feature', properties: { name: '天津' }, geometry: { type: 'Polygon', coordinates: box(116.8, 38.6, 118, 40.2) } },
    { type: 'Feature', properties: { name: '广东' }, geometry: { type: 'Polygon', coordinates: [[[109.7, 20.2], [117.2, 23.5], [116, 25.4], [111, 25.2], [109.7, 20.2]]] } },
    { type: 'Feature', properties: { name: '香港' }, geometry: { type: 'Polygon', coordinates: box(113.85, 22.15, 114.4, 22.55) } },
    { type: 'Feature', properties: { name: '澳门' }, geometry: { type: 'Polygon', coordinates: box(113.52, 22.1, 113.6, 22.22) } },
    { type: 'Feature', properties: { name: '台湾' }, geometry: { type: 'Polygon', coordinates: [[[120.1, 22.0], [121.9, 25.2], [121.5, 25.3], [120.0, 23.2], [120.1, 22.0]]] } },
  ],
};
const MAPS = [
  { name: 'g4', text: JSON.stringify(g4()) },
  { name: 'g2', text: JSON.stringify(g2()) },
  { name: 'USA', text: JSON.stringify(readJson(path.join(EXAMPLES, 'public/data/asset/geo/USA.json'))) },
  { name: 'iceland', text: JSON.stringify(readJson(path.join(EXAMPLES, 'public/data/asset/geo/iceland.geo.json'))) },
  { name: 'ch', text: JSON.stringify(readJson(path.join(EXAMPLES, 'public/data/asset/geo/ch.geo.json'))) },
  { name: 'china', text: JSON.stringify(CHINA) },
];
const USA_SPECIAL = {
  Alaska: { left: -131, top: 25, width: 15 },
  Hawaii: { left: -110, top: 28, width: 5 },
  'Puerto Rico': { left: -76, top: 26, width: 2 },
};
function registerMaps() {
  for (const m of MAPS) {
    if (m.name === 'USA') echarts.registerMap(m.name, m.text, USA_SPECIAL);
    else echarts.registerMap(m.name, m.text);
  }
}

// ---------- the renderItems ----------
const RENDER = {
  // a rect two by one degrees round each point, through api.coord / api.size
  geoRect(params, api) {
    const v = [api.value(0), api.value(1)];
    const p = api.coord(v);
    const s = api.size([2, 1], v);
    CU_LOG.push({ i: params.dataIndex, coord: [v.map(hex), pt(p)], size: [[hex(2), hex(1), hex(v[0]), hex(v[1])], s.map(hex)] });
    CU_SYS = params.coordSys;
    return { type: 'rect', shape: { x: p[0] - s[0] / 2, y: p[1] - s[1] / 2, width: s[0], height: s[1] },
      style: { fill: api.visual('color') } };
  },
  // a line between two points: coord with a region name is not taken by
  // api.coord (numbers only), so two pairs
  geoSeg(params, api) {
    const a = api.coord([api.value(0), api.value(1)]);
    const b = api.coord([api.value(2), api.value(3)]);
    CU_LOG.push({ i: params.dataIndex, coord: [[api.value(0), api.value(1)].map(hex), pt(a)] });
    CU_LOG.push({ i: params.dataIndex, coord: [[api.value(2), api.value(3)].map(hex), pt(b)] });
    CU_SYS = params.coordSys;
    return { type: 'line', shape: { x1: a[0], y1: a[1], x2: b[0], y2: b[1] }, style: { stroke: '#333', lineWidth: 2 } };
  },
};
let CU_LOG = [];
let CU_SYS = null;
function withHandlers(v) {
  if (Array.isArray(v)) return v.map(withHandlers);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      if (k === 'renderItem' && typeof v[k] === 'string' && v[k][0] === '@') o[k] = RENDER[v[k].slice(1)];
      else o[k] = withHandlers(v[k]);
    }
    return o;
  }
  return v;
}

// ---------- reading ----------
function colour(c) {
  if (c == null) return null;
  if (typeof c === 'string') return c;
  return 'object';
}
function labelOf(p) {
  const t = p.getTextContent();
  if (!t) return null;
  const m = t.ignore ? null : t.innerTransformable.getLocalTransform([]);
  return {
    ignore: !!t.ignore,
    text: t.style.text == null ? null : String(t.style.text),
    fill: colour(t.style.fill),
    tx: m ? hex(m[4]) : null,
    ty: m ? hex(m[5]) : null,
  };
}
function readMapDraw(md, owner, geo) {
  const v = geo.view;
  const vr = v.getViewRect();
  const o = { owner, overall: Array.from(v.mtOverall).map(hex),
    view: [vr.x, vr.y, vr.width, vr.height].map(hex), groups: [] };
  for (const g of md._regionsGroup.children()) {
    const inner = innerOf(g);
    let name = null;
    let ds = null;
    if (inner && inner.eventData) name = inner.eventData.name;
    if (inner && inner.dataIndex != null) {
      ds = { s: inner.seriesIndex, d: inner.dataIndex };
      name = null;
    }
    const rec = { name, ds, hover: g.hoverState || 0, selected: !!g.selected, paths: [] };
    for (const p of g.children()) {
      rec.paths.push({
        states: (p.currentStates || []).join(','),
        fill: colour(p.style.fill),
        stroke: colour(p.style.stroke),
        lw: p.style.lineWidth == null ? null : hex(p.style.lineWidth),
        opacity: p.style.opacity == null ? null : hex(p.style.opacity),
        z2: p.z2,
        label: labelOf(p),
      });
    }
    o.groups.push(rec);
  }
  // the names of a data-hosting draw, in group order
  if (o.groups.some(x => x.name === null)) {
    const names = [];
    md._regionsGroupByName.each((g, nm) => names.push([g, nm]));
    for (const rec of o.groups) {
      if (rec.name !== null) continue;
    }
    const byGroup = new Map(names);
    md._regionsGroup.children().forEach((g, i) => { if (o.groups[i].name === null) o.groups[i].name = byGroup.get(g); });
  }
  return o;
}
function draws(chart) {
  const out = [];
  const model = chart.getModel();
  model.eachComponent('geo', (gm, i) => {
    const view = chart.getViewOfComponentModel(gm);
    if (view && view._mapDraw) out.push(readMapDraw(view._mapDraw, 'geo ' + i, gm.coordinateSystem));
  });
  model.eachSeries(sm => {
    if (sm.subType !== 'map') return;
    const view = chart.getViewOfSeriesModel(sm);
    if (view && view._mapDraw && view.group.children().indexOf(view._mapDraw.group) >= 0) {
      out.push(readMapDraw(view._mapDraw, 'series ' + sm.seriesIndex, sm.coordinateSystem));
    }
  });
  return out;
}
function readSymbols(chart, sm) {
  const view = chart.getViewOfSeriesModel(sm);
  const out = [];
  for (const c of view.group.children()) {
    if (c.type !== 'circle') continue;
    out.push({ cx: hex(c.shape.cx), cy: hex(c.shape.cy), r: c.shape.r, fill: colour(c.style.fill), z2: c.z2, label: labelOf(c) });
  }
  return out;
}
function readScatter(sm) {
  const data = sm.getData();
  const items = [];
  for (let i = 0; i < data.count(); i++) {
    const el = data.getItemGraphicEl(i);
    let size = data.getItemVisual(i, 'symbolSize');
    if (!Array.isArray(size)) size = [size, size];
    let sym = null;
    let ripples = null;
    if (el) {
      sym = sm.subType === 'effectScatter' ? el.childAt(0).getSymbolPath() : el.getSymbolPath();
      if (sm.subType === 'effectScatter') ripples = el.childAt(1).childCount();
    }
    items.push({ i, p: pt(data.getItemLayout(i)), el: !!el, x: el ? hex(el.x) : null, y: el ? hex(el.y) : null,
      size: size.map(Number), fill: sym ? colour(sym.style.fill) : null, z2: sym ? sym.z2 : null,
      states: sym ? (sym.currentStates || []).join(',') : null, ripples });
  }
  return { items };
}
function readLines(sm) {
  const data = sm.getData();
  const items = [];
  for (let i = 0; i < data.count(); i++) {
    const lay = data.getItemLayout(i);
    items.push({ i, pts: lay ? lay.map(p => pt(p)) : null, el: !!data.getItemGraphicEl(i) });
  }
  return { items };
}
function readPie(sm) {
  const data = sm.getData();
  const items = [];
  for (let i = 0; i < data.count(); i++) {
    const l = data.getItemLayout(i);
    items.push({ i, cx: hex(l.cx), cy: hex(l.cy), r0: hex(l.r0), r: hex(l.r), sa: hex(l.startAngle), ea: hex(l.endAngle) });
  }
  return { items };
}
function readGraph(sm) {
  const data = sm.getData();
  const nodes = [];
  for (let i = 0; i < data.count(); i++) nodes.push({ i, p: pt(data.getItemLayout(i)), el: !!data.getItemGraphicEl(i) });
  return { nodes };
}
function shapeOf(el) {
  const s = {};
  for (const k of Object.keys(el.shape || {})) if (typeof el.shape[k] === 'number') s[k] = hex(el.shape[k]);
  return s;
}
function readCustom(chart, sm) {
  const view = chart.getViewOfSeriesModel(sm);
  const els = [];
  view.group.traverse(el => { if (el !== view.group && el.type !== 'group') els.push({ type: el.type, shape: shapeOf(el) }); });
  return { els };
}
function readHeatmap(chart, sm) {
  const view = chart.getViewOfSeriesModel(sm);
  const img = view.group.children().find(c => c.type === 'image');
  if (!img) return { img: null };
  return { img: [img.style.x, img.style.y, img.style.width, img.style.height].map(hex), silent: !!img.silent };
}
function seriesOf(chart) {
  const out = [];
  chart.getModel().eachRawSeries(sm => {
    const t = sm.subType;
    let r = null;
    if (chart.getModel().isSeriesFiltered(sm)) r = null;
    else if (t === 'map') r = { type: t, symbols: readSymbols(chart, sm) };
    else if (t === 'scatter' || t === 'effectScatter') r = Object.assign({ type: t }, readScatter(sm));
    else if (t === 'lines') r = Object.assign({ type: t }, readLines(sm));
    else if (t === 'pie') r = Object.assign({ type: t }, readPie(sm));
    else if (t === 'graph') r = Object.assign({ type: t }, readGraph(sm));
    else if (t === 'custom') r = Object.assign({ type: t }, readCustom(chart, sm));
    else if (t === 'heatmap') r = Object.assign({ type: t }, readHeatmap(chart, sm));
    out[sm.seriesIndex] = r;
  });
  for (let i = 0; i < out.length; i++) if (out[i] === undefined) out[i] = null;
  return out;
}
function tipNow(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  const view = m ? chart.getViewOfComponentModel(m) : null;
  if (!view) return null;
  const c = view._tooltipContent;
  if (!c || !c.el || !c._show) return null;
  const text = String(c.el.style.text);
  if (text.indexOf('__EC_aUTo_') < 0) return { text };
  // the markup's rich segments as rows (lines.js' reading): the marker, the
  // name, the value
  const rich = c.el.style.rich || {};
  return { rows: text.split('\n').map(line => {
    const row = { marker: null, name: null, value: null };
    SEGMENT.lastIndex = 0;
    let m;
    while ((m = SEGMENT.exec(line))) {
      const st = rich[m[1]] || {};
      if (st.width != null) row.marker = st.width === 10 ? 'item' : 'subItem';
      else if ((st.fontWeight != null && +st.fontWeight >= 700) || st.fontWeight === 'bold') row.value = m[2];
      else if (row.name === null && row.marker === null && st.align !== 'right') row.name = m[2];
      else row.value = m[2];
    }
    return row;
  }) };
}
const SEGMENT = /\{(__EC_aUTo_\d+)\|([^}]*)\}/g;

// ---------- targets ----------
function geoOf(chart, t, where) {
  const model = chart.getModel();
  if (t.series != null) {
    const sm = model.getSeriesByIndex(t.series);
    must(sm && sm.coordinateSystem, where + ': no geo of series ' + t.series);
    return sm.coordinateSystem;
  }
  const gm = model.getComponent('geo', t.geo || 0);
  must(gm, where + ': no geo ' + (t.geo || 0));
  return gm.coordinateSystem;
}
function resolvePoint(chart, t, where) {
  if (Array.isArray(t)) return t.slice();
  let p;
  if (t.item != null) {
    const sm = chart.getModel().getSeriesByIndex(t.item[0]);
    p = sm.getData().getItemLayout(t.item[1]);
    must(p, where + ': no layout for ' + JSON.stringify(t.item));
  }
  else {
    const geo = geoOf(chart, t, where);
    if (t.region !== undefined) {
      const regs = geo.regions.filter(r => r.name === t.region);
      must(regs.length > 0, where + ': no region ' + t.region);
      p = geo.dataToPoint(regs[0].getCenter());
    }
    else if (t.at) p = geo.dataToPoint(t.at);
    else throw new OracleError(where + ': an unknown target ' + JSON.stringify(t));
  }
  return [Math.round(p[0]) + (t.dx || 0), Math.round(p[1]) + (t.dy || 0)];
}
function resolveStep(chart, step, where) {
  const r = Object.assign({}, step);
  if (step.move) r.move = resolvePoint(chart, step.move, where);
  if (step.click) r.click = resolvePoint(chart, step.click, where);
  if (step.drag) r.drag = step.drag.map(t => resolvePoint(chart, t, where));
  if (step.wheel) {
    const q = resolvePoint(chart, step.wheel.at, where);
    r.wheel = [q[0], q[1], step.wheel.delta];
  }
  return r;
}

// ---------- a case ----------
const MOUSE = ['click', 'mouseover', 'mouseout', 'mousemove'];
// brushselected only where a case has a brush (the brush's visual stage
// fires an empty one on many an update otherwise)
const ACTION_EVENTS = ['georoam', 'selectchanged', 'legendselectchanged', 'geoselectchanged'];

function runCase(c) {
  registerMaps();
  const chart = mk(c.W, c.H);
  const events = [];
  for (const t of MOUSE) {
    chart.on(t, p => {
      events.push({ type: t, componentType: p.componentType == null ? null : p.componentType,
        seriesIndex: p.seriesIndex == null ? null : p.seriesIndex,
        dataIndex: p.dataIndex == null ? null : p.dataIndex,
        name: p.name == null ? null : String(p.name) });
    });
  }
  for (const t of ACTION_EVENTS.concat(c.option.brush ? ['brushselected'] : [])) {
    chart.on(t, e => events.push({ type: t, json: JSON.stringify(e) }));
  }
  const states = [];
  const steps = [];
  const hm = [];
  const snap = () => {
    chart._onframe();
    refresh(chart);
    const st = { events: events.splice(0), tip: tipNow(chart), draws: draws(chart), series: seriesOf(chart) };
    if (CU_LOG.length || CU_SYS) {
      st.custom = { calls: CU_LOG.splice(0),
        coordSys: CU_SYS ? { type: CU_SYS.type, x: hex(CU_SYS.x), y: hex(CU_SYS.y), width: hex(CU_SYS.width),
          height: hex(CU_SYS.height), zoom: hex(CU_SYS.zoom) } : null };
      CU_SYS = null;
    }
    if (hm.length) st.heat = hm.splice(0);
    return st;
  };
  const run = fn => {
    HM_LOG = { draws: [], px: null };
    fn();
    if (HM_LOG.draws.length || HM_LOG.px) hm.push(HM_LOG);
    HM_LOG = null;
  };
  CU_LOG = [];
  CU_SYS = null;
  try {
    run(() => chart.setOption(withHandlers(clone(c.option))));
    refresh(chart);
    states.push(snap());
    // convertToPixel / convertFromPixel by a series finder: the series' geo
    if (c.convert) {
      states[0].convert = c.convert.map(cv => (cv.value !== undefined
        ? { to: pt(chart.convertToPixel(clone(cv.finder), clone(cv.value))) }
        : { from: pt(chart.convertFromPixel(clone(cv.finder), clone(cv.pixel))) }));
    }
    (c.steps || []).forEach((step0, i) => {
      const where = c.id + ' step ' + i;
      const step = resolveStep(chart, step0, where);
      run(() => {
        if (step.move) fire(chart, 'mousemove', { zrX: step.move[0], zrY: step.move[1] });
        else if (step.click) {
          fire(chart, 'mousemove', { zrX: step.click[0], zrY: step.click[1] });
          fire(chart, 'mousedown', { zrX: step.click[0], zrY: step.click[1] });
          fire(chart, 'mouseup', { zrX: step.click[0], zrY: step.click[1] });
          fire(chart, 'click', { zrX: step.click[0], zrY: step.click[1] });
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
      });
      steps.push(step);
      states.push(snap());
    });
  } finally {
    chart.dispose();
  }
  return { id: c.id, note: c.note, W: c.W || W, H: c.H || H, option: c.option, convert: c.convert || [], steps, states };
}

// ---------- the cases ----------
const TIP = { hideDelay: 0, position: [5, 5] };
function opt(extra) { return Object.assign({ animation: false }, extra); }
function gallery(name) { return JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8')); }
const SC_DATA = [[2, 3, 10], [15, 5, 20], [5, 15, 30], ['x', 5, 5], [18, 22, 40], [28, 2, 15], [-3, 12, 8]];

const CASES = [
  // ======== the map series ========
  {
    id: 'map-basic',
    note: "a map series on its own geo: the data's names (one not on the map, one '-'), a data item with its own itemStyle and label; the regions not in the data appended; G's echartsStyle merged into its appended item; labels on the NaN regions only (no legend); hover through the regions; the default tooltip",
    option: opt({ tooltip: Object.assign({}, TIP),
      series: [{ type: 'map', map: 'g4', name: 'm',
        data: [{ name: 'A', value: 10 }, { name: 'B', value: 20 }, { name: 'X', value: 5 }, { name: 'D', value: '-' },
          { name: 'C', value: 7, itemStyle: { areaColor: '#0000ff' }, label: { show: true } }] }] }),
    steps: [{ move: { series: 0, region: 'A' } }, { move: { series: 0, region: 'C' } }, { move: { series: 0, at: [23, 10] } },
      { move: { series: 0, region: 'D' } }, { leave: true }],
    convert: [{ finder: { seriesIndex: 0 }, value: [5, 5] }, { finder: { seriesIndex: 0 }, value: 'C' },
      { finder: { seriesIndex: 0 }, pixel: [300, 200] }, { finder: { seriesId: 'nope' }, value: [5, 5] }],
  },
  {
    id: 'map-visualmap',
    note: 'a continuous visualMap colours the regions (the data visual over the areaColor); a NaN region keeps the areaColor',
    option: opt({ visualMap: { min: 0, max: 30, inRange: { color: ['#ffffff', '#ff0000'] } },
      series: [{ type: 'map', map: 'g4', data: [{ name: 'A', value: 0 }, { name: 'B', value: 15 }, { name: 'C', value: 30 }, { name: 'F', value: 22.5 }] }] }),
  },
  {
    id: 'map-piecewise',
    note: 'a piecewise visualMap with outOfRange: the pieces colour the regions',
    option: opt({ visualMap: { type: 'piecewise', pieces: [{ min: 0, max: 10, color: '#00aa00' }, { min: 10, max: 20, color: '#aa0000' }],
      outOfRange: { color: '#999999' } },
    series: [{ type: 'map', map: 'g4', data: [{ name: 'A', value: 5 }, { name: 'B', value: 15 }, { name: 'C', value: 25 }] }] }),
  },
  {
    id: 'map-group',
    note: "three map series on one map with a legend: the statistic (mapValueCalculation of the first, 'average'), the legend symbols with their offsets and labels; a region tooltip names the series with a value there; the legend switches the first series off -- the second draws the map, the statistic now the second's 'sum' default; then the third off too",
    option: opt({ legend: {}, tooltip: Object.assign({ trigger: 'item' }, TIP),
      series: [
        { type: 'map', map: 'g4', name: 's1', mapValueCalculation: 'average', data: [{ name: 'A', value: 4 }, { name: 'B', value: 8 }, { name: 'X', value: 1 }] },
        { type: 'map', map: 'g4', name: 's2', data: [{ name: 'A', value: 6 }, { name: 'C', value: 3 }, { name: 'B', value: '-' }] },
        { type: 'map', map: 'g4', name: 's3', mapValueCalculation: 'max', data: [{ name: 'A', value: 11 }, { name: 'D', value: 2 }] },
      ] }),
    steps: [{ move: { series: 0, region: 'A', dx: 4, dy: -4 } }, { move: { series: 0, region: 'B' } }, { leave: true },
      { action: { type: 'legendToggleSelect', name: 's1' } }, { move: { series: 1, region: 'A', dx: 4, dy: -4 } },
      { leave: true }, { action: { type: 'legendToggleSelect', name: 's3' } }],
  },
  {
    id: 'map-calc',
    note: "mapValueCalculation max / min on the first series of a group; showLegendSymbol false (a legend, no symbols: every region labelled by showLabel)",
    option: opt({ legend: {},
      series: [
        { type: 'map', map: 'g4', name: 'p', mapValueCalculation: 'max', showLegendSymbol: false, data: [{ name: 'A', value: 4 }, { name: 'B', value: 9 }] },
        { type: 'map', map: 'g4', name: 'q', showLegendSymbol: false, data: [{ name: 'A', value: 6 }, { name: 'B', value: 2 }] },
        { type: 'map', map: 'g2', name: 'r', mapValueCalculation: 'min', left: 400, top: 250, width: 150, height: 100, data: [{ name: 'P', value: 5 }] },
        { type: 'map', map: 'g2', name: 's', left: 0, width: 10, data: [{ name: 'P', value: 1 }, { name: 'Q', value: 7 }] },
      ] }),
  },
  {
    id: 'map-calc-min',
    note: "mapValueCalculation min on the first series of a group whose second series has a smaller value at one name and a larger at the other: the statistic in the visual fill and the tooltip",
    option: opt({ tooltip: Object.assign({ trigger: 'item' }, TIP),
      visualMap: { min: 0, max: 10, inRange: { color: ['#ffffff', '#ff0000'] } },
      series: [
        { type: 'map', map: 'g2', name: 'r', mapValueCalculation: 'min', data: [{ name: 'P', value: 5 }, { name: 'Q', value: 3 }] },
        { type: 'map', map: 'g2', name: 's', data: [{ name: 'P', value: 1 }, { name: 'Q', value: 7 }] },
      ] }),
    steps: [{ move: { series: 0, region: 'P' } }, { move: { series: 0, region: 'Q' } }, { leave: true }],
  },
  {
    id: 'map-cs-written',
    note: "a map series is on a geo whatever coordinateSystem it writes: a name no coordinate system has, and 'radar' with no radar component -- each draws its map",
    option: opt({
      series: [
        { type: 'map', map: 'g4', name: 'n', coordinateSystem: 'nope', data: [{ name: 'A', value: 4 }] },
        { type: 'map', map: 'g2', name: 'r', coordinateSystem: 'radar', left: 400, top: 250, width: 150, height: 100, data: [{ name: 'P', value: 5 }] },
      ] }),
  },
  {
    id: 'map-on-geo',
    note: "a map series on a geo component (geoIndex): the geo draws the regions with the series' data -- the visual fill, labels always (the geo's), the regions the series' items (events and tooltip the series')",
    option: opt({ tooltip: Object.assign({}, TIP),
      visualMap: { min: 0, max: 20, inRange: { color: ['#e0f3f8', '#313695'] }, seriesIndex: 0, hoverLink: false },
      geo: { map: 'g4', label: { show: true } },
      series: [{ type: 'map', geoIndex: 0, name: 'on', data: [{ name: 'A', value: 5 }, { name: 'B', value: 20 }, { name: 'D', value: 12 }] }] }),
    convert: [{ finder: { seriesIndex: 0 }, value: [15, 5] }, { finder: { seriesIndex: 0 }, pixel: [200, 300] }],
    steps: [{ move: { region: 'A' } }, { move: { region: 'D', dx: -6, dy: -6 } }, { click: { region: 'B' } }, { leave: true }],
  },
  {
    id: 'map-layout',
    note: "the series' own geo laid out from the first declared series: a box, zoom and centre, aspectScale, nameMap (merged over the group); a second series on the same map with other layout options shares that geo; layoutCenter + layoutSize on another map",
    option: opt({
      series: [
        { type: 'map', map: 'g4', left: 20, top: 30, width: 300, height: 250, zoom: 1.5, center: [12, 12], aspectScale: 1,
          nameMap: { A: 'Alpha' }, data: [{ name: 'Alpha', value: 3 }, { name: 'B', value: 4 }] },
        { type: 'map', map: 'g4', left: 300, nameMap: { B: 'Beta' }, data: [{ name: 'Beta', value: 1 }] },
        { type: 'map', map: 'g2', layoutCenter: ['80%', '70%'], layoutSize: 120, data: [{ name: 'P', value: 1 }] },
      ] }),
  },
  {
    id: 'map-select',
    note: "selectedMode 'multiple' on a map series: clicks select through the series' data (selectchanged); the legacy mapToggleSelect; the select action by name; selectedMode false: a click selects nothing",
    option: opt({
      series: [
        { type: 'map', map: 'g4', selectedMode: 'multiple', left: 10, width: 280, data: [{ name: 'A', value: 1 }, { name: 'B', value: 2, selected: true }] },
        { type: 'map', map: 'g2', selectedMode: false, right: 10, width: 250, data: [{ name: 'P', value: 1 }] },
      ] }),
    steps: [{ click: { series: 0, region: 'A' } }, { click: { series: 0, region: 'C' } }, { click: { series: 0, region: 'A' } },
      { action: { type: 'mapToggleSelect', seriesIndex: 0, name: 'D' } }, { action: { type: 'select', seriesIndex: 0, name: 'F' } },
      { action: { type: 'unselect', seriesIndex: 0, name: 'B' } }, { click: { series: 1, region: 'P' } }],
  },
  {
    id: 'map-single',
    note: 'selectedMode true (the default) is single: a second click moves the selection',
    option: opt({ series: [{ type: 'map', map: 'g4', data: [{ name: 'A', value: 1 }] }] }),
    steps: [{ click: { series: 0, region: 'A' } }, { click: { series: 0, region: 'B' } }, { click: { series: 0, region: 'B' } }],
  },
  {
    id: 'map-label',
    note: "labels from the series: show with a template '{a}|{b}|{c}', an emphasis formatter, a data item's own label; hover shows the emphasis text",
    option: opt({
      series: [{ type: 'map', map: 'g4', name: 'L', label: { show: true, formatter: '{a}|{b}|{c}' },
        emphasis: { label: { formatter: '{b}!' } },
        data: [{ name: 'A', value: 3 }, { name: 'B', value: 4, label: { formatter: 'bee {c}' } }] }] }),
    steps: [{ move: { series: 0, region: 'A' } }, { move: { series: 0, region: 'B' } }, { leave: true }],
  },
  {
    id: 'map-states',
    note: "focus 'self' on a map series: hovering a region blurs the others; highlight / downplay by name",
    option: opt({
      series: [{ type: 'map', map: 'g4', emphasis: { focus: 'self', itemStyle: { areaColor: '#ffcc00' } }, blur: { itemStyle: { opacity: 0.3 } },
        data: [{ name: 'A', value: 1 }, { name: 'B', value: 2 }] }] }),
    steps: [{ move: { series: 0, region: 'A' } }, { leave: true }, { action: { type: 'highlight', seriesIndex: 0, name: 'B' } },
      { action: { type: 'downplay', seriesIndex: 0, name: 'B' } }],
  },
  {
    id: 'map-roam',
    note: "roam on a map series: a drag and a wheel dispatch geoRoam with componentType 'series' and the seriesId; a geoRoam by seriesIndex; the symbols follow",
    option: opt({ legend: {},
      series: [{ type: 'map', map: 'g4', name: 'r', roam: true, data: [{ name: 'A', value: 1 }, { name: 'C', value: 2 }] }] }),
    steps: [{ drag: [{ series: 0, region: 'B' }, { series: 0, region: 'B', dx: 10, dy: 5 }] },
      { wheel: { at: { series: 0, region: 'B' }, delta: 240 } },
      { action: { type: 'geoRoam', seriesIndex: 0, dx: -20, dy: 10 } }],
  },
  // ======== series on a geo ========
  {
    id: 'scatter-geo',
    note: 'scatter and effectScatter on a geo: the points through dataToPoint (a string lng is NaN: not drawn); hover a point; a geoRoam pan and zoom move the points (updateTransform)',
    option: opt({ tooltip: Object.assign({}, TIP), geo: { map: 'g4' },
      series: [{ type: 'scatter', coordinateSystem: 'geo', name: 'sc', symbolSize: 10, data: SC_DATA },
        { type: 'effectScatter', coordinateSystem: 'geo', symbolSize: [12, 6], rippleEffect: { number: 2 }, data: [[5, 5, 1], [25, 12, 2]] }] }),
    convert: [{ finder: { seriesIndex: 0 }, value: [12, 7] }, { finder: { seriesIndex: 1 }, pixel: [250, 180] },
      { finder: { seriesIndex: 1 }, value: 'D' }],
    steps: [{ move: { item: [0, 0] } }, { leave: true }, { action: { type: 'geoRoam', geoIndex: 0, dx: 30, dy: -15 } },
      { action: { type: 'geoRoam', geoIndex: 0, zoom: 1.6, originX: 300, originY: 200 } }, { move: { item: [0, 1] } }],
  },
  {
    id: 'scatter-clip',
    note: "a geo that clips, zoomed: a scatter (clip true by default) keeps only the points in the geo's view rect (getArea(0.1), not roamed); one with clip false keeps all; a later zoom changes which",
    option: opt({ geo: { map: 'g4', clip: true, zoom: 2, left: 100, top: 50, width: 400, height: 300 },
      series: [{ type: 'scatter', coordinateSystem: 'geo', data: SC_DATA }, { type: 'scatter', coordinateSystem: 'geo', clip: false, data: SC_DATA }] }),
    steps: [{ action: { type: 'geoRoam', geoIndex: 0, zoom: 0.5, originX: 300, originY: 200 } }],
  },
  {
    id: 'scatter-two-geos',
    note: 'two geos: series by geoIndex and geoId; a series naming no geo is on the first',
    option: opt({ geo: [{ map: 'g4', left: 10, width: 280 }, { id: 'right', map: 'g2', right: 10, width: 250 }],
      series: [{ type: 'scatter', coordinateSystem: 'geo', geoIndex: 1, data: [[4, 4], [12, 6]] },
        { type: 'scatter', coordinateSystem: 'geo', geoId: 'right', data: [[2, 2]] },
        { type: 'scatter', coordinateSystem: 'geo', data: [[2, 2]] }] }),
  },
  {
    id: 'lines-geo',
    note: 'lines on a geo: two-point lines with curveness, a polyline series; after a pan the lines follow',
    option: opt({ geo: { map: 'g4' },
      series: [{ type: 'lines', coordinateSystem: 'geo', lineStyle: { curveness: 0.2 }, data: [{ coords: [[1, 1], [25, 15]] }, { coords: [[5, 20], [15, 2]] }] },
        { type: 'lines', polyline: true, data: [{ coords: [[0, 0], [10, 5], [20, 0], [28, 12]] }] }] }),
    steps: [{ action: { type: 'geoRoam', geoIndex: 0, dx: -40, dy: 25 } }],
  },
  {
    id: 'pie-geo',
    note: "pies on a geo: the centre a coordinate (center as the coord, then coord with a percentage center that is not used), the radius a percentage of the chart; after a zoom the pies move",
    option: opt({ geo: { map: 'g4' },
      series: [{ type: 'pie', coordinateSystem: 'geo', center: [5, 5], radius: 20, data: [1, 2, 3] },
        { type: 'pie', coordinateSystem: 'geo', coord: [25, 12], center: ['10%', '10%'], radius: ['5%', '10%'], data: [{ value: 4 }, { value: 4 }] }] }),
    steps: [{ action: { type: 'geoRoam', geoIndex: 0, zoom: 1.5, originX: 200, originY: 150 } }],
  },
  {
    id: 'custom-geo',
    note: "custom on a geo: api.coord and api.size (dataToCoordSize: the two-point spans through dataToPoint), params.coordSys {type 'geo', the data rect, zoom}; after a pan renderItem runs again",
    option: opt({ geo: { map: 'g4' },
      series: [{ type: 'custom', coordinateSystem: 'geo', renderItem: '@geoRect', data: [[3, 3], [15, 15], [27, 2]] },
        { type: 'custom', coordinateSystem: 'geo', renderItem: '@geoSeg', data: [[0, 0, 20, 20]] }] }),
    steps: [{ action: { type: 'geoRoam', geoIndex: 0, dx: 10, dy: 10 } }],
  },
  {
    id: 'graph-geo',
    note: 'a graph on a geo: the nodes at their [lng, lat] values, the edges between them; after a pan',
    option: opt({ geo: { map: 'g4' },
      series: [{ type: 'graph', coordinateSystem: 'geo', data: [{ name: 'n1', value: [2, 2] }, { name: 'n2', value: [18, 8] }, { name: 'n3', value: [12, 22] }],
        edges: [{ source: 'n1', target: 'n2' }, { source: 'n2', target: 'n3' }] }] }),
    steps: [{ action: { type: 'geoRoam', geoIndex: 0, dx: 15, dy: -5 } }],
  },
  {
    id: 'heatmap-geo',
    W: 160, H: 120,
    note: "a heatmap on a geo: HeatmapLayer -- the brush (pointSize + blurSize), every point drawn at its alpha (the visualMap's normalizer), the alpha coloured through the gradient; a piecewise visualMap after",
    option: opt({ geo: { map: 'g2', left: 10, top: 10, width: 140, height: 100 },
      visualMap: { min: 0, max: 10, inRange: { color: ['#0000ff', '#ffff00', '#ff0000'] }, show: false },
      series: [{ type: 'heatmap', coordinateSystem: 'geo', pointSize: 6, blurSize: 5, data: [[2, 2, 3], [6, 5, 8], [12, 3, 10], [14, 7, 1]] }] }),
    steps: [{ setOption: opt({ geo: { map: 'g2', left: 10, top: 10, width: 140, height: 100 },
      visualMap: { type: 'piecewise', pieces: [{ min: 0, max: 5, color: '#00ff00' }, { min: 5, max: 10, color: '#ff00ff' }], show: false },
      series: [{ type: 'heatmap', coordinateSystem: 'geo', pointSize: 4, blurSize: 3, minOpacity: 0.2, maxOpacity: 0.9,
        data: [[2, 2, 3], [6, 5, 8], [12, 3, 10]] }] }), notMerge: true }],
  },
  {
    id: 'brush-geo',
    note: 'brush with geoIndex (its own brushStyle: the default one is the skin colour in the port): a rect area by coordRange selects the scatter points inside; then a polygon by coordRange',
    option: opt({ geo: { map: 'g4' }, brush: { geoIndex: 0, brushStyle: { borderWidth: 1, color: 'rgba(0,0,0,0.1)', borderColor: '#333333' } },
      series: [{ type: 'scatter', coordinateSystem: 'geo', data: SC_DATA }] }),
    steps: [{ action: { type: 'brush', areas: [{ brushType: 'rect', geoIndex: 0, coordRange: [[1, 16], [2, 16]] }] } },
      { action: { type: 'brush', areas: [{ brushType: 'polygon', geoIndex: 0, coordRange: [[2, 2], [18, 3], [16, 18], [3, 16]] }] } }],
  },
  // ======== gallery ========
  {
    id: 'gallery-map-usa',
    note: 'examples map-usa: the USA map with the special areas, a continuous visualMap, the map series',
    option: (() => {
      const o = gallery('map-usa');
      delete o.toolbox;
      o.animation = false;
      o.tooltip = Object.assign({}, o.tooltip, TIP);
      return o;
    })(),
    steps: [{ move: { series: 0, region: 'Texas' } }, { leave: true }],
  },
  {
    id: 'gallery-geo-choropleth-scatter',
    note: 'examples geo-choropleth-scatter: a scatter on the Iceland geo and a map series hosted on the same geo (geoIndex)',
    option: (() => { const o = gallery('geo-choropleth-scatter'); o.animation = false; o.tooltip = Object.assign({}, o.tooltip, TIP); return o; })(),
  },
  {
    id: 'gallery-geo-graph',
    note: 'examples geo-graph: a graph on the Swiss geo',
    option: (() => { const o = gallery('geo-graph'); o.animation = false; return o; })(),
  },
  {
    id: 'gallery-effectScatter-map',
    note: "examples effectScatter-map on the hand-made 'china': a scatter and an effectScatter on the geo",
    option: (() => { const o = gallery('effectScatter-map'); o.animation = false; delete o.tooltip; return o; })(),
  },
];

// ---------- guards ----------
function guards(out) {
  const g = [];
  const C = id => out.find(c => c.id === id);
  const add = (id, ok, detail) => g.push({ id, ok: !!ok, detail });
  const grp = (d, name) => d.groups.find(x => x.name === name);
  let c = C('map-basic');
  let d = c.states[0].draws[0];
  add('own-geo-draw', d && d.owner === 'series 0', 'the map series draws its own geo');
  add('appended', grp(d, 'G') && grp(d, 'G').ds && grp(d, 'G').ds.d === 7, 'G appended after the five data rows and the missing E, F');
  add('no-legend-labels', grp(d, 'D').paths[0].label && grp(d, 'A').paths[0].label && grp(d, 'A').paths[0].label.ignore,
    'no legend: no symbol offsets, so showLabel on every region -- a text on each, ignored while label.show is off');
  add('item-style', grp(d, 'C').paths[0].fill === '#0000ff', "a data item's areaColor");
  add('echarts-style', grp(d, 'G').paths[0].fill === '#99ccff', 'echartsStyle merged into the appended item');
  add('item-label', grp(d, 'C').paths[0].label && !grp(d, 'C').paths[0].label.ignore, "C's own label.show");
  add('hover-emphasis', grp(c.states[1].draws[0], 'A').paths[0].states === 'emphasis', 'hovering A puts it in emphasis');
  add('series-events', c.states[1].events.some(e => e.type === 'mouseover' && e.componentType === 'series' && e.dataIndex === 0),
    'the events are the series item');
  c = C('map-visualmap');
  d = c.states[0].draws[0];
  add('visual-fill', grp(d, 'A').paths[0].fill !== grp(d, 'B').paths[0].fill, 'the visualMap colours the regions');
  c = C('map-group');
  d = c.states[0].draws;
  add('one-draw', d.length === 1 && d[0].owner === 'series 0', 'only the main series draws the map');
  add('symbols', c.states[0].series[1].symbols.length === 2, 's2 has symbols where it has values (A, C)');
  add('legend-main', c.states[4].draws.length === 1 && c.states[4].draws[0].owner === 'series 1', 'with s1 off, s2 draws');
  c = C('map-on-geo');
  d = c.states[0].draws;
  add('geo-hosts', d.length === 1 && d[0].owner === 'geo 0' && grp(d[0], 'A').ds && grp(d[0], 'A').ds.s === 0, 'the geo draws with the data');
  c = C('map-select');
  add('select-event', c.states[1].events.some(e => e.type === 'selectchanged'), 'a click selects through the series');
  c = C('scatter-geo');
  const it = st => st.series[0].items;
  add('nan-point', it(c.states[0])[3].el === false, 'a string lng is not drawn');
  add('roam-moves', it(c.states[3])[0].p[0] !== it(c.states[2])[0].p[0], 'a pan moves the points');
  c = C('scatter-clip');
  add('clipped', c.states[0].series[0].items.some(x => !x.el && x.p && x.p[0] !== '7ff8000000000000')
    && c.states[0].series[1].items.filter(x => x.el).length > c.states[0].series[0].items.filter(x => x.el).length,
  'a clipping geo drops points outside its view rect; clip false keeps them');
  c = C('pie-geo');
  add('pie-moves', c.states[1].series[0].items[0].cx !== c.states[0].series[0].items[0].cx, 'the pies follow the zoom');
  c = C('custom-geo');
  add('custom-calls', c.states[0].custom && c.states[0].custom.calls.length >= 3 && c.states[0].custom.coordSys.type === 'geo', 'renderItem with api.coord and api.size');
  add('custom-rerun', c.states[1].custom && c.states[1].custom.calls.length >= 3, 'renderItem runs again after a roam');
  c = C('heatmap-geo');
  add('heat-image', c.states[0].series[0].img && c.states[0].heat && c.states[0].heat[0].px, 'the heatmap is one image of coloured bytes');
  c = C('brush-geo');
  add('brush-select', c.states[1].events.some(e => e.type === 'brushselected'), 'brushselected after the brush');
  return g;
}

// ---------- the tokens ----------
// the theme's defaults the port answers with its skin's ink: a geo
// component's and a map series'
const TOKENS = (() => {
  registerMaps();
  const chart = mk();
  chart.setOption({ animation: false, geo: { map: 'g2' }, series: [{ type: 'map', map: 'g2' }] });
  const o = chart.getModel().getComponent('geo', 0).option;
  const m = chart.getModel().getSeriesByIndex(0).option;
  const lift = c => echarts.color.lift(c, -0.1);
  const t = {
    area: o.itemStyle.color, border: o.itemStyle.borderColor, label: o.label.color,
    highlight: o.emphasis.itemStyle.color, labelHighlight: o.emphasis.label.color,
    mapArea: m.itemStyle.areaColor,
  };
  must(m.itemStyle.borderColor === t.border && m.label.color === t.label
    && m.emphasis.itemStyle.areaColor === t.highlight && m.select.itemStyle.color === t.highlight
    && m.emphasis.label.color === t.labelHighlight, 'the map series takes the geo tokens but its area');
  t.liftedArea = lift(t.area);
  t.liftedMapArea = lift(t.mapArea);
  t.liftedBorder = lift(t.border);
  t.liftedHighlight = lift(t.highlight);
  chart.dispose();
  return t;
})();

function generate() {
  const out = CASES.map(runCase);
  const g = guards(out);
  const doc = {
    source: 'tools/advchart-oracle/geo-series.js against ' + path.basename(DIST) + ' (ECharts 6.1)',
    W, H,
    tokens: TOKENS,
    maps: MAPS.map(m => ({ name: m.name, text: m.text, special: m.name === 'USA' ? USA_SPECIAL : null })),
    notes: [
      'Every case is a new chart, the maps registered afresh; animation false; a tooltip hides at once and sits at [5, 5].',
      'A click is mousemove, mousedown, mouseup and click at one point; a drag mousemove and mousedown at the first point, a mousemove to each further one, mouseup and click at the last.',
      'After every step: chart._onframe() and a display-list refresh.',
      'The heatmap canvas is this script\'s reference raster (see the header); the colouring of it is upstream\'s.',
    ],
    cases: out,
    guards: g,
  };
  return { doc, bad: g.filter(x => !x.ok) };
}

try {
  const a = generate();
  if (process.env.ORACLE_DEBUG) fs.writeFileSync(process.env.ORACLE_DEBUG, JSON.stringify(a.doc, null, 1));
  if (a.bad.length) {
    for (const b of a.bad) console.error('GUARD FAILED: ' + b.id + ' -- ' + b.detail);
    process.exit(1);
  }
  const textA = JSON.stringify(a.doc);
  const b = generate();
  const textB = JSON.stringify(b.doc);
  must(textA === textB, 'two generations differ');
  fs.writeFileSync(OUT, textA + '\n');
  let states = 0;
  a.doc.cases.forEach(c => { states += c.states.length; });
  console.log('wrote ' + OUT + ': ' + a.doc.cases.length + ' cases, ' + states + ' states, ' + a.doc.guards.length + ' guards');
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e.stack);
  process.exit(1);
}
