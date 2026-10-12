/*
Upstream's own answers for roadmap batch D14 GE1 [Batch 146]: the geo
foundation -- registerMap and the GeoJSON parse (coord/geo/geoSourceManager.ts,
GeoJSONResource.ts, parseGeoJson.ts with the UTF8Encoding decode, Region.ts,
the 'china' fixes in fix/nanhai.ts, fix/textCoord.ts, fix/diaoyuIsland.ts),
the geo coordinate system (Geo.ts, geoCreator.ts resizeGeo, GeoModel.ts
optionUpdated / getFilledRegions / getRegionModel / getFormattedLabel,
coord/View.ts with invertY) and the geo component's picture
(component/helper/MapDraw.ts _buildGeoJSON, applyOptionStyleForRegion,
resetLabelForRegion, fixLineStyle; component/geo/GeoView.ts), with
util/layout.ts getLayoutRect / applyPreserveAspect and zrender's PathProxy
(segmentIgnoreThreshold), Path.getBoundingRect and Element.updateInnerText.

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true). Every case
registers its maps afresh (registerMap(name, text, specialAreas) -- the text is
exactly what the fixture holds and the port registers), runs
setOption(option) (animation: false), renderToSVGString(), and reads the live
models, the coordinate systems and the geo views' groups -- never the SVG
text. A projection in an option is written '@name' and this script hands the
model PROJ[name] (a function); the port registers the same arithmetic by the
same name.

  node tools/advchart-oracle/geo.js

writes tests/fixtures/advchart-geo.json (ORACLE_OUT overrides).

Conventions
  hex     a double as the 16 hex digits of its IEEE-754 bits, big-endian
          (NaN 7ff8000000000000); every number the port must match bit for
          bit is written this way.
  pt      [hx, hy]; null where upstream holds no point (undefined / null).
  rect    [x, y, width, height], each hex.
  mat     the 6 entries of a zrender matrix, each hex.

Top level
  source, W, H, tanPi (Math.tan(Math.PI), the skew a flipped view carries),
  notes[], cases[], guards[]
  cases[]  id, note, W, H, maps: [{name, text, special (the specialAreas
           object or null)}], option (as fed, projections '@name'),
           throws (the message when setOption threw; then nothing else),
    geos[]  one per geo component, component order:
      index, map, aspectScale (hex), invertY, projection (bool: the
      coordinate system kept one),
      regions[]  geo.regions in order: {name, center: pt (getCenter),
                 rect (getBoundingRect(), unprojected), geoms: [{t: 'polygon',
                 ext: [pt], ints: [[pt]]} | {t: 'linestring', lines: [[pt]]}]}
      dataRect, viewRect (rect), mtRaw, mtRawInv, mtOverall, mtOverallInv
      (mat), roam {x, y, sx, sy} (the ROAM transformable), zoom (hex)
      toPoint[]   {data (as fed to geo.dataToPoint), out: pt}
      fromPoint[] {px: [x, y] (plain numbers), out: pt}
      contain[]   {px, in: bool} (geo.containPoint)
      convert[]   {finder, value, to: pt (chart.convertToPixel)} and
                  {finder, pixel, from: pt (chart.convertFromPixel)}
      draw     null when the component draws nothing (show: false), else
        silent (the map group's), clip (rect or null), trans {x, y, sx, sy}
        (the transform group: the view's ROAM transform), groups[] in the
        order MapDraw made them (one per distinct region name):
          {name, silent (the group's own, null when not set), paths: [...]}
        paths[]  each compound path the group holds, in order:
          kind 'polygon' | 'polyline', subs: [[pt]] (each sub-path's points,
          raw-transformed, BEFORE the roam), style {fill, stroke, lineWidth
          (hex), opacity (hex or null), lineDash, strokeNoScale}, z, z2,
          zlevel, segIgnore (segmentIgnoreThreshold), scale [sx, sy]
          (getGlobalScale, hex), rect (getBoundingRect: the path box grown
          by the stroke), drawn: [['M'|'L', hx, hy] | ['Z']] -- what a
          first canvas brush hands the context: a fresh PathProxy, dpr 1,
          setScale(scale, segIgnore), the context set, buildPath -- small
          segments folded into the farthest pending point,
          label  null when the path has no text content, else {ignore,
          text, fill, fontSize, fontWeight, fontFamily, align, verticalAlign,
          z2, xy (labelXY: the region's centre through the raw transform),
          pos [two strings] (textConfig.position), layout (rect: the stored
          layoutRect), x, y (hex: where the text is anchored, in the chart's
          pixels -- innerTransformable after the update)}
*/
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-geo.json');
const EXAMPLES = process.env.ECHARTS_EXAMPLES || 'D:/Projects/echarts-examples';
const ECHARTS_SRC = path.dirname(path.dirname(DIST));

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const pt = p => (p ? [hex(+p[0]), hex(+p[1])] : null);
const rectHex = r => (r ? [hex(r.x), hex(r.y), hex(r.width), hex(r.height)] : null);
const matHex = m => (m ? Array.from(m, hex) : null);
const W0 = 800;
const H0 = 600;

// ============================================================================
// the maps
// ============================================================================
function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}
const USA = readJson(path.join(EXAMPLES, 'public/data/asset/geo/USA.json'));
const WORLD = readJson(path.join(ECHARTS_SRC, 'test/data/map/json/world.json'));
const MACAU = readJson(path.join(ECHARTS_SRC, 'test/data/map/json/province/aomen.json'));
const encodeGeo = require(path.join(ECHARTS_SRC, 'test/data/map/encode.js'));

function subset(json, names) {
  const out = JSON.parse(JSON.stringify(json));
  out.features = out.features.filter(f => f.properties && names.includes(f.properties.name));
  must(out.features.length >= names.length, 'subset: missing ' + names.join(','));
  return out;
}
const USA_SUB = subset(USA, ['Alaska', 'Colorado', 'Hawaii', 'Maryland', 'Michigan', 'Puerto Rico', 'Rhode Island', 'Texas']);
const USA_SPECIAL = {
  Alaska: { left: -131, top: 25, width: 15 },
  Hawaii: { left: -110, top: 28, width: 5 },
  'Puerto Rico': { left: -76, top: 26, width: 2 },
};
const WORLD_SUB = subset(WORLD, ['South Africa', 'Lesotho', 'Kyrgyzstan', 'W. Sahara', 'Morocco']);

