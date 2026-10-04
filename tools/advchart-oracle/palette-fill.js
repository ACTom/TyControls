// Upstream's own answers for PALETTES AND FILLS, batch B9: which colour every
// series and every datum is given (model/mixin/palette.ts getFromPalette with
// `colorLayer` chosen by the requested count, visual/style.ts seriesStyleTask /
// dataStyleTask / dataColorPaletteTask with `colorBy` and its scope shared per
// `type + '-' + colorBy`), what the legend icons are painted with, and what a
// fill that is an OBJECT resolves to on the canvas: a linear or radial
// gradient (zrender canvas/helper.ts createLinearGradient /
// createRadialGradient against Path.getBoundingRect, global or local) and an
// image pattern (canvas/graphic.ts createCanvasPattern: the repetition and the
// DOMMatrix translate(x, y) . rotate(rotation) . scale(scaleX, scaleY)).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) at
// 800 x 600 with `animation: false`, Math.random replaced by the port's
// xorshift32 (seed 2463534242, reset before each chart). After setOption the
// display list is updated (zr.storage.getDisplayList(true)) and the live models
// and elements are read. Every chart is disposed in a finally.
//
//   node tools/advchart-oracle/palette-fill.js
//
// writes tests/fixtures/advchart-palette-fill.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// THE CANVAS COORDINATES ARE A TRANSCRIPTION. The SVG renderer maps a gradient
// to objectBoundingBox units and never calls createLinearGradient, so the
// numbers a canvas would be handed are worked out here from what the canvas
// painter would read: the element's getBoundingRect() (the path's box, grown
// by the stroke when the element has one -- by max(lineWidth, 5) when it has
// no fill) and the gradient object, by helper.ts createLinearGradient /
// createRadialGradient verbatim. The element's transform takes them to the
// chart's coordinates (`grad`); a radial gradient is recorded only on an
// element whose transform is a uniform scale and a move. The pattern matrix
// is DOMMatrix's translate / rotate (degrees, as zrender hands it over) /
// scale, multiplied out here (node has no DOMMatrix).
//
// Conventions (as markers-area.js)
//   hex     a double as the 16 hex digits of its IEEE-754 bits, big-endian
//   paint   a style colour exactly as upstream holds it: a css string, an
//           object (gradient or pattern, as JSON), or null (undefined / null)
//
// Top level
//   source, W, H, seed, api, notes[], images {name: data URL}, cases[], guards[]
//   cases[]  one per chart:
//     id, note, option (as fed; a pattern's image is written as
//       "@img:<name>" and stands for images[name]), seriesCount
//       (ecModel.getSeriesCount())
//     series[] every series model, eachRawSeries order:
//       index, type, name (the option's, null when unnamed), colorBy
//       (getColorBy()), drawType, filtered (ecModel.isSeriesFiltered), fill /
//       stroke (paint: data.getVisual('style') fill and stroke), fromPalette
//       (data.getVisual('colorFromPalette') == true),
//       facts  what the transcription is fed: keyWritten (the style's
//              colour under drawType is truthy), hasAuto ('auto' on fill or
//              stroke as written), ownColor (the series' own `color`
//              normalised, json, null when none), ownLayer (its own
//              `colorLayer`, json or null)
//       rows[] every RAW row: raw, name (dataAll.getName), key (the palette
//              key: the name, else the raw index as a string), inView,
//              own (the raw item writes the colour under drawType), mapped
//              (in view, not own, and yet not from the palette: a visual
//              channel wrote it), fill (paint: the item visual's colour under
//              drawType; null when not in view), el (null, or the drawn
//              element: see below)
//       line   a line series: {polyline: el, area: el | null}, else null
//       areas  markArea polygons in areaData order: [{item, el}] (null when
//              allClipped)
//     legends[] per legend component, its content group's items in order:
//              [{name, icons: [{fill, stroke}]}] -- every displayable of the
//              icon in traversal order
//   el       {kind (el.type), fill, stroke (paint), lineWidth, rect [hex x, y,
//            w, h] (getBoundingRect, local), transform [hex a..f] | null,
//            grad / sgrad: the fill / stroke gradient on the canvas in chart
//            coordinates, {type, x1, y1, x2, y2, r} hex (r 0 linear; x2 = x1,
//            y2 = y1 radial), or null; pat / spat: the fill / stroke pattern,
//            {repeat, matrix [hex a, b, c, d, e, f]}, or null}
//   guards[] one per mutation of the transcriptions: id, mutation, named (the
//            cases that must change), changed, ok = named is a subset of
//            changed
//
// The palette transcription (getFromPalette, SeriesModel.getColorFromPalette,
// seriesStyleTask's palette branch, dataColorPaletteTask) is fed `facts`,
// `rows[].key / inView / own / mapped` and the root option, and must give
// every series' and every in-view row's colour bit for bit. Self-checks (any
// failure: nothing is written, exit 1): the transcription reproduces every
// series; the facts agree with what upstream did (fromPalette, the row flags);
// the gradient transcription is fed only elements it can place; anchors;
// every guard is ok; two generations in the process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-palette-fill.json');

const W = 800;
const H = 600;

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
const json = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
const isObj = v => v !== null && typeof v === 'object';

// ---------- the pattern images: tiny PNGs, made here ----------
const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
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
// pixels: rows of [r, g, b, a]
function png(pixels) {
  const h = pixels.length;
  const w = pixels[0].length;
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const raw = [];
  for (const row of pixels) {
    raw.push(0);
    for (const p of row) raw.push(p[0], p[1], p[2], p[3]);
  }
  const idat = zlib.deflateSync(Buffer.from(raw), { level: 9 });
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  return 'data:image/png;base64,' + Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]).toString('base64');
}
const RED = [255, 0, 0, 255];
const BLUE = [0, 0, 255, 255];
const CLEAR = [0, 0, 0, 0];
const IMAGES = {
  // a 2 x 2 checker: red where (x + y) is even
  checker: png([[RED, BLUE], [BLUE, RED]]),
  // 4 x 2: two red columns, two blue
  stripes: png([[RED, RED, BLUE, BLUE], [RED, RED, BLUE, BLUE]]),
  // 2 x 2: one opaque red pixel top-left, the rest clear
  dot: png([[RED, CLEAR], [CLEAR, CLEAR]]),
};
// an option with "@img:<name>" in it, made real
function realise(v) {
  if (typeof v === 'string' && v.startsWith('@img:')) {
    must(IMAGES[v.slice(5)], 'no image ' + v);
    return IMAGES[v.slice(5)];
  }
  if (Array.isArray(v)) return v.map(realise);
  if (isObj(v)) {
    const o = {};
    for (const k of Object.keys(v)) o[k] = realise(v[k]);
    return o;
  }
  return v;
}
// and back: a paint recorded with the image written as it was fed
function unrealise(v) {
  if (typeof v === 'string') {
    for (const k of Object.keys(IMAGES)) if (IMAGES[k] === v) return '@img:' + k;
    return v;
  }
  if (Array.isArray(v)) return v.map(unrealise);
  if (isObj(v)) {
    const o = {};
    for (const k of Object.keys(v)) o[k] = unrealise(v[k]);
    return o;
  }
  return v;
}
const paint = v => (v == null ? null : typeof v === 'string' ? v : unrealise(json(v)));

