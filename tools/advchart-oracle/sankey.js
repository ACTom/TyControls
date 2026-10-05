/*
Upstream's own answers for the SANKEY series, first static frame (batch K1):
the graph build, the layout, the colour visual, every link band, node rect and
node label exactly as chart/sankey/SankeySeries.ts (getInitialData, the level
models keyed by depth, the item model chain item -> levels[layout depth] ->
series), helper/createGraphFromNodeEdge.ts + data/Graph.ts (node keys id ?? name
?? index, a numeric source / target is an array index, dropped edges),
sankeyLayout.ts (node values, the Kahn breadth pass, nodeAlign, kx, the columns,
ky, resolveCollisions, the relaxation, the edge depths), sankeyVisual.ts (the
linear colour map over the palette by node value), SankeyView.ts (SankeyPath,
applyCurveStyle, the rects, the labels), zrender PathProxy / bbox / curve (the
band bbox), Element.updateInnerText + contain/text calculateTextPosition (the
label anchor and colours), ZRText (the tspans) and echarts util/graphic.ts
traverseUpdateZ (label z2) build them. The dist is the oracle, not the TS
source: the 6.1.0 dist has no `sort` option (see wf78/upstream.md).

Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) with
Math.random replaced by the port's xorshift32 (seed 2463534242, reset before
each chart) and process.env.TZ = 'UTC' set inside this script before anything
touches Date. EVERY case is rendered with `animation: false` (forced on the
gallery files, recorded as animationForced). After setOption it runs
zr.storage.getDisplayList(true) (transforms, updateInnerText, TSpan layout) and
reads the live graph, the view's main group and the display list. Every chart
is disposed in a finally. The hand-written and gallery cases are also recorded
through dist/echarts.min.js and must record identically.

  node tools/advchart-oracle/sankey.js

writes tests/fixtures/advchart-sankey.json (ORACLE_OUT overrides;
ORACLE_RANDOM=<n> sets the number of random graphs, each run through the 20
variants).

-----------------------------------------------------------------------------
Number encoding.
  hex    a double as its 16 hex digits, big-endian IEEE-754 bits (the Pascal
         side: StrToQWord('$' + s) moved into a Double). Every GEOMETRY value
         is written this way (layout, kx, ky, shapes, bboxes, transforms,
         anchors, gradient points): JSON decimal parsing is not trusted to the
         last bit on the Pascal side.
  dec    a plain JSON number (shortest round-trip form), or one of the strings
         'NaN', 'Infinity', '-Infinity', '-0'. Every hex field has a dec
         companion (`<name>Text`, or the same key under a `...Text` object), for
         reading only.
A colour is a css string exactly as upstream holds it ('rgba(...)' from the
visual, the option's own string otherwise), a gradient record, or null
(undefined: nothing is filled / stroked).

Top level
  source, seed, tz ('UTC'), api {...}, notes[] (including the REFUSED inputs),
  measure   zrender's node width estimator (core/platform.ts), the same table as
            advchart-treemap.json's: firstCode 32, lastCode 126, fontSize 12,
            ratio[] (hex: the width of each char code at 1px), ratioText[],
            rule, samples[]. TZrSsrMeasurer.Create(measure.ratio,
            measure.firstCode). A label's line height is measure('\u56fd') = px.
  counts    totals over the fixture (cases, nodes, links, rects, labels, tspans,
            and coverage counters): minimums for the test
  cases[], guards[]

Per case
  id, note, gallery (the gallery file name or null), option (the exact JSON
  fed, animation false included; null for a gallery case: load
  examples/advchart/gallery/<gallery>.json and set animation false),
  animationForced, W, H (the canvas), random (null or {graph, variant}),
  palette   ecModel.option.color: the global palette (the theme's nine colours
            unless the option has a top-level `color`); inject it
  textStyle ecModel.option.textStyle (fontFamily 'Microsoft YaHei' here)
  ground    {background (zr.getBackgroundColor(): 'transparent' unless the option
            sets backgroundColor), isDark}: an
            INPUT of the outside label halo (and the outside fill in dark mode)
  foreignElements  display-list elements of other components (a gallery title)
            left out of `elements`
  series[]  exactly one sankey series

Per series
  name (the option name or null)
  resolved (the transcription's account; box / transform are also read from
            upstream and compared):
    box {x, y, width, height} (hex) + boxText; transform null (the 5e-5 rule
    dropped it) or [tx, ty] (hex) + transformText; orient, nodeWidth, nodeGap,
    layoutIterations (the option), iterations (after the any-zero-value rule),
    nodeAlign (the option value as fed, null when absent -> 'justify'),
    maxDepth, kx, minKy (hex + dec), columns (the final nodesByBreadth, node
    indices, in the order of the last collision pass), colorList (the list the
    colour visual maps: series `color` ?? the global palette, as an array),
    colourExtent [min, max] (dec), levels (depth (dec) -> the level index that
    won, last one per depth)
  nodes[] in data order (= graph.nodes order):
    index, id (the graph key: '' + (id ?? name ?? index)), name (the store name:
    the item name as a string, '' when none), rawValue (dec: node.getValue(),
    NaN when absent), value (dec, the layout value), depth (dec, the layout
    depth after nodeAlign), kahnDepth (dec, before nodeAlign), skNodeHeight
    (only 'right'; else null), x, y, dx, dy (hex, LOCAL to the box, exactly as
    upstream holds them: NaN, negative, -0 included) + layoutText, colour (the
    colour visual: css string, gradient record, or null), colourSource
    ('mapped' | 'custom'), level (the level depth the chain used, dec, or null),
    outEdges / inEdges (edge indices in their FINAL, sorted order), label (null:
    label.show false, no Text) or the label record below (the node's Text)
  edges[] in edge dataIndex order (= graph.edges = draw order):
    index (dataIndex among the surviving edges), row (the option index of the
    link item), source, target (node indices), value (dec, NaN when absent),
    dy, sy, ty (hex + layoutText), level (the SOURCE node's level depth or
    null), band (the SankeyPath, see "piece")
  nodes[].rect  the node's Rect, see "piece"
  piece  z, z2, zlevel, transform (6 hex or null), fill, stroke, lineWidth,
    opacity (el.style as read: lineWidth / opacity include zrender's prototype
    defaults 1),
    link:  shape {x1, y1, x2, y2, cpx1, cpy1, cpx2, cpy2, extent (hex), orient}
           + shapeText, bbox {x, y, width, height} (hex: el.getBoundingRect(),
           the zrender path bbox of M C L C Z, GROWN by the stroke when stroked)
           + bboxText
    node:  shape {x, y, width, height, r} (hex) + shapeText, bbox (likewise)
    A gradient fill record: {type, x, y, x2, y2, global (the object's own
    fields, null when absent), colorStops [{offset, color}], canvas {x, y, x2,
    y2} (hex: zrender canvas createLinearGradient's points for this element:
    obj * bbox + bbox origin, a non-finite value replaced by 0 / 1 / 0 / 0) +
    canvasText, canvasGlobal {x, y, x2, y2} (hex: those points through
    el.transform) + canvasGlobalText}. The SVG renderer (what SSR writes) uses
    objectBoundingBox units instead; `canvas` is the rule a raster renderer
    follows.
  elements[] zrender's display list for this series in PAINT order: kind 'link'
    | 'node' | 'tspan', index (edge or node index; a tspan's node), z, z2,
    zlevel; a tspan also carries line (its line number), transform (6 hex or
    null), fill, stroke, lineWidth, opacity, text, x, y (hex), textAlign,
    textBaseline, font
  label record (nodes[].label):
    index, text (the full string), lines (the tspan texts; [] for ''),
    hostRect {x, y, width, height} (hex: the rect's bbox incl. stroke, through
    the rect's transform, a negative size flipped), position (the chain value),
    distance, anchor {x, y} (hex: calculateTextPosition's point, global),
    transform (6 hex or null: the 5e-5 rule on the anchor), align,
    verticalAlign (calculateTextPosition's, null for an [x, y] position),
    insidePosition (a string position containing 'inside'), inside (that AND
    the rect has a fill: Path.canBeInsideText), colourRule ('option' |
    'inside' | 'outside'), fill, stroke, lineWidth, font (the first tspan's;
    null without tspans), z2

Guards[] one per mutation of the transcription (ref.js's mutants plus the
  traps of upstream.md 8): id, mutation, named (cases that must change), red
  (recorded fields the mutated transcription gets wrong over the whole fixture),
  cases (how many cases change), sample, ok (red > 0 and every named case red),
  differs (the first changed fields of up to two cases: upstream vs mutated).
*/
'use strict';
process.env.TZ = 'UTC';
if (new Date(2017, 0, 1).getTimezoneOffset() !== 0 || new Date(2017, 6, 1).getTimezoneOffset() !== 0
  || new Date(2017, 0, 1).getTime() !== Date.UTC(2017, 0, 1)) {
  console.log('FAILED: process.env.TZ = \'UTC\' did not take effect');
  process.exit(1);
}
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const PROD = require(DIST.replace(/echarts(\.min)?\.js$/, 'echarts.min.js'));
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-sankey.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');

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

// ---------- zrender core/util.ts, in effect for plain JSON-born data ----------
const isArray = Array.isArray;
const isObject = v => v !== null && (typeof v === 'object' || typeof v === 'function');
const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
function zrClone(source) {
  if (source == null || typeof source !== 'object') return source;
  if (isArray(source)) return source.map(zrClone);
  const r = {};
  for (const k in source) if (hasOwn(source, k) && k !== '__proto__') r[k] = zrClone(source[k]);
  return r;
}
const json = v => (v === undefined ? null : zrClone(v));
const m6 = t => (t ? Array.from(t).slice(0, 6) : null);

// ---------- number encodings ----------
const hexBuf = new DataView(new ArrayBuffer(8));
function hex(v) {
  hexBuf.setFloat64(0, v);
  return hexBuf.getUint32(0).toString(16).padStart(8, '0') + hexBuf.getUint32(4).toString(16).padStart(8, '0');
}
function dec(v) {
  if (typeof v !== 'number') return v;
  if (Number.isNaN(v)) return 'NaN';
  if (v === Infinity) return 'Infinity';
  if (v === -Infinity) return '-Infinity';
  if (Object.is(v, -0)) return '-0';
  return v;
}
const hexOrNull = v => (v == null ? null : hex(v));
const decOrNull = v => (v == null ? null : dec(v));