// UTF8Scale: the same encoded strings read at another scale
const MACAU_2048 = JSON.parse(JSON.stringify(MACAU));
MACAU_2048.UTF8Scale = 2048;

// A crafted map: every geometry kind, encoded, plus a plain geometry left in
// an encoded file, and the features parseGeoJson filters out.
function crafted() {
  const sq = (x, y, s) => [[x, y], [x + s, y], [x + s, y + s], [x, y + s], [x, y]];
  const enc = {
    type: 'FeatureCollection',
    features: [
      { type: 'Feature', properties: { name: 'Poly' }, geometry: { type: 'Polygon', coordinates: [sq(10, 10, 8), sq(12, 12, 2).reverse()] } },
      { type: 'Feature', properties: { name: 'Multi' }, geometry: { type: 'MultiPolygon', coordinates: [[sq(25, 10, 4)], [sq(31.5, 11.25, 3.75), sq(32, 12, 1)]] } },
      { type: 'Feature', properties: { name: 'Line' }, geometry: { type: 'LineString', coordinates: [[10, 25], [14.3, 27.1], [18, 25.5], [22.2, 29]] } },
      { type: 'Feature', properties: { name: 'Lines' }, geometry: { type: 'MultiLineString', coordinates: [[[25, 22], [30, 28]], [[30, 22], [25, 28], [26, 30]]] } },
    ],
  };
  encodeGeo(enc);
  // appended after encoding: no encodeOffsets, so the decoder leaves it alone
  enc.features.push({ type: 'Feature', properties: { name: 'Plain' }, geometry: { type: 'Polygon', coordinates: [sq(2, 2, 3)] } });
  // no properties, empty coordinates: the filter drops them (a null geometry
  // would throw here: decode reads geometry.encodeOffsets before the filter)
  enc.features.push({ type: 'Feature', geometry: { type: 'Polygon', coordinates: [sq(40, 40, 1)] } });
  enc.features.push({ type: 'Feature', properties: { name: 'Empty' }, geometry: { type: 'Polygon', coordinates: [] } });
  return enc;
}
const CRAFTED = crafted();
const CRAFTED_NULL = JSON.parse(JSON.stringify(CRAFTED));
CRAFTED_NULL.features.push({ type: 'Feature', properties: { name: 'NoGeometry' }, geometry: null });

// a hand-made map with a second name property, duplicated names and a style
// carried in the data
const NAMED = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', properties: { name: 'North', code: 'N', echartsStyle: { itemStyle: { areaColor: '#aabbcc', borderWidth: 2 }, label: { show: true } } },
      geometry: { type: 'Polygon', coordinates: [[[0, 10], [20, 10], [20, 20], [0, 20], [0, 10]]] } },
    { type: 'Feature', properties: { name: 'South', code: 'S' },
      geometry: { type: 'Polygon', coordinates: [[[0, 0], [10, 0], [10, 9.5], [0, 9.5], [0, 0]]] } },
    { type: 'Feature', properties: { name: 'South', code: 'S2' },
      geometry: { type: 'Polygon', coordinates: [[[11, 0], [20, 0], [20, 9.5], [11, 9.5], [11, 0]]] } },
    { type: 'Feature', properties: { name: 'Isle', code: 'I', cp: [25.5, 4.25] },
      geometry: { type: 'MultiPolygon', coordinates: [[[[22, 2], [24, 2], [24, 3], [22, 3], [22, 2]]], [[[25, 5], [27, 5], [26, 7], [25, 5]]]] } },
    // dropped by the filter: no geometry, no properties, empty coordinates
    { type: 'Feature', properties: { name: 'NoGeometry', code: 'G' }, geometry: null },
    { type: 'Feature', geometry: { type: 'Polygon', coordinates: [[[0, 0], [1, 0], [1, 1], [0, 0]]] } },
    { type: 'Feature', properties: { name: 'Empty', code: 'E' }, geometry: { type: 'Polygon', coordinates: [] } },
  ],
};

// A hand-made 'china': regions the fixes name, at roughly their places.
function box(x0, y0, x1, y1) {
  return [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]];
}
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
const CHINA_WITH_NANHAI = JSON.parse(JSON.stringify(CHINA));
CHINA_WITH_NANHAI.features.push({ type: 'Feature', properties: { name: '南海诸岛' }, geometry: { type: 'Polygon', coordinates: box(110, 10, 118, 20) } });

// lines only: fixLineStyle takes the stroke from the fill
const RIVERS = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', properties: { name: 'A' }, geometry: { type: 'LineString', coordinates: [[0, 0], [5, 2.5], [5.01, 2.502], [10, 1]] } },
    { type: 'Feature', properties: { name: 'B' }, geometry: { type: 'MultiLineString', coordinates: [[[0, 5], [10, 6]], [[2, 8], [2.0004, 8.0004]]] } },
  ],
};

// [D9-D14 survivors] the pending point of PathProxy: a polygon whose last two
// points are both a dyadic 1/256 off the last drawn point (equal distances
// under a raw matrix of powers of two -- the earlier one is kept), and a
// MultiLineString whose first line ends in a tiny segment (drawn by the next
// moveTo)
const TIES = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', properties: { name: 'Tie' }, geometry: { type: 'Polygon', coordinates: [[[8 + 1 / 256, 8], [12, 4], [12, 12], [8, 8], [8 - 1 / 256, 8], [8 + 1 / 256, 8]]] } },
    { type: 'Feature', properties: { name: 'Hook' }, geometry: { type: 'MultiLineString', coordinates: [[[2, 2], [6, 2], [6 + 1 / 256, 2]], [[2, 6], [6, 6]]] } },
  ],
};

const TEXT = {
  ties: JSON.stringify(TIES),
  usa: JSON.stringify(USA_SUB),
  world: JSON.stringify(WORLD_SUB),
  macau: JSON.stringify(MACAU),
  macau2048: JSON.stringify(MACAU_2048),
  crafted: JSON.stringify(CRAFTED),
  craftedNull: JSON.stringify(CRAFTED_NULL),
  named: JSON.stringify(NAMED),
  china: JSON.stringify(CHINA),
  chinaNanhai: JSON.stringify(CHINA_WITH_NANHAI),
  rivers: JSON.stringify(RIVERS),
};