// ============================================================================
// The transcriptions
// ============================================================================

// ---------- the palette: palette.ts, Series.ts, style.ts ----------
const normalizeToArray = v => (v instanceof Array ? v : v == null ? [] : [v]);
function getNearestPalette(palettes, n, mut) {
  for (let i = 0; i < palettes.length; i++) {
    if (mut.layerGe ? palettes[i].length >= n : palettes[i].length > n) return palettes[i];
  }
  return palettes[palettes.length - 1];
}
// getFromPalette; `layer` is the raw colorLayer (undefined when absent)
function getFromPalette(defaultPalette, layer, name, scope, n, mut) {
  if (Object.prototype.hasOwnProperty.call(scope.names, name)) return scope.names[name];
  if (mut.noLayer) layer = undefined;
  let palette = (n == null || !layer) ? defaultPalette : getNearestPalette(layer, n, mut);
  palette = palette || defaultPalette;
  if (!palette || !palette.length) return undefined;
  const picked = mut.idxMod ? palette[scope.idx % palette.length] : palette[scope.idx];
  if (name && !(mut.noMemoUndefined && picked === undefined)) scope.names[name] = picked;
  scope.idx = (scope.idx + 1) % palette.length;
  return picked;
}
const newScope = () => ({ idx: 0, names: {} });

function transcribePalette(c, mut) {
  const root = c.realOption;
  const globalPalette = normalizeToArray(root.color === undefined ? DEFAULT_COLORS : root.color);
  const globalLayer = root.colorLayer;
  const globalScope = newScope();
  const n = c.seriesCount;
  const out = { series: {}, rows: {} };
  // seriesStyleTask, every series (filtered too), in order
  for (const s of c.series) {
    const f = s.facts;
    const ownScope = newScope();
    const pick = (name, scope, req) => {
      let col = getFromPalette(normalizeToArray(f.ownColor), f.ownLayer === null ? undefined : f.ownLayer, name,
        scope || ownScope, req, mut);
      if (!col && !(mut.ownFallbackEmptyOnly && normalizeToArray(f.ownColor).length)) {
        col = getFromPalette(globalPalette, globalLayer, name, scope || globalScope, req, mut);
      }
      return col;
    };
    let fill;
    if (!f.keyWritten || f.hasAuto) {
      const name = s.name == null ? 'series\u0000' + s.index : String(s.name);
      const col = pick(name, null, mut.noSeriesRequest ? undefined : n);
      fill = f.keyWritten ? s[s.drawType] : col;
    }
    else fill = s[s.drawType];
    out.series[s.index] = { fill, pick };
  }
  // dataColorPaletteTask
  const scopes = {};
  const live = c.series.filter(s => mut.hiddenTakes || !s.filtered);
  for (const s of live) {
    if (s.colorBy === 'series') continue;
    const key = mut.scopePerSeries ? 'S' + s.index : mut.scopeTypeOnly ? s.type : s.type + '-' + s.colorBy;
    if (!scopes[key]) scopes[key] = newScope();
    s._scope = scopes[key];
  }
  for (const s of live) {
    if (s.colorBy === 'series') continue;
    const fromPaletteSeries = mut.autoPerData ? (!s.facts.keyWritten || s.facts.hasAuto) : !s.facts.keyWritten;
    const count = s.rows.length;
    for (const r of s.rows) {
      let fromPalette = fromPaletteSeries;
      if (r.inView || mut.ownAnywhere) {
        if (r.own || r.mapped) fromPalette = false;
      }
      if (!fromPalette) continue;
      const col = out.series[s.index].pick(r.key, mut.ownScopeForData ? null : s._scope,
        mut.dataRequestSeries ? n : count);
      out.rows[s.index + ':' + r.raw] = col;
    }
  }
  return out;
}

// the difference between the transcription and the record
function paletteDiff(c, mut) {
  const t = transcribePalette(c, mut);
  const d = [];
  for (const s of c.series) {
    const want = s[s.drawType];
    if (JSON.stringify(paint(t.series[s.index].fill)) !== JSON.stringify(want)) {
      d.push('series ' + s.index + ': ' + JSON.stringify(want) + ' upstream, ' + JSON.stringify(paint(t.series[s.index].fill)));
    }
    if (s.filtered) continue;
    for (const r of s.rows) {
      if (!r.inView) continue;
      const k = s.index + ':' + r.raw;
      if (!(k in t.rows)) continue;
      if (JSON.stringify(paint(t.rows[k])) !== JSON.stringify(r.fill)) {
        d.push('row ' + k + ': ' + JSON.stringify(r.fill) + ' upstream, ' + JSON.stringify(paint(t.rows[k])));
      }
    }
  }
  // a row the transcription did not colour keeps the series' colour or its own
  return d;
}