// ============================================================================
// zrender's node width estimator (core/platform.ts), decoded from the dist
// ============================================================================
const FIRST_CODE = 32;
const LAST_CODE = 126;
const DEFAULT_FONT_SIZE = 12;
function decodeTable(literal, where) {
  const s = Function('"use strict"; return (' + literal + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, where + ': the width table is not 95 characters');
  return s;
}
const DIST_TEXT = fs.readFileSync(DIST, 'utf8');
const MAP_STR = (() => {
  const line = DIST_TEXT.split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = decodeTable(line.slice(line.indexOf('=') + 1).trim().replace(/;$/, ''), DIST);
  if (fs.existsSync(ZRENDER_SRC)) {
    const m = /const defaultWidthMapStr = (`[^`]*`)/.exec(fs.readFileSync(ZRENDER_SRC, 'utf8'));
    must(m && decodeTable(m[1], ZRENDER_SRC) === s, 'the dist and the zrender source disagree on the width table');
  }
  return s;
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);
function measure(text, font) {
  font = font || '12px sans-serif';
  const r = /((?:\d+)?\.?\d*)px/.exec(font);
  const px = (r && +r[1]) || DEFAULT_FONT_SIZE;
  if (font.indexOf('mono') >= 0) return px * text.length;
  let w = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    w += c >= FIRST_CODE && c <= LAST_CODE ? RATIO[c - FIRST_CODE] * px : px;
  }
  return w;
}
function checkMeasurer() {
  RATIO.forEach((r, i) => {
    const w = new echarts.graphic.Text({ style: { text: String.fromCharCode(FIRST_CODE + i), font: '1px sans-serif' } }).getBoundingRect().width;
    must(Object.is(w, r), 'char code ' + (FIRST_CODE + i) + ': the table says ' + r + ', a 1px Text measures ' + w);
  });
  const samples = [];
  for (const font of ['12px sans-serif', 'normal normal 12px Microsoft YaHei', 'normal normal 10px Arial', 'normal normal 14px Arial']) {
    for (const t of ['a', '\u56fd', 'n1', 'n12Longer label', 'Agricultural waste', 'x: 5 (Flow)', '\u4e2d\u6587', 'W']) {
      const w = new echarts.graphic.Text({ style: { text: t, font } }).getBoundingRect().width;
      must(Object.is(w, measure(t, font)), JSON.stringify(t) + ' @ ' + font + ': a Text measures ' + w + ', the rule ' + measure(t, font));
      samples.push({ text: t, font, width: hex(w), widthText: dec(w) });
    }
  }
  return {
    firstCode: FIRST_CODE, lastCode: LAST_CODE, fontSize: DEFAULT_FONT_SIZE, ratio: RATIO.map(hex), ratioText: RATIO.map(dec),
    rule: "px = the number before 'px' in the font (else 12); a font containing 'mono' measures px * length; otherwise the sum, over UTF-16 units left to right, of ratio[code - 32] * px for codes 32..126 and px for any other unit. A label's line height is measure('\u56fd') = px. Sankey labels are never truncated (no width): the measure only places the text box around the anchor.",
    samples,
  };
}

// ---------- zrender canvas createLinearGradient, taken verbatim from the dist (for the upstream reading only) ----------
const DIST_LINEAR_GRADIENT = (() => {
  const grab = name => {
    const i = DIST_TEXT.indexOf('function ' + name + '(');
    must(i >= 0, 'no ' + name + ' in the dist');
    let depth = 0; let j = DIST_TEXT.indexOf('{', i);
    for (; j < DIST_TEXT.length; j++) { if (DIST_TEXT[j] === '{') depth++; else if (DIST_TEXT[j] === '}' && --depth === 0) break; }
    return DIST_TEXT.slice(i, j + 1);
  };
  const src = grab('isSafeNum') + '\n' + grab('createLinearGradient') + '\nreturn createLinearGradient;';
  return Function(src)();
})();

// ============================================================================
// The transcription (wf78/ref.js, extended to every recorded field; mutants as switches)
// ============================================================================
const THEME_NEUTRAL50 = '#86878c';
const SK_DEFAULTS = {
  orient: 'horizontal', nodeWidth: 20, nodeGap: 8, layoutIterations: 32, nodeAlign: 'justify', z: 2, zlevel: 0,
  label: { show: true, position: 'right', fontSize: 12 }, lineStyle: { color: THEME_NEUTRAL50, opacity: 0.2, curveness: 0.5 },
  emphasis: { label: { show: true } },
};
// keys a case may not use (the first frame differs in ways K1 does not transcribe)
const REFUSED_KEYS = ['zoom', 'center', 'edgeLabel', 'fontStyle', 'fontWeight', 'textBorderColor', 'textBorderWidth', 'lineHeight', 'rich', 'padding', 'backgroundColor', 'offset', 'rotate', 'width', 'overflow', 'decal', 'sort'];
function refusedKeys(so) {
  const out = [];
  if (so.zoom != null && so.zoom !== 1) out.push('zoom');
  if (so.center != null) out.push('center');
  if (so.edgeLabel && so.edgeLabel.show) out.push('edgeLabel.show');
  const walkLabel = (l, where) => {
    if (!isObject(l)) return;
    for (const k of Object.keys(l)) if (REFUSED_KEYS.includes(k) && l[k] != null) out.push(where + '.' + k);
  };
  const items = [so].concat(so.levels || [], so.data || so.nodes || []);
  items.forEach((it, i) => { if (isObject(it)) { walkLabel(it.label, 'item' + i + '.label'); if (it.itemStyle && it.itemStyle.decal) out.push('decal'); } });
  if (so.sort !== undefined) out.push('sort (not in the 6.1.0 dist)');
  return out;
}

function parsePct(v, base) {                          // util/number.ts parsePercent (layout flavour)
  if (v === 'center' || v === 'middle') v = '50%';
  else if (v === 'left' || v === 'top') v = '0%';
  else if (v === 'right' || v === 'bottom') v = '100%';
  if (typeof v === 'string') return /%$/.test(v.trim()) ? parseFloat(v) / 100 * base + 0 : parseFloat(v);
  return v == null ? NaN : +v;
}
function layoutRect(p, cw, ch) {                      // util/layout.ts getLayoutRect, margin 0, no aspect
  let left = parsePct(p.left, cw); let top = parsePct(p.top, ch);
  const right = parsePct(p.right, cw); const bottom = parsePct(p.bottom, ch);
  let width = parsePct(p.width, cw); let height = parsePct(p.height, ch);
  if (isNaN(width)) width = cw - right - 0 - left;
  if (isNaN(height)) height = ch - bottom - 0 - top;
  if (isNaN(left)) left = cw - right - width - 0;
  if (isNaN(top)) top = ch - bottom - height - 0;
  switch (p.left || p.right) { case 'center': left = cw / 2 - width / 2 - 0; break; case 'right': left = cw - width - 0; break; }
  switch (p.top || p.bottom) { case 'middle': case 'center': top = ch / 2 - height / 2 - 0; break; case 'bottom': top = ch - height - 0; break; }
  left = left || 0; top = top || 0;
  if (isNaN(width)) width = cw - 0 - left - (right || 0);
  if (isNaN(height)) height = ch - 0 - top - (bottom || 0);
  return { x: 0 + left + 0, y: 0 + top + 0, width, height };
}
function mergeBox(user) {                             // util/layout.ts mergeLayoutParam, layoutMode 'box', sankey defaults
  const def = { left: '5%', top: '5%', right: '20%', bottom: '5%' };
  const has = (o, k) => o[k] != null && o[k] !== 'auto';
  const out = {};
  for (const names of [['left', 'right', 'width'], ['top', 'bottom', 'height']]) {
    const np = {}; const merged = {}; let nc = 0; let mc = 0;
    for (const k of names) merged[k] = def[k];
    for (const k of names) { if (hasOwn(user, k)) np[k] = merged[k] = user[k]; has(np, k) && nc++; has(merged, k) && mc++; }
    let res;
    if (mc === 2 || !nc) res = merged;
    else if (nc >= 2) res = np;
    else { for (const k of names) if (!(k in np) && (k in def)) { np[k] = def[k]; break; } res = np; }
    for (const k of names) out[k] = res[k];
  }
  return out;
}
function pathGet(obj, p) { for (const k of p) { obj = (obj && typeof obj === 'object') ? obj[k] : null; if (obj == null) return obj; } return obj; }
function chain(models, p) { for (const m of models) { const v = pathGet(m, p); if (v != null) return v; } return undefined; }
function numOrNaN(v) { if (v == null || v === '') return NaN; if (isArray(v)) v = v[0]; return +v; }   // parseDataValue for the value dim
const EPS_T = 5e-5;
const T = (x, y) => ((x > EPS_T || x < -EPS_T || y > EPS_T || y < -EPS_T) ? [x, y] : null);   // needLocalTransform
const T6 = t => (t ? [1, 0, 0, 1, t[0], t[1]] : null);
function stableSort(arr, cmp) {                       // == V8 TimSort for a consistent comparator; NaN -> not > 0 -> stays
  for (let i = 1; i < arr.length; i++) {
    const v = arr[i]; let j = i - 1;
    while (j >= 0) { const c = cmp(arr[j], v); if (c > 0) { arr[j + 1] = arr[j]; j--; } else break; }
    arr[j + 1] = v;
  }
  return arr;
}

// ---------- zrender tool/color.ts (parse, lum, fastLerp, stringify) ----------
const CSS_NAMES = { transparent: [0, 0, 0, 0], red: [255, 0, 0, 1], green: [0, 128, 0, 1], blue: [0, 0, 255, 1], white: [255, 255, 255, 1], black: [0, 0, 0, 1] };
const CSS_UNPARSED = ['none', 'gradient', 'source', 'target'];     // bare words zrender's table does not hold (checked at start)
function clampCssByte(i) { i = Math.round(i); return i < 0 ? 0 : i > 255 ? 255 : i; }
function clampCssFloat(f) { return f < 0 ? 0 : f > 1 ? 1 : f; }
function parseCssInt(s) { return (s.length && s.charAt(s.length - 1) === '%') ? clampCssByte(parseFloat(s) / 100 * 255) : clampCssByte(parseInt(s, 10)); }
function parseCssFloat(s) { return (s.length && s.charAt(s.length - 1) === '%') ? clampCssFloat(parseFloat(s) / 100) : clampCssFloat(parseFloat(s)); }
function parseColour(c) {
  if (!c) return undefined;
  const str = (c + '').replace(/ /g, '').toLowerCase();
  if (hasOwn(CSS_NAMES, str)) return CSS_NAMES[str].slice();
  const n = str.length;
  if (str.charAt(0) === '#') {
    if (n === 4 || n === 5) {
      const iv = parseInt(str.slice(1, 4), 16);
      if (!(iv >= 0 && iv <= 0xfff)) return undefined;
      return [((iv & 0xf00) >> 4) | ((iv & 0xf00) >> 8), (iv & 0xf0) | ((iv & 0xf0) >> 4), (iv & 0xf) | ((iv & 0xf) << 4), n === 5 ? parseInt(str.slice(4), 16) / 0xf : 1];
    }
    if (n === 7 || n === 9) {
      const iv = parseInt(str.slice(1, 7), 16);
      if (!(iv >= 0 && iv <= 0xffffff)) return undefined;
      return [(iv & 0xff0000) >> 16, (iv & 0xff00) >> 8, iv & 0xff, n === 9 ? parseInt(str.slice(7), 16) / 0xff : 1];
    }
    return undefined;
  }
  const op = str.indexOf('('); const ep = str.indexOf(')');
  if (op !== -1 && ep + 1 === n) {
    const fname = str.substr(0, op); const p = str.substr(op + 1, ep - (op + 1)).split(',');
    if (fname === 'rgba' && p.length === 4) return [parseCssInt(p[0]), parseCssInt(p[1]), parseCssInt(p[2]), parseCssFloat(p[3])];
    if (fname === 'rgb' && p.length === 3) return [parseCssInt(p[0]), parseCssInt(p[1]), parseCssInt(p[2]), 1];
    throw new OracleError('a colour function the transcription does not parse: ' + JSON.stringify(c));
  }
  if (CSS_UNPARSED.includes(str)) return undefined;
  throw new OracleError('a colour the transcription does not parse: ' + JSON.stringify(c));
}
const rgbaText = a => 'rgba(' + a[0] + ',' + a[1] + ',' + a[2] + ',' + a[3] + ')';
function lum(color, bgLum) { const a = parseColour(color); return a ? (0.299 * a[0] + 0.587 * a[1] + 0.114 * a[2]) * a[3] / 255 + (1 - a[3]) * bgLum : 0; }
function linearMap01(val, d0, d1) {                  // util/number.ts linearMap(val, [d0, d1], [0, 1], clamp = true)
  const sub = d1 - d0;
  if (sub === 0) return 0.5;
  if (sub > 0) { if (val <= d0) return 0; if (val >= d1) return 1; } else { if (val >= d0) return 0; if (val <= d1) return 1; }
  return (val - d0) / sub * 1 + 0;
}

// zrender PathProxy.getBoundingRect for M C L C Z (curve.ts cubicExtrema / cubicAt, bbox.ts fromLine / fromCubic)
function cubicAt(p0, p1, p2, p3, t) { const o = 1 - t; return o * o * (o * p0 + 3 * t * p1) + t * t * (t * p3 + 3 * o * p2); }
function cubicExtrema(p0, p1, p2, p3, ex) {
  const b = 6 * p2 - 12 * p1 + 6 * p0; const a = 9 * p1 + 3 * p3 - 3 * p0 - 9 * p2; const c = 3 * p1 - 3 * p0;
  const az = v => v > -1e-8 && v < 1e-8;
  let n = 0;
  if (az(a)) { if (!az(b)) { const t1 = -c / b; if (t1 >= 0 && t1 <= 1) ex[n++] = t1; } } else {
    const disc = b * b - 4 * a * c;
    if (az(disc)) ex[0] = -b / (2 * a);              // n stays 0: the double root is not counted
    else if (disc > 0) { const s = Math.sqrt(disc); const t1 = (-b + s) / (2 * a); const t2 = (-b - s) / (2 * a); if (t1 >= 0 && t1 <= 1) ex[n++] = t1; if (t2 >= 0 && t2 <= 1) ex[n++] = t2; }
  }
  return n;
}

// so: the series option as fed; env: {W, H, palette, fontFamily, ground}; mut: a mutant name or null
function transcribe(soIn, env, mut) {
  const M = k => mut === k;
  const so = zrClone(soIn);
  const ground = env.ground;
  const stat = { iter0: 0, relaxNaNFallback: 0, pushBack: 0, droppedEdges: 0, labelOnStroked: 0, gradients: 0, gradientUnsafe: 0, nanBreadth: 0, negativeSize: 0, insideUnfilled: 0 };
  const S = Object.assign({}, so);
  for (const k of Object.keys(SK_DEFAULTS)) {
    const d = SK_DEFAULTS[k];
    if (d && typeof d === 'object') S[k] = Object.assign({}, d, isObject(so[k]) ? so[k] : {});
    else if (so[k] == null) S[k] = d;
  }
  const box = layoutRect(mergeBox(so), env.W, env.H);
  const width = box.width; const height = box.height;
  const orient = S.orient; const vertical = orient === 'vertical';

  // ---- graph (createGraphFromNodeEdge + Graph.addNode / addEdge) ----
  const nodeItems = so.data || so.nodes || [];
  const linkItems = so.edges || so.links || [];
  const nodes = []; const map = {};
  nodeItems.forEach((it, i) => {
    must(isObject(it) && !isArray(it), 'a node item that is not an object');
    const key = it.id != null ? it.id : it.name != null ? it.name : i;
    const id = '' + key;
    if (map['_EC_' + id]) throw new OracleError('refused: duplicate node key ' + JSON.stringify(id));
    const n = { id, i, item: it, out: [], in: [], L: {} };
    nodes.push(n); map['_EC_' + id] = n;
  });
  const edges = [];
  linkItems.forEach((link, row) => {
    must(isObject(link), 'a link item that is not an object');
    let n1 = link.source; let n2 = link.target;
    if (M('numericSource')) { n1 = map['_EC_' + n1]; n2 = map['_EC_' + n2]; } else {
      n1 = typeof n1 === 'number' ? nodes[n1] : map['_EC_' + n1];
      n2 = typeof n2 === 'number' ? nodes[n2] : map['_EC_' + n2];
    }
    if (!n1 || !n2) { stat.droppedEdges++; return; }
    const e = { n1, n2, i: edges.length, row, item: link, v: numOrNaN(link.value), L: {} };
    n1.out.push(e); n2.in.push(e); edges.push(e);
  });
  const sumOf = (arr, f) => { let s = 0; for (const a of arr) { const v = +f(a); if (M('sumNaN') || !isNaN(v)) s += v; } return s; };

  // ---- computeNodeValues ----
  for (const n of nodes) {
    const v1 = sumOf(n.out, e => e.v); const v2 = sumOf(n.in, e => e.v);
    const raw = numOrNaN(n.item.value) || 0;
    n.L.value = Math.max(v1, v2, raw);
  }
  let iterations = (!M('zeroIter') && nodes.some(n => n.L.value === 0)) ? 0 : S.layoutIterations;
  const iterationsResolved = iterations;
  if (iterations === 0 && nodes.length) stat.iter0++;

  // ---- computeNodeBreadths (the Kahn pass) ----
  const nodeWidth = S.nodeWidth; const nodeGap = S.nodeGap;
  const indeg = nodes.map(n => n.in.length);
  let zero = nodes.filter(n => n.in.length === 0); let next = [];
  let x = 0; let maxNodeDepth = -1;
  const itemDepth = n => n.item.depth != null && n.item.depth >= 0;
  const remain = edges.map(() => 1);
  while (zero.length) {
    for (const n of zero) {
      const isD = itemDepth(n);
      if (isD && n.item.depth > maxNodeDepth) maxNodeDepth = n.item.depth;
      n.L.depth = isD ? n.item.depth : x;
      if (vertical) n.L.dy = nodeWidth; else n.L.dx = nodeWidth;
      for (const e of n.out) {
        remain[e.i] = 0;
        const t = nodes.indexOf(e.n2);
        if (--indeg[t] === 0 && next.indexOf(e.n2) < 0) next.push(e.n2);
      }
    }
    ++x; zero = next; next = [];
  }
  if (remain.some(r => r === 1)) throw new OracleError('refused: the graph has a cycle');
  for (const n of nodes) n.kahnDepth = n.L.depth;
  const maxDepth = maxNodeDepth > x - 1 ? maxNodeDepth : x - 1;
  const align = S.nodeAlign;
  if (align && align !== 'left') {
    if (align === 'right') {
      let rem = nodes; let nsrc = []; let h = 0;
      while (rem.length) {
        for (const n of rem) {
          if (!M('rightAlign') || n.L.skNodeHeight == null) n.L.skNodeHeight = h;
          for (const e of n.in) if (nsrc.indexOf(e.n1) < 0) nsrc.push(e.n1);
        }
        rem = nsrc; nsrc = []; ++h;
      }
      for (const n of nodes) if (M('rightExplicit') || !itemDepth(n)) n.L.depth = Math.max(0, maxDepth - n.L.skNodeHeight);
    } else if (align === 'justify' && !M('justify')) {
      for (const n of nodes) if (!itemDepth(n) && !n.out.length) n.L.depth = maxDepth;
    }
  }
  const kx = M('kxOrder') ? (vertical ? height / maxDepth - nodeWidth / maxDepth : width / maxDepth - nodeWidth / maxDepth)
    : (vertical ? (height - nodeWidth) / maxDepth : (width - nodeWidth) / maxDepth);
  const BK = vertical ? 'y' : 'x'; const PK = vertical ? 'x' : 'y'; const SK = vertical ? 'dx' : 'dy';
  for (const n of nodes) { n.L[BK] = n.L.depth * kx; if (Number.isNaN(n.L[BK])) stat.nanBreadth++; }

  // ---- computeNodeDepths ----
  const gmap = new Map(); const keys = [];
  for (const n of nodes) {
    const k = M('groupKey') ? n.L.depth : n.L[BK];
    if (!gmap.has(k)) { keys.push(k); gmap.set(k, []); }
    gmap.get(k).push(n);
  }
  stableSort(keys, (a, b) => a - b);
  const cols = keys.map(k => gmap.get(k));
  let minKy = Infinity;
  const kys = [];
  for (const col of cols) {
    let sum = 0; for (const n of col) sum += n.L.value;
    const ky = vertical ? (width - (col.length - 1) * nodeGap) / sum : (height - (col.length - 1) * nodeGap) / sum;
    kys.push(ky);
    if (ky < minKy) minKy = ky;
  }
  cols.forEach((col, ci) => col.forEach((n, i) => { n.L[PK] = i; n.L[SK] = n.L.value * (M('minKyPerColumn') ? kys[ci] : minKy); }));
  for (const e of edges) e.L.dy = +e.v * minKy;
  const viewWidth = vertical ? width : height;
  function resolveCollisions() {
    for (const col of cols) {
      if (!M('nosort')) stableSort(col, M('unstable') ? ((a, b) => (a.L[PK] - b.L[PK]) || (b.i - a.i)) : ((a, b) => a.L[PK] - b.L[PK]));
      let y0 = 0; let node; let dy;
      const n = col.length;
      for (let i = 0; i < n; i++) {
        node = col[i];
        dy = y0 - node.L[PK];
        if (dy > 0) node.L[PK] = node.L[PK] + dy;
        y0 = node.L[PK] + node.L[SK] + nodeGap;
      }
      dy = M('resolveGapEnd') ? y0 - viewWidth : y0 - nodeGap - viewWidth;
      if (dy > 0 && !M('backpass')) {
        stat.pushBack++;
        const nx = node.L[PK] - dy;
        node.L[PK] = nx;
        y0 = nx;
        for (let i = n - 2; i >= 0; --i) {
          node = col[i];
          dy = node.L[PK] + node.L[SK] + nodeGap - y0;
          if (dy > 0) node.L[PK] = node.L[PK] - dy;
          y0 = node.L[PK];
        }
      }
    }
  }
  const center = n => (M('center') ? n.L[PK] + n.L[SK] * 0.5 : n.L[PK] + n.L[SK] / 2);
  function relax(colsOrder, edgesOf, other, alpha) {
    const pending = [];
    for (const col of colsOrder) {
      for (const n of col) {
        const es = edgesOf(n);
        if (!es.length) continue;
        let y;
        if (M('weighted')) y = sumOf(es, e => center(other(e))) / es.length;
        else {
          y = sumOf(es, e => center(other(e)) * e.v) / sumOf(es, e => e.v);
          if (isNaN(y)) { stat.relaxNaNFallback++; const len = es.length; y = len ? sumOf(es, e => center(other(e))) / len : 0; }
        }
        const ny = n.L[PK] + (y - center(n)) * alpha;
        if (M('jacobi')) pending.push([n, ny]); else n.L[PK] = ny;
      }
    }
    for (const [n, ny] of pending) n.L[PK] = ny;
  }
  resolveCollisions();
  let k = 0;
  for (let alpha = 1; iterations > 0; iterations--) {
    k++;
    alpha = M('alphaDecay') ? Math.pow(0.99, k) : alpha * 0.99;
    relax(M('relaxOrder') ? cols : cols.slice().reverse(), n => n.out, e => e.n2, alpha);
    resolveCollisions();
    relax(cols, n => n.in, e => e.n1, alpha);
    resolveCollisions();
  }
  // ---- computeEdgeDepths ----
  for (const n of nodes) {
    if (!M('edgeSort')) {
      const key = M('edgeSortKey') ? (m => center(m)) : (m => m.L[PK]);
      stableSort(n.out, M('edgeUnstable') ? ((a, b) => (key(a.n2) - key(b.n2)) || (b.i - a.i)) : ((a, b) => key(a.n2) - key(b.n2)));
      stableSort(n.in, (a, b) => key(a.n1) - key(b.n1));
    }
  }
  for (const n of nodes) {
    let sy = 0; let ty = 0;
    for (const e of n.out) { e.L.sy = sy; sy += e.L.dy; }
    for (const e of n.in) { e.L.ty = ty; ty += e.L.dy; }
    if (n.L[SK] < 0) stat.negativeSize++;
  }

  // ---- models: item -> levels[layout depth] -> series ----
  const levelModels = {}; const levelIndex = {};
  (so.levels || []).forEach((l, li) => { if (isObject(l) && l.depth != null && l.depth >= 0) { levelModels[l.depth] = l; levelIndex[l.depth] = li; } });
  const levelKeyOf = n => (M('levelKahn') ? n.kahnDepth : n.L.depth);
  const nodeLevel = n => (hasOwn(levelModels, levelKeyOf(n)) ? levelModels[levelKeyOf(n)] : undefined);
  const nodeChain = n => { const lv = nodeLevel(n); return lv ? [n.item, lv, S] : [n.item, S]; };
  const edgeLevelNode = e => (M('levelDepthEdge') ? e.n2 : e.n1);
  const edgeChain = e => { const lv = nodeLevel(edgeLevelNode(e)); return lv ? [e.item, lv, S] : [e.item, S]; };

  // ---- visual (sankeyVisual.ts) ----
  let colorList = so.color != null ? so.color : env.palette;
  colorList = isArray(colorList) ? colorList : [colorList];
  const parsed = colorList.map(c => parseColour(c) || [0, 0, 0, 1]);
  let mn = Infinity; let mx = -Infinity;
  for (const n of nodes) { if (n.L.value < mn) mn = n.L.value; if (n.L.value > mx) mx = n.L.value; }
  nodes.forEach((n, i) => {
    const norm = M('palette') ? linearMap01(i, 0, nodes.length - 1) : linearMap01(n.L.value, mn, mx);
    let mapped;
    if (parsed.length && norm >= 0 && norm <= 1) {                 // zrender fastLerp
      const value = norm * (parsed.length - 1);
      const li = Math.floor(value); const ri = Math.ceil(value);
      const L = parsed[li]; const R = parsed[ri]; const dv = value - li;
      const ch = j => (M('lerpRound') ? Math.floor(L[j] + (R[j] - L[j]) * dv) : clampCssByte(L[j] + (R[j] - L[j]) * dv));
      mapped = rgbaText([ch(0), ch(1), ch(2), clampCssFloat(L[3] + (R[3] - L[3]) * dv)]);
    }
    const custom = chain(nodeChain(n), ['itemStyle', 'color']);
    n.colour = custom != null ? custom : mapped;
    n.colourSource = custom != null ? 'custom' : 'mapped';
  });

  // ---- fills, bboxes, gradients ----
  function fillRec(v, bb, T2) {
    if (v == null) return null;
    if (typeof v === 'string') return v;
    must(isObject(v) && v.type === 'linear' && isArray(v.colorStops), 'a fill object that is not a linear gradient');
    let gx = v.x == null ? 0 : v.x; let gx2 = v.x2 == null ? 1 : v.x2; let gy = v.y == null ? 0 : v.y; let gy2 = v.y2 == null ? 0 : v.y2;
    if (!v.global) { gx = gx * bb.width + bb.x; gx2 = gx2 * bb.width + bb.x; gy = gy * bb.height + bb.y; gy2 = gy2 * bb.height + bb.y; }
    if (!(isFinite(gx) && isFinite(gx2) && isFinite(gy) && isFinite(gy2))) stat.gradientUnsafe++;
    if (!M('gradientUnsafe')) { gx = isFinite(gx) ? gx : 0; gx2 = isFinite(gx2) ? gx2 : 1; gy = isFinite(gy) ? gy : 0; gy2 = isFinite(gy2) ? gy2 : 0; }
    const m = T2 ? [1, 0, 0, 1, T2[0], T2[1]] : null;
    const ap = (px, py) => (m ? [m[0] * px + m[2] * py + m[4], m[1] * px + m[3] * py + m[5]] : [px, py]);
    const p1 = ap(gx, gy); const p2 = ap(gx2, gy2);
    return {
      type: v.type, x: json(v.x), y: json(v.y), x2: json(v.x2), y2: json(v.y2), global: json(v.global),
      colorStops: v.colorStops.map(s => ({ offset: s.offset, color: json(s.color) })),
      canvas: { x: gx, y: gy, x2: gx2, y2: gy2 }, canvasGlobal: { x: p1[0], y: p1[1], x2: p2[0], y2: p2[1] },
    };
  }
  const hasFill = f => f != null && f !== 'none';
  function strokeGrow(bb, stroke, lw, fill) {
    const has = !(stroke == null || stroke === 'none' || !(lw > 0));
    if (!has) return bb;
    let w = lw;
    if (!hasFill(fill) && !M('unfilled5')) w = Math.max(w, 5);
    return { x: bb.x - w / 1 / 2, y: bb.y - w / 1 / 2, width: bb.width + w / 1, height: bb.height + w / 1 };
  }
  function bandBBox(s) {
    const e = s.extent; const mnb = [Number.MAX_VALUE, Number.MAX_VALUE]; const mxb = [-Number.MAX_VALUE, -Number.MAX_VALUE];
    const m2 = [0, 0]; const M2 = [0, 0];
    const uni = () => { mnb[0] = Math.min(mnb[0], m2[0]); mnb[1] = Math.min(mnb[1], m2[1]); mxb[0] = Math.max(mxb[0], M2[0]); mxb[1] = Math.max(mxb[1], M2[1]); };
    const line = (x0, y0, x1, y1) => { m2[0] = Math.min(x0, x1); m2[1] = Math.min(y0, y1); M2[0] = Math.max(x0, x1); M2[1] = Math.max(y0, y1); };
    const cubic = (x0, y0, x1, y1, x2, y2, x3, y3) => {
      if (M('bbox')) { line(x0, y0, x3, y3); return; }
      const ex = [];
      let n = cubicExtrema(x0, x1, x2, x3, ex);
      m2[0] = Infinity; m2[1] = Infinity; M2[0] = -Infinity; M2[1] = -Infinity;
      for (let i = 0; i < n; i++) { const xx = cubicAt(x0, x1, x2, x3, ex[i]); m2[0] = Math.min(xx, m2[0]); M2[0] = Math.max(xx, M2[0]); }
      n = cubicExtrema(y0, y1, y2, y3, ex);
      for (let i = 0; i < n; i++) { const yy = cubicAt(y0, y1, y2, y3, ex[i]); m2[1] = Math.min(yy, m2[1]); M2[1] = Math.max(yy, M2[1]); }
      m2[0] = Math.min(x0, m2[0]); M2[0] = Math.max(x0, M2[0]); m2[0] = Math.min(x3, m2[0]); M2[0] = Math.max(x3, M2[0]);
      m2[1] = Math.min(y0, m2[1]); M2[1] = Math.max(y0, M2[1]); m2[1] = Math.min(y3, m2[1]); M2[1] = Math.max(y3, M2[1]);
    };
    m2[0] = M2[0] = s.x1; m2[1] = M2[1] = s.y1; uni();
    cubic(s.x1, s.y1, s.cpx1, s.cpy1, s.cpx2, s.cpy2, s.x2, s.y2); uni();
    if (s.orient === 'vertical') {
      line(s.x2, s.y2, s.x2 + e, s.y2); uni();
      cubic(s.x2 + e, s.y2, s.cpx2 + e, s.cpy2, s.cpx1 + e, s.cpy1, s.x1 + e, s.y1); uni();
    } else {
      line(s.x2, s.y2, s.x2, s.y2 + e); uni();
      cubic(s.x2, s.y2 + e, s.cpx2, s.cpy2 + e, s.cpx1, s.cpy1 + e, s.x1, s.y1 + e); uni();
    }
    return { x: mnb[0], y: mnb[1], width: mxb[0] - mnb[0], height: mxb[1] - mnb[1] };
  }
  const rectBBox = sh => {                            // Rect: fromLine(x, y, x + w, y + h)
    const o = { x: Math.min(sh.x, sh.x + sh.width), y: Math.min(sh.y, sh.y + sh.height) };
    o.width = Math.max(sh.x, sh.x + sh.width) - o.x; o.height = Math.max(sh.y, sh.y + sh.height) - o.y;
    return o;
  };

  // ---- elements ----
  const GT = T(box.x, box.y);
  const els = [];
  let maxZ2 = -Infinity;
  const edgeRecs = [];
  for (const e of edges) {
    const ch = edgeChain(e);
    const c = chain(ch, ['lineStyle', 'curveness']);
    const n1 = e.n1; const n2 = e.n2;
    const d1x = chain(nodeChain(n1), ['localX']); const d1y = chain(nodeChain(n1), ['localY']);
    const d2x = chain(nodeChain(n2), ['localX']); const d2y = chain(nodeChain(n2), ['localY']);
    const s = { x1: 0, y1: 0, x2: 0, y2: 0, cpx1: 0, cpy1: 0, cpx2: 0, cpy2: 0, extent: M('extent') ? e.L.dy : Math.max(1, e.L.dy), orient };
    if (vertical) {
      s.x1 = (d1x != null ? d1x * width : n1.L.x) + e.L.sy;
      s.y1 = (d1y != null ? d1y * height : n1.L.y) + n1.L.dy;
      s.x2 = (d2x != null ? d2x * width : n2.L.x) + e.L.ty;
      s.y2 = d2y != null ? d2y * height : n2.L.y;
      s.cpx1 = s.x1; s.cpy1 = M('cpx') ? s.y1 + (s.y2 - s.y1) * c : s.y1 * (1 - c) + s.y2 * c;
      s.cpx2 = s.x2; s.cpy2 = s.y1 * c + s.y2 * (1 - c);
    } else {
      s.x1 = (d1x != null ? d1x * width : n1.L.x) + n1.L.dx;
      s.y1 = (d1y != null ? d1y * height : n1.L.y) + e.L.sy;
      s.x2 = d2x != null ? d2x * width : n2.L.x;
      s.y2 = (d2y != null ? d2y * height : n2.L.y) + e.L.ty;
      s.cpx1 = M('cpx') ? s.x1 + (s.x2 - s.x1) * c : s.x1 * (1 - c) + s.x2 * c; s.cpy1 = s.y1;
      s.cpx2 = s.x1 * c + s.x2 * (1 - c); s.cpy2 = s.y2;
    }
    let fill = chain(ch, ['lineStyle', 'color']);
    const stroke = chain(ch, ['lineStyle', 'borderColor']);
    const lwOpt = chain(ch, ['lineStyle', 'borderWidth']);
    const lw = lwOpt != null ? lwOpt : 1;
    const op = chain(ch, ['lineStyle', 'opacity']);
    if (fill === 'source') fill = n1.colour;
    else if (fill === 'target') fill = n2.colour;
    else if (fill === 'gradient') {
      if (typeof n1.colour === 'string' && typeof n2.colour === 'string') {
        stat.gradients++;
        fill = { type: 'linear', x: 0, y: 0, x2: +(orient === 'horizontal'), y2: +(orient === 'vertical'), global: false, colorStops: [{ offset: 0, color: n1.colour }, { offset: 1, color: n2.colour }] };
      }
    }
    const bb = strokeGrow(bandBBox(s), stroke, lw, fill);
    maxZ2 = Math.max(0, maxZ2);
    const el = { kind: 'link', index: e.i, z: S.z, z2: 0, zlevel: S.zlevel, transform: T6(GT), fill: fillRec(fill, bb, GT), stroke: stroke == null ? null : stroke, lineWidth: lw, opacity: op == null ? 1 : op, shape: s, bbox: bb };
    els.push(el);
    const lv = nodeLevel(edgeLevelNode(e));
    edgeRecs.push({ index: e.i, row: e.row, source: e.n1.i, target: e.n2.i, value: e.v, dy: e.L.dy, sy: e.L.sy, ty: e.L.ty, level: lv ? levelKeyOf(edgeLevelNode(e)) : null });
  }
  const labels = []; const tspans = [];
  const outsideStroke = () => {                       // Element.getOutsideStroke
    let arr = typeof ground.background === 'string' && parseColour(ground.background);
    if (!arr) arr = [255, 255, 255, 1];
    const alpha = arr[3];
    for (let i = 0; i < 3; i++) arr[i] = arr[i] * alpha + (ground.isDark ? 0 : 255) * (1 - alpha);
    arr[3] = 1;
    return rgbaText(arr);
  };
  const nodeRecs = [];
  for (const n of nodes) {
    const ch = nodeChain(n);
    const dx = chain(ch, ['localX']); const dy = chain(ch, ['localY']);
    const shape = { x: dx != null ? dx * width : n.L.x, y: dy != null ? dy * height : n.L.y, width: n.L.dx, height: n.L.dy, r: chain(ch, ['itemStyle', 'borderRadius']) || 0 };
    const stroke = chain(ch, ['itemStyle', 'borderColor']);
    const lwOpt = chain(ch, ['itemStyle', 'borderWidth']);
    const op = chain(ch, ['itemStyle', 'opacity']);
    const lw = lwOpt != null ? lwOpt : 1;
    const fill = n.colour;
    const hasStroke = !(stroke == null || stroke === 'none' || !(lw > 0));
    const bb = strokeGrow(rectBBox(shape), stroke, lw, fill);
    els.push({ kind: 'node', index: n.i, z: S.z, z2: 10, zlevel: S.zlevel, transform: T6(GT), fill: fillRec(fill, bb, GT), stroke: stroke == null ? null : stroke, lineWidth: lw, opacity: op == null ? 1 : op, shape, bbox: bb });
    maxZ2 = Math.max(10, maxZ2);
    const lv = nodeLevel(n);
    const rec = { index: n.i, id: n.id, name: n.item.name != null ? '' + n.item.name : '', rawValue: numOrNaN(n.item.value), value: n.L.value, depth: n.L.depth, kahnDepth: n.kahnDepth,
      skNodeHeight: n.L.skNodeHeight == null ? null : n.L.skNodeHeight, x: n.L.x, y: n.L.y, dx: n.L.dx, dy: n.L.dy,
      colour: n.colour == null ? null : n.colour, colourSource: n.colourSource, level: lv ? levelKeyOf(n) : null,
      outEdges: n.out.map(e => e.i), inEdges: n.in.map(e => e.i), label: null };
    nodeRecs.push(rec);
    // ---- label ----
    if (!chain(ch, ['label', 'show'])) continue;
    const fmt = chain(ch, ['label', 'formatter']);
    let text;
    if (typeof fmt === 'string') {
      const params = { a: so.name != null ? '' + so.name : 'series\u00000', b: n.item.name != null ? '' + n.item.name : '', c: n.item.value != null ? n.item.value : n.L.value };
      text = fmt;
      for (const key of ['a', 'b', 'c']) text = M('fmtAll') ? text.split('{' + key + '}').join('' + params[key]) : text.replace('{' + key + '}', '' + params[key]);
    } else {
      must(fmt == null, 'a non-string label.formatter');
      text = M('defaultText') ? (n.item.name != null ? '' + n.item.name : n.id) : n.id;
    }
    // the host rect: the rect's path bbox, grown by the stroke, through the rect's transform
    let hb = rectBBox(shape);
    if (hasStroke && !M('labelStroke')) {
      let w = lw; if (!hasFill(fill) && !M('unfilled5')) w = Math.max(w, 5);
      hb = { x: hb.x - w / 1 / 2, y: hb.y - w / 1 / 2, width: hb.width + w / 1, height: hb.height + w / 1 };
      stat.labelOnStroked++;
    }
    if (GT) {
      hb = { x: hb.x * 1 + GT[0], y: hb.y * 1 + GT[1], width: hb.width * 1, height: hb.height * 1 };
      if (hb.width < 0) { hb.x += hb.width; hb.width = -hb.width; }
      if (hb.height < 0) { hb.y += hb.height; hb.height = -hb.height; }
    }
    const pos = chain(ch, ['label', 'position']) || 'inside';
    const dOpt = chain(ch, ['label', 'distance']);
    const dist = dOpt != null ? dOpt : 5;
    let ax = hb.x; let ay = hb.y; let align = 'left'; let valign = 'top';
    const hh = hb.height / 2;
    if (isArray(pos)) { ax += parsePct(pos[0], hb.width); ay += parsePct(pos[1], hb.height); align = null; valign = null; } else {
      switch (pos) {
        case 'left': ax -= dist; ay += hh; align = 'right'; valign = 'middle'; break;
        case 'right': if (M('labelOrder')) ax = (ax + dist) + hb.width; else ax += dist + hb.width; ay += hh; valign = 'middle'; break;
        case 'top': ax += hb.width / 2; ay -= dist; align = 'center'; valign = 'bottom'; break;
        case 'bottom': ax += hb.width / 2; ay += hb.height + dist; align = 'center'; break;
        case 'inside': ax += hb.width / 2; ay += hh; align = 'center'; valign = 'middle'; break;
        case 'insideLeft': ax += dist; ay += hh; valign = 'middle'; break;
        case 'insideRight': ax += hb.width - dist; ay += hh; align = 'right'; valign = 'middle'; break;
        case 'insideTop': ax += hb.width / 2; ay += dist; align = 'center'; break;
        case 'insideBottom': ax += hb.width / 2; ay += hb.height - dist; align = 'center'; valign = 'bottom'; break;
        default: throw new OracleError('label position ' + JSON.stringify(pos) + ' is not transcribed');
      }
    }
    const insidePosition = typeof pos === 'string' && pos.indexOf('inside') >= 0;
    const inside = insidePosition && (hasFill(fill) || M('insideUnfilled'));
    if (insidePosition && !hasFill(fill)) stat.insideUnfilled++;
    const colorOpt = chain(ch, ['label', 'color']);
    let dFill; let dStroke;
    if (inside) {
      if (fill !== 'none' && typeof fill === 'string') { const l = lum(fill, 0); dFill = l > 0.5 ? '#333' : l > 0.2 ? '#eee' : '#ccc'; } else if (fill !== 'none' && fill) dFill = '#ccc'; else dFill = '#333';
      if (typeof fill === 'string' && ground.isDark === (lum(dFill, 0) < 0.4)) dStroke = fill;
    } else { dFill = ground.isDark ? '#ccc' : '#333'; dStroke = outsideStroke(); }
    const colourRule = colorOpt != null ? 'option' : inside ? 'inside' : 'outside';
    const tFill = colorOpt != null ? colorOpt : dFill;
    const tStroke = colorOpt != null ? null : (dStroke == null ? null : dStroke);
    const tLw = tStroke ? 2 : 1;
    const fsz = chain(ch, ['label', 'fontSize']);
    const fam = chain(ch, ['label', 'fontFamily']) || env.fontFamily;
    const font = 'normal normal ' + fsz + 'px ' + fam;
    const lines = text === '' ? [] : text.split('\n');
    const lh = measure('\u56fd', font);
    const va = valign || 'top';
    let ty = 0; if (va === 'middle') ty -= lines.length * lh / 2; else if (va === 'bottom') ty -= lines.length * lh;
    ty += lh / 2;
    const LT = T(ax, ay);
    const z2 = M('z2') ? 11 : maxZ2 + 2;
    lines.forEach((line, li) => {
      tspans.push({ kind: 'tspan', index: n.i, line: li, z: S.z, z2, zlevel: S.zlevel, transform: T6(LT), fill: tFill, stroke: tStroke, lineWidth: tLw, opacity: 1,
        text: line, x: 0, y: ty, textAlign: align || 'left', textBaseline: 'middle', font });
      ty += lh;
    });
    const lab = { index: n.i, text, lines, hostRect: hb, position: pos, distance: dist, anchor: { x: ax, y: ay }, transform: T6(LT), align, verticalAlign: valign,
      insidePosition, inside, colourRule, fill: lines.length ? tFill : null, stroke: lines.length ? tStroke : null, lineWidth: lines.length ? tLw : null, font: lines.length ? font : null, z2 };
    labels.push(lab);
    rec.label = lab;
  }
  // paint order: a stable sort by (zlevel, z, z2) over creation order
  const order = els.concat(tspans).map((e, i) => [e, i]).sort((a, b) => (a[0].zlevel - b[0].zlevel) || (a[0].z - b[0].z) || (a[0].z2 - b[0].z2) || (a[1] - b[1])).map(a => a[0]);
  return {
    resolved: {
      box, transform: GT, orient, nodeWidth, nodeGap, layoutIterations: S.layoutIterations, iterations: iterationsResolved, nodeAlign: so.nodeAlign === undefined ? null : so.nodeAlign,
      maxDepth, kx, minKy, columns: cols.map(col => col.map(n => n.i)), colorList, colourExtent: [mn, mx],
      levels: Object.keys(levelModels).map(d => ({ depth: +d, level: levelIndex[d] })),
    },
    nodes: nodeRecs, edges: edgeRecs, elements: order, labels, stat,
  };
}

// ============================================================================
// Reading upstream
// ============================================================================
function ecInner(el, key) { for (const k of Object.keys(el)) if (k.indexOf('__ec_inner_') === 0 && el[k] && key in el[k]) return el[k]; return null; }
function runChart(E, option, W, H, fn) {
  rngState = SEED;
  const chart = E.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(option);
    chart.getZr().storage.getDisplayList(true);
    return fn(chart);
  } finally {
    chart.dispose();
  }
}
const rect4 = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
function upFill(v, el) {
  if (v == null) return null;
  if (typeof v === 'string') return v;
  must(v.type === 'linear', 'a ' + v.type + ' gradient');
  const bb = el.getBoundingRect();
  const pts = {};
  DIST_LINEAR_GRADIENT({ createLinearGradient: (x, y, x2, y2) => { Object.assign(pts, { x, y, x2, y2 }); return {}; } }, v, bb);
  const m = el.transform;
  const ap = (px, py) => (m ? [m[0] * px + m[2] * py + m[4], m[1] * px + m[3] * py + m[5]] : [px, py]);
  const p1 = ap(pts.x, pts.y); const p2 = ap(pts.x2, pts.y2);
  return {
    type: v.type, x: json(v.x), y: json(v.y), x2: json(v.x2), y2: json(v.y2), global: json(v.global),
    colorStops: v.colorStops.map(s => ({ offset: s.offset, color: json(s.color) })),
    canvas: pts, canvasGlobal: { x: p1[0], y: p1[1], x2: p2[0], y2: p2[1] },
  };
}
function readSankey(chart, fedSeries) {
  const ec = chart.getModel();
  const zr = chart.getZr();
  const list = zr.storage.getDisplayList(true);
  const sm = ec.getSeriesByIndex(0);
  must(sm && sm.subType === 'sankey', 'series 0 is not a sankey');
  must(!ec.getSeriesByIndex(1), 'more than one series');
  const view = chart.getViewOfSeriesModel(sm);
  const graph = sm.getGraph();
  const nodeData = sm.getData();
  const edgeData = sm.getData('edge');
  const main = view.group.childrenRef();
  must(main.length === 1 && main[0].isGroup, 'the view group holds one main group');
  const mainGroup = main[0];
  must(!view.group.transform || view.group.transform.every((v, i) => v === [1, 0, 0, 1, 0, 0][i]), 'a view transform (zoom / center)');
  const linkItems = sm.option.edges || sm.option.links || [];
  const nodes = graph.nodes.map((n, i) => {
    must(n.dataIndex === i, 'node ' + i + ': dataIndex');
    const L = n.getLayout();
    return { index: i, id: n.id, name: nodeData.getName(i), rawValue: n.getValue(), value: L.value, depth: L.depth, skNodeHeight: L.skNodeHeight === undefined ? null : L.skNodeHeight,
      x: L.x, y: L.y, dx: L.dx, dy: L.dy, colour: json(n.getVisual('color')), outEdges: n.outEdges.map(e => e.dataIndex), inEdges: n.inEdges.map(e => e.dataIndex) };
  });
  const edges = graph.edges.map((e, i) => {
    must(e.dataIndex === i, 'edge ' + i + ': dataIndex');
    const L = e.getLayout();
    const row = linkItems.indexOf(edgeData.getRawDataItem(i));
    must(row >= 0, 'edge ' + i + ': its option item');
    return { index: i, row, source: e.node1.dataIndex, target: e.node2.dataIndex, value: e.getValue(), dy: L.dy, sy: L.sy, ty: L.ty };
  });
  const kindOf = new Map();
  const labels = [];
  for (const el of mainGroup.childrenRef()) {
    const d = ecInner(el, 'dataIndex');
    must(d, 'a main-group child without ecData');
    if (d.dataType === 'edge') {
      must(el.type === 'path', 'an edge element of type ' + el.type);
      must(!el.getTextContent(), 'an edge label');
      kindOf.set(el, { kind: 'link', index: d.dataIndex });
    } else if (d.dataType === 'node') {
      must(el.type === 'rect', 'a node element of type ' + el.type);
      kindOf.set(el, { kind: 'node', index: d.dataIndex });
      const t = el.getTextContent();
      if (t) {
        must(!t.ignore && !t.invisible, 'node ' + d.dataIndex + ': a hidden label Text');
        const kids = t.childrenRef();
        kids.forEach((k, li) => kindOf.set(k, { kind: 'tspan', index: d.dataIndex, line: li }));
        const tc = el.textConfig;
        const ds = el._innerTextDefaultStyle;
        const host = el.getBoundingRect().clone();
        if (el.transform) host.applyTransform(el.transform);
        const insidePosition = typeof tc.position === 'string' && tc.position.indexOf('inside') >= 0;
        const k0 = kids[0];
        labels.push({ index: d.dataIndex, text: t.style.text, lines: kids.map(k => k.style.text), hostRect: rect4(host), position: json(tc.position), distance: tc.distance,
          anchor: { x: t.innerTransformable.x, y: t.innerTransformable.y }, transform: m6(t.transform), align: json(ds.align), verticalAlign: json(ds.verticalAlign),
          insidePosition, inside: insidePosition && el.canBeInsideText(),
          fill: k0 ? json(k0.style.fill) : null, stroke: k0 ? json(k0.style.stroke) : null, lineWidth: k0 ? json(k0.style.lineWidth) : null, font: k0 ? json(k0.style.font) : null, z2: t.z2 });
      }
    } else must(false, 'a main-group child of dataType ' + d.dataType);
  }
  const ours = new Set(kindOf.keys());
  const foreign = list.filter(el => !ours.has(el)).length;
  const elements = list.filter(el => ours.has(el)).map(el => {
    const k = kindOf.get(el);
    const s = el.style;
    const e = { kind: k.kind, index: k.index };
    if (k.kind === 'tspan') e.line = k.line;
    Object.assign(e, { z: el.z, z2: el.z2, zlevel: el.zlevel, transform: m6(el.transform), fill: upFill(s.fill, el), stroke: json(s.stroke), lineWidth: json(s.lineWidth), opacity: json(s.opacity) });
    if (k.kind === 'link') {
      const sh = el.shape;
      e.shape = { x1: sh.x1, y1: sh.y1, x2: sh.x2, y2: sh.y2, cpx1: sh.cpx1, cpy1: sh.cpy1, cpx2: sh.cpx2, cpy2: sh.cpy2, extent: sh.extent, orient: sh.orient };
      e.bbox = rect4(el.getBoundingRect());
    } else if (k.kind === 'node') {
      const sh = el.shape;
      e.shape = { x: sh.x, y: sh.y, width: sh.width, height: sh.height, r: sh.r };
      e.bbox = rect4(el.getBoundingRect());
    } else Object.assign(e, { text: s.text, x: s.x, y: s.y, textAlign: json(s.textAlign), textBaseline: json(s.textBaseline), font: json(s.font) });
    return e;
  });
  must(elements.filter(e => e.kind === 'link').length === edges.length && elements.filter(e => e.kind === 'node').length === nodes.length, 'not every edge / node painted');
  return {
    name: fedSeries.name == null ? null : String(fedSeries.name),
    box: rect4(sm.layoutInfo), transform: mainGroup.transform ? [mainGroup.transform[4], mainGroup.transform[5]] : null,
    mainTransform: m6(mainGroup.transform),
    nodes, edges, elements, labels, foreign,
  };
}

// the fields both sides produce, in one shape (raw numbers); compared with Object.is
const NODE_KEYS = ['index', 'id', 'name', 'rawValue', 'value', 'depth', 'skNodeHeight', 'x', 'y', 'dx', 'dy', 'colour', 'outEdges', 'inEdges'];
const EDGE_KEYS = ['index', 'row', 'source', 'target', 'value', 'dy', 'sy', 'ty'];
const pick = (o, ks) => { const r = {}; for (const k of ks) r[k] = o[k]; return r; };
function upstreamView(u) {
  return { box: u.box, transform: u.transform, nodes: u.nodes.map(n => pick(n, NODE_KEYS)), edges: u.edges.map(e => pick(e, EDGE_KEYS)), elements: u.elements, labels: u.labels };
}
function transcribedView(t) {
  const LK = ['index', 'text', 'lines', 'hostRect', 'position', 'distance', 'anchor', 'transform', 'align', 'verticalAlign', 'insidePosition', 'inside', 'fill', 'stroke', 'lineWidth', 'font', 'z2'];
  return {
    box: t.resolved.box, transform: t.resolved.transform,
    nodes: t.nodes.map(n => pick(n, NODE_KEYS)), edges: t.edges.map(e => pick(e, EDGE_KEYS)),
    elements: t.elements.map(e => {
      const o = { kind: e.kind, index: e.index };
      if (e.kind === 'tspan') o.line = e.line;
      Object.assign(o, { z: e.z, z2: e.z2, zlevel: e.zlevel, transform: e.transform, fill: e.fill, stroke: e.stroke, lineWidth: e.lineWidth, opacity: e.opacity });
      if (e.kind === 'tspan') Object.assign(o, { text: e.text, x: e.x, y: e.y, textAlign: e.textAlign, textBaseline: e.textBaseline, font: e.font });
      else { o.shape = e.shape; o.bbox = e.bbox; }
      return o;
    }),
    labels: t.labels.map(l => pick(l, LK)),
  };
}
function flat(v, pre, out) {
  if (v === null || v === undefined || typeof v !== 'object') { out[pre] = v === undefined ? null : v; return out; }
  if (isArray(v)) { out[pre + '#'] = v.length; v.forEach((x, i) => flat(x, pre + '[' + i + ']', out)); return out; }
  for (const k of Object.keys(v)) flat(v[k], pre + '.' + k, out);
  return out;
}
function diffFlat(a, b) {
  const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))));
  return keys.filter(k => !Object.is(a[k], b[k])).map(k => ({ field: k, upstream: a[k] === undefined ? '(absent)' : a[k], transcribed: b[k] === undefined ? '(absent)' : b[k] }));
}

// ============================================================================
// Recording a case
// ============================================================================
const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));
function recordCase(def, withProd) {
  const opt = def.gallery ? gallery(def.gallery) : zrClone(def.option);
  const animationForced = opt.animation !== false;
  opt.animation = false;
  const optionText = JSON.stringify(opt);
  const fed = JSON.parse(optionText);
  must(isArray(fed.series) ? fed.series.length === 1 : !!fed.series, 'one sankey series per case');
  const fedSeries = [].concat(fed.series)[0];
  must(fedSeries.type === 'sankey', 'not a sankey');
  const ref = refusedKeys(fedSeries);
  must(!ref.length, 'refused keys: ' + ref.join(', '));
  const W = def.W || 800; const H = def.H || 600;
  const rec = runChart(echarts, JSON.parse(optionText), W, H, chart => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const u = readSankey(chart, fedSeries);
    must(!u.foreign || def.gallery, 'elements of another component in a hand-written case');
    const bg = zr.getBackgroundColor();
    return { palette: json(ec.option.color), textStyle: json(ec.option.textStyle), ground: { background: bg == null || bg === '' ? null : json(bg), isDark: !!zr.isDarkMode() }, u };
  });
  if (withProd) {
    const p = runChart(PROD, JSON.parse(optionText), W, H, chart => readSankey(chart, fedSeries));
    must(JSON.stringify(flat(upstreamView(rec.u), 's', {})) === JSON.stringify(flat(upstreamView(p), 's', {})), 'the production build records differently');
  }
  const env = { W, H, palette: rec.palette, fontFamily: rec.textStyle.fontFamily, ground: rec.ground };
  must(typeof env.fontFamily === 'string', 'no global fontFamily');
  return { def, W, H, optionText, animationForced, fedSeries, env, rec };
}

// ============================================================================
// The cases
// ============================================================================
const one = (series, extra) => Object.assign({ animation: false, series: [Object.assign({ type: 'sankey' }, series)] }, extra || {});
const D4 = () => ({ data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }], links: [{ source: 'a', target: 'c', value: 3 }, { source: 'b', target: 'c', value: 1 }, { source: 'c', target: 'd', value: 2 }] });
const D6 = () => ({ data: ['a', 'b', 'c', 'd', 'e', 'f'].map(name => ({ name })), links: [{ source: 'a', target: 'b', value: 5 }, { source: 'b', target: 'c', value: 3 }, { source: 'c', target: 'f', value: 4 }, { source: 'd', target: 'c', value: 2 }, { source: 'a', target: 'e', value: 1 }] });
const PAR = () => ({ data: [{ name: 'p' }, { name: 'q' }, { name: 'r' }], links: [{ source: 'p', target: 'q', value: 2 }, { source: 'p', target: 'q', value: 5 }, { source: 'p', target: 'r', value: 3 }, { source: 'p', target: 'q', value: 1 }, { source: 'q', target: 'r', value: 4 }] });
// the hand cases; each is recorded at 800 x 600 and at 700 x 420 (id suffix @700)
const HAND = [
  ['D4', 'the upstream.md 6 anchor graph D4 (a->c 3, b->c 1, c->d 2), defaults: 32 iterations', one(D4())],
  ['D4-iter0', 'D4 with layoutIterations 0', one(Object.assign(D4(), { layoutIterations: 0 }))],
  ['D4-iter1', 'D4 with layoutIterations 1 (c y 1.98)', one(Object.assign(D4(), { layoutIterations: 1 }))],
  ['D6-left', 'D6 (a->b->c->f, d->c, a->e) nodeAlign left', one(Object.assign(D6(), { nodeAlign: 'left' }))],
  ['D6-justify', 'D6 default justify: the sink e moves to the last column', one(D6())],
  ['D6-right', "D6 nodeAlign 'right': depth = maxDepth - longest path to a sink (skNodeHeight)", one(Object.assign(D6(), { nodeAlign: 'right' }))],
  ['D6-foo', "D6 nodeAlign 'foo': any other string is 'left'", one(Object.assign(D6(), { nodeAlign: 'foo' }))],
  ['no-links', 'no links: kx = Infinity, every breadth NaN, every size NaN (minKy stays Infinity)', one({ data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }] })],
  ['no-links-values', 'no links but node values: NaN breadths, sizes from (H - 2 gap) / sum', one({ data: [{ name: 'a', value: 3 }, { name: 'b', value: 0 }, { name: 'c', value: 1 }] })],
  ['one-node', 'one node', one({ data: [{ name: 'a' }] })],
  ['no-data', 'no data at all', one({ data: [] })],
  ['missing-value', 'a link without value: NaN dy, NaN extent, NaN bbox', one({ data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }], links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c', value: 2 }] })],
  ['relax-nan', "a node whose out-links are one valued and one without a value, every node positive so the relaxation runs: the weighted mean skips the NaN product and the NaN weight (the plain-mean fallback does not fire)", one({ data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }], links: [{ source: 'a', target: 'c', value: 3 }, { source: 'a', target: 'd' }, { source: 'b', target: 'd', value: 2 }, { source: 'b', target: 'c', value: 1 }] })],
  ['missing-value-gradient', "a link without value under 'gradient' links: the NaN bbox gives canvas gradient points 0 / 1 / 0 / 0 (isSafeNum)", one({ data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }], links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c', value: 2 }], lineStyle: { color: 'gradient' } })],
  ['zero-values', 'zero-valued links (1-px slivers, extent max(1, 0)); every node keeps a positive value, so the relaxation runs', one({ data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }], links: [{ source: 'a', target: 'b', value: 0 }, { source: 'b', target: 'c', value: 2 }, { source: 'a', target: 'c', value: 1 }] })],
  ['negative-value', 'a negative link: both nodes value 0, minKy Infinity', one({ data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: -3 }] })],
  ['all-zero-out', "data beats nodes; a's out-links are all 0 (a has value 0 -> iterations 0)", one({ data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }], links: [{ source: 'a', target: 'b', value: 0 }, { source: 'c', target: 'b', value: 4 }, { source: 'a', target: 'd', value: 0 }, { source: 'c', target: 'd', value: 2 }, { source: 'a', target: 'd', value: 0 }], nodes: [{ name: 'ignored' }] })],
  ['nan-fallback', 'the relaxation 0/0 fallback (plain mean of the neighbour centres) with iterations > 0', one({ data: [{ name: 'a', value: 5 }, { name: 'b' }, { name: 'c' }], links: [{ source: 'a', target: 'b', value: 0 }, { source: 'c', target: 'b', value: 4 }] })],
  ['tiny-box', 'left 0.00001, top -0.00002: the group translation is dropped (5e-5 rule), elements draw at local coordinates', one(Object.assign(D4(), { left: 0.00001, top: -0.00002 }))],
  ['kx-zero', 'nodeWidth = box width: kx 0, one column', one(Object.assign(D4(), { nodeWidth: 600 }))],
  ['kx-negative', 'nodeWidth > box width: kx < 0, the columns run right to left, depth 0 at x = -0', one(Object.assign(D4(), { nodeWidth: 700, layoutIterations: 5 }))],
  ['ky-negative', 'nodeGap 400: ky < 0, negative sizes (flipped label hosts)', one(Object.assign(D4(), { nodeGap: 400 }))],
  ['explicit-depth', 'explicit depths 3, 0.5, 1: maxDepth 3, a fractional column, successors keep their Kahn layers', one(Object.assign(D4(), { data: [{ name: 'a', depth: 3 }, { name: 'b', depth: 0.5 }, { name: 'c' }, { name: 'd', depth: 1 }] }))],
  ['local-vertical', 'localX / localY (box fractions) in the vertical orient: rect, label and link ends move, the layout does not', one(Object.assign(D4(), { data: [{ name: 'a', localX: 0.1, localY: 0.2 }, { name: 'b' }, { name: 'c', localY: 0.5 }, { name: 'd', localX: 0.9 }], orient: 'vertical' }))],
  ['same-depth-levels', 'two levels with depth 1: the later one wins', one(Object.assign(D4(), { levels: [{ depth: 1, itemStyle: { color: 'red' } }, { depth: 1, itemStyle: { color: 'blue' } }] }))],
  ['numeric-names', "nodes named 1, 2, '0': source 1 / target 2 are INDICES (nodes[1] -> nodes[2]); '1' / '2' are keys", one({ data: [{ name: 1 }, { name: 2 }, { name: '0' }], links: [{ source: 1, target: 2, value: 1 }, { source: '1', target: '2', value: 1 }] })],
  ['dropped-edges', "unresolved links (a missing key, an index out of range, a non-integer index) are dropped without consuming an edge dataIndex: edges[].row keeps the option index", one({ data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }], links: [{ source: 'a', target: 'zz', value: 4 }, { source: 'a', target: 'b', value: 3 }, { source: 7, target: 'c', value: 1 }, { source: 1.5, target: 2, value: 2 }, { source: 1, target: 2, value: 2 }] })],
  ['edges-beat-links', 'edges beats links (JS truthiness)', one({ data: [{ name: 'p' }, { name: 'q' }], edges: [{ source: 'p', target: 'q', value: 1 }], links: [{ source: 'q', target: 'p', value: 9 }] })],
  ['empty-palette', 'color: []: every node colour undefined, rects unfilled', one(Object.assign(D4(), { color: [] }))],
  ['unfilled-stroked', "color: [] with a rect border and a stroked 'source' band: unfilled hosts grow by max(lw, 5)", one(Object.assign(D4(), { color: [], itemStyle: { borderColor: '#000' }, lineStyle: { color: 'source', borderColor: '#f00' }, label: { position: 'left' } }))],
  ['inside-unfilled', "color: [] with label position 'inside': Path.canBeInsideText is hasFill, so an unfilled rect takes the OUTSIDE colours (#333 + the halo)", one(Object.assign(D4(), { color: [], itemStyle: { borderColor: '#000' }, label: { position: 'inside' } }))],
  ['gradient-object', "a node colour that is a gradient object under 'gradient' links: the band keeps the literal fill 'gradient'", one(Object.assign(D4(), { lineStyle: { color: 'gradient' }, data: [{ name: 'a', itemStyle: { color: { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: 'red' }, { offset: 1, color: 'blue' }] } } }, { name: 'b' }, { name: 'c' }, { name: 'd' }] }))],
  ['gradient-object-source', "a gradient-object node colour under 'source' links: the band takes the object", one(Object.assign(D4(), { lineStyle: { color: 'source' }, data: [{ name: 'a', itemStyle: { color: { type: 'linear', x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: 'rgba(0,0,255,0.5)' }] } } }, { name: 'b' }, { name: 'c' }, { name: 'd' }] }))],
  ['gradient-vertical', "'gradient' links in the vertical orient: x2 0, y2 1", one(Object.assign(D6(), { orient: 'vertical', lineStyle: { color: 'gradient' } }))],
  ['parallel', 'parallel links p->q (2, 5, 1): the edge sort keeps ties in option order', one(PAR())],
  ['source-stroked', "'source' links over rects with a default-width border: labels move by 0.5", one(Object.assign(D6(), { lineStyle: { color: 'source' }, itemStyle: { borderColor: '#222' } }))],
  ['curve14-gradient', "curveness 1.4 with 'gradient': the symmetric control points do NOT overshoot the ends (the local extrema stay inside), so the bbox is the end points up to the last bit", one(Object.assign(D6(), { lineStyle: { color: 'gradient', curveness: 1.4 } }))],
  ['curve4-gradient', "curveness 4 with 'gradient': the band overshoots its ends, the bbox (hence the canvas gradient) takes the cubic extrema", one(Object.assign(D6(), { lineStyle: { color: 'gradient', curveness: 4 } }))],
  ['fmt-first', "formatter '{b}-{b} {c}/{c} {a}': only the first occurrence of each placeholder is replaced", one(Object.assign(D4(), { name: 'Ser', label: { formatter: '{b}-{b} {c}/{c} {a}' } }))],
  ['fmt-layout-value', "formatter '{c}' on nodes without a value: the layout value; with a value: the raw value", one(Object.assign(D4(), { data: [{ name: 'a', value: 10 }, { name: 'b' }, { name: 'c', value: '4' }, { name: 'd' }], label: { formatter: '{b}={c}' } }))],
  ['id-name', "the default label is node.id: {id 'I', name 'nm'} shows 'I'; a nameless node shows its index", one({ data: [{ id: 'I', name: 'nm' }, { name: 'b' }, {}], links: [{ source: 'I', target: 'b', value: 2 }, { source: 'b', target: '2', value: 1 }] })],
  ['right-explicit', "nodeAlign 'right' leaves an explicit depth alone", one(Object.assign(D6(), { nodeAlign: 'right', data: [{ name: 'a' }, { name: 'b', depth: 0 }, { name: 'c' }, { name: 'd' }, { name: 'e', depth: 1 }, { name: 'f' }] }))],
  ['levels-aligned', "levels are looked up by the ALIGNED depth: under 'justify' the sink e takes the last column's level", one(Object.assign(D6(), { levels: [{ depth: 1, itemStyle: { color: '#0a0' } }, { depth: 3, itemStyle: { color: '#a00' }, label: { position: 'left', color: '#00f' } }] }))],
  ['edge-level-source', "an edge takes the level of its SOURCE node's depth", one(Object.assign(D4(), { levels: [{ depth: 0, lineStyle: { color: 'source', opacity: 0.6 } }, { depth: 1, lineStyle: { color: '#00f' } }] }))],
  ['label-positions', 'every label position on one graph via item labels', one({ data: ['left', 'right', 'top', 'bottom', 'inside', 'insideLeft', 'insideRight', 'insideTop', 'insideBottom'].map((p, i) => ({ name: p, label: { position: p, distance: i } })).concat([{ name: 'arr', label: { position: ['30%', 4] } }]), links: [{ source: 'left', target: 'top', value: 3 }, { source: 'right', target: 'top', value: 2 }, { source: 'top', target: 'inside', value: 4 }, { source: 'bottom', target: 'inside', value: 1 }, { source: 'inside', target: 'insideLeft', value: 2 }, { source: 'insideRight', target: 'insideLeft', value: 3 }, { source: 'insideTop', target: 'insideBottom', value: 1 }, { source: 'insideLeft', target: 'arr', value: 5 }] })],
  ['bg-alpha', "a half-transparent blue background: the outside halo is 'rgba(127.5,127.5,255,1)'", one(D4(), { backgroundColor: 'rgba(0,0,255,0.5)' })],
  ['dark', 'darkMode: outside labels #ccc, the halo blended over black; inside strokes by the dark rule', one(Object.assign(D6(), { data: D6().data.map((d, i) => (i % 2 ? Object.assign(d, { label: { position: 'inside' } }) : d)) }), { darkMode: true })],
  ['styles', 'item styles: borderRadius, opacity, borderWidth 0 (no stroke), per-link colour / opacity / curveness, multi-line name, fonts', one({ data: [{ name: 'a', itemStyle: { borderRadius: 3, opacity: 0.5 } }, { name: 'b\nsecond', itemStyle: { borderColor: '#0f0', borderWidth: 0 } }, { name: 'c', itemStyle: { borderColor: 'red', borderWidth: 3 }, label: { fontSize: 15, fontFamily: 'Arial' } }, { name: 'd', label: { show: false } }], links: [{ source: 'a', target: 'c', value: 3, lineStyle: { color: '#aa3344', opacity: 0.8 } }, { source: 'b\nsecond', target: 'c', value: 1, lineStyle: { curveness: 0.2 } }, { source: 'c', target: 'd', value: 2, lineStyle: { color: 'target' } }] })],
  ['palette-mixed', "a global colour list with alpha, an unparseable 'none' (black) and a 3-digit hex", one(D6(), { color: ['none', 'rgba(0,128,255,0.25)', '#f80', '#123456'] })],
  ['palette-single', 'a single colour string as the series colour', one(Object.assign(D6(), { color: '#123456' }))],
  ['equal-values', 'all node values equal: the middle palette entry', one({ data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: 4 }] })],
  ['sums-order', 'sums in list order: 0.1 + 0.2 = 0.30000000000000004', one({ data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }], links: [{ source: 'a', target: 'c', value: 0.1 }, { source: 'b', target: 'c', value: 0.2 }] })],
  ['box-options', 'left 10, top 10%, width 300, height 50%', one(Object.assign(D6(), { left: 10, top: '10%', width: 300, height: '50%', name: 'Box' }))],
  ['z', 'z 5 reaches every element', one(Object.assign(D4(), { z: 5 }))],
  ['layout-none', "layout: 'none' is not a sankey option (ignored)", one(Object.assign(D4(), { layout: 'none' }))],
];
const GALLERY_FILES = ['sankey-energy', 'sankey-itemstyle', 'sankey-levels', 'sankey-nodeAlign-left', 'sankey-nodeAlign-right', 'sankey-simple', 'sankey-vertical'];

// ---------------- the random families (wf78/ref.js generator) ----------------
function randomCases(nGraphs) {
  let seed = 20260930;
  const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
  const ri = n => Math.floor(rnd() * n);
  const pickR = a => a[ri(a.length)];
  function genGraph(opts) {
    const n = 1 + ri(opts.maxN || 16);
    const rank = []; const data = [];
    const order = []; for (let i = 0; i < n; i++) order.push(i);
    for (let i = n - 1; i > 0; i--) { const j = ri(i + 1); [order[i], order[j]] = [order[j], order[i]]; }
    for (let i = 0; i < n; i++) rank.push(ri(1 + ri(6)));
    const key = [];
    for (let i = 0; i < n; i++) {
      const it = {}; const u = rnd();
      if (u < 0.85) { it.name = 'n' + i + (rnd() < 0.1 ? 'Longer label' : ''); key.push(it.name); } else if (u < 0.93) { it.id = 'id' + i; it.name = 'nm' + i; key.push(it.id); } else { key.push(String(i)); if (rnd() < 0.5) it.value = ri(9); }
      if (rnd() < 0.04) it.name = (it.name || 'x') + '\nsecond';
      if (it.name && it.name.indexOf('\n') >= 0 && !it.id) key[i] = it.name;
      if (rnd() < 0.1) it.value = +(rnd() * 40).toFixed(ri(3));
      if (rnd() < 0.05) it.depth = rnd() < 0.8 ? ri(4) : ri(4) + 0.5;
      if (rnd() < 0.04) { it.localX = +(rnd()).toFixed(2); if (rnd() < 0.5) it.localY = +(rnd()).toFixed(2); }
      if (opts.styles && rnd() < 0.08) it.itemStyle = pickR([{ color: '#123456' }, { borderColor: '#000' }, { borderColor: 'red', borderWidth: 3 }, { opacity: 0.4 }, { borderWidth: 0, borderColor: '#0f0' }, { borderRadius: 2 }]);
      if (opts.styles && rnd() < 0.04) it.label = pickR([{ show: false }, { position: 'left' }, { color: 'blue' }, { position: 'inside' }]);
      data.push(it);
    }
    const links = [];
    const m = ri(2 * n + 2);
    for (let k = 0; k < m; k++) {
      const a = ri(n); const b = ri(n);
      if (rank[a] >= rank[b]) continue;
      const l = {};
      const refOf = i => (rnd() < 0.08 ? i : key[i]);
      l.source = refOf(a); l.target = refOf(b);
      if (rnd() < 0.02) l.target = 'missing';
      const u = rnd();
      if (u < 0.6) l.value = 1 + ri(20); else if (u < 0.85) l.value = +(rnd() * 30).toFixed(3); else if (u < 0.95) l.value = opts.noZero ? 1 : 0; else if (u < 0.98 && !opts.noMissing) { /* missing */ } else l.value = 5;
      if (opts.styles && rnd() < 0.06) l.lineStyle = pickR([{ color: 'source' }, { color: 'target' }, { color: 'gradient' }, { color: '#aa3344', opacity: 0.8 }, { curveness: 0.2 }]);
      links.push(l);
      if (rnd() < 0.05) links.push(zrClone(l));
      if (l.target !== 'missing' && l.value > 0) { data[a].__pos = 1; data[b].__pos = 1; }
    }
    for (const it of data) { if (opts.full && !it.__pos && !(it.value > 0)) it.value = 1 + ri(12); delete it.__pos; }
    return { data, links };
  }
  const VARIANTS = [
    () => ({}),
    () => ({ nodeAlign: 'left' }),
    () => ({ nodeAlign: 'right' }),
    () => ({ orient: 'vertical', label: { position: 'top' } }),
    () => ({ orient: 'vertical', nodeAlign: 'right', lineStyle: { color: 'gradient' } }),
    () => ({ nodeGap: 0, nodeWidth: 5, layoutIterations: 1 }),
    () => ({ nodeGap: 30, nodeWidth: 60, layoutIterations: 0 }),
    () => ({ levels: [{ depth: 0, itemStyle: { color: '#fbb4ae' }, lineStyle: { color: 'source', opacity: 0.6 } }, { depth: 1, itemStyle: { color: '#b3cde3' }, label: { position: 'left' } }, { depth: 2, lineStyle: { color: 'target', curveness: 0.8 } }], lineStyle: { curveness: 0.3 } }),
    () => ({ lineStyle: { color: 'gradient', opacity: 0.6 }, color: ['#000', '#ff0000', 'rgba(0,0,255,0.5)'] }),
    () => ({ left: 10, top: '15%', width: '60%', height: 300, name: 'Ser' }),
    () => ({ left: 0, top: 0, right: 0, bottom: 0, label: { position: 'inside' } }),
    () => ({ itemStyle: { borderColor: '#333', borderWidth: 2 }, label: { position: 'bottom', distance: 9 } }),
    () => ({ lineStyle: { color: 'target', curveness: 1.4 }, layoutIterations: 3 }),
    // ref.js has no series name here; a name keeps {a} free of 'series\u00000' (fpjson drops \u0000)
    () => ({ label: { formatter: '{b}: {c} ({a})', fontSize: 14, fontFamily: 'Arial' }, nodeAlign: 'right', name: 'Flow' }),
    () => ({ nodeGap: 150 }),
    () => ({ nodeWidth: 900, layoutIterations: 2 }),
    () => ({ label: { position: ['50%', 10] }, lineStyle: { color: 'source', borderColor: '#000', borderWidth: 1 } }),
    () => ({ orient: 'vertical', label: { position: 'insideTop' }, itemStyle: { borderColor: 'red' }, layoutIterations: 7 }),
    () => ({ color: '#123456', label: { position: 'insideRight', color: '#fff' } }),
    () => ({ layoutIterations: 64, nodeAlign: 'justify', nodeGap: 3 }),
  ];
  const SIZES = [[800, 600], [700, 420], [300, 200], [1000, 350], [400, 700]];
  const GLOBALS = [undefined, undefined, undefined, { color: ['#c23531', '#2f4554', '#61a0a8', '#d48265'] }];
  const out = [];
  for (let f = 0; f < nGraphs; f++) {
    const g = genGraph({ styles: f % 2 === 0, maxN: f % 5 === 4 ? 40 : 16, full: f % 3 !== 0, noZero: f % 6 === 1, noMissing: f % 3 !== 0 });
    for (let v = 0; v < VARIANTS.length; v++) {
      const [W, H] = SIZES[(f + v) % SIZES.length];
      const glob = GLOBALS[(f + v) % GLOBALS.length];
      out.push({ id: 'R-' + f + '-' + v, note: 'ref.js random graph ' + f + ' x variant ' + v + ' at ' + W + ' x ' + H + (glob ? ' with a global colour list' : ''),
        option: one(Object.assign({}, zrClone(g), VARIANTS[v]()), glob ? zrClone(glob) : undefined), W, H, random: { graph: f, variant: v } });
    }
  }
  return out;
}

// ============================================================================
// The guards: ref.js's mutants ('center' omitted: `pos + size * 0.5` and `pos + size / 2` are the same IEEE
// operation) plus the upstream.md 8 traps ref.js did not break
// ============================================================================
const GUARDS = [
  ['alphaDecay', 'alpha = Math.pow(0.99, k) instead of the running product alpha *= 0.99', ['H-D4']],
  ['nosort', 'no column sort in resolveCollisions', []],
  ['unstable', 'node-sort ties broken in reverse (not stable)', ['H-guard-unstable']],
  ['relaxOrder', 'the right-to-left pass walks the columns left to right', []],
  ['jacobi', 'relaxation updates applied after the whole pass (Jacobi, not Gauss-Seidel)', ['H-D4']],
  ['minKyPerColumn', 'each column its own ky', ['H-D4']],
  ['zeroIter', "the 'any zero-valued node -> 0 iterations' rule ignored", ['H-missing-value']],
  ['justify', "'justify' does not move the sinks right", ['H-D6-justify']],
  ['rightAlign', "'right': skNodeHeight from the first visit instead of the last", ['H-D6-right']],
  ['rightExplicit', "'right' alignment overrides an explicit depth", ['H-right-explicit']],
  ['kxOrder', '`W/maxDepth - nw/maxDepth` instead of `(W - nw) / maxDepth`', []],
  ['cpx', 'control points `x1 + (x2 - x1)*c` instead of `x1*(1-c) + x2*c`', []],
  ['extent', 'no `max(1, dy)` band extent', ['H-zero-values']],
  ['edgeSort', 'out / in edges left in option order', ['H-zero-values', 'H-parallel']],
  ['edgeSortKey', "edges sorted by the other node's centre instead of its top", []],
  ['edgeUnstable', 'ties in the edge sort reversed (parallel links)', ['H-parallel']],
  ['palette', 'colour by node index instead of node value', ['H-D4']],
  ['lerpRound', 'fastLerp channels floored instead of Math.round', ['H-D4']],
  ['levelDepthEdge', "an edge takes the TARGET node's level", ['H-edge-level-source']],
  ['levelKahn', 'levels looked up by the Kahn depth (before nodeAlign)', ['H-levels-aligned', 'G-levels']],
  ['labelStroke', 'the label host ignores the stroke', ['H-source-stroked', 'G-itemstyle']],
  ['unfilled5', 'an unfilled stroked host grows by lw, not max(lw, 5)', ['H-unfilled-stroked']],
  ['insideUnfilled', "an 'inside' label on an unfilled rect uses the inside colours (canBeInsideText ignored)", ['H-inside-unfilled']],
  ['labelOrder', "'right' label x as `(x + d) + w` instead of `x + (d + w)`", ['H-guard-labelOrder']],
  ['backpass', 'no backward pass in resolveCollisions', ['H-D4']],
  ['resolveGapEnd', '`y0 - H` instead of `(y0 - gap) - H`', []],
  ['sumNaN', 'NaN not skipped in the sums', ['H-missing-value']],
  ['weighted', 'unweighted mean of the neighbour centres', ['H-D4']],
  ['numericSource', 'a numeric source / target looked up as a key', ['H-numeric-names']],
  ['z2', 'label z2 = host z2 + 1', ['H-D4']],
  ['defaultText', 'the default label is the name instead of node.id', ['H-id-name']],
  ['fmtAll', 'the formatter replaces every occurrence of a placeholder', ['H-fmt-first']],
  ['groupKey', 'columns keyed by depth instead of the scaled breadth x', ['H-kx-zero']],
  ['bbox', 'the cubic bbox from the end points only', ['H-curve4-gradient', 'H-D6-left']],
  ['gradientUnsafe', 'non-finite canvas gradient points kept (no isSafeNum fallback)', ['H-missing-value-gradient']],
];

// ============================================================================
// Output
// ============================================================================
const hx = v => (v === null || v === undefined ? null : hex(v));
const hxRect = r => ({ x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) });
const dcRect = r => ({ x: dec(r.x), y: dec(r.y), width: dec(r.width), height: dec(r.height) });
function fillOut(f) {
  if (f == null || typeof f === 'string') return f;
  return { type: f.type, x: decOrNull(f.x), y: decOrNull(f.y), x2: decOrNull(f.x2), y2: decOrNull(f.y2), global: f.global, colorStops: f.colorStops.map(s => ({ offset: dec(s.offset), color: s.color })),
    canvas: { x: hex(f.canvas.x), y: hex(f.canvas.y), x2: hex(f.canvas.x2), y2: hex(f.canvas.y2) }, canvasText: { x: dec(f.canvas.x), y: dec(f.canvas.y), x2: dec(f.canvas.x2), y2: dec(f.canvas.y2) },
    canvasGlobal: { x: hex(f.canvasGlobal.x), y: hex(f.canvasGlobal.y), x2: hex(f.canvasGlobal.x2), y2: hex(f.canvasGlobal.y2) },
    canvasGlobalText: { x: dec(f.canvasGlobal.x), y: dec(f.canvasGlobal.y), x2: dec(f.canvasGlobal.x2), y2: dec(f.canvasGlobal.y2) } };
}
function emitSeries(c) {
  const u = c.rec.u;
  const t = c.tr;
  const R = t.resolved;
  const labelOut = l => ({
    index: l.index, text: l.text, lines: l.lines, hostRect: hxRect(l.hostRect), hostRectText: dcRect(l.hostRect), position: l.position, distance: l.distance,
    anchor: { x: hex(l.anchor.x), y: hex(l.anchor.y) }, anchorText: { x: dec(l.anchor.x), y: dec(l.anchor.y) }, transform: l.transform ? l.transform.map(hex) : null,
    align: l.align, verticalAlign: l.verticalAlign, insidePosition: l.insidePosition, inside: l.inside, colourRule: t.labels.find(x => x.index === l.index).colourRule,
    fill: l.fill, stroke: l.stroke, lineWidth: l.lineWidth, font: l.font, z2: l.z2,
  });
  const pieceOut = e => {
    const o = { z: e.z, z2: e.z2, zlevel: e.zlevel, transform: e.transform ? e.transform.map(hex) : null, fill: fillOut(e.fill), stroke: e.stroke, lineWidth: e.lineWidth, opacity: e.opacity };
    const s = e.shape;
    if (e.kind === 'link') {
      o.shape = { x1: hex(s.x1), y1: hex(s.y1), x2: hex(s.x2), y2: hex(s.y2), cpx1: hex(s.cpx1), cpy1: hex(s.cpy1), cpx2: hex(s.cpx2), cpy2: hex(s.cpy2), extent: hex(s.extent), orient: s.orient };
      o.shapeText = { x1: dec(s.x1), y1: dec(s.y1), x2: dec(s.x2), y2: dec(s.y2), cpx1: dec(s.cpx1), cpy1: dec(s.cpy1), cpx2: dec(s.cpx2), cpy2: dec(s.cpy2), extent: dec(s.extent) };
    } else {
      o.shape = { x: hex(s.x), y: hex(s.y), width: hex(s.width), height: hex(s.height), r: hex(s.r) };
      o.shapeText = { x: dec(s.x), y: dec(s.y), width: dec(s.width), height: dec(s.height), r: dec(s.r) };
    }
    o.bbox = hxRect(e.bbox); o.bboxText = dcRect(e.bbox);
    return o;
  };
  const elOf = (kind, i) => u.elements.find(e => e.kind === kind && e.index === i);
  const nodes = u.nodes.map((n, i) => {
    const tn = t.nodes[i];
    const lab = u.labels.find(l => l.index === i);
    return {
      index: n.index, id: n.id, name: n.name, rawValue: dec(n.rawValue), value: dec(n.value), depth: dec(n.depth), kahnDepth: dec(tn.kahnDepth), skNodeHeight: n.skNodeHeight,
      x: hex(n.x), y: hex(n.y), dx: hex(n.dx), dy: hex(n.dy), layoutText: { x: dec(n.x), y: dec(n.y), dx: dec(n.dx), dy: dec(n.dy) },
      colour: n.colour, colourSource: tn.colourSource, level: decOrNull(tn.level), outEdges: n.outEdges, inEdges: n.inEdges,
      rect: pieceOut(elOf('node', i)),
      label: lab ? labelOut(lab) : null,
    };
  });
  const edges = u.edges.map((e, i) => ({
    index: e.index, row: e.row, source: e.source, target: e.target, value: dec(e.value), dy: hex(e.dy), sy: hex(e.sy), ty: hex(e.ty),
    layoutText: { dy: dec(e.dy), sy: dec(e.sy), ty: dec(e.ty) }, level: decOrNull(t.edges[i].level),
    band: pieceOut(elOf('link', i)),
  }));
  const elements = u.elements.map(e => {
    const o = { kind: e.kind, index: e.index };
    if (e.kind !== 'tspan') return Object.assign(o, { z: e.z, z2: e.z2, zlevel: e.zlevel });
    return Object.assign(o, { line: e.line, z: e.z, z2: e.z2, zlevel: e.zlevel, transform: e.transform ? e.transform.map(hex) : null, fill: e.fill, stroke: e.stroke, lineWidth: e.lineWidth, opacity: e.opacity,
      text: e.text, x: hex(e.x), y: hex(e.y), textAlign: e.textAlign, textBaseline: e.textBaseline, font: e.font });
  });
  return {
    name: u.name,
    resolved: {
      box: hxRect(u.box), boxText: dcRect(u.box), transform: u.transform ? u.transform.map(hex) : null, transformText: u.transform ? u.transform.map(dec) : null,
      orient: R.orient, nodeWidth: dec(R.nodeWidth), nodeGap: dec(R.nodeGap), layoutIterations: R.layoutIterations, iterations: R.iterations, nodeAlign: R.nodeAlign,
      maxDepth: hex(R.maxDepth), maxDepthText: dec(R.maxDepth), kx: hex(R.kx), kxText: dec(R.kx), minKy: hex(R.minKy), minKyText: dec(R.minKy),
      columns: R.columns, colorList: R.colorList, colourExtent: R.colourExtent.map(dec), levels: R.levels.map(l => ({ depth: dec(l.depth), level: l.level })),
    },
    nodes, edges, elements,
  };
}
const LINE = 250;
function oneLine(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (isArray(v)) return '[' + v.map(x => oneLine(x === undefined ? null : x)).join(',') + ']';
  return '{' + Object.keys(v).filter(k => v[k] !== undefined).map(k => JSON.stringify(k) + ':' + oneLine(v[k])).join(',') + '}';
}
function fmt(v, ind) {
  const f = oneLine(v);
  if (f.length + ind.length <= LINE || v === null || typeof v !== 'object') return f;
  const inner = ind + ' ';
  if (isArray(v)) return '[\n' + v.map(x => inner + fmt(x === undefined ? null : x, inner)).join(',\n') + '\n' + ind + ']';
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner)).join(',\n') + '\n' + ind + '}';
}

// ============================================================================
// Main
// ============================================================================
const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));
const NRANDOM = +(process.env.ORACLE_RANDOM || 16);
let exitCode = 0;
if (require.main !== module) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  module.exports = { transcribe, measure, SK_DEFAULTS, recordCase, readSankey, upstreamView, transcribedView, flat, diffFlat, randomCases, one };
} else try {
  // the bare words the transcription treats as unparseable really are (zrender's colour table)
  for (const w of CSS_UNPARSED) must(echarts.color.parse(w) === undefined, 'zrender parses ' + w);
  for (const w of Object.keys(CSS_NAMES)) must(JSON.stringify(echarts.color.parse(w)) === JSON.stringify(CSS_NAMES[w]), 'zrender parses ' + w + ' differently');
  const measureRec = checkMeasurer();
  const defs = [];
  for (const [id, note, option] of HAND) {
    defs.push({ id: 'H-' + id, note, option, W: 800, H: 600 });
    defs.push({ id: 'H-' + id + '@700', note: note + ' (700 x 420)', option, W: 700, H: 420 });
  }
  defs.push({ id: 'H-guard-unstable', note: "found by a search over the transcription (mutated vs not): nodeGap -30 makes a node's size + gap exactly 0, the forward pass pushes the next node onto the same position, and the next collision pass meets a tie that only a stable sort keeps in order", option: GUARD_UNSTABLE(), W: 800, H: 600 });
  defs.push({ id: 'H-guard-labelOrder', note: "found by a search over the transcription (mutated vs not): at 328 x 391 with nodeWidth 27 a right label's x + (5 + 27) and (x + 5) + 27 differ in the last bit", option: GUARD_LABEL_ORDER(), W: 328, H: 391 });
  for (const g of GALLERY_FILES) {
    for (const [W, H] of [[800, 600], [700, 420]]) {
      const id = 'G-' + g.replace(/^sankey-/, '') + (W === 800 ? '' : '@700');
      defs.push({ id, gallery: g, note: 'examples/advchart/gallery/' + g + '.json verbatim (animation forced false where the file lacks it; a title is another component and is left out) at ' + W + ' x ' + H, W, H });
    }
  }
  for (const d of randomCases(NRANDOM)) defs.push(d);
  { const seen = new Set(); for (const d of defs) { must(!seen.has(d.id), 'duplicate id ' + d.id); seen.add(d.id); } }
  const recs = [];
  let checks = 0;
  for (const d of defs) {
    let c;
    try {
      c = recordCase(d, !d.id.startsWith('R-'));
      c.tr = transcribe(c.fedSeries, c.env, null);
      const a = flat(upstreamView(c.rec.u), 's', {});
      const b = flat(transcribedView(c.tr), 's', {});
      const df = diffFlat(a, b);
      checks += Object.keys(a).length;
      must(!df.length, 'the transcription differs from upstream at ' + df.length + ' fields: ' + df.slice(0, +(process.env.ORACLE_NDIFF || 6)).map(x => JSON.stringify(x)).join('; '));
      c.flatUp = a;
    } catch (e) {
      if (e instanceof OracleError) e.message = d.id + ': ' + e.message;
      throw e;
    }
    recs.push(c);
  }
  // anchors from upstream.md
  const byId = {};
  recs.forEach(c => { byId[c.def.id] = c; });
  const U = id => byId[id].rec.u;
  const is = Object.is;
  {
    const n = U('H-D4').nodes;
    must(is(n[0].y, 7.815970093361102e-14) && is(n[0].dy, 399) && is(n[1].y, 407.00000000000006) && is(n[2].x, 290) && is(n[2].y, 2.0000000000000133) && is(n[3].y, 135), 'H-D4: layout anchors');
    must(n.map(x => x.colour).join(' ') === 'rgba(254,172,53,1) rgba(80,112,221,1) rgba(63,190,149,1) rgba(197,130,89,1)', 'H-D4: colours');
    must(is(U('H-D4').labels[0].anchor.x, 65) && is(U('H-D4').labels[0].anchor.y, 229.50000000000009), 'H-D4: label a at (65, 229.50000000000009)');
    must(is(U('H-D4-iter1').nodes[3].y, 133.63020000000003) && is(U('H-D4-iter1').nodes[2].y, 1.98), 'H-D4-iter1: c 1.98, d 133.63020000000003');
    must(U('H-no-links').nodes.every(x => Number.isNaN(x.x) && Number.isNaN(x.dy)), 'H-no-links: NaN breadths and sizes');
    must(U('H-D4').labels.every(l => l.z2 === 12), 'H-D4: label z2 12');
    must(U('H-tiny-box').transform === null && U('H-tiny-box').elements.every(e => e.transform === null || e.kind === 'tspan'), 'H-tiny-box: no group transform');
    must(is(U('H-kx-negative').nodes[0].x, -0), 'H-kx-negative: x = -0');
    must(U('H-bg-alpha').labels[0].stroke === 'rgba(127.5,127.5,255,1)', 'H-bg-alpha: the halo');
    must(U('H-inside-unfilled').labels.every(l => l.insidePosition && !l.inside && l.fill === '#333' && l.stroke === 'rgba(255,255,255,1)'), 'H-inside-unfilled: outside colours on an unfilled rect');
    must(U('H-fmt-first').labels[0].text === 'a-{b} 3/{c} Ser', 'H-fmt-first: first occurrences only: ' + U('H-fmt-first').labels[0].text);
    must(U('H-id-name').labels.map(l => l.text).join() === 'I,b,2', 'H-id-name: I, b, 2');
    must(U('H-numeric-names').edges[0].source === 1 && U('H-numeric-names').edges[0].target === 2 && U('H-numeric-names').edges[1].source === 0, 'H-numeric-names: index vs key');
    must(U('H-missing-value-gradient').elements.some(e => e.fill && e.fill.canvas && Number.isNaN(e.bbox.y) && e.fill.canvas.y === 0 && e.fill.canvas.y2 === 0), 'H-missing-value-gradient: isSafeNum fallback (a NaN bbox y gives canvas y = y2 = 0)');
    const sx = nm => U('G-simple').nodes.find(x => x.id === nm);
    must(is(sx('a').y, 2.842170943040401e-14) && is(sx('b1').y, 193.75651816775618) && is(sx('a1').y, 102.30029075838291) && is(sx('c').y, 370.3002907583829), 'G-simple: anchors');
    must(U('G-energy').foreign > 0 && U('G-simple').foreign === 0, 'the gallery titles were left out');
  }
  // counts
  const counts = { cases: recs.length, gallery: 0, random: 0, nodes: 0, links: 0, rects: 0, labels: 0, tspans: 0, gradients: 0, stats: {} };
  for (const c of recs) {
    const u = c.rec.u;
    if (c.def.gallery) counts.gallery++;
    if (c.def.random) counts.random++;
    counts.nodes += u.nodes.length;
    counts.links += u.edges.length;
    counts.rects += u.elements.filter(e => e.kind === 'node').length;
    counts.tspans += u.elements.filter(e => e.kind === 'tspan').length;
    counts.labels += u.labels.length;
    counts.gradients += u.elements.filter(e => e.fill && typeof e.fill === 'object').length;
    for (const k of Object.keys(c.tr.stat)) counts.stats[k] = (counts.stats[k] || 0) + c.tr.stat[k];
  }
  counts.orients = { vertical: recs.filter(c => c.tr.resolved.orient === 'vertical').length };
  counts.stats.casesWithoutIterations = recs.filter(c => c.tr.resolved.iterations === 0 && c.rec.u.nodes.length).length;
  // guards
  const guards = GUARDS.map(([id, mutation, named]) => {
    let red = 0; const changed = []; const differs = [];
    for (const c of recs) {
      let b;
      try { b = flat(transcribedView(transcribe(c.fedSeries, c.env, id)), 's', {}); } catch (e) { b = { threw: String(e.message) }; }
      const df = diffFlat(c.flatUp, b);
      if (df.length) {
        red += df.length; changed.push(c.def.id);
        if (differs.length < 2 && (named.includes(c.def.id) || !named.length || differs.length < 1)) differs.push({ case: c.def.id, fields: df.slice(0, 3).map(x => ({ field: x.field, upstream: dec(x.upstream), mutated: dec(x.transcribed) })) });
      }
    }
    const missing = named.filter(x => !changed.includes(x));
    return { id, mutation, named, red, cases: changed.length, sample: changed.slice(0, 6), ok: red > 0 && !missing.length, ...(missing.length ? { namedNotRed: missing } : {}), differs };
  });
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version + ' (V8 ' + process.versions.v8 + ')',
    seed: SEED, tz: 'UTC',
    api: {
      update: "echarts.init(null, null, {renderer: 'svg', ssr: true, width: W, height: H}); setOption (animation false); zr.storage.getDisplayList(true); no animation frame is ever stepped",
      model: "sm.getGraph(): graph.nodes[i] {id, dataIndex, getValue(), getLayout() {value, depth, x, y, dx, dy, skNodeHeight}, getVisual('color'), outEdges, inEdges (after the in-place sort)}, graph.edges[i] {dataIndex, node1, node2, getValue(), getLayout() {dy, sy, ty}}; sm.getData('edge').getRawDataItem(i) located in the option's links; sm.layoutInfo",
      view: "chart.getViewOfSeriesModel(sm).group -> the one main group (its transform = the box origin or none); its children: SankeyPath (ecData dataType 'edge') then Rect (dataType 'node'); rect.getTextContent() (style.text, innerTransformable.x / y = the anchor, transform, z2, childrenRef() TSpans), rect._innerTextDefaultStyle {align, verticalAlign}, rect.textConfig {position, distance}, rect.canBeInsideText()",
      paint: "zr.storage.getDisplayList(true), restricted to the main group's elements and their label TSpans (a gallery title is another component)",
      gradient: "canvas / canvasGlobal: the dist's own createLinearGradient (with isSafeNum) run on el.getBoundingRect() with a recording ctx, then through el.transform",
      production: 'every hand-written and gallery case records identically through dist/echarts.min.js',
    },
    notes: [
      'REFUSED (not in the fixture; upstream throws, nothing is drawn): a duplicate node key (id ?? name ?? index; Graph.addNode refuses the second node and graph.update() then throws a TypeError) and any cycle or self loop (sankeyLayout: "Sankey is a DAG, the original data has cycle!"). A port must draw nothing for such a series.',
      'REFUSED keys (a case using them stops the run): a series zoom other than 1 or a center (the View transform moves the first frame), edgeLabel.show, label fontStyle / fontWeight / textBorder* / lineHeight / rich / padding / backgroundColor / offset / rotate / width / overflow, decal, and `sort` (absent from the 6.1.0 dist, a no-op there).',
      "Graph: nodes = data || nodes, links = edges || links (JS truthiness). Node key = '' + (id ?? name ?? index). A NUMBER source / target is an index into the node list; a string is a key; an unresolved link is dropped and does not consume an edge dataIndex (edges[].row keeps the option index).",
      'Values: node value = max(sum out, sum in, raw || 0), sums skip NaN in list order. Any node with value 0 sets iterations to 0. Depth = the Kahn layer (longest path from a source) unless item.depth >= 0; justify moves sinks without an explicit depth to maxDepth; right uses maxDepth - skNodeHeight (longest path to a sink) for nodes without an explicit depth; anything else is left.',
      'Layout: kx = (W - nodeWidth) / maxDepth (H in vertical), breadth = depth * kx; columns grouped by the breadth value (SameValueZero), keys sorted ascending; minKy = min over columns of (H - (n - 1) gap) / sum; initial pos = index in the column; resolveCollisions (stable in-place sort by pos, push down, then (y0 - gap) - H back pass); iterations of alpha *= 0.99, relax right-to-left (out-edges), collisions, relax left-to-right (in-edges), collisions; then out / in edges stably sorted by the other node top, sy / ty accumulate dy. All values LOCAL to the box; nothing rounded or clamped.',
      "Colour: a linear colour map of the node value over series.color ?? the global palette (array, a single string -> [string]); min == max -> the middle; unparseable entries -> black; [] -> undefined; channels Math.round, alpha unrounded; always 'rgba(r,g,b,a)'. An itemStyle.color on the chain (item -> level by layout depth -> series) wins verbatim.",
      "Links: lineStyle through the item-style key map (color -> fill, borderColor / borderWidth -> stroke / lineWidth, opacity default 0.2), chain item -> level of the SOURCE node's layout depth -> series. 'source' / 'target' take the node colour visual (undefined -> unfilled); 'gradient' becomes a LinearGradient(0, 0, 1, 0) (0, 0, 0, 1 vertical) from the source to the target colour only when both are strings, else the literal fill 'gradient'. Default fill '#86878c' (theme neutral50).",
      'Elements: per edge (graph.edges order) a SankeyPath M C L C Z, z2 0; per node a Rect, z2 10, shape (localX * W ?? x, localY * H ?? y, dx, dy, borderRadius || 0), fill = the colour visual; the main group translation (box x, y) is dropped when both |x| and |y| <= 5e-5; the label Text z2 = 12 (running max + 2). Paint order: stable by (zlevel, z, z2): links, rects, tspans.',
      "Labels: text = the chain formatter ({a} series name, {b} store name, {c} raw value ?? layout value; first occurrence of each only) else node.id; '\\n' splits lines. Host = the rect's path bbox grown by the stroke (lineWidth, max(lineWidth, 5) when unfilled) through the rect transform; calculateTextPosition with distance (default 5). Colours: label.color -> that fill, no stroke; an 'inside*' position on a FILLED rect -> #333 / #eee / #ccc by luminance (> 0.5 / > 0.2), stroke = the rect fill when (lum(textFill) < 0.4) == dark mode; anything else, including 'inside' on an UNFILLED rect (Path.canBeInsideText = hasFill) -> #333 (#ccc dark) with a 2px halo = the background blended over white (black in dark mode). Font 'normal normal <fontSize>px <fontFamily>' (label fontSize default 12, the global textStyle family). TSpans at x 0, y from the vertical alignment, lineHeight measure('\u56fd').",
      "Colours are upstream's literals: palette '#5070dd' .. '#3fbe95', link grey '#86878c', label ink '#333' / '#eee' / '#ccc', halo 'rgba(255,255,255,1)'. A theme-driven port must inject these, never compare theme colours against them.",
      "ref.js variant 13 ({a} in a formatter) carries a series name here: the auto name ('series', U+0000, '0') would put a NUL character in the fixture (fpjson drops it).",
      "Guards: ref.js's 'center' mutant (pos + size * 0.5) is not a guard: it is the same IEEE operation as pos + size / 2 and can never go red. 'unstable' (a tie in a column sort) and 'labelOrder' (a last-bit difference) survive the random set; H-guard-unstable and H-guard-labelOrder were found by a search.",
      'Not recorded: hover / emphasis / focus, edge labels, dragging, tooltip, zoom / center / roam, the animated clip of the first frame.',
    ],
    measure: measureRec,
    counts,
    cases: recs.map(c => ({
      id: c.def.id, note: c.def.note, gallery: c.def.gallery || null, option: c.def.gallery ? null : JSON.parse(c.optionText), animationForced: c.animationForced,
      W: c.W, H: c.H, random: c.def.random || null, palette: c.rec.palette, textStyle: c.rec.textStyle, ground: c.rec.ground, foreignElements: c.rec.u.foreign, series: [emitSeries(c)],
    })),
    guards,
  };
  const text = fmt(out, '') + '\n';
  if (text.includes('\\u0000')) { const i = text.indexOf('\\u0000'); must(false, 'the fixture holds a \\u0000: ' + text.slice(Math.max(0, i - 300), i + 50)); }
  console.error = quiet.error;
  console.warn = quiet.warn;
  guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.id + ': red ' + g.red + ' in ' + g.cases + ' cases' + (g.namedNotRed ? ' (named not red: ' + g.namedNotRed.join(', ') + ')' : '') + (process.env.GUARD_DEBUG ? ' ' + JSON.stringify(g.sample) + ' ' + JSON.stringify(g.differs) : '')));
  console.log(JSON.stringify(counts) + '; ' + checks + ' checks, 0 fails; ' + text.length + ' bytes; ' + logged.length + ' console messages from upstream'
    + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 3).join(' | ') : ''));
  const bad = guards.filter(g => !g.ok);
  if (bad.length) {
    console.log('FAILED: guards not red: ' + bad.map(g => g.id).join(', ') + '; the fixture was not written');
    exitCode = 1;
  } else {
    fs.writeFileSync(OUT, text);
    console.log('wrote', OUT);
  }
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  exitCode = 1;
}
if (require.main === module) process.exit(exitCode);

// Two of ref.js's mutants survive the random data: these cases were found by a search over the transcription
// (mutated vs not) and make them go red; the dist records them like any other case.
function GUARD_UNSTABLE() {
  return one({ data: [{ name: 'n0', value: 5 }, { name: 'n1' }, { name: 'n2', value: 5 }, { name: 'n3' }, { name: 'n4', value: 2 }, { name: 'n5', value: 5 }, { name: 'n6', value: 5 }], links: [{ source: 'n3', target: 'n1', value: 1 }], nodeGap: -30, layoutIterations: 1 });
}
function GUARD_LABEL_ORDER() {
  return one({ data: [{ name: 'n0' }, { name: 'n1', value: 5 }, { name: 'n2' }, { name: 'n3' }, { name: 'n4' }, { name: 'n5', value: 1 }, { name: 'n6', value: 5 }, { name: 'n7' }], links: [{ source: 'n3', target: 'n7', value: 17 }, { source: 'n3', target: 'n4', value: 14 }, { source: 'n2', target: 'n3', value: 20 }, { source: 'n0', target: 'n4', value: 1 }], nodeWidth: 27 });
}