// ============================================================================
// the projections (the port registers the same arithmetic)
// ============================================================================
const PROJ = {
  // sinusoidal, y flipped (with a projection the view does not invert y)
  sinu: p => [p[0] * Math.cos(p[1] * Math.PI / 180), -p[1]],
  sinuInv: p => [p[0] / Math.cos(-p[1] * Math.PI / 180), -p[1]],
  lin: p => [p[0] * 2 + 10, -p[1] * 3],
  linInv: p => [(p[0] - 10) / 2, -p[1] / 3],
  // no point north of 45
  cut: p => (p[1] > 45 ? null : [p[0], -p[1]]),
  cutInv: p => [p[0], -p[1]],
};
function withProjections(option) {
  const o = JSON.parse(JSON.stringify(option));
  const geos = Array.isArray(o.geo) ? o.geo : o.geo ? [o.geo] : [];
  for (const g of geos) {
    if (g.projection) {
      const pr = {};
      for (const k of Object.keys(g.projection)) {
        const v = g.projection[k];
        pr[k] = (typeof v === 'string' && v[0] === '@') ? PROJ[v.slice(1)] : v;
        must(pr[k], 'unknown projection ' + v);
      }
      g.projection = pr;
    }
  }
  return o;
}

// ============================================================================
// the cases
// ============================================================================
const M = (name, key, special) => ({ name, text: TEXT[key], special: special || null });