// ---------- the canvas: helper.ts createLinearGradient / createRadialGradient ----------
const isSafeNum = v => isFinite(v);
function canvasGradient(obj, rect, mut) {
  const global = mut.globalAsLocal ? false : mut.localAsGlobal ? true : !!obj.global;
  if (obj.type === 'radial') {
    const width = rect.width;
    const height = rect.height;
    const min = mut.radialWidth ? width : Math.min(width, height);
    let x = obj.x == null ? 0.5 : obj.x;
    let y = obj.y == null ? 0.5 : obj.y;
    let r = obj.r == null ? 0.5 : obj.r;
    if (!global) {
      x = x * width + rect.x;
      y = y * height + rect.y;
      r = r * min;
    }
    x = isSafeNum(x) ? x : 0.5;
    y = isSafeNum(y) ? y : 0.5;
    r = r >= 0 && isSafeNum(r) ? r : 0.5;
    return { type: 'radial', x1: x, y1: y, x2: x, y2: y, r };
  }
  let x = obj.x == null ? 0 : obj.x;
  let x2 = obj.x2 == null ? 1 : obj.x2;
  let y = obj.y == null ? 0 : obj.y;
  let y2 = obj.y2 == null ? (mut.y2One ? 1 : 0) : obj.y2;
  if (!global) {
    x = x * rect.width + rect.x;
    x2 = x2 * rect.width + rect.x;
    y = y * rect.height + rect.y;
    y2 = y2 * rect.height + rect.y;
  }
  x = isSafeNum(x) ? x : 0;
  x2 = isSafeNum(x2) ? x2 : 1;
  y = isSafeNum(y) ? y : 0;
  y2 = isSafeNum(y2) ? y2 : 0;
  return { type: 'linear', x1: x, y1: y, x2, y2, r: 0 };
}
// Path.getBoundingRect from the path's own box: grown by the stroke
function strokeRect(pathRect, style, hasPath, mut) {
  const r = { x: pathRect.x, y: pathRect.y, width: pathRect.width, height: pathRect.height };
  const hasStroke = style.stroke != null && style.stroke !== 'none' && style.lineWidth > 0;
  if (mut.noStrokeRect || !hasStroke || !hasPath) return r;
  const hasFill = style.fill != null && style.fill !== 'none';
  let w = style.lineWidth;
  if (!hasFill) w = Math.max(w, mut.threshold4 ? 4 : 5);
  // strokeNoScale (a symbol): the width is screen pixels, the box local
  const ls = style.lineScale;
  if (ls > 1e-10) {
    r.width += w / ls;
    r.height += w / ls;
    r.x -= w / ls / 2;
    r.y -= w / ls / 2;
  }
  return r;
}
// the canvas pattern's DOMMatrix: translateSelf . rotateSelf(0, 0, deg) . scaleSelf
function patternMatrix(p, mut) {
  const RAD2DEG = 180 / Math.PI;
  const deg = (p.rotation || 0) * RAD2DEG;
  const rad = deg * Math.PI / 180;
  const cs = Math.cos(rad);
  const sn = Math.sin(rad);
  const sx = p.scaleX || 1;
  const sy = p.scaleY || 1;
  const tx = p.x || 0;
  const ty = p.y || 0;
  if (mut.patternScaleFirst) {
    // scale . rotate . translate: the move scaled
    return [sx * cs, sx * sn, -sy * sn, sy * cs, sx * (cs * tx - sn * ty), sy * (sn * tx + cs * ty)];
  }
  return [sx * cs, sx * sn, -sy * sn, sy * cs, tx, ty];
}
// the global form of a local gradient: through the element's transform
function toGlobal(g, m) {
  if (!m) return g;
  const ap = (x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
  const p1 = ap(g.x1, g.y1);
  const p2 = ap(g.x2, g.y2);
  const sc = Math.sqrt(m[0] * m[0] + m[1] * m[1]);
  return { type: g.type, x1: p1[0], y1: p1[1], x2: p2[0], y2: p2[1], r: g.r * sc };
}
const gradRec = g => (g ? { type: g.type, x1: hex(g.x1), y1: hex(g.y1), x2: hex(g.x2), y2: hex(g.y2), r: hex(g.r) } : null);

// what the canvas makes of one element, from its record's facts
function elementCanvas(e, mut) {
  const style = { fill: e.rawFill, stroke: e.rawStroke, lineWidth: e.lineWidth, lineScale: e.lineScale };
  const rect = strokeRect(e.pathRect, style, e.hasPath, mut);
  const out = {};
  for (const [k, v, gk, pk] of [['fill', e.rawFill, 'grad', 'pat'], ['stroke', e.rawStroke, 'sgrad', 'spat']]) {
    out[gk] = null;
    out[pk] = null;
    if (!isObj(v)) continue;
    if (v.colorStops != null) out[gk] = gradRec(toGlobal(canvasGradient(v, rect, mut), e.transform));
    else if (v.image != null) out[pk] = { repeat: v.repeat || 'repeat', matrix: patternMatrix(v, mut).map(hex) };
  }
  return out;
}

// ============================================================================
// Reading upstream
// ============================================================================
function readEl(el) {
  if (!el) return null;
  if (el.type === 'group') {
    // a symbol: its path; a radar's group of polygon and symbols is not read
    if (!el.getSymbolPath) return null;
    const p = el.getSymbolPath();
    must(p && p.style, 'a group without a symbol path');
    el = p;
  }
  const rect = el.getBoundingRect();
  must(el.path && el.path.getBoundingRect, 'no path proxy');
  const pr = el.path.getBoundingRect();
  el.updateTransform && el.updateTransform();
  const m = el.transform ? Array.from(el.transform) : null;
  const s = el.style;
  const hasStroke = s.stroke != null && s.stroke !== 'none' && s.lineWidth > 0;
  const hasObj = isObj(s.fill) || isObj(s.stroke);
  if (hasObj && m) {
    const sc = Math.sqrt(m[0] * m[0] + m[1] * m[1]);
    must(m[1] === 0 && m[2] === 0 && m[0] === m[3] && sc > 0,
      'an object fill on an element whose transform is not a uniform scale: ' + m.join());
  }
  const lineScale = s.strokeNoScale ? el.getLineScale() : 1;
  const facts = { rawFill: s.fill, rawStroke: s.stroke, lineWidth: s.lineWidth, lineScale, hasPath: el.path.len() > 0,
    pathRect: { x: pr.x, y: pr.y, width: pr.width, height: pr.height }, transform: m };
  // the transcription's rect is getBoundingRect itself
  const tr = strokeRect(facts.pathRect, { fill: s.fill, stroke: s.stroke, lineWidth: s.lineWidth, lineScale }, facts.hasPath, {});
  must(tr.x === rect.x && tr.y === rect.y && tr.width === rect.width && tr.height === rect.height,
    'getBoundingRect is not the path box grown by the stroke: ' + JSON.stringify([rect, tr]) + ' ' + hasStroke);
  const cv = elementCanvas(facts, {});
  return Object.assign({ kind: el.type, fill: paint(s.fill), stroke: paint(s.stroke),
    lineWidth: typeof s.lineWidth === 'number' ? hex(s.lineWidth) : null,
    rect: [rect.x, rect.y, rect.width, rect.height].map(hex), transform: m ? m.map(hex) : null }, cv,
  { _facts: facts });
}

const DEFAULT_COLORS = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];

function slaveOf(ec, sm) {
  const master = ec.getComponent('markArea');
  if (!master) return null;
  const MM = Object.getPrototypeOf(master.constructor);
  must(typeof MM.getMarkerModelFromSeries === 'function', 'MarkerModel.getMarkerModelFromSeries not reachable');
  return MM.getMarkerModelFromSeries(sm, 'markArea') || null;
}

