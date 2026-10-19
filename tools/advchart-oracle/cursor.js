/*
Upstream's own answers for the fix phase's F6a: the CURSOR the chart's canvas
shows under scripted pointer steps, and where an `image://` picture lands
once it has loaded.

CURSOR. zrender's Handler.mousemove sets the canvas cursor to the hovered
element's `cursor` (Displayable's prototype says 'pointer'; a series sets
an item's `cursor` option on its element, a draggable graph node takes
'move', a large batch 'default', a visualMap handle 'ns-resize' ...) or
'default' over nothing; then the zr-level listeners may set it again
(zr.setCursorStyle): a RoamController 'grabbing' while it pans and 'grab'
over its area where nothing is hovered, again on mouseup; the brush its
crosshair. Every step records the cursor the canvas holds after it -- the
last setCursor of the step (HandlerProxy writes `cursor || 'default'`), or
the one before when the step set none -- with every call made during it.

PICTURES. The SVG renderer never loads an image; a browser does, and then
zrender keeps it on the element (__image: the natural size an Image without
a width or a height takes) and calls the element's onload (makeImage's
'center' layout, symbolKeepAspect). This run does what the load would: every
ZRImage in the display list gets __image = {width, height} of its PNG and
its onload, then a frame. Each image case records every image element as it
then stands: its source and its four corners (the style's x, y, width,
height through the element's global transform: top-left, top-right,
bottom-right, bottom-left).

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node, SVG renderer, ssr: true then chart._ssr = false (the
browser's model, as mouse-events.js), 600 x 400, animation off on every case,
setTimeout a no-op (the throttles' deferred halves never run), Math.random
the port's xorshift32 reseeded per chart. Pointer steps go straight to
zrender's Handler with integer {zrX, zrY, which 1}: move = mousemove, down =
mousedown, up = mouseup then click (the browser's DOM click). After every
step chart._onframe() and renderToSVGString() (the frame and a paint).

  node tools/advchart-oracle/cursor.js

writes tests/fixtures/advchart-cursor.json (ORACLE_OUT overrides). Ends with
process.exit().

-----------------------------------------------------------------------------
Fixture:
  source, W, H, seed, images {name: {url, width, height}} (the PNGs: data
  URLs), maps[] {name, text} (GeoJSON every case registers), notes[]
  cases[] (cursor):
    id, note, option, steps[]:
      type ('move' | 'down' | 'up'), x, y (integers), aim (what the point was
      aimed at, for the reader), hover (zrender's findHover target before the
      step: '<type>:<its cursor>' or null), calls[] (every setCursor of the
      step, `|| 'default'` applied), cursor (the canvas' cursor after it)
  pictures[] (image):
    id, note, option (every image as its data URL), images[] in display-list
    order: {image (its key in `images`), corners [[x, y] x 4] hex + Text}
  guards[], checks: self-checks (any failure: nothing is written, exit 1):
    every step's aim found an element of the kind it names; the cursors the
    notes promise; the fixture generated twice byte-identical.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-cursor.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

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

const hexOf = v => {
  const b = Buffer.alloc(8);
  b.writeDoubleBE(v);
  return b.toString('hex');
};
const textOf = v => (Object.is(v, -0) ? '-0' : String(v));

// ---------- the pictures ----------
const CRC = (() => {
  const t = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(w, h, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const raw = [];
  for (let y = 0; y < h; y++) {
    raw.push(0);
    for (let x = 0; x < w; x++) raw.push(...rgba(x, y));
  }
  const idat = zlib.deflateSync(Buffer.from(raw), { level: 9 });
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  return 'data:image/png;base64,' + Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]).toString('base64');
}
// a wide red one (left half red, right half blue) and a tall green one
const IMAGES = {
  wide: { width: 20, height: 10, url: png(20, 10, x => (x < 10 ? [255, 0, 0, 255] : [0, 0, 255, 255])) },
  tall: { width: 8, height: 16, url: png(8, 16, (x, y) => (y < 8 ? [0, 160, 0, 255] : [0, 0, 0, 255])) },
};
const imageKey = url => {
  for (const k of Object.keys(IMAGES)) if (IMAGES[k].url === url || 'image://' + IMAGES[k].url === url) return k;
  return null;
};
const IMG = k => 'image://' + IMAGES[k].url;

// ---------- the maps ----------
function sq(x0, y0, x1, y1) { return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]; }
const MAPS = [
  { name: 'cursorSquares', text: JSON.stringify({
    type: 'FeatureCollection',
    features: [
      { type: 'Feature', properties: { name: 'A' }, geometry: { type: 'Polygon', coordinates: [sq(0, 0, 10, 10)] } },
      { type: 'Feature', properties: { name: 'B' }, geometry: { type: 'Polygon', coordinates: [sq(20, 0, 30, 10)] } },
    ],
  }) },
];
for (const m of MAPS) echarts.registerMap(m.name, m.text);

// ---------- driving a chart ----------
function newChart() {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function frame(chart) {
  chart._onframe();
  chart.renderToSVGString();
  chart.getZr().storage.getDisplayList(true);
}
// what a browser does once the pictures have loaded
function loadImages(chart) {
  let any = false;
  chart.getZr().storage.getDisplayList(true).forEach(el => {
    if (el.type !== 'image') return;
    const src = el.style.image;
    const k = typeof src === 'string' ? imageKey(src) : null;
    if (!k) return;
    const img = { width: IMAGES[k].width, height: IMAGES[k].height };
    el.__image = img;
    el._rect = null;
    if (typeof el.onload === 'function') el.onload(img);
    el.dirty();
    any = true;
  });
  if (any) frame(chart);
}
function globalRect(el) {
  const r = el.getBoundingRect().clone();
  if (el.transform) r.applyTransform(el.transform);
  return r;
}
function centre(el, dx, dy) {
  const r = globalRect(el);
  return [Math.round(r.x + r.width / 2 + (dx || 0)), Math.round(r.y + r.height / 2 + (dy || 0))];
}
function itemEl(chart, s, d) {
  let el = chart.getModel().getSeriesByIndex(s).getData().getItemGraphicEl(d);
  must(el, 'no element for series ' + s + ' item ' + d);
  // a symbol's group: its path
  if (el.isGroup && el.childAt(0) && !el.childAt(0).isGroup && el.type !== 'group' || (el.isGroup && el.childAt(0) && el.childAt(0).type === 'path')) el = el.childAt(0);
  return el;
}
function displayFind(chart, pred, nth, aim) {
  const list = chart.getZr().storage.getDisplayList(true).filter(pred);
  must(list.length > (nth || 0), 'no display element for ' + aim);
  return list[nth || 0];
}
function componentEls(chart, mainType, index) {
  const m = chart.getModel().getComponent(mainType, index || 0);
  must(m, 'no ' + mainType);
  const view = chart._componentsMap[m.__viewId];
  const out = [];
  view.group.traverse(e => { if (!e.isGroup) out.push(e); });
  return out;
}

// aims: a function (chart) -> {x, y, aim}
const at = (x, y, aim) => () => ({ x, y, aim: aim || 'point ' + x + ',' + y });
const item = (s, d, dx, dy) => chart => {
  const p = centre(itemEl(chart, s, d), dx, dy);
  return { x: p[0], y: p[1], aim: 'item s' + s + ' d' + d };
};
const label = (s, d) => chart => {
  const el = chart.getModel().getSeriesByIndex(s).getData().getItemGraphicEl(d);
  let t = el.getTextContent && el.getTextContent();
  if (!t && el.isGroup) el.traverse(c => { if (!t && c.getTextContent && c.getTextContent()) t = c.getTextContent(); });
  must(t, 'no label for series ' + s + ' item ' + d);
  const p = centre(t);
  return { x: p[0], y: p[1], aim: 'label s' + s + ' d' + d };
};
const comp = (mainType, index, pred, nth, aim, dx, dy) => chart => {
  const els = componentEls(chart, mainType, index).filter(pred);
  must(els.length > (nth || 0), 'no ' + mainType + ' element for ' + aim);
  const p = centre(els[nth || 0], dx, dy);
  return { x: p[0], y: p[1], aim };
};
const disp = (pred, nth, aim, dx, dy) => chart => {
  const p = centre(displayFind(chart, pred, nth, aim), dx, dy);
  return { x: p[0], y: p[1], aim };
};
// [R2-I1] a point OFF px off the tree edge into node D (the node's __edge,
// from its parent) a quarter of the way along it (where the curve is not its
// chord), along the curve's normal: the edge is no
// silent element (TreeView.drawEdge), Path.contain takes its stroke within
// max(lineWidth, 5) / 2
const treeEdge = (s, d, off, aim) => chart => {
  const sym = chart.getModel().getSeriesByIndex(s).getData().getItemGraphicEl(d);
  must(sym && sym.__edge, 'no tree edge into ' + d);
  const e = sym.__edge;
  e.updateTransform();
  const m = e.getComputedTransform();
  const pt = t => {
    const p = e.pointAt(t);
    return m ? [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]] : p;
  };
  const a = pt(0.24);
  const b = pt(0.26);
  const c = pt(0.25);
  let tx = b[0] - a[0];
  let ty = b[1] - a[1];
  const len = Math.hypot(tx, ty);
  tx /= len;
  ty /= len;
  return { x: Math.round(c[0] - ty * off), y: Math.round(c[1] + tx * off), aim };
};
const mv = a => ({ type: 'move', at: a });
const down = a => ({ type: 'down', at: a });
const up = a => ({ type: 'up', at: a });
const isText = e => e.type === 'tspan' || e.type === 'text';

// ---------- the cursor cases ----------
const CAT = ['Mon', 'Tue', 'Wed', 'Thu'];
const CASES = [
  { id: 'bar',
    note: 'a bar is its item\'s cursor, else its series\', else the prototype\'s pointer; a label is a text of its own (pointer, whatever its bar says); empty ground, a title without link or triggerEvent, an axis label without triggerEvent: default; a legend item: its hit rect\'s pointer',
    option: { animation: false, title: { text: 'Title' }, legend: { top: 30 }, grid: { top: 70 }, xAxis: { type: 'category', data: CAT }, yAxis: {},
      series: [
        { name: 'A', type: 'bar', data: [10, 20, { value: 15, cursor: 'help' }, 30], label: { show: true, position: 'top' } },
        { name: 'B', type: 'bar', data: [5, 12, 8, 16], cursor: 'crosshair' },
      ] },
    steps: [mv(at(300, 75, 'empty grid')), mv(item(0, 0)), mv(item(0, 2)), mv(item(1, 1)), mv(label(0, 1)),
      mv(comp('legend', 0, e => e.type === 'rect' && !e.silent, 0, 'legend item 0')), mv(comp('title', 0, isText, 0, 'title text')),
      mv(disp(e => isText(e) && e.style.text === 'Tue', 0, 'x axis label Tue')), mv(item(1, 3)), mv(at(2, 398, 'corner'))] },
  { id: 'bar-root',
    note: 'the root option\'s cursor reaches every item (getShallow climbs the item model, the series, the global model); a legend item is not a series\' (pointer)',
    option: { animation: false, cursor: 'wait', legend: {}, xAxis: { type: 'category', data: CAT }, yAxis: {},
      series: [{ name: 'A', type: 'bar', data: [10, 20, 15, 30], label: { show: true, position: 'top' } }, { name: 'B', type: 'bar', cursor: 'help', data: [3, 4, 5, 6] }] },
    steps: [mv(item(0, 1)), mv(item(1, 1)), mv(label(0, 2)), mv(comp('legend', 0, e => e.type === 'rect' && !e.silent, 0, 'legend item 0'))] },
  { id: 'triggers',
    note: 'a title with triggerEvent or a link (its subtext with a sublink) and an axis label or name with triggerEvent answer the pointer: pointer',
    option: { animation: false, title: [{ text: 'Zero', triggerEvent: true }, { text: 'One', top: 40, link: 'https://example.com/a', subtext: 'Sub', sublink: 'https://example.com/b' }, { text: 'Two', top: 100 }],
      grid: { top: 140 }, xAxis: { type: 'category', data: CAT, triggerEvent: true, name: 'Days' }, yAxis: {}, series: [{ type: 'line', data: [1, 2, 3, 4] }] },
    steps: [mv(comp('title', 0, isText, 0, 'title 0')), mv(comp('title', 1, isText, 0, 'title 1 text')), mv(comp('title', 1, isText, 1, 'title 1 subtext')),
      mv(comp('title', 2, isText, 0, 'title 2 (silent)')), mv(disp(e => isText(e) && e.style.text === 'Wed', 0, 'x axis label Wed')),
      mv(disp(e => isText(e) && e.style.text === 'Days', 0, 'x axis name'))] },
  { id: 'silent',
    note: 'a silent series and its labels are no target; a legend without selectedMode has only silent children',
    option: { animation: false, legend: { selectedMode: false }, xAxis: { type: 'category', data: CAT }, yAxis: {},
      series: [{ name: 'A', type: 'bar', silent: true, cursor: 'help', data: [10, 20, 15, 30], label: { show: true, position: 'top' } }] },
    steps: [mv(item(0, 1)), mv(label(0, 1)), mv(comp('legend', 0, e => e.type === 'rect', 0, 'legend item 0'))] },
  { id: 'line',
    note: 'a line\'s symbols take the item / series cursor; its polyline and area are elements of their own (pointer)',
    option: { animation: false, xAxis: { type: 'category', data: CAT, boundaryGap: false }, yAxis: {},
      series: [
        { type: 'line', data: [10, 20, { value: 15, cursor: 'help' }, 30], areaStyle: {}, symbolSize: 10 },
        { type: 'line', cursor: 'move', data: [32, 34, 33, 35], symbolSize: 10 },
      ] },
    steps: [mv(item(0, 1)), mv(item(0, 2)), mv(item(1, 2)),
      mv(chart => { const p = chart.getModel().getSeriesByIndex(0).getData().getLayout('points'); return { x: Math.round((p[2] + p[4]) / 2), y: Math.round((p[3] + p[5]) / 2), aim: 'polyline between d1 and d2' }; }),
      mv(chart => { const p = chart.getModel().getSeriesByIndex(0).getData().getLayout('points'); return { x: Math.round((p[2] + p[4]) / 2), y: Math.round((p[3] + p[5]) / 2) + 40, aim: 'area under d1-d2' }; })] },
  { id: 'large',
    note: 'a large scatter is one element, LargeSymbolDraw\'s cursor \'default\' whatever the series says',
    option: { animation: false, xAxis: {}, yAxis: {},
      series: [{ type: 'scatter', large: true, largeThreshold: 100, cursor: 'help', symbolSize: 8, data: Array.from({ length: 300 }, (_, i) => [i % 30, Math.floor(i / 30)]) }] },
    steps: [mv(chart => { const p = chart.getModel().getSeriesByIndex(0).getData().getLayout('points'); return { x: Math.round(p[62]), y: Math.round(p[63]), aim: 'large point 31' }; }), mv(at(300, 20, 'above the grid'))] },
  { id: 'pie',
    note: 'a sector is its item\'s cursor, else pointer; its label is a text (pointer)',
    option: { animation: false, series: [{ type: 'pie', radius: ['30%', '60%'], data: [{ value: 3, name: 'a', cursor: 'help' }, { value: 2, name: 'b' }, { value: 1, name: 'c' }] }] },
    steps: [mv(item(0, 0)), mv(item(0, 1)), mv(label(0, 2)), mv(at(300, 200, 'the hole'))] },
  { id: 'sunburst',
    note: 'a sunburst piece: its item\'s cursor, else its level\'s (the item model\'s parent), else the series\'',
    option: { animation: false, series: [{ type: 'sunburst', cursor: 'wait', levels: [{}, { cursor: 'help' }], label: { show: false },
      data: [{ name: 'a', value: 4, children: [{ name: 'a1', value: 2, cursor: 'crosshair' }, { name: 'a2', value: 2 }] }, { name: 'b', value: 3, cursor: 'move' }] }] },
    steps: [mv(item(0, 1)), mv(item(0, 2)), mv(item(0, 3)), mv(item(0, 4))] },
  { id: 'treemap',
    note: 'a treemap leaf\'s content rect takes the node\'s cursor (level, series); its label is pointer; the breadcrumb pointer; roam (true by default) grabs where nothing is hovered and grabs while it pans',
    option: { animation: false, series: [{ type: 'treemap', cursor: 'help', top: 30, bottom: 60, left: 30, right: 30, levels: [{}, { cursor: 'wait', itemStyle: { borderWidth: 6, borderColor: '#999' } }],
      data: [{ name: 'a', value: 6, children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 2, cursor: 'crosshair' }] }, { name: 'b', value: 4 }] }] },
    steps: [mv(item(0, 2, 20, 30)), mv(item(0, 3, 20, 30)), mv(item(0, 4, 20, 30)), mv(label(0, 4)),
      mv(disp(e => e.type === 'polygon' && !e.silent, 0, 'breadcrumb item', -10, 0)),
      mv(at(10, 10, 'empty')), down(at(10, 10, 'empty')), mv(at(20, 18, 'panning')), up(at(20, 18, 'released')), mv(at(12, 12, 'empty again')),
      mv(chart => { const r = globalRect(itemEl(chart, 0, 1)); return { x: Math.round(r.x + 2), y: Math.round(r.y + r.height / 2), aim: 'the border of parent a (its background)' }; })] },
  { id: 'graph',
    note: 'a draggable node with no cursor option is \'move\'; an item cursor wins over it; a node draggable false keeps pointer; an edge pointer; the RoamController grabs over its area where nothing is hovered, grabbing while it pans, grab again on release',
    option: { animation: false, series: [{ type: 'graph', layout: 'none', roam: true, draggable: true, left: 100, right: 100, top: 80, bottom: 80,
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100, cursor: 'help' }, { name: 'c', x: 100, y: 0, draggable: false }, { name: 'd', x: 0, y: 100 }],
      links: [{ source: 'a', target: 'b' }, { source: 'c', target: 'd' }], lineStyle: { width: 4 }, symbolSize: 20 }] },
    steps: [mv(item(0, 0)), mv(item(0, 1)), mv(item(0, 2)),
      mv(chart => { const g = chart.getModel().getSeriesByIndex(0).getGraph(); const e = g.getEdgeByIndex(0).getGraphicEl(); const p = centre(e); return { x: p[0], y: p[1], aim: 'edge a-b middle' }; }),
      mv(at(300, 120, 'inside the view, nothing')), down(at(300, 120, 'press')), mv(at(310, 125, 'panning')), mv(at(320, 130, 'panning')), up(at(320, 130, 'release')),
      mv(at(5, 5, 'outside the view'))] },
  // [R2-H] a graph on a cartesian2d has no view, but GraphView.render still calls setDraggable: its
  // draggable nodes are 'move' too, while one drags and after
  { id: 'graph-cartesian',
    note: 'a graph on a cartesian2d: a draggable node with no cursor option is "move" (setDraggable whatever the coordinate system), an item cursor wins, draggable false keeps pointer; a drag moves the node (the pointer outruns it on the move of the drag: default there), "move" again over it; no roam here',
    option: { animation: false, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'graph', coordinateSystem: 'cartesian2d', draggable: true, symbolSize: 20,
        data: [{ name: 'a', value: [2, 2] }, { name: 'b', value: [5, 8], cursor: 'help' }, { name: 'c', value: [8, 3], draggable: false }],
        links: [{ source: 'a', target: 'b' }], lineStyle: { width: 4 } }] },
    steps: [mv(item(0, 0)), mv(item(0, 1)), mv(item(0, 2)), mv(item(0, 0)), down(item(0, 0)),
      mv(chart => { const p = item(0, 0)(chart); return { x: p.x + 30, y: p.y - 20, aim: 'dragging a' }; }),
      up(chart => { const p = item(0, 0)(chart); return { x: p.x, y: p.y, aim: 'released a where it went' }; }),
      mv(chart => { const p = item(0, 0)(chart); return { x: p.x, y: p.y, aim: 'a where it went' }; }),
      mv(at(300, 200, 'the grid, nothing'))] },
  { id: 'tree',
    note: 'a tree node is pointer (its item cursor where it has one); roam grabs where nothing is hovered',
    option: { animation: false, series: [{ type: 'tree', roam: true, expandAndCollapse: false, top: 40, bottom: 40, left: 80, right: 120, symbolSize: 12, label: { show: false },
      data: [{ name: 'root', children: [{ name: 'x', cursor: 'help' }, { name: 'y' }] }] }] },
    steps: [mv(item(0, 1)), mv(item(0, 2)), mv(item(0, 3)), mv(at(300, 380, 'empty')), down(at(300, 380, 'press')), mv(at(310, 382, 'panning')), up(at(310, 382, 'release'))] },
  { id: 'sankey',
    note: 'a draggable sankey node (draggable by default) is \'move\' whatever else is written; one that is not keeps pointer; a link pointer; roam true grabs where nothing is hovered',
    option: { animation: false, series: [{ type: 'sankey', roam: true, left: 40, right: 140, top: 40, bottom: 40,
      data: [{ name: 'a' }, { name: 'b', draggable: false }, { name: 'c', cursor: 'help' }], links: [{ source: 'a', target: 'b', value: 1 }, { source: 'a', target: 'c', value: 1 }] }] },
    steps: [mv(item(0, 0)), mv(item(0, 1)), mv(item(0, 2)),
      mv(chart => { const g = chart.getModel().getSeriesByIndex(0).getGraph(); const e = g.getEdgeByIndex(1).getGraphicEl(); const p = centre(e); return { x: p[0], y: p[1], aim: 'link a-c middle' }; }),
      mv(at(300, 395, 'empty'))] },
  { id: 'geo',
    note: 'a geo region is pointer; inside the geo\'s box off its regions the RoamController grabs; grabbing while it pans',
    option: { animation: false, geo: { map: 'cursorSquares', roam: true, left: 100, right: 100, top: 100, bottom: 100 } },
    steps: [mv(disp(e => e.type === 'compound' && !e.silent, 0, 'region A')), mv(at(300, 200, 'between the regions')), down(at(300, 200, 'press')), mv(at(305, 205, 'panning')),
      up(at(305, 205, 'release')), mv(at(5, 5, 'outside'))] },
  { id: 'graphic',
    note: 'a graphic element is its own `cursor`, pointer by default; a silent one is no target',
    option: { animation: false, graphic: [
      { type: 'rect', left: 50, top: 50, shape: { width: 80, height: 40 }, style: { fill: '#c00' }, cursor: 'help' },
      { type: 'circle', left: 200, top: 50, shape: { r: 20 }, style: { fill: '#0c0' } },
      { type: 'rect', left: 300, top: 50, shape: { width: 80, height: 40 }, style: { fill: '#00c' }, silent: true },
    ] },
    steps: [mv(at(90, 70, 'help rect')), mv(at(220, 70, 'circle')), mv(at(340, 70, 'silent rect')), mv(at(500, 300, 'nothing'))] },
  { id: 'matrix',
    note: 'a matrix cell written silent false with a cursor answers on its outline (no fill) with that cursor',
    option: { animation: false, matrix: { left: 100, right: 100, top: 80, bottom: 80, x: { data: ['A', 'B'] }, y: { data: ['X', 'Y'] },
      body: { data: [{ coord: [0, 0], value: 'v', cursor: 'help', silent: false, itemStyle: { borderColor: '#333', borderWidth: 2 } }] } } },
    steps: [
      mv(chart => { const e = componentEls(chart, 'matrix', 0).filter(x => x.type === 'rect' && !x.silent)[0]; must(e, 'no live cell'); const r = globalRect(e);
        return { x: Math.round(r.x), y: Math.round(r.y + r.height / 2), aim: 'the cell\'s left edge' }; }),
      mv(chart => { const e = componentEls(chart, 'matrix', 0).filter(x => x.type === 'rect' && !x.silent)[0]; const r = globalRect(e);
        return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) + 15, aim: 'the cell\'s inside (no fill)' }; })] },
  { id: 'candle-pictorial',
    note: 'a candlestick and a pictorialBar\'s glyphs take the item / series cursor',
    option: { animation: false, xAxis: { data: ['a', 'b', 'c'] }, yAxis: { scale: true }, series: [
      { type: 'candlestick', cursor: 'help', data: [[10, 20, 5, 25], [20, 15, 10, 30], [15, 18, 12, 22]] },
      { type: 'pictorialBar', symbol: 'rect', symbolRepeat: true, symbolSize: [12, 6], data: [8, { value: 12, cursor: 'crosshair' }, 6] }] },
    steps: [mv(item(0, 0)), mv(item(0, 1)), mv(disp(e => e.type === 'path' && !e.silent && e.cursor === 'crosshair', 0, 'a glyph of pictorial d1'))] },
  { id: 'visualmap',
    note: 'a continuous visualMap\'s handles and handle labels are ns-resize standing (ew-resize lying), its in-range bar the same when calculable, its out-of-range bar none (default); its end texts and a piecewise one\'s items pointer',
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: {}, series: [{ type: 'bar', data: [1, 5, 8, 3] }], grid: { right: 140, bottom: 120 },
      visualMap: [
        { type: 'continuous', min: 0, max: 10, calculable: true, range: [2, 8], right: 20, top: 40, text: ['High', 'Low'] },
        { type: 'continuous', orient: 'horizontal', min: 0, max: 10, calculable: true, left: 60, bottom: 20, seriesIndex: 0 },
        { type: 'piecewise', min: 0, max: 10, splitNumber: 2, left: 380, bottom: 20, seriesIndex: 0 },
      ] },
    steps: [
      mv(comp('visualMap', 0, e => e.type === 'path' && e.cursor === 'ns-resize', 0, 'vm0 handle thumb')),
      mv(comp('visualMap', 0, e => isText(e) && e.cursor === 'ns-resize', 0, 'vm0 handle label')),
      mv(comp('visualMap', 0, e => e.type === 'polygon' && e.cursor === 'ns-resize', 0, 'vm0 in-range bar')),
      mv(chart => { const e = componentEls(chart, 'visualMap', 0).filter(x => x.type === 'polygon' && !x.cursor)[0]; must(e, 'no out-of-range bar'); const r = globalRect(e);
        return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + 3), aim: 'vm0 out-of-range bar, its top' }; }),
      mv(comp('visualMap', 0, e => isText(e) && e.style.text === 'High', 0, 'vm0 text High')),
      mv(comp('visualMap', 1, e => e.type === 'path' && e.cursor === 'ew-resize', 0, 'vm1 handle thumb')),
      mv(comp('visualMap', 2, e => e.type === 'path' && !e.silent, 0, 'vm2 piece 0 symbol')),
    ] },
  { id: 'legend-scroll',
    note: 'a scrolling legend\'s page buttons: pointer where it can turn the page, default where it cannot',
    option: { animation: false, legend: { type: 'scroll', top: 10, left: 20, width: 300 }, xAxis: { type: 'category', data: CAT }, yAxis: {},
      series: Array.from({ length: 12 }, (_, i) => ({ name: 'Series number ' + i, type: 'bar', data: [i, i + 1, i + 2, i + 3] })) },
    steps: [mv(comp('legend', 0, e => e.type === 'path' && !e.silent, 0, 'page previous (cannot)')), mv(comp('legend', 0, e => e.type === 'path' && !e.silent, 1, 'page next'))] },
  { id: 'datazoom-inside',
    note: 'an inside dataZoom\'s RoamController grabs over its grid where nothing is hovered (a bar is hovered: its pointer), grabbing while it pans, grab on release',
    option: { animation: false, xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] }, yAxis: {}, dataZoom: [{ type: 'inside' }],
      series: [{ type: 'bar', data: [5, 6, 7, 8, 7, 6, 5, 4], barWidth: 10 }] },
    steps: [mv(at(300, 80, 'grid, above the bars')), mv(item(0, 3)), mv(at(300, 80, 'grid again')), down(at(300, 80, 'press')), mv(at(280, 82, 'panning')), up(at(280, 82, 'release')),
      mv(at(300, 395, 'below the grid'))] },
  { id: 'thumbnail',
    note: 'a graph\'s thumbnail: its box and its window are \'grab\' (ThumbnailView), the copy inside silent',
    option: { animation: false, thumbnail: { right: 10, bottom: 10, width: 160, height: 120 }, series: [{ type: 'graph', layout: 'none', roam: true, left: 40, right: 240, top: 40, bottom: 40,
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100 }], links: [{ source: 'a', target: 'b' }] }] },
    steps: [mv(comp('thumbnail', 0, e => e.type === 'rect' && !e.silent, 0, 'the thumbnail box', -70, -50)), mv(comp('thumbnail', 0, e => e.type === 'rect' && !e.silent, 1, 'its window'))] },
  { id: 'toolbox',
    note: 'a toolbox icon: pointer',
    option: { animation: false, toolbox: { feature: { restore: {}, saveAsImage: {} } }, xAxis: { type: 'category', data: CAT }, yAxis: {}, series: [{ type: 'bar', data: [1, 2, 3, 4] }] },
    steps: [mv(comp('toolbox', 0, e => e.type === 'path', 0, 'restore icon')), mv(at(300, 10, 'nothing'))] },
  // [R2-E] RoamControllers that overlap: their zr listeners run in z order, the highest first (a tie: the one enabled later
  // first); a pan consumes the move (the ones after it do nothing); a release is decided by the last (the lowest)
  { id: 'roam-overlap',
    note: 'two graphs whose roam areas overlap, equal z: the second (enabled later) runs first; a release is for the first to decide -- grab inside its area where nothing is hovered, default outside it',
    option: { animation: false, series: [
      { type: 'graph', layout: 'none', roam: true, left: 50, width: 300, top: 50, height: 300, symbolSize: 10, data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100 }] },
      { type: 'graph', layout: 'none', roam: true, left: 250, width: 300, top: 50, height: 300, symbolSize: 10, data: [{ name: 'c', x: 0, y: 0 }, { name: 'd', x: 100, y: 100 }] }] },
    steps: [mv(at(300, 200, 'in both areas')), down(at(300, 200, 'press in both')), mv(at(320, 205, 'panning')), up(at(320, 205, 'release in both')),
      mv(at(300, 200, 'in both again')), down(at(300, 200, 'press in both')), mv(at(450, 210, 'panning into the second only')), up(at(450, 210, 'release in the second only')),
      mv(at(470, 230, 'the second only')), mv(at(100, 200, 'the first only')), down(at(100, 200, 'press')), mv(at(110, 205, 'panning')), up(at(110, 205, 'release in the first only')),
      mv(at(535, 200, 'the second only, past the first')), down(at(535, 200, 'press in the second only')), mv(at(540, 205, 'the second pans')), up(at(540, 205, 'release in the second only: its word'))] },
  { id: 'roam-overlap-z',
    note: 'the same with the first graph above (z 3): it runs first; a release is for the second to decide',
    option: { animation: false, series: [
      { type: 'graph', layout: 'none', roam: true, z: 3, left: 50, width: 300, top: 50, height: 300, symbolSize: 10, data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100 }] },
      { type: 'graph', layout: 'none', roam: true, left: 250, width: 300, top: 50, height: 300, symbolSize: 10, data: [{ name: 'c', x: 0, y: 0 }, { name: 'd', x: 100, y: 100 }] }] },
    steps: [mv(at(300, 200, 'in both areas')), down(at(300, 200, 'press in both')), mv(at(150, 205, 'panning into the first only')), up(at(150, 205, 'release in the first only')),
      mv(at(300, 200, 'in both again')), down(at(300, 200, 'press in both')), mv(at(450, 210, 'panning into the second only')), up(at(450, 210, 'release in the second only'))] },
  { id: 'roam-globalpan',
    note: 'a graph roam with the brush holding globalPan: a move leaves the brush crosshair; the RoamController mouseup does not look at globalPan',
    option: { animation: false, brush: {}, series: [{ type: 'graph', layout: 'none', roam: true, left: 100, width: 400, top: 50, height: 300, symbolSize: 10,
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100 }] }] },
    steps: [mv(at(300, 200, 'the area')), { type: 'action', payload: { type: 'takeGlobalCursor', key: 'brush', brushOption: { brushType: 'rect', brushMode: 'single' } } },
      mv(at(300, 200, 'the area, the brush on')), down(at(300, 200, 'press')), up(at(300, 200, 'release under the brush')), mv(at(305, 200, 'a move after'))] },
  { id: 'tree-edges',
    note: '[R2-I1] a tree edge is a target of no data: pointer on it (the prototype\'s -- not the cursor of the node it leads to), within max(lineWidth, 5) / 2 of its curve; off it the roam grabs. The edge into x is 1.5 wide (reach 2.5), the one into y 8 (reach 4); a press on an edge still pans',
    option: { animation: false, series: [{ type: 'tree', roam: true, expandAndCollapse: false, top: 60, bottom: 60, left: 80, right: 120, symbolSize: 12, label: { show: false },
      data: [{ name: 'root', children: [{ name: 'x', cursor: 'help' }, { name: 'y', lineStyle: { width: 8 } }] }] }] },
    steps: [mv(treeEdge(0, 2, 0, 'on the edge into x')), mv(treeEdge(0, 2, 1, '1 px off the edge into x')), mv(treeEdge(0, 2, 5, '5 px off the edge into x')),
      mv(treeEdge(0, 3, 2, '2 px off the edge into y')), mv(treeEdge(0, 3, 7, '7 px off the edge into y')),
      down(treeEdge(0, 2, 0, 'press on the edge into x')), mv(chart => { const p = treeEdge(0, 2, 0, '')(chart); return { x: p.x + 20, y: p.y + 10, aim: 'panning' }; }),
      up(chart => { const p = treeEdge(0, 2, 0, '')(chart); return { x: p.x, y: p.y, aim: 'release on the edge where it went' }; })] },
];

// ---------- the picture cases ----------
const PICTURES = [
  { id: 'scatter-symbols',
    note: 'symbol image:// in the unit box scaled by half the symbol size: keepAspect centres the picture there first (so an oblong symbolSize still stretches it), without it the picture covers the box; symbolRotate turns it',
    option: { animation: false, xAxis: { min: 0, max: 10 }, yAxis: { min: 0, max: 10 }, series: [
      { type: 'scatter', symbol: IMG('wide'), symbolSize: [40, 20], symbolKeepAspect: true, data: [[2, 2]] },
      { type: 'scatter', symbol: IMG('tall'), symbolSize: [30, 30], symbolKeepAspect: true, data: [[4, 4]] },
      { type: 'scatter', symbol: IMG('wide'), symbolSize: 24, symbolRotate: 30, data: [[6, 6]] },
      { type: 'scatter', symbol: IMG('tall'), symbolSize: [10, 30], symbolOffset: [5, '50%'], data: [[8, 8]] },
    ] } },
  { id: 'legend-icon',
    note: 'a legend icon image:// in the item box, keepAspect (symbolKeepAspect, true by default) centred in the real 25 x 14 box',
    option: { animation: false, legend: { icon: IMG('wide'), itemWidth: 25, itemHeight: 14 }, xAxis: { type: 'category', data: CAT }, yAxis: {},
      series: [{ name: 'A', type: 'bar', data: [1, 2, 3, 4] }, { name: 'B', type: 'bar', data: [2, 3, 4, 5] }] } },
  { id: 'graphic-natural',
    note: 'a graphic image without a width or a height takes its natural size once loaded; one side written scales the other by the aspect',
    option: { animation: false, graphic: [
      { type: 'image', x: 100, y: 80, style: { image: IMAGES.wide.url } },
      { type: 'image', x: 200, y: 80, style: { image: IMAGES.tall.url, width: 24 } },
      { type: 'image', x: 300, y: 80, style: { image: IMAGES.wide.url, height: 30 } },
      { type: 'image', x: 400, y: 80, style: { image: IMAGES.tall.url, width: 50, height: 20 } },
    ] } },
  { id: 'pictorial',
    note: 'a pictorialBar of pictures, repeated, keepAspect',
    option: { animation: false, xAxis: { data: ['a', 'b'] }, yAxis: { max: 10 }, series: [{ type: 'pictorialBar', symbol: IMG('tall'), symbolKeepAspect: true, symbolRepeat: true, symbolSize: [20, 20], data: [4, 6] }] } },
  { id: 'axis-arrow',
    note: 'an axis line\'s arrow image:// (keepAspect)',
    option: { animation: false, xAxis: { type: 'category', data: CAT, axisLine: { symbol: ['none', IMG('wide')], symbolSize: [20, 20] } }, yAxis: { axisLine: { show: true, symbol: ['none', IMG('tall')], symbolSize: [20, 20] } }, series: [{ type: 'bar', data: [1, 2, 3, 4] }] } },
  { id: 'toolbox-icon',
    note: 'a toolbox feature\'s image:// icon fills the item box (createIcon)',
    option: { animation: false, toolbox: { itemSize: 20, feature: { myTool: { show: true, title: 'mine', icon: IMG('wide'), onclick: '@noop' }, restore: {} } }, xAxis: { type: 'category', data: CAT }, yAxis: {}, series: [{ type: 'bar', data: [1, 2, 3, 4] }] } },
  { id: 'datazoom-handle',
    note: 'a slider dataZoom\'s handleIcon image:// (createSymbol keepAspect) in the handle box',
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: {}, dataZoom: [{ type: 'slider', handleIcon: IMG('tall'), start: 20, end: 80 }], series: [{ type: 'bar', data: [1, 2, 3, 4] }] } },
];

// a function in an option as the port writes it: '@name'
const FN = { noop: function () {} };
function withFns(v) {
  if (typeof v === 'string' && v.startsWith('@') && FN[v.slice(1)]) return FN[v.slice(1)];
  if (Array.isArray(v)) return v.map(withFns);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[k] = withFns(v[k]);
    return o;
  }
  return v;
}

// ---------- running ----------
function describe(t) {
  if (!t) return null;
  return t.type + ':' + (t.cursor || 'default');
}

function runCase(def) {
  const chart = newChart();
  try {
    chart.setOption(withFns(JSON.parse(JSON.stringify(def.option))));
    frame(chart);
    const h = chart.getZr().handler;
    let current = 'default';
    let calls = null;
    h.proxy.setCursor = c => {
      const v = c || 'default';
      if (calls) calls.push(v);
      current = v;
    };
    const steps = [];
    for (const st of def.steps) {
      // [R2-E] an action between the pointer steps
      if (st.type === 'action') {
        calls = [];
        chart.dispatchAction(JSON.parse(JSON.stringify(st.payload)));
        frame(chart);
        steps.push({ type: 'action', payload: st.payload, calls: calls.slice(), cursor: current });
        calls = null;
        continue;
      }
      let p;
      try {
        p = st.at(chart);
      } catch (e) {
        if (e instanceof OracleError) e.message = def.id + ': ' + e.message;
        throw e;
      }
      must(Number.isInteger(p.x) && Number.isInteger(p.y), def.id + ': a step off the integers');
      const hv = h.findHover(p.x, p.y);
      calls = [];
      const ev = { zrX: p.x, zrY: p.y, which: 1, preventDefault() {}, stopPropagation() {} };
      if (st.type === 'move') h.mousemove(ev);
      else if (st.type === 'down') h.mousedown(ev);
      else {
        h.mouseup(ev);
        h.click(Object.assign({}, ev));
      }
      frame(chart);
      steps.push({ type: st.type, x: p.x, y: p.y, aim: p.aim, hover: describe(hv.target), calls: calls.slice(), cursor: current });
      calls = null;
    }
    return { id: def.id, note: def.note, option: def.option, steps };
  } finally {
    chart.dispose();
  }
}

function runPicture(def) {
  const chart = newChart();
  try {
    chart.setOption(withFns(JSON.parse(JSON.stringify(def.option))));
    frame(chart);
    loadImages(chart);
    const images = [];
    chart.getZr().storage.getDisplayList(true).forEach(el => {
      if (el.type !== 'image') return;
      const k = imageKey(el.style.image);
      must(k, def.id + ': an image of no known source');
      const x = el.style.x || 0;
      const y = el.style.y || 0;
      const w = el.getWidth();
      const hh = el.getHeight();
      const m = el.transform || [1, 0, 0, 1, 0, 0];
      const pts = [[x, y], [x + w, y], [x + w, y + hh], [x, y + hh]].map(q => [m[0] * q[0] + m[2] * q[1] + m[4], m[1] * q[0] + m[3] * q[1] + m[5]]);
      images.push({ image: k, corners: pts.map(q => q.map(hexOf)), cornersText: pts.map(q => q.map(textOf)), ignore: !!el.ignore, invisible: !!el.invisible });
    });
    return { id: def.id, note: def.note, option: def.option, images };
  } finally {
    chart.dispose();
  }
}

function generate() {
  return { cases: CASES.map(runCase), pictures: PICTURES.map(runPicture) };
}

// what the notes promise, checked against the run
function check(g) {
  const byId = id => g.cases.find(c => c.id === id);
  const cur = (id, i) => byId(id).steps[i].cursor;
  const hov = (id, i) => byId(id).steps[i].hover;
  const expect = [
    ['bar', 0, 'default', null], ['bar', 1, 'pointer', 'rect'], ['bar', 2, 'help', 'rect'], ['bar', 3, 'crosshair', 'rect'], ['bar', 4, 'pointer', 'tspan'],
    ['bar', 5, 'pointer', 'rect'], ['bar', 6, 'default', null], ['bar', 7, 'default', null],
    ['bar-root', 0, 'wait', 'rect'], ['bar-root', 1, 'help', 'rect'], ['bar-root', 2, 'pointer', 'tspan'], ['bar-root', 3, 'pointer', 'rect'],
    ['triggers', 0, 'pointer', 'tspan'], ['triggers', 1, 'pointer', 'tspan'], ['triggers', 2, 'pointer', 'tspan'], ['triggers', 4, 'pointer', 'tspan'], ['triggers', 5, 'pointer', 'tspan'],
    ['silent', 0, 'default', null], ['silent', 1, 'default', null], ['silent', 2, 'default', null],
    ['line', 0, 'pointer', 'path'], ['line', 1, 'help', 'path'], ['line', 2, 'move', 'path'], ['line', 3, 'pointer', 'ec-polyline'], ['line', 4, 'pointer', 'ec-polygon'],
    ['large', 0, 'default', 'path'],
    ['pie', 0, 'help', 'sector'], ['pie', 1, 'pointer', 'sector'], ['pie', 2, 'pointer', 'tspan'],
    ['graph', 0, 'move', 'path'], ['graph', 1, 'help', 'path'], ['graph', 2, 'pointer', 'path'], ['graph', 4, 'grab', null], ['graph', 6, 'grabbing', null], ['graph', 8, 'grab', null],
    ['graph-cartesian', 0, 'move', 'path'], ['graph-cartesian', 1, 'help', 'path'], ['graph-cartesian', 2, 'pointer', 'path'],
    // (a drag's move: zrender's Handler finds the hover before Draggable drifts the node, and the pointer has outrun it)
    ['graph-cartesian', 3, 'move', 'path'], ['graph-cartesian', 5, 'default', null], ['graph-cartesian', 7, 'move', 'path'],
    ['graph-cartesian', 8, 'default', null],
    ['sankey', 0, 'move', 'rect'], ['sankey', 1, 'pointer', 'rect'], ['sankey', 2, 'move', 'rect'],
    ['geo', 0, 'pointer', 'compound'], ['geo', 1, 'grab', null], ['geo', 3, 'grabbing', null],
    ['graphic', 0, 'help', 'rect'], ['graphic', 1, 'pointer', 'circle'], ['graphic', 2, 'default', null],
    ['matrix', 0, 'help', 'rect'], ['matrix', 1, 'default', null],
    ['tree', 0, 'pointer', 'path'], ['tree', 1, 'help', 'path'], ['tree', 3, 'grab', null], ['tree', 5, 'grabbing', null], ['tree', 6, 'grab', null],
    ['treemap', 0, 'help', 'rect'], ['treemap', 1, 'crosshair', 'rect'], ['treemap', 2, 'wait', 'rect'], ['treemap', 4, 'pointer', 'polygon'], ['treemap', 5, 'grab', null], ['treemap', 7, 'grabbing', null], ['treemap', 10, 'pointer', 'rect'],
    ['sunburst', 0, 'help', 'sector'], ['sunburst', 1, 'crosshair', 'sector'], ['sunburst', 2, 'wait', 'sector'], ['sunburst', 3, 'move', 'sector'],
    ['candle-pictorial', 0, 'help', 'normalCandlestickBox'], ['candle-pictorial', 2, 'crosshair', 'path'],
    ['visualmap', 0, 'ns-resize', 'path'], ['visualmap', 1, 'ns-resize', 'tspan'], ['visualmap', 2, 'ns-resize', 'polygon'], ['visualmap', 3, 'default', 'polygon'],
    ['visualmap', 4, 'pointer', 'tspan'], ['visualmap', 5, 'ew-resize', 'path'], ['visualmap', 6, 'pointer', 'path'],
    ['legend-scroll', 0, 'default', 'path'], ['legend-scroll', 1, 'pointer', 'path'],
    ['datazoom-inside', 0, 'grab', null], ['datazoom-inside', 1, 'pointer', 'rect'], ['datazoom-inside', 4, 'grabbing', null], ['datazoom-inside', 5, 'grab', null],
    ['toolbox', 0, 'pointer', 'path'],
    ['thumbnail', 0, 'grab', 'rect'], ['thumbnail', 1, 'grab', 'rect'],
    // [R2-E] the first graph (enabled first, equal z) runs first and pans; the last decides a release
    ['roam-overlap', 2, 'grabbing', null], ['roam-overlap', 7, 'grab', null], ['roam-overlap', 9, 'default', null], ['roam-overlap', 12, 'default', null],
    ['roam-overlap', 15, 'grabbing', null], ['roam-overlap', 16, 'grab', null],
    ['roam-overlap-z', 3, 'default', null], ['roam-overlap-z', 7, 'grab', null],
    ['roam-globalpan', 2, 'crosshair', null], ['roam-globalpan', 4, 'grab', null], ['roam-globalpan', 5, 'crosshair', null],
    // [R2-I1] a tree edge
    ['tree-edges', 0, 'pointer', 'bezier-curve'], ['tree-edges', 1, 'pointer', 'bezier-curve'], ['tree-edges', 2, 'grab', null],
    ['tree-edges', 3, 'pointer', 'bezier-curve'], ['tree-edges', 4, 'grab', null], ['tree-edges', 6, 'grabbing', null],
  ];
  let n = 0;
  for (const [id, i, c, h] of expect) {
    must(cur(id, i) === c, id + ' step ' + i + ': cursor ' + cur(id, i) + ', the note says ' + c + ' (hover ' + hov(id, i) + ')');
    const hv = hov(id, i);
    must(h === null ? hv === null : (hv !== null && hv.split(':')[0] === h), id + ' step ' + i + ': hovered ' + hv + ', the aim says ' + h);
    n++;
  }
  // the pictures: each case drew some, all of known sources, none at NaN
  for (const p of g.pictures) {
    must(p.images.length > 0, p.id + ': no image drawn');
    for (const im of p.images) for (const q of im.cornersText) for (const v of q) must(isFinite(Number(v)), p.id + ': a corner not finite');
  }
  return n;
}

function oneLine(v) { return JSON.stringify(v); }
function fmt(v, ind) {
  if (Array.isArray(v)) {
    if (v.every(x => x === null || typeof x !== 'object' || (Array.isArray(x) && x.every(y => typeof y !== 'object')))) return oneLine(v);
    return '[\n' + v.map(x => ind + '  ' + fmt(x, ind + '  ')).join(',\n') + '\n' + ind + ']';
  }
  if (v && typeof v === 'object') {
    const ks = Object.keys(v);
    if (ks.length === 0) return '{}';
    if (ks.every(k => v[k] === null || typeof v[k] !== 'object')) return oneLine(v);
    return '{\n' + ks.map(k => ind + '  ' + JSON.stringify(k) + ': ' + (k === 'option' ? oneLine(v[k]) : fmt(v[k], ind + '  '))).join(',\n') + '\n' + ind + '}';
  }
  return JSON.stringify(v);
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

let json1;
let json2;
let checked = 0;
let g1;
try {
  g1 = generate();
  if (process.env.ORACLE_DEBUG) for (const c of g1.cases) { console.log('== ' + c.id); c.steps.forEach((st, i) => console.log('  ' + i + ' ' + st.type + ' ' + st.x + ',' + st.y + ' ' + st.aim + ' -> ' + st.cursor + ' hover ' + st.hover + ' calls ' + st.calls.join(','))); }
  checked = check(g1);
  const images = {};
  for (const k of Object.keys(IMAGES)) images[k] = { url: IMAGES[k].url, width: IMAGES[k].width, height: IMAGES[k].height };
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version,
    W, H, seed: SEED, images, maps: MAPS,
    notes: [
      'The cursor: zrender Handler.mousemove calls proxy.setCursor(target ? target.cursor : \'default\') before it dispatches anything; then the zr-level listeners run: a RoamController (graph, tree, sankey, treemap, geo, map, an inside dataZoom) sets \'grabbing\' while it pans (moveOnMouseMove) and otherwise \'grab\' when the event has no target and the pointer passes its _checkPointer -- the lowest precedence (_decideCursorStyle); on mouseup the same controller sets \'grab\' there, else the target\'s cursor or \'default\'. Nothing is done while globalPan is taken (a brush). HandlerProxy writes `cursor || \'default\'`.',
      'Which elements carry which cursor: Displayable.prototype.cursor = \'pointer\'; silent elements are no target (findHover goes on below them). Series: bar, pictorialBar (each glyph), candlestick, scatter / effectScatter / line symbols, pie, sunburst, a treemap leaf\'s content rect: itemModel.getShallow(\'cursor\') -- the item, its level (treemap / sunburst) or category (graph), the series, the root option; a graph node: item.get(\'cursor\'), else \'move\' when draggable; a draggable sankey node: \'move\'; LargeSymbolDraw / LargeLineDraw: \'default\'. Components: a graphic element its `cursor`; a matrix cell its `cursor`; a scrolling legend\'s page button \'pointer\' / \'default\' by canJump; a continuous visualMap\'s handle thumbs and labels getCursor(orient), its in-range bar the same when calculable; a slider dataZoom\'s handles ew- / ns-resize, its move zone grab / grabbing, its click panel crosshair under brushSelect; brush covers move / the resizes. Everything else that is not silent: pointer.',
      'Pictures: each ZRImage is given __image (its PNG\'s natural size) and its onload, as a browser\'s load would, then a frame; the corners are its style rect (x, y, getWidth(), getHeight()) through its global transform.',
    ],
    cases: g1.cases,
    pictures: g1.pictures,
    checks: { expectations: checked },
  };
  json1 = fmt(out, '') + '\n';
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(out), 'the written JSON does not parse back');
  const g2 = generate();
  check(g2);
  json2 = fmt(Object.assign({}, out, { cases: g2.cases, pictures: g2.pictures }), '') + '\n';
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
const deterministic = json1 === json2;
console.log(g1.cases.length + ' cursor cases (' + g1.cases.reduce((a, c) => a + c.steps.length, 0) + ' steps), ' + g1.pictures.length + ' picture cases ('
  + g1.pictures.reduce((a, c) => a + c.images.length, 0) + ' images); ' + checked + ' expectations; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; '
  + json1.length + ' bytes; ' + logged.length + ' console messages' + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (!deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