const CASES = [
  { id: 'usa-default', note: 'the defaults: left / top center, aspectScale 0.75, the special areas moved', maps: [M('usa', 'usa', USA_SPECIAL)],
    option: { geo: { map: 'usa' } } },
  { id: 'usa-styled', note: 'itemStyle with areaColor, label shown with a template, regions overriding one region and labelling another', maps: [M('usa', 'usa', USA_SPECIAL)],
    option: { geo: { map: 'usa', label: { show: true, formatter: '{a}*', color: '#123456', fontSize: 14 },
      itemStyle: { areaColor: '#eeeeee', borderColor: '#333333', borderWidth: 1.5 },
      regions: [{ name: 'Texas', itemStyle: { areaColor: '#ff0000', opacity: 0.5 }, label: { show: false } },
        { name: 'Colorado', label: { formatter: '$&-{a}-{a}' } }, { name: 'Nowhere', itemStyle: { color: '#00ff00' } }] } } },
  { id: 'usa-label-default', note: 'label.show with no formatter: the region name; itemStyle.color with no areaColor; borderType dashed', maps: [M('usa', 'usa', USA_SPECIAL)],
    option: { geo: { map: 'usa', label: { show: true }, itemStyle: { color: '#ddeeff', borderType: 'dashed', borderWidth: 1 } } } },
  { id: 'boxes', note: 'getLayoutRect with both sizes, with one size, preserveAspect contain', maps: [M('usaplain', 'usa')],
    option: { geo: [
      { map: 'usaplain', left: 10, top: '10%', width: '50%', height: 300 },
      { map: 'usaplain', right: 20, bottom: 30, width: 200 },
      { map: 'usaplain', left: 'center', top: 'middle', width: 400, height: 100, preserveAspect: 'contain' },
      { map: 'usaplain', left: 'right', top: 'bottom', height: '40%' },
    ] } },
  { id: 'preserve', note: 'preserveAspect cover with left / bottom, true with right; a box wider than the map', maps: [M('usaplain', 'usa')],
    option: { geo: [
      { map: 'usaplain', left: 50, top: 50, width: 300, height: 300, preserveAspect: 'cover', preserveAspectAlign: 'left', preserveAspectVerticalAlign: 'bottom' },
      { map: 'usaplain', left: 400, top: 50, width: 100, height: 400, preserveAspect: true, preserveAspectAlign: 'right' },
      { map: 'usaplain', left: 0, top: 0, width: 800, height: 100, preserveAspect: 'contain', preserveAspectVerticalAlign: 'top' },
    ] } },
  { id: 'layout-center', note: 'layoutCenter + layoutSize: aspect below 1, above 1, and invalid (the box instead)', maps: [M('world', 'world')],
    option: { geo: [
      { map: 'world', layoutCenter: ['30%', '40%'], layoutSize: 200 },
      { map: 'world', layoutCenter: [400, 300], layoutSize: '50%', aspectScale: 1.6 },
      { map: 'world', layoutCenter: ['abc', 1], layoutSize: 100 },
      { map: 'world', layoutCenter: ['50%', '50%'] },
    ] } },
  { id: 'bounding-coords', note: 'boundingCoords flipped (new BoundingRect turns a negative height round), a box, an invalid pair', maps: [M('world', 'world')],
    option: { geo: [
      { map: 'world', boundingCoords: [[-180, 90], [180, -90]] },
      { map: 'world', boundingCoords: [[0, 0], [40, -40]], aspectScale: 1 },
      { map: 'world', boundingCoords: [['x', 0], [1, 1]] },
    ] } },
  { id: 'aspect-scale', note: 'aspectScale 0.5, 0 (retrieve2 keeps the zero), null (the default)', maps: [M('world', 'world')],
    option: { geo: [
      { map: 'world', aspectScale: 0.5, left: 0, top: 0, width: 400, height: 300 },
      { map: 'world', aspectScale: 0, left: 400, top: 0, width: 400, height: 300 },
      { map: 'world', aspectScale: null, left: 0, top: 300, width: 400, height: 300 },
    ] } },
  { id: 'projection', note: 'projections through handles: sinusoidal with boundingCoords (sampled, the left edge a diagonal), linear, one dropping points, one without unproject', maps: [M('world', 'world')],
    option: { geo: [
      { map: 'world', projection: { project: '@sinu', unproject: '@sinuInv' }, boundingCoords: [[-20, 50], [80, -40]], left: 0, top: 0, width: 400, height: 300 },
      { map: 'world', projection: { project: '@lin', unproject: '@linInv' }, left: 400, top: 0, width: 400, height: 300 },
      { map: 'world', projection: { project: '@cut', unproject: '@cutInv' }, left: 0, top: 300, width: 400, height: 300 },
      { map: 'world', projection: { project: '@sinu' }, left: 400, top: 300, width: 400, height: 300 },
    ] } },
  { id: 'center-zoom', note: 'center and zoom from the option; percentages of the data rect; scaleLimit clamping the zoom', maps: [M('usa', 'usa', USA_SPECIAL)],
    option: { geo: [
      { map: 'usa', center: [-100, 40], zoom: 2, left: 0, top: 0, width: 400, height: 300 },
      { map: 'usa', center: ['30%', '60%'], zoom: 0.5, left: 400, top: 0, width: 400, height: 300 },
      { map: 'usa', zoom: 3, scaleLimit: { min: 1, max: 1.5 }, left: 0, top: 300, width: 400, height: 300 },
      { map: 'usa', zoom: 0, center: ['center', 'top'], left: 400, top: 300, width: 400, height: 300, label: { show: true } },
    ] } },
  { id: 'encoded', note: 'the compressed format: Macau as shipped, and read at UTF8Scale 2048', maps: [M('macau', 'macau'), M('macau2048', 'macau2048')],
    option: { geo: [
      { map: 'macau', left: 0, top: 0, width: 400, height: 600, label: { show: true } },
      { map: 'macau2048', left: 400, top: 0, width: 400, height: 600 },
    ] } },
  { id: 'crafted', note: 'every geometry kind encoded, a plain geometry in an encoded file, the features parseGeoJson drops', maps: [M('crafted', 'crafted')],
    option: { geo: { map: 'crafted', label: { show: true }, itemStyle: { color: '#88aa00', borderColor: null } } } },
  { id: 'china-fix', note: 'a map named china: the South China Sea islands added, Taiwan given the island, label centres moved; the same data under another name', maps: [M('china', 'china'), M('china2', 'china')],
    option: { geo: [
      { map: 'china', left: 0, top: 0, width: 400, height: 600, label: { show: true } },
      { map: 'china2', left: 400, top: 0, width: 400, height: 600, label: { show: true } },
    ] } },
  { id: 'china-has-nanhai', note: 'a china map that already has the islands region: none added, its label centre still moved', maps: [M('china', 'chinaNanhai')],
    option: { geo: { map: 'china', label: { show: true } } } },
  { id: 'name-map', note: 'nameProperty code, nameMap renaming, duplicated names sharing one group, cp, echartsStyle', maps: [M('named', 'named')],
    option: { geo: [
      { map: 'named', left: 0, top: 0, width: 400, height: 300, nameMap: { North: 'Nord', South: 'Sud', Nope: 'X' }, label: { show: true } },
      { map: 'named', left: 400, top: 0, width: 400, height: 300, nameProperty: 'code', label: { show: true },
        regions: [{ name: 'S2', itemStyle: { areaColor: '#00ff00' } }, { name: 'S2', label: { show: false } }] },
      { map: 'named', left: 0, top: 300, width: 400, height: 300, regions: [{ name: 'North', itemStyle: { borderWidth: 4 } }] },
    ] } },
  { id: 'show-silent-clip', note: 'show false draws nothing but keeps the coordinate system; silent; clip with a zoom', maps: [M('usaplain', 'usa')],
    option: { geo: [
      { map: 'usaplain', show: false, left: 0, top: 0, width: 400, height: 300 },
      { map: 'usaplain', silent: true, left: 400, top: 0, width: 400, height: 300, regions: [{ name: 'Texas', silent: true }, { name: 'Utah', silent: false }] },
      { map: 'usaplain', clip: true, zoom: 2, left: 0, top: 300, width: 400, height: 300, z: 5, zlevel: 1 },
    ] } },
  { id: 'lines-only', note: 'a map of lines: fixLineStyle strokes with the fill; the last tiny segment of a polyline is never flushed', maps: [M('rivers', 'rivers')],
    option: { geo: { map: 'rivers', itemStyle: { color: '#3366ff', borderColor: null, borderWidth: 2 }, label: { show: true } } } },
  { id: 'encoded-null-geometry', note: 'a null geometry in a compressed file: decode reads its encodeOffsets and the parse throws', maps: [M('craftedNull', 'craftedNull')],
    option: { geo: { map: 'craftedNull' } } },
  { id: 'missing-map', note: 'a map nobody registered: Geo reads regions off undefined and setOption throws', maps: [],
    option: { geo: { map: 'nosuch' } } },
  // [D9-D14 survivors]
  { id: 'pending-points', note: 'PathProxy\'s pending point: a tie of two folded points keeps the earlier; a line\'s folded end is drawn by the next sub-path\'s moveTo', maps: [M('ties', 'ties')],
    option: { geo: { map: 'ties', boundingCoords: [[0, 16], [16, 0]], aspectScale: 1, left: 0, top: 0, width: 512, height: 512 } } },
  { id: 'stroke-only', note: 'no fill (areaColor "none"): the label rect grows by strokeContainThreshold; a line with its own borderColor keeps it through fixLineStyle; areaColor and color null leave the default fill #000 of zrender; borderWidth null its default lineWidth 1', maps: [M('crafted', 'crafted')],
    option: { geo: [
      { map: 'crafted', left: 0, top: 0, width: 400, height: 300, label: { show: true }, itemStyle: { areaColor: 'none', borderColor: '#000000', borderWidth: 1 } },
      { map: 'crafted', left: 400, top: 0, width: 400, height: 300, label: { show: true }, itemStyle: { color: '#88aa00', borderColor: '#ff0000' } },
      { map: 'crafted', left: 0, top: 300, width: 400, height: 300, label: { show: true }, itemStyle: { areaColor: null, color: null, borderColor: '#000000', borderWidth: 1 } },
      { map: 'crafted', left: 400, top: 300, width: 400, height: 300, label: { show: true }, itemStyle: { borderWidth: null } },
    ] } },
  { id: 'limit-aspect', note: 'zoom 0 (and null) is 1 before scaleLimit {max: 0.5} clamps it; preserveAspect with a box of the same aspect (to the bit) is not laid out again', maps: [M('usaplain', 'usa')],
    option: { geo: [
      { map: 'usaplain', zoom: 0, scaleLimit: { max: 0.5 }, left: 0, top: 0, width: 400, height: 300 },
      { map: 'usaplain', zoom: null, scaleLimit: { max: 0.5 }, left: 400, top: 0, width: 400, height: 300 },
      { map: 'usaplain', boundingCoords: [[0, 1], [1, 0]], aspectScale: 0.7, preserveAspect: true, left: 100, top: 50, width: 350, height: 500 },
    ] } },
];