function readChart(cs) {
  const realOption = realise(cs.option);
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: cs.width || W, height: cs.height || H });
  try {
    chart.setOption(Object.assign({ animation: false }, realOption));
    chart.getZr().storage.getDisplayList(true);
    const ec = chart.getModel();
    const series = [];
    ec.eachRawSeries(s => {
      const data = s.getData();
      const all = s.getRawData();
      const dk = data.getVisual('drawType');
      const vstyle = data.getVisual('style');
      const stylePath = s.visualStyleAccessPath || 'itemStyle';
      const keyOpt = { fill: 'color', stroke: stylePath === 'lineStyle' ? 'color' : 'borderColor' }[dk];
      const written = s.get([stylePath, keyOpt]);
      const fillW = s.get([stylePath, 'color']);
      const strokeW = s.get([stylePath, stylePath === 'lineStyle' ? 'color' : 'borderColor']);
      const own = s.option.color === undefined ? null : json(normalizeToArray(s.option.color));
      const filtered = ec.isSeriesFiltered(s);
      const idxMap = {};
      if (!filtered) data.each(i => { idxMap[data.getRawIndex(i)] = i; });
      const rows = [];
      const view = chart.getViewOfSeriesModel(s);
      all.each(raw => {
        const i = idxMap[raw];
        const inView = i !== undefined;
        const item = all.getRawDataItem(raw);
        const ist = item && item[stylePath];
        const ownCol = !!(ist && ist[keyOpt] != null);
        const name = all.getName(raw);
        let fill = null;
        let fp = null;
        let el = null;
        if (inView) {
          const st = data.getItemVisual(i, 'style');
          fill = paint(st[dk]);
          fp = !!data.getItemVisual(i, 'colorFromPalette');
          el = readEl(data.getItemGraphicEl(i));
        }
        rows.push({ raw, name: name == null ? null : String(name), key: name || (raw + ''), inView, own: ownCol,
          mapped: inView && !ownCol && !fp && !!data.getVisual('colorFromPalette'), fill, el, _fp: fp });
      });
      let line = null;
      if (s.subType === 'line' && view && view._polyline) {
        line = { polyline: readEl(view._polyline), area: view._polygon ? readEl(view._polygon) : null };
      }
      let areas = null;
      const slave = slaveOf(ec, s);
      if (slave) {
        const ad = slave.getData();
        areas = [];
        for (let k = 0; k < ad.count(); k++) areas.push({ item: k, el: readEl(ad.getItemGraphicEl(k)) });
      }
      series.push({ index: s.seriesIndex, type: s.subType, name: s.option.name == null ? null : String(s.option.name),
        colorBy: s.getColorBy(), drawType: dk, filtered, fill: paint(vstyle.fill), stroke: paint(vstyle.stroke),
        fromPalette: !!data.getVisual('colorFromPalette'),
        facts: { keyWritten: !!written, hasAuto: fillW === 'auto' || strokeW === 'auto', ownColor: own,
          ownLayer: s.option.colorLayer === undefined ? null : json(s.option.colorLayer) },
        rows, line, areas });
    });
    const legends = [];
    for (const lm of ec.findComponents({ mainType: 'legend' })) {
      const lv = chart.getViewOfComponentModel(lm);
      const items = [];
      lv.getContentGroup().eachChild(g => {
        if (!g.childAt) return;
        const icon = g.childAt(0);
        const text = g.childAt(1);
        const icons = [];
        const visit = e => {
          if (e.isGroup) { e.eachChild(visit); return; }
          if (e.style) icons.push({ fill: paint(e.style.fill), stroke: paint(e.style.stroke) });
        };
        visit(icon);
        items.push({ name: text && text.style ? String(text.style.text) : null, icons });
      });
      legends.push(items);
    }
    return { seriesCount: ec.getSeriesCount(), series, legends, realOption };
  } finally {
    chart.dispose();
  }
}

// ============================================================================
// The cases
// ============================================================================
const CASES = [];
function add(id, note, option, extra) {
  CASES.push(Object.assign({ id, note, option }, extra || {}));
}
const P3 = ['#aa0000', '#00aa00', '#0000aa'];
const L3 = [['#110000', '#220000'], ['#003300', '#006600', '#009900'], ['#000044', '#000088', '#0000bb', '#0000ee', '#4444ff']];
const cat = n => Array.from({ length: n }, (_, i) => 'c' + i);
const bars = (k, extra) => Array.from({ length: k }, (_, i) => Object.assign({ type: 'bar', data: [1, 2, 3] }, extra || {}));
const pieData = (names, extra) => names.map((n, i) => Object.assign({ name: n, value: i + 1 }, extra || {}));
const noLabel = { label: { show: false }, labelLine: { show: false } };
const pie = (names, extra) => Object.assign({ type: 'pie', data: pieData(names) }, noLabel, extra || {});
const grid = { xAxis: { type: 'category', data: cat(4) }, yAxis: { type: 'value' } };
const lin = (stops, o) => Object.assign({ type: 'linear', colorStops: stops }, o || {});
const rad = (stops, o) => Object.assign({ type: 'radial', colorStops: stops }, o || {});
const S2 = [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }];
const S3 = [{ offset: 0, color: 'rgba(255,0,0,1)' }, { offset: 0.5, color: '#00ff00' }, { offset: 1, color: 'transparent' }];

// ---- colorLayer, series scope: the layer is chosen by the SERIES count ----
for (const k of [1, 2, 3, 4, 6]) {
  add('layer-series-' + k, k + ' bars: the first layer longer than ' + k,
    Object.assign({ color: P3, colorLayer: L3 }, grid, { series: bars(k) }));
}
add('layer-empty', 'colorLayer: [] -- palettes[-1] is undefined, the default palette stands',
  Object.assign({ color: P3, colorLayer: [] }, grid, { series: bars(2) }));
add('layer-no-color', 'a colorLayer and no color: the default palette is upstream\'s (the test writes it)',
  Object.assign({ colorLayer: L3 }, grid, { series: bars(2) }));
add('layer-holes', 'a hole in the series: getSeriesCount counts models, so 2 picks layer [1]',
  Object.assign({ color: P3, colorLayer: L3 }, grid, { series: [{ type: 'bar', data: [1, 2] }, null, { type: 'bar', data: [2, 1] }] }));
add('layer-series-own', 'one series with its own colorLayer, another with its own color',
  Object.assign({ color: P3 }, grid, { series: [
    { type: 'bar', data: [1, 2], colorLayer: [['#123456'], ['#654321', '#abcdef', '#fedcba']] },
    { type: 'bar', data: [2, 3], color: ['#0f0f0f', '#f0f0f0'] },
    { type: 'bar', data: [3, 1] }] }));
add('layer-own-empty-layer', "a series' own colorLayer whose layer is empty answers undefined, and the chart's palette answers instead -- though the series wrote its own color",
  Object.assign({ color: P3 }, grid, { series: [
    { type: 'bar', data: [1, 2] },
    { type: 'bar', data: [2, 3], color: ['#0f0f0f'], colorLayer: [[]] }] }));
add('layer-written-skip', 'a written colour takes no slot; a repeated name shares one',
  Object.assign({ color: P3, colorLayer: L3 }, grid, { series: [
    { type: 'bar', name: 'A', data: [1] }, { type: 'bar', name: 'B', data: [1], itemStyle: { color: '#777777' } },
    { type: 'bar', name: 'A', data: [2] }, { type: 'bar', name: 'C', data: [3] }] }));

// ---- colorLayer, data scope: the layer is chosen by the DATA count ----
for (const k of [1, 2, 3, 5]) {
  add('layer-pie-' + k, 'a pie of ' + k + ': the layer by its data count',
    { color: P3, colorLayer: L3, series: [pie(cat(k))] });
}
add('layer-pie-overflow', 'five slices take layer [2] to index 0; two slices then ask layer [0] (length 2) for index 0 -- and a third? see the next case',
  { color: P3, colorLayer: L3, series: [pie(cat(4)), pie(['q0', 'q1'], { center: ['75%', '50%'] })] });
add('layer-pie-undefined', 'four slices leave the shared scope at index 4; a one-slice pie asks layer [0] for palette[4]: undefined, no fill',
  { color: P3, colorLayer: L3, series: [pie(cat(4)), pie(['q0'], { center: ['75%', '50%'] }), pie(['r0', 'r1', 'r2'], { center: ['25%', '80%'], radius: 40 })] });
add('layer-pie-undefined-memo', 'the undefined pick is remembered under its name: the same name in the next pie gets undefined too',
  { color: P3, colorLayer: L3, series: [pie(cat(4)), pie(['q0'], { center: ['75%', '50%'] }), pie(['q0', 'z'], { center: ['25%', '80%'], radius: 40 })] });

// ---- colorBy ----
add('colorby-bar-data', 'colorBy: data on a bar: one colour per datum; the series still takes its slot',
  Object.assign({ color: P3, legend: {} }, grid, { series: [{ type: 'bar', name: 'b', colorBy: 'data', data: [1, 2, 3, 4] }, { type: 'bar', name: 'b2', data: [2, 2, 2, 2] }] }));
add('colorby-root-data', 'a root colorBy: data reaches every series whose type has no default; a pie keeps its own',
  Object.assign({ color: P3, colorBy: 'data' }, grid, { series: [
    { type: 'bar', data: [1, 2, 3] }, { type: 'line', data: [3, 2, 1] }, { type: 'scatter', data: [2, 3, 1] },
    pie(['x', 'y'], { radius: 40, center: ['80%', '20%'] })] }));
add('colorby-line-data', 'a line by data: the symbols take the per-datum colours, the line and its area the series\'',
  Object.assign({ color: P3 }, grid, { series: [{ type: 'line', colorBy: 'data', symbol: 'circle', areaStyle: {}, data: [1, 3, 2, 4] }] }));
add('colorby-scatter-data', 'scatter by data',
  { color: P3, xAxis: {}, yAxis: {}, series: [{ type: 'scatter', colorBy: 'data', data: [[1, 2], [2, 3], [3, 1], [4, 4], [5, 2]] }] });
add('colorby-shared-scope', 'two bars by data share one scope (bar-data); a line by data has its own (line-data)',
  Object.assign({ color: ['#a00001', '#a00002', '#a00003', '#a00004', '#a00005', '#a00006', '#a00007'] }, grid, { series: [
    { type: 'bar', colorBy: 'data', data: [{ name: 'p', value: 1 }, { name: 'q', value: 2 }] },
    { type: 'bar', colorBy: 'data', data: [{ name: 'r', value: 2 }, { name: 's', value: 1 }, { name: 't', value: 3 }] },
    { type: 'line', colorBy: 'data', symbol: 'rect', data: [3, 1, 2, 4] }] }));
add('colorby-shared-names', 'the shared scope remembers names: the second bar\'s categories reuse the first\'s colours',
  { color: P3, xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: {}, series: [
    { type: 'bar', colorBy: 'data', data: [{ name: 'a', value: 1 }, { name: 'b', value: 2 }] },
    { type: 'bar', colorBy: 'data', data: [{ name: 'b', value: 1 }, { name: 'c', value: 2 }, { name: 'a', value: 3 }] }] });
add('colorby-unknown', 'colorBy: \'foo\' is not \'series\': per datum, in a scope of its own (bar-foo)',
  Object.assign({ color: P3 }, grid, { series: [{ type: 'bar', colorBy: 'data', data: [{ name: 'p', value: 1 }, { name: 'q', value: 2 }] },
    { type: 'bar', colorBy: 'foo', data: [{ name: 'r', value: 2 }, { name: 's', value: 1 }, { name: 't', value: 3 }] }] }));
add('colorby-pie-series', 'a pie by series: every slice the series colour, and the legend says so',
  { color: P3, legend: {}, series: [pie(['a', 'b', 'c'], { colorBy: 'series', radius: 80, center: ['30%', '50%'] }), pie(['d', 'e'], { radius: 80, center: ['70%', '50%'] })] });
add('colorby-funnel', 'a funnel by data and a funnel by series; the legend follows',
  { color: P3, legend: {}, series: [
    { type: 'funnel', left: '5%', width: '40%', data: pieData(['a', 'b', 'c']), label: { show: false } },
    { type: 'funnel', left: '55%', width: '40%', colorBy: 'series', data: pieData(['d', 'e']), label: { show: false } }] });
add('colorby-pie-funnel-scopes', 'a pie and a funnel do not share: pie-data and funnel-data',
  { color: P3, series: [pie(['a', 'b'], { center: ['25%', '50%'], radius: 60 }), { type: 'funnel', left: '55%', width: '40%', data: pieData(['c', 'd']), label: { show: false } }] });
add('colorby-two-pies', 'two pies share pie-data: the second continues where the first stopped, a shared name shares a colour',
  { color: ['#c1', '#c2', '#c3', '#c4', '#c5'].map(s => s + '0000'), legend: {}, series: [pie(['a', 'b', 'c'], { center: ['25%', '50%'], radius: 60 }),
    pie(['b', 'd', 'e'], { center: ['75%', '50%'], radius: 60 })] });
add('colorby-pie-own-palette', 'a pie with its own color list shares the scope index with a pie that has none',
  { color: P3, series: [pie(['a', 'b'], { color: ['#101010', '#202020', '#303030'], center: ['25%', '50%'], radius: 60 }),
    pie(['c', 'd'], { center: ['75%', '50%'], radius: 60 })] });
add('colorby-pie-auto', 'itemStyle.color: auto on a pie: the series pick for every slice, and no per-data slot',
  { color: P3, series: [pie(['a', 'b'], { itemStyle: { color: 'auto' }, center: ['25%', '50%'], radius: 60 }),
    pie(['c', 'd'], { center: ['75%', '50%'], radius: 60 })] });
add('colorby-pie-written', 'a written series colour: no per-data slot at all, so the next pie starts at 0',
  { color: P3, series: [pie(['a', 'b'], { itemStyle: { color: '#445566' }, center: ['25%', '50%'], radius: 60 }),
    pie(['c', 'd'], { center: ['75%', '50%'], radius: 60 })] });
add('colorby-item-own', 'a datum with its own colour takes no slot',
  { color: P3, legend: {}, series: [{ type: 'pie', ...noLabel, data: [{ name: 'a', value: 1 }, { name: 'b', value: 2, itemStyle: { color: '#123456' } }, { name: 'c', value: 3 }, { name: 'd', value: 1 }] }] });
add('colorby-hidden-own', 'a legend-hidden slice with its own colour still takes a slot: it is not in the data the style task saw',
  { color: P3, legend: { selected: { b: false } }, series: [{ type: 'pie', ...noLabel, data: [{ name: 'a', value: 1 }, { name: 'b', value: 2, itemStyle: { color: '#123456' } }, { name: 'c', value: 3 }] }] });
add('colorby-hidden-series', 'a legend-hidden bar series by data takes no data slots; the other bar starts at 0',
  Object.assign({ color: P3, legend: { selected: { first: false } } }, grid, { series: [
    { type: 'bar', name: 'first', colorBy: 'data', data: [{ name: 'p', value: 1 }, { name: 'q', value: 2 }] },
    { type: 'bar', name: 'second', colorBy: 'data', data: [{ name: 'r', value: 2 }, { name: 's', value: 1 }, { name: 't', value: 3 }] }] }));
add('colorby-bar-item-own', 'a bar by data, one datum written: the others skip it',
  Object.assign({ color: P3 }, grid, { series: [{ type: 'bar', colorBy: 'data', data: [1, { value: 2, itemStyle: { color: '#0a0b0c' } }, 3, 4] }] }));