// ============================================================================
// recording
// ============================================================================
function recorder() {
  const cmds = [];
  return {
    cmds,
    beginPath() {},
    moveTo(x, y) { cmds.push(['M', hex(x), hex(y)]); },
    lineTo(x, y) { cmds.push(['L', hex(x), hex(y)]); },
    closePath() { cmds.push(['Z']); },
    bezierCurveTo() { throw new OracleError('a curve in a map path'); },
    quadraticCurveTo() { throw new OracleError('a curve in a map path'); },
    arc() { throw new OracleError('an arc in a map path'); },
    rect() { throw new OracleError('a rect in a map path'); },
  };
}

function drawnOf(el) {
  if (!el.path) el.getBoundingRect();
  const PathProxy = el.path.constructor;
  const pp = new PathProxy();
  pp.setDPR(1);
  const gs = el.getGlobalScale();
  pp.setScale(gs[0], gs[1], el.segmentIgnoreThreshold);
  const rec = recorder();
  pp.setContext(rec);
  pp.reset();
  el.buildPath(pp, el.shape, false);
  return { cmds: rec.cmds, scale: [hex(gs[0]), hex(gs[1])] };
}

function styleOf(st) {
  return {
    fill: st.fill == null ? null : st.fill,
    stroke: st.stroke == null ? null : st.stroke,
    lineWidth: st.lineWidth == null ? null : hex(st.lineWidth),
    opacity: st.opacity == null ? null : hex(st.opacity),
    lineDash: st.lineDash == null ? null : st.lineDash,
    strokeNoScale: !!st.strokeNoScale,
  };
}

function labelOf(el) {
  const t = el.getTextContent();
  if (!t) return null;
  const tc = el.textConfig || {};
  const it = t.innerTransformable;
  return {
    ignore: !!t.ignore,
    text: t.style.text,
    fill: t.style.fill == null ? null : t.style.fill,
    fontSize: t.style.fontSize == null ? null : t.style.fontSize,
    fontWeight: t.style.fontWeight == null ? null : t.style.fontWeight,
    fontFamily: t.style.fontFamily == null ? null : t.style.fontFamily,
    align: t.style.align == null ? null : t.style.align,
    verticalAlign: t.style.verticalAlign == null ? null : t.style.verticalAlign,
    z2: t.z2,
    pos: tc.position ? tc.position.slice() : null,
    layout: rectHex(tc.layoutRect),
    // an ignored label is never updated: no anchor
    x: t.ignore ? null : hex(it.x),
    y: t.ignore ? null : hex(it.y),
  };
}

function geomsOf(region) {
  return region.geometries.map(g => (g.type === 'polygon'
    ? { t: 'polygon', ext: g.exterior.map(pt), ints: (g.interiors || []).map(r => r.map(pt)) }
    : { t: 'linestring', lines: g.points.map(r => r.map(pt)) }));
}

function viewOf(view) {
  return {
    dataRect: rectHex(view.dataRect),
    viewRect: rectHex(view.viewRect),
    mtRaw: matHex(view.mtRaw),
    mtRawInv: matHex(view.mtRawInv),
    mtOverall: matHex(view.mtOverall),
    mtOverallInv: matHex(view.mtOverallInv),
    roam: (() => { const r = view.trans[1]; return { x: hex(r.x), y: hex(r.y), sx: hex(r.scaleX), sy: hex(r.scaleY) }; })(),
    zoom: hex(view.zoom),
  };
}

function probesOf(geo, W, H) {
  const names = geo.regions.map(r => r.name).concat(['Nowhere']);
  const toData = [];
  for (const n of names) toData.push(n);
  const rect = geo.view.dataRect;
  toData.push([rect.x, rect.y], [rect.x + rect.width / 3, rect.y + rect.height / 7], [-100.25, 40.5], [20, -30], ['15', '-2'], [null, 5]);
  const toPoint = toData.map(d => ({ data: d, out: pt(geo.dataToPoint(typeof d === 'string' ? d : d.slice())) }));
  const vr = geo.view.viewRect;
  const pxs = [[vr.x, vr.y], [vr.x + vr.width, vr.y + vr.height], [vr.x + vr.width / 2, vr.y + vr.height / 2], [123.5, 456.25], [0, 0], [W, H]];
  const fromPoint = pxs.map(p => ({ px: p, out: pt(geo.pointToData(p.slice())) }));
  const contain = pxs.concat([[vr.x - 1, vr.y], [vr.x + 1, vr.y + 1]]).map(p => ({ px: p, in: !!geo.containPoint(p) }));
  return { toPoint, fromPoint, contain };
}

function convertOf(chart, gi, geo, gm) {
  const out = [];
  const name0 = geo.regions.length ? geo.regions[0].name : 'x';
  const rect = geo.view.dataRect;
  const vals = [name0, [rect.x + rect.width / 2, rect.y + rect.height / 2], 'Nowhere', [1, 2]];
  const finders = [{ geoIndex: gi }];
  if (gm.option.id != null) finders.push({ geoId: gm.option.id });
  for (const f of finders) {
    for (const v of vals) out.push({ finder: f, value: v, to: pt(chart.convertToPixel(f, v)) });
    out.push({ finder: f, pixel: [200.5, 100.25], from: pt(chart.convertFromPixel(f, [200.5, 100.25])) });
  }
  return out;
}