add('colorby-visualmap', 'a piecewise visualMap colours some rows; the palette skips them',
  Object.assign({ color: P3, visualMap: { type: 'piecewise', show: false, dimension: 1, pieces: [{ gt: 2.5, color: '#999999' }], outOfRange: {} } }, grid,
    { series: [{ type: 'bar', colorBy: 'data', data: [1, 3, 2, 4] }] }));
add('colorby-dup-names', 'repeated datum names inside one pie share a slot; an empty name keys on the raw index',
  { color: P3, series: [{ type: 'pie', ...noLabel, data: [{ name: 'a', value: 1 }, { name: 'a', value: 2 }, { name: '', value: 1 }, { value: 2 }, { name: '1', value: 3 }] }] });
add('colorby-radar', 'two radars share radar-data',
  { color: P3, radar: { indicator: [{ max: 5 }, { max: 5 }, { max: 5 }] }, series: [
    { type: 'radar', data: [{ name: 'r1', value: [1, 2, 3] }, { name: 'r2', value: [3, 2, 1] }] },
    { type: 'radar', data: [{ name: 'r3', value: [2, 2, 2] }] }] });

// ---- gradients ----
const area = (fill, extra) => Object.assign({ type: 'line', data: [1, 3, 2, 4], markArea: { data: [[{ xAxis: 'c1', itemStyle: { color: fill } }, { xAxis: 'c2' }]] } }, extra || {});
add('grad-area-linear', 'a markArea filled with a local linear gradient, left to right by default',
  Object.assign({ color: P3 }, grid, { series: [area(lin(S2))] }));
add('grad-area-vertical', 'a local linear gradient top to bottom, three stops with transparent',
  Object.assign({ color: P3 }, grid, { series: [area(lin(S3, { x: 0, y: 0, x2: 0, y2: 1 }))] }));
add('grad-area-radial', 'a local radial gradient on a wide, short area: the radius scales by the smaller side',
  Object.assign({ color: P3 }, grid, { series: [area(null, { markArea: { data: [[{ xAxis: 'c0', yAxis: 1, itemStyle: { color: rad(S2, { x: 0.3, y: 0.6, r: 0.8 }) } },
    { xAxis: 'c3', yAxis: 2 }]] } })] }));
add('grad-area-global', 'global linear and radial gradients: chart coordinates',
  Object.assign({ color: P3 }, grid, { series: [
    area(lin(S2, { x: 100, y: 0, x2: 700, y2: 0, global: true })),
    Object.assign(area(rad(S2, { x: 400, y: 300, r: 200, global: true })), { markArea: { data: [[{ xAxis: 'c2', itemStyle: { color: rad(S2, { x: 400, y: 300, r: 200, global: true }) } }, { xAxis: 'c3' }]] } })] }));
add('grad-area-stroke', 'a gradient area with a border: the box grows by the border width',
  Object.assign({ color: P3 }, grid, { series: [area(lin(S2), { markArea: { itemStyle: { borderWidth: 6, borderColor: '#333333' }, data: [[{ xAxis: 'c1', itemStyle: { color: lin(S2) } }, { xAxis: 'c2' }]] } })] }));
add('grad-area-stroke-grad', 'a gradient border on a plain area',
  Object.assign({ color: P3 }, grid, { series: [area('#cccccc', { markArea: { itemStyle: { borderWidth: 4, borderColor: lin(S2, { x2: 0, y2: 1 }) }, data: [[{ xAxis: 'c0', itemStyle: { color: '#dddddd' } }, { xAxis: 'c3' }]] } })] }));
add('grad-area-series', 'no item colour: the series colour, a gradient, is the area\'s fill and border',
  Object.assign({ color: P3 }, grid, { series: [{ type: 'line', itemStyle: { color: lin(S2, { x2: 0, y2: 1 }) }, data: [1, 3, 2, 4],
    markArea: { data: [[{ yAxis: 1 }, { yAxis: 2 }]] } }] }));
add('grad-bar-items', 'a bar series gradient and a datum gradient, local; a datum written plain replaces the series gradient',
  Object.assign({ color: P3 }, grid, { series: [{ type: 'bar', itemStyle: { color: lin(S2, { x2: 0, y2: 1 }) },
    data: [1, { value: 3, itemStyle: { color: rad(S2) } }, { value: 2, itemStyle: { color: '#00ff00' } }, { value: 4, itemStyle: { color: lin(S2, { x: 0, y: 0, x2: 1, y2: 1 }) } }] }] }));
add('grad-bar-global', 'a datum gradient in chart coordinates',
  Object.assign({ color: P3 }, grid, { series: [{ type: 'bar', data: [2, { value: 3, itemStyle: { color: lin(S2, { x: 0, y: 100, x2: 0, y2: 500, global: true }) } }] }] }));
add('grad-bar-border', 'a gradient bar with a border: the box grows by it',
  Object.assign({ color: P3 }, grid, { series: [{ type: 'bar', itemStyle: { color: lin(S2), borderWidth: 4, borderColor: '#222222' }, data: [1, 2, 3] }] }));
add('grad-pie', 'a pie gradient: each sector\'s own box -- the arc\'s extent, not the disc',
  { color: P3, series: [pie(['a', 'b'], { startAngle: 0, itemStyle: { color: rad(S2, { r: 0.7 }) } }),
    pie(['c', 'd', 'e'], { center: ['85%', '20%'], radius: 50, itemStyle: { color: lin(S2) } })].map((s, i) =>
    (i === 0 ? Object.assign(s, { data: [{ name: 'a', value: 1 }, { name: 'b', value: 1 }] }) : s)) });
add('grad-pie-items', 'pie data gradients, local and global; a ring',
  { color: P3, series: [pie(['a', 'b', 'c', 'd'], { radius: ['30%', '70%'] })].map(s => Object.assign(s, { data: [
    { name: 'a', value: 1, itemStyle: { color: lin(S2) } }, { name: 'b', value: 2 },
    { name: 'c', value: 3, itemStyle: { color: rad(S3, { x: 0.5, y: 0.5, r: 0.5 }) } },
    { name: 'd', value: 2, itemStyle: { color: lin(S2, { x: 0, y: 0, x2: 800, y2: 600, global: true }) } }] })) });
add('grad-pie-border', 'a pie gradient with a border colour: the box grows by the border width (1 by default)',
  { color: P3, series: [pie(['a', 'b'], { itemStyle: { color: lin(S2), borderColor: '#ffffff', borderWidth: 3 } })] });
add('grad-funnel', 'a funnel datum gradient and a series gradient',
  { color: P3, series: [{ type: 'funnel', label: { show: false }, itemStyle: { color: lin(S2, { x2: 0, y2: 1 }) },
    data: [{ name: 'a', value: 3 }, { name: 'b', value: 2, itemStyle: { color: rad(S2) } }, { name: 'c', value: 1 }] }] });
add('grad-line-stroke', 'a line drawn with a gradient: a stroke with no fill grows its box by max(width, 5)',
  Object.assign({ color: P3 }, grid, { series: [{ type: 'line', symbol: 'none', lineStyle: { width: 2, color: lin(S2) }, data: [1, 3, 2, 4] }] }));