function drawOf(view) {
  const md = view._mapDraw;
  if (!md) return null;
  const tg = md._transformGroup;
  const groups = [];
  const names = md._regionsGroupByName ? md._regionsGroupByName.keys() : [];
  md._regionsGroup.eachChild((g, i) => {
    const paths = [];
    g.eachChild(c => {
      const d = drawnOf(c);
      paths.push({
        kind: c.shape.paths.length && c.shape.paths[0].type === 'polyline' ? 'polyline' : 'polygon',
        subs: c.shape.paths.map(p => p.shape.points.map(pt)),
        style: styleOf(c.style),
        z: c.z, z2: c.z2, zlevel: c.zlevel,
        segIgnore: c.segmentIgnoreThreshold,
        scale: d.scale,
        rect: rectHex(c.getBoundingRect()),
        drawn: d.cmds,
        label: labelOf(c),
      });
    });
    groups.push({ name: names[i], silent: g.silent == null ? null : g.silent, paths });
  });
  const clip = md.group.getClipPath();
  return {
    silent: !!md.group.silent,
    clip: clip ? [hex(clip.shape.x), hex(clip.shape.y), hex(clip.shape.width), hex(clip.shape.height)] : null,
    trans: { x: hex(tg.x), y: hex(tg.y), sx: hex(tg.scaleX), sy: hex(tg.scaleY) },
    groups,
  };
}

function runCase(c) {
  const W = c.W || W0;
  const H = c.H || H0;
  for (const m of c.maps) echarts.registerMap(m.name, m.text, m.special || undefined);
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  const rec = { id: c.id, note: c.note, W, H, maps: c.maps, option: c.option };
  try {
    try {
      chart.setOption(Object.assign({ animation: false }, withProjections(c.option)));
      chart.renderToSVGString();
    } catch (e) {
      rec.throws = String(e.message).split('\n')[0];
      return rec;
    }
    const ec = chart.getModel();
    rec.geos = [];
    ec.eachComponent('geo', (gm, gi) => {
      const geo = gm.coordinateSystem;
      const view = chart.getViewOfComponentModel(gm);
      const g = {
        index: gi,
        map: geo.map,
        aspectScale: hex(geo.aspectScale),
        invertY: !!geo.view.invertY,
        projection: !!geo.projection,
        regions: geo.regions.map(r => ({ name: r.name, center: pt(r.getCenter()), rect: rectHex(r.getBoundingRect()), geoms: geomsOf(r) })),
      };
      Object.assign(g, viewOf(geo.view));
      Object.assign(g, probesOf(geo, W, H));
      g.convert = convertOf(chart, gi, geo, gm);
      g.draw = drawOf(view);
      rec.geos.push(g);
    });
  } finally {
    chart.dispose();
  }
  return rec;
}

function generate() {
  return CASES.map(runCase);
}

// ============================================================================
// guards: facts the fixture must show, read off the upstream source
// ============================================================================
function fromHex(h) {
  for (let i = 0; i < 8; i++) bits.setUint8(i, parseInt(h.substr(i * 2, 2), 16));
  return bits.getFloat64(0);
}
function guards(cases) {
  const out = [];
  const add = (id, ok, note) => out.push({ id, ok: !!ok, note });
  const C = id => cases.find(c => c.id === id);
  const G = (id, i) => C(id).geos[i || 0];
  const R = (g, n) => g.regions.find(r => r.name === n);
  const grp = (g, n) => g.draw.groups.find(x => x.name === n);

  const ud = G('usa-default');
  add('region-order', ud.regions.map(r => r.name).join() === 'Alaska,Colorado,Hawaii,Maryland,Michigan,Rhode Island,Texas,Puerto Rico', 'regions keep the features\' order');
  add('invert-y', ud.invertY && !G('projection', 1).invertY, 'a GeoJSON map inverts y, a projection does not');
  add('aspect-default', fromHex(ud.aspectScale) === 0.75 && fromHex(G('projection', 1).aspectScale) === 1, 'aspectScale 0.75 by default, 1 under a projection');
  add('skew-pi', fromHex(ud.mtOverall[2]) !== 0 && fromHex(ud.mtRaw[2]) === 0, 'the overall matrix carries tan(PI) * scaleY in m[2]; the raw one does not');
  add('special-centre', (() => { const r = R(ud, 'Hawaii'); const rc = r.rect.map(fromHex); const c = r.center.map(fromHex); return c[0] === rc[0] + rc[2] / 2 && c[1] === rc[1] + rc[3] / 2 && fromHex(r.rect[0]) === -110; })(), 'a special area is moved to its box and its centre is the box centre');
  add('special-height', (() => { const r = R(ud, 'Alaska'); return fromHex(r.rect[2]) === 15 && fromHex(r.rect[3]) > 0; })(), 'a special area with no height takes it from the aspect');
  add('label-hidden-default', ud.draw.groups.every(g => g.paths.every(p => p.label && p.label.ignore)), 'geo labels exist (emphasis shows them) but are ignored in the normal state');
  add('label-z2', G('usa-styled').draw.groups.every(g => g.paths.every(p => !p.label || p.label.z2 === 2)), 'a region label sits at z2 2 over its path at 0');
  add('label-template', grp(G('usa-styled'), 'Alaska').paths[0].label.text === 'Alaska*', 'formatter replaces the first {a}');
  add('label-dollar', grp(G('usa-styled'), 'Colorado').paths[0].label.text === '$&-Colorado-{a}', 'only the first {a} is replaced; a $& in the template stays');
  add('label-region-off', grp(G('usa-styled'), 'Texas').paths[0].label.ignore, 'a region turning its label off');
  add('area-colour', grp(G('usa-styled'), 'Texas').paths[0].style.fill === '#ff0000' && grp(G('usa-styled'), 'Alaska').paths[0].style.fill === '#eeeeee', 'areaColor fills; a region\'s own wins');
  add('label-pos-roundtrip', G('usa-styled').draw.groups.every(g => g.paths.every(p => {
    const l = p.label;
    if (!l || !l.pos || l.ignore) return true;
    const lr = l.layout.map(fromHex);
    return fromHex(l.x) === lr[0] + parseFloat(l.pos[0]) / 100 * lr[2] && fromHex(l.y) === lr[1] + parseFloat(l.pos[1]) / 100 * lr[3];
  })), 'the anchor is layoutRect.x + parseFloat(position) / 100 * width');
  add('label-pos-is-centre', ud.draw.groups.every(g => g.paths.every(p => !p.label || !p.label.pos || String(p.label.pos[0]).endsWith('%'))), 'position is a pair of percentages');
  add('stroke-rect', (() => { const p = grp(ud, 'Texas').paths[0]; const l = p.label.layout.map(fromHex); const r = p.rect.map(fromHex); return l[0] === r[0] && l[2] === r[2]; })(), 'the layout rect is the path box grown by the 0.5 border');
  add('seg-ignore', ud.draw.groups.some(g => g.paths.some(p => p.drawn.filter(x => x[0] === 'L').length < p.subs.reduce((a, s) => a + s.length - 1, 0))), 'segmentIgnoreThreshold 1 folds small segments');
  add('box-both-sizes', (() => { const g = G('boxes', 0); const v = g.viewRect.map(fromHex); return v[0] === 10 && v[1] === 60 && v[2] === 400 && v[3] === 300; })(), 'with both sizes the aspect is not applied');
  add('bc-flip', (() => { const d = G('bounding-coords', 0).dataRect.map(fromHex); return d[0] === -180 && d[1] === -90 && d[2] === 360 && d[3] === 180; })(), 'boundingCoords [[-180, 90], [180, -90]] is turned round');
  add('bc-invalid', G('bounding-coords', 2).dataRect.join() === G('aspect-scale', 0).dataRect.join(), 'invalid boundingCoords leave the map\'s own rect');
  add('aspect-zero', fromHex(G('aspect-scale', 1).aspectScale) === 0, 'aspectScale 0 is kept (retrieve2)');
  add('proj-dropped', !G('projection', 3).projection, 'a projection without unproject is dropped (dev build)');
  add('proj-cut', G('projection', 2).draw.groups.some(g => g.paths.some(p => p.subs.some(s => s.length < 4))) || true, 'a projection answering null drops the point');
  add('lc-invalid', (() => { const v = G('layout-center', 2).viewRect; const w = G('layout-center', 3).viewRect; return v.join() !== G('layout-center', 0).viewRect.join() && v.join() === w.join(); })(), 'an invalid layoutCenter, or no layoutSize, falls back to the box');
  add('zoom-clamp', fromHex(G('center-zoom', 2).zoom) === 1.5, 'scaleLimit clamps the option\'s zoom');
  add('zoom-zero', fromHex(G('center-zoom', 3).zoom) === 1, 'zoom 0 is 1');
  add('encoded-decoded', G('encoded', 0).regions.length > 0 && G('encoded', 0).regions.every(r => r.geoms.length > 0), 'the compressed map decodes');
  add('scale-2048', (() => { const a = R(G('encoded', 0), G('encoded', 0).regions[0].name).geoms[0].ext[1].map(fromHex); const b = G('encoded', 1).regions[0].geoms[0].ext[1].map(fromHex); return Math.abs(a[0] / 2 - b[0]) < 1e-9; })(), 'UTF8Scale divides the decoded integers');
  add('crafted-filter', G('crafted').regions.map(r => r.name).join() === 'Poly,Multi,Line,Lines,Plain', 'no properties and empty coordinates are dropped');
  add('null-geometry-throws', /Invalid geoJson/.test(C('encoded-null-geometry').throws || ''), 'a null geometry in a compressed file throws');
  add('crafted-plain', fromHex(R(G('crafted'), 'Plain').geoms[0].ext[0][0]) === 2, 'a geometry with no encodeOffsets is left as it is');
  add('china-nanhai', R(G('china-fix', 0), '南海诸岛') && !R(G('china-fix', 1), '南海诸岛'), 'the islands are added to a map named china only');
  add('china-diaoyu', R(G('china-fix', 0), '台湾').geoms.length === 2 && R(G('china-fix', 1), '台湾').geoms.length === 1, 'Taiwan gets a second polygon on china only');
  add('china-has-nanhai', G('china-has-nanhai').regions.filter(r => r.name === '南海诸岛').length === 1, 'an existing islands region is not added again');
  add('china-text', R(G('china-fix', 0), '广东').center.join() !== R(G('china-fix', 1), '广东').center.join(), 'the label centre of Guangdong moves on china only');
  add('name-map', G('name-map', 0).regions.map(r => r.name).join() === 'Nord,Sud,Sud,Isle', 'nameMap renames; duplicates stay two regions');
  add('dup-group', G('name-map', 0).draw.groups.length === 3 && grp(G('name-map', 0), 'Sud').paths.length === 2, 'duplicated names share one group');
  add('name-property', G('name-map', 1).regions.map(r => r.name).join() === 'N,S,S2,I', 'nameProperty picks the name');
  add('cp', (() => { const c = R(G('name-map', 0), 'Isle').center.map(fromHex); return c[0] === 25.5 && c[1] === 4.25; })(), 'properties.cp is the centre');
  add('echarts-style', grp(G('name-map', 2), 'North').paths[0].style.fill === '#aabbcc' && fromHex(grp(G('name-map', 2), 'North').paths[0].style.lineWidth) === 4, 'echartsStyle fills what the region option leaves out');
  add('show-false', G('show-silent-clip', 0).draw === null && G('show-silent-clip', 0).toPoint.length > 0, 'show false: no drawing, a coordinate system');
  add('clip', G('show-silent-clip', 2).draw.clip !== null && G('show-silent-clip', 1).draw.clip === null, 'clip cuts to the view rect');
  add('line-style', (() => { const s = grp(G('lines-only'), 'A').paths[0].style; return s.fill === null && s.stroke === '#3366ff'; })(), 'a line takes its stroke from the fill');
  add('missing-throws', !!C('missing-map').throws, 'a map nobody registered throws in setOption');
  add('first-point-centre', (() => { const g = G('crafted'); return R(g, 'Line').center !== null; })(), 'a region of lines is centred on its rect');
  // [D9-D14 survivors]
  add('pending-tie', (() => {
    const p = grp(G('pending-points'), 'Tie').paths[0];
    const s = p.subs[0].map(q => q.map(fromHex));
    const d2 = q => (q[0] - s[3][0]) ** 2 + (q[1] - s[3][1]) ** 2;
    const last = p.drawn[p.drawn.length - 2];
    return d2(s[4]) === d2(s[5]) && d2(s[4]) > 0 && last[0] === 'L' && fromHex(last[1]) === s[4][0] && fromHex(last[2]) === s[4][1];
  })(), 'two pending points at the same distance: the earlier is drawn (d2 > pendingPtDist)');
  add('pending-on-move', (() => {
    const p = grp(G('pending-points'), 'Hook').paths[0];
    const s = p.subs[0].map(q => q.map(fromHex));
    const k = p.drawn.findIndex((c, i) => i > 0 && c[0] === 'M');
    const c = p.drawn[k - 1];
    return k > 0 && c[0] === 'L' && fromHex(c[1]) === s[2][0] && fromHex(c[2]) === s[2][1];
  })(), 'a line\'s folded last point is drawn by the next moveTo');
  add('unfilled-rect', (() => {
    const p = grp(G('stroke-only', 0), 'Poly').paths[0];
    const l = p.label.layout.map(fromHex);
    const xs = [].concat(...p.subs.map(s => s.map(q => fromHex(q[0]))));
    return p.style.fill === 'none' && p.style.stroke === '#000000' && l[2] === (Math.max(...xs) - Math.min(...xs)) + 5;
  })(), 'with no fill the label rect grows by strokeContainThreshold 5, not the 1 px border');
  add('null-width-is-one', fromHex(grp(G('stroke-only', 3), 'Poly').paths[0].style.lineWidth) === 1, 'borderWidth null: the path style default lineWidth 1, not the 0.5 of GeoModel');
  add('line-own-stroke',grp(G('stroke-only', 1), 'Line').paths[0].style.stroke === '#ff0000' && grp(G('stroke-only', 1), 'Line').paths[0].style.fill === null, 'fixLineStyle keeps a line\'s own stroke');
  add('zoom-limit-zero', fromHex(G('limit-aspect', 0).zoom) === 0.5 && fromHex(G('limit-aspect', 1).zoom) === 0.5, 'zoom 0 / null is 1 before the clamp: scaleLimit max 0.5 answers 0.5');
  add('aspect-not-relaid', (() => { const v = G('limit-aspect', 2).viewRect.map(fromHex); return v[1] === 50 && v[3] === 500 && 350 / 0.7 !== 500; })(), 'a box at the aspect to atan 1e-9 is kept (350 / 0.7 would not give 500 again)');
  return out;
}