add('grad-area-fill', 'an area gradient: the polygon has no stroke',
  Object.assign({ color: P3 }, grid, { series: [{ type: 'line', symbol: 'none', areaStyle: { color: lin(S3, { x2: 0, y2: 1 }) }, data: [1, 3, 2, 4] }] }));

// ---- patterns ----
const pat = (img, o) => Object.assign({ image: '@img:' + img }, o || {});
add('pat-bar', 'a bar series filled with a repeating pattern',
  Object.assign({ color: P3, legend: {} }, grid, { series: [{ type: 'bar', name: 'p', itemStyle: { color: pat('checker') }, data: [1, 2, 3] }] }));
add('pat-pie-items', 'pie data patterns: repeat-x, no-repeat moved and scaled, a turned one',
  { color: P3, legend: {}, series: [pie(['a', 'b', 'c', 'd'])].map(s => Object.assign(s, { data: [
    { name: 'a', value: 1, itemStyle: { color: pat('stripes', { repeat: 'repeat-x' }) } },
    { name: 'b', value: 2, itemStyle: { color: pat('dot', { repeat: 'no-repeat', x: 400, y: 300, scaleX: 8, scaleY: 8 }) } },
    { name: 'c', value: 3, itemStyle: { color: pat('checker', { rotation: Math.PI / 4, scaleX: 3, scaleY: 2 }) } },
    { name: 'd', value: 2 }] })) });
add('pat-area', 'a markArea filled with a pattern',
  Object.assign({ color: P3 }, grid, { series: [area(pat('checker', { repeat: 'repeat-y', x: 3, y: 1 }))] }));
add('pat-url', 'a pattern whose image is a URL: upstream fetches it; the port cannot',
  Object.assign({ color: P3 }, grid, { series: [{ type: 'bar', itemStyle: { color: { image: 'https://example.invalid/tile.png', repeat: 'repeat' } }, data: [1, 2] }] }));

// ---- legend icons ----
add('legend-pie-data', 'a pie\'s legend icons are its slices\' colours, palette and written alike',
  { color: P3, legend: {}, series: [{ type: 'pie', ...noLabel, data: [{ name: 'a', value: 1 }, { name: 'b', value: 2, itemStyle: { color: '#123123' } }, { name: 'c', value: 1 }, { name: 'd', value: 1 }] }] });
add('legend-bar-data', 'a bar by data: its legend icon is the series colour, not a datum\'s',
  Object.assign({ color: P3, legend: {} }, grid, { series: [{ type: 'bar', name: 'x', colorBy: 'data', data: [1, 2, 3] }, { type: 'bar', name: 'y', data: [1, 1, 1] }] }));
add('legend-layer', 'legend icons of a layered palette',
  Object.assign({ color: P3, colorLayer: L3, legend: {} }, grid, { series: bars(3).map((s, i) => Object.assign(s, { name: 's' + i })) }));

// ============================================================================
// Generation, checks and guards
// ============================================================================
function strip(o) {
  // the private facts out of the record
  if (Array.isArray(o)) return o.map(strip);
  if (isObj(o)) {
    const r = {};
    for (const k of Object.keys(o)) if (!k.startsWith('_')) r[k] = strip(o[k]);
    return r;
  }
  return o;
}

function generate() {
  const cases = [];
  for (const cs of CASES) {
    const rec = readChart(cs);
    cases.push({ id: cs.id, note: cs.note, option: cs.option, seriesCount: rec.seriesCount, series: rec.series,
      legends: rec.legends, realOption: rec.realOption });
  }
  return cases;
}

function allEls(c) {
  const out = [];
  for (const s of c.series) {
    for (const r of s.rows) if (r.el) out.push(r.el);
    if (s.line) { out.push(s.line.polyline); if (s.line.area) out.push(s.line.area); }
    if (s.areas) for (const a of s.areas) if (a.el) out.push(a.el);
  }
  return out;
}
function canvasDiff(c, mut) {
  const d = [];
  for (const e of allEls(c)) {
    const cv = elementCanvas(e._facts, mut);
    for (const k of ['grad', 'sgrad', 'pat', 'spat']) {
      if (JSON.stringify(cv[k]) !== JSON.stringify(e[k])) d.push(k + ' differs');
    }
  }
  return d;
}

const GUARDS = [
  { id: 'layer-ge', mutation: 'a layer is long enough at length >= count', mut: { layerGe: true }, named: ['layer-series-2', 'layer-pie-3'] },
  { id: 'layer-ignored', mutation: 'colorLayer is never read', mut: { noLayer: true }, named: ['layer-series-1', 'layer-pie-2', 'layer-series-own'] },
  { id: 'series-no-request', mutation: 'the series scope asks with no count (so no layer)', mut: { noSeriesRequest: true }, named: ['layer-series-3', 'legend-layer'] },
  { id: 'data-request-series', mutation: 'the data scope asks with the series count', mut: { dataRequestSeries: true }, named: ['layer-pie-5'] },
  { id: 'idx-mod', mutation: 'palette[idx % length]: no undefined pick', mut: { idxMod: true }, named: ['layer-pie-undefined'] },
  { id: 'memo-undefined', mutation: 'an undefined pick is not remembered', mut: { noMemoUndefined: true }, named: ['layer-pie-undefined-memo'] },
  { id: 'scope-per-series', mutation: 'every series its own data scope', mut: { scopePerSeries: true }, named: ['colorby-shared-scope', 'colorby-two-pies', 'colorby-radar', 'colorby-shared-names', 'colorby-pie-own-palette'] },
  { id: 'scope-type-only', mutation: 'the scope key is the type alone', mut: { scopeTypeOnly: true }, named: ['colorby-unknown'] },
  { id: 'auto-per-data', mutation: '\'auto\' still asks per datum', mut: { autoPerData: true }, named: ['colorby-pie-auto'] },
  { id: 'own-anywhere', mutation: 'a datum\'s own colour counts out of view too', mut: { ownAnywhere: true }, named: ['colorby-hidden-own'] },
  { id: 'hidden-takes-slots', mutation: 'a legend-hidden series takes data slots', mut: { hiddenTakes: true }, named: ['colorby-hidden-series'] },
  { id: 'own-fallback-only-when-empty', mutation: "the chart's palette answers only for a series with no color of its own", mut: { ownFallbackEmptyOnly: true }, named: ['layer-own-empty-layer'] },
  { id: 'own-scope-for-data', mutation: 'the data pass uses the series\' own scope', mut: { ownScopeForData: true }, named: ['colorby-two-pies'] },
  { id: 'no-stroke-rect', mutation: 'the gradient box ignores the stroke', mut: { noStrokeRect: true }, named: ['grad-area-stroke', 'grad-bar-border', 'grad-line-stroke', 'grad-pie-border'] },
  { id: 'threshold-4', mutation: 'a stroke-only path grows by max(width, 4)', mut: { threshold4: true }, named: ['grad-line-stroke'] },
  { id: 'global-as-local', mutation: 'global: true is ignored', mut: { globalAsLocal: true }, named: ['grad-area-global', 'grad-bar-global', 'grad-pie-items'] },
  { id: 'local-as-global', mutation: 'every gradient is global', mut: { localAsGlobal: true }, named: ['grad-area-linear', 'grad-pie'] },
  { id: 'radial-width', mutation: 'a radial radius scales by the width', mut: { radialWidth: true }, named: ['grad-area-radial', 'grad-pie'] },
  { id: 'linear-y2-one', mutation: 'a linear gradient defaults downward', mut: { y2One: true }, named: ['grad-area-linear', 'grad-bar-border'] },
  { id: 'pattern-scale-first', mutation: 'the pattern matrix scales the move', mut: { patternScaleFirst: true }, named: ['pat-pie-items'] },
];

function check(cases) {
  const byId = {};
  for (const c of cases) byId[c.id] = c;
  for (const c of cases) {
    const d = paletteDiff(c, {});
    must(!d.length, c.id + ': the palette transcription: ' + d.join('; '));
    must(!canvasDiff(c, {}).length, c.id + ': the canvas transcription');
    for (const s of c.series) {
      must(s.fromPalette === !s.facts.keyWritten, c.id + '/' + s.index + ': fromPalette ' + s.fromPalette);
      for (const r of s.rows) {
        if (!r.inView) continue;
        must(r._fp === (s.fromPalette && !r.own && !r.mapped), c.id + '/' + s.index + '/' + r.raw + ': the row flag');
      }
    }
  }
  // anchors
  const sOf = (id, i) => byId[id].series[i];
  must(sOf('layer-series-1', 0).fill === '#110000', 'one bar: layer [0] (length 2 > 1)');
  must(sOf('layer-series-2', 1).fill === '#006600', 'two bars: layer [1] (length 3 > 2)');
  must(sOf('layer-series-6', 0).fill === '#000044', 'six bars: the last layer');
  must(sOf('layer-pie-undefined', 1).rows[0].fill === null, 'the undefined pick');
  must(sOf('layer-pie-undefined', 1).rows[0].el.fill === null, 'the undefined pick draws no fill');
  must(sOf('colorby-root-data', 0).colorBy === 'data' && sOf('colorby-root-data', 3).colorBy === 'data', 'root colorBy');
  must(sOf('colorby-pie-series', 0).rows.every(r => r.fill === sOf('colorby-pie-series', 0).fill), 'pie by series');
  must(sOf('colorby-hidden-own', 0).rows[2].fill === P3[2], 'the hidden own-colour slice took a slot');
  must(sOf('colorby-pie-auto', 0).rows.every(r => r.fill === P3[0]), 'auto');
  must(sOf('colorby-pie-auto', 1).rows[0].fill === P3[0], 'auto took no per-data slot');
  must(byId['legend-pie-data'].legends[0][1].icons[0].fill === '#123123', 'the legend icon follows the datum');
  must(sOf('grad-pie', 0).rows[0].el.grad !== null, 'a pie gradient placed');
  must(sOf('pat-bar', 0).rows[0].el.pat !== null, 'a pattern placed');
  must(sOf('grad-area-stroke', 0).areas[0].el.rect[2] !== sOf('grad-area-linear', 0).areas[0].el.rect[2], 'the stroke grew the box');
  return GUARDS.map(gd => {
    const changed = [];
    for (const c of cases) {
      let d;
      try {
        d = paletteDiff(c, gd.mut).concat(canvasDiff(c, gd.mut));
      } catch (e) {
        d = ['threw ' + e.message];
      }
      if (d.length) changed.push(c.id);
    }
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(n => changed.includes(n)) };
  });
}

// the compact writer of box-merge.js
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
  if (Array.isArray(v)) {
    const items = Array.from(v, x => fmt(x === undefined ? null : x, inner));
    if (items.every(t => !t.includes('\n'))) {
      const lines = [];
      let cur = '';
      for (const t of items) {
        if (cur && inner.length + cur.length + 1 + t.length + 1 > LINE) { lines.push(cur); cur = ''; }
        cur += (cur ? ',' : '') + t;
      }
      lines.push(cur);
      return '[\n' + lines.map(l => inner + l).join(',\n') + '\n' + ind + ']';
    }
    return '[\n' + items.map(x => inner + x).join(',\n') + '\n' + ind + ']';
  }
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner))
    .join(',\n') + '\n' + ind + '}';
}

function build() {
  const cases = generate();
  const guards = check(cases);
  return {
    source: 'ECharts 6.1 dist (' + path.basename(DIST) + '), SVG SSR; canvas fill coordinates transcribed from zrender canvas/helper.ts',
    W, H, seed: SEED,
    api: {
      palette: 'palette.ts getFromPalette: the name memo first (undefined included); palette = (requestNum == null || !colorLayer) ? color : the first layer longer than requestNum, else the last; palette || color; nothing when empty; palette[idx] (undefined past the end), remembered under a non-empty name; idx = (idx + 1) % length',
      series: 'Series.getColorFromPalette: its own color / colorLayer (get(..., true)) first, else the chart\'s, with the same scope (a series scope is the series itself, then the global model)',
      seriesStyleTask: 'every series, filtered too: getColorFromPalette(series name, null, getSeriesCount()) when the colour under drawType is falsy, or a function, or fill / stroke is \'auto\'; colorFromPalette only when it was falsy',
      dataColorPaletteTask: 'eachSeries (not filtered) with getColorBy() !== \'series\' (series colorBy, else the type default -- pie, funnel, gauge, radar, chord, themeRiver are \'data\' -- else the root\'s, else \'series\'): one scope per type + \'-\' + colorBy; every RAW row whose item visual says colorFromPalette (a row not in view reads the series visual) gets getColorFromPalette(name || rawIndex, scope, rawCount)',
      canvas: 'createLinearGradient / createRadialGradient against getBoundingRect(): the path box, grown by lineWidth (max(lineWidth, 5) without a fill) when the element has a stroke; a pattern is createPattern(image, repeat || \'repeat\') with setTransform(translate(x, y) rotate(rotation) scale(scaleX || 1, scaleY || 1))',
    },
    notes: [
      'An undefined palette pick leaves the style without a fill: nothing is painted (layer-pie-undefined).',
      'A legend icon is painted with the series\' or the datum\'s style as it is, gradient and pattern objects included.',
      'pat-url: upstream starts a fetch and fills nothing until the image arrives; a data: URL is decoded at once.',
    ],
    images: IMAGES,
    cases: strip(cases).map(c => { delete c.realOption; return c; }),
    guards,
  };
}

let g1;
let json1;
let json2;
try {
  g1 = build();
  json1 = fmt(g1, '') + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(g1), 'the written JSON does not parse back to the record');
  const g2 = build();
  json2 = fmt(g2, '') + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = g1.guards.filter(gd => !gd.ok);
g1.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ' (' + gd.mutation + '): named '
  + gd.named.join(' / ') + '; changes ' + gd.changed.length + ': ' + gd.changed.join(', ')));
const deterministic = json1 === json2;
const nRows = g1.cases.reduce((n, c) => n + c.series.reduce((m, s) => m + s.rows.length, 0), 0);
console.log(g1.cases.length + ' cases (' + nRows + ' rows); ' + (g1.guards.length - bad.length) + '/' + g1.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