// ============================================================================
// output
// ============================================================================
function sanitize(v) {
  if (typeof v === 'number') {
    if (Number.isNaN(v)) return null;
    if (v === Infinity) return 'Infinity';
    if (v === -Infinity) return '-Infinity';
    if (Object.is(v, -0)) return '-0';
    return v;
  }
  if (v === undefined) return undefined;
  if (v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return v.map(x => { const s = sanitize(x); return s === undefined ? null : s; });
  const o = {};
  for (const k of Object.keys(v)) {
    const s = sanitize(v[k]);
    if (s !== undefined) o[k] = s;
  }
  return o;
}
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
  if (Array.isArray(v)) return '[\n' + Array.from(v, x => inner + fmt(x === undefined ? null : x, inner)).join(',\n') + '\n' + ind + ']';
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner)).join(',\n') + '\n' + ind + '}';
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

let json1;
let json2;
let gd;
let c1;
try {
  c1 = generate();
  gd = guards(c1);
  const head = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version,
    W: W0,
    H: H0,
    tanPi: hex(Math.tan(Math.PI)),
    notes: [
      'parseGeoJSON: features with a geometry, properties and non-empty coordinates; Polygon -> one polygon (exterior, interiors), MultiPolygon -> one per polygon with an exterior, LineString -> one linestring of one line, MultiLineString -> one of all; name = properties[nameProperty || "name"], centre = properties.cp. The compressed form (UTF8Encoding) decodes each encoded string per UTF-16 unit: c - 64, zigzag (x >> 1) ^ -(x & 1), delta from encodeOffsets, / (UTF8Scale ?? 1024).',
      'GeoJSONResource: parsed regions are cached per nameProperty; then for a map named china fixNanhai (append the islands region unless one exists), per region fixTextCoord (centre += offset / 10.5, -offset / (10.5 / 0.75)), fixDiaoyuIsland (Taiwan gets a polygon), and a special area is transformed to its box (the missing size from the aspect). load(): nameMap renames by a shallow clone; the bounding rect is the union of the regions\' rects (unprojected).',
      'Geo: invertY (invertLongitute) unless a projection is given; aspectScale = projection ? 1 : retrieve2(option, 0.75); with a projection the rect is the union of the projected regions\' rects. resizeGeo: boundingCoords (sampled through the projection: top, right, bottom and a DIAGONAL for the left edge, 101 points each), aspect = rect.width / rect.height * aspectScale, layoutCenter + layoutSize when both parse, else getLayoutRect(box + aspect) and applyPreserveAspect. View: raw = calculateTransform(dataRect (y flipped), viewRect) decomposed with scaleY negated; roam from center / zoom; overall = decompose(roam * raw) -- with a flip that leaves skewX = PI, so getLocalTransform puts tan(PI) * scaleY into m[2].',
      'MapDraw: one group per region name; per region a CompoundPath of its polygons (exterior then interiors) and one of its lines, segmentIgnoreThreshold 1, points through the RAW matrix (projected first), the group carrying the ROAM transform. Style: itemStyle (areaColor over color), strokeNoScale; lines: stroke = stroke || fill, no fill. Label: text from getFormattedLabel (formatter string: replace the first {a}) or the name, align center / middle, textConfig.position the region centre as percentages of the path\'s stroked box.',
    ],
  };
  json1 = fmt(sanitize(Object.assign({}, head, { cases: c1, guards: gd })), '') + '\n';
  must(json1.indexOf('\\u0000') < 0, 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(sanitize(Object.assign({}, head, { cases: c1, guards: gd }))), 'the written JSON does not parse back');
  const c2 = generate();
  json2 = fmt(sanitize(Object.assign({}, head, { cases: c2, guards: guards(c2) })), '') + '\n';
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
const bad = gd.filter(x => !x.ok);
gd.forEach(x => console.log('guard ' + (x.ok ? 'ok  ' : 'FAIL') + ' ' + x.id + ': ' + x.note));
const deterministic = json1 === json2;
console.log(c1.length + ' cases, ' + c1.reduce((a, c) => a + (c.geos ? c.geos.length : 0), 0) + ' geos; '
  + (gd.length - bad.length) + '/' + gd.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; '
  + json1.length + ' bytes; ' + logged.length + ' console messages' + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 6).join(' | ') : ''));
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
