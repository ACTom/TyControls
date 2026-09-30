/*
Upstream's own answers for the TREEMAP series, first static frame (batch M1):
the data model, the layout, the colour visual, every rect, label and breadcrumb
item exactly as chart/treemap/TreemapSeries.ts (getInitialData: the virtual
root named after the series name, completeTreeValue -- byte-identical to
sunburst's --, setDefault putting the global palette on levels[0], the option
chain item -> levels[depth] -> designated -> series), treemapLayout.ts (the box,
squarify / initChildren / filterByThreshold / worst / position, childrenVisibleMin,
prunning), treemapVisual.ts (the colour by sorted, filtered child index, the
border colour), TreemapView.ts (group / background / content rects, the label,
findTarget), Breadcrumb.ts (item widths, collapse, polygon points,
positionElement), zrender Transformable (the 5e-5 needLocalTransform rule),
Element.updateInnerText + parseText (the label anchor, line drop, truncation)
and echarts util/graphic.ts traverseUpdateZ (the running-max label z2) build
them.

Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) at 800 x 600
with Math.random replaced by the port's xorshift32 (seed 2463534242, reset
before each chart) and process.env.TZ = 'UTC' set inside this script before
anything touches Date. EVERY case is rendered with `animation: false` (forced
on the gallery file, recorded as animationForced). After setOption it runs
zr.storage.getDisplayList(true) (transforms, label beforeUpdate,
updateInnerText, TSpan layout) and reads the live models, the view's element
storage and the display list. Every chart is disposed in a finally. The
hand-written cases are also recorded through dist/echarts.min.js and must record
identically.

  node tools/advchart-oracle/treemap.js

writes tests/fixtures/advchart-treemap.json (ORACLE_OUT overrides;
ORACLE_RANDOM=<n> sets the number of random forests, default below).

-----------------------------------------------------------------------------
Number encoding.
  hex    a double as its 16 hex digits, big-endian IEEE-754 bits (the Pascal
         side: StrToQWord('$' + s) moved into a Double). Every GEOMETRY value
         is written this way (layout, T, transforms, shapes, points, anchors,
         label boxes, crumb widths): JSON decimal parsing is not trusted to the
         last bit on the Pascal side.
  dec    a plain JSON number (shortest round-trip form), or one of the strings
         'NaN', 'Infinity', '-Infinity', '-0'. The *Text companions of hex
         fields are dec, for reading only.
A colour is a css string exactly as upstream holds it, or null (undefined).

Top level
  source, W, H, seed, tz ('UTC'), api {...}, notes[],
  measure   zrender's node width estimator (core/platform.ts): firstCode 32,
            lastCode 126, fontSize (12, for a font without 'px'), ratio[] (hex:
            the width of each char code at 1px), ratioText[], rule, samples[]
            ({text, font, width hex, widthText}: the estimator's own answers).
            Same table as advchart-grid-bounds.json's `ratios`: TZrSsrMeasurer
            .Create(measure.ratio, measure.firstCode).
  counts    totals over the fixture (cases, rows, elements, rects, tspans, crumbs,
            crumbTexts, labels, and coverage: truncatedLines, ellipsisLines,
            labelsLosingLines, invisibleRows, visibleMinCuts, localOffsetsDropped,
            collapsedCrumbs, fallbackRoot, ignoredLabels): minimums for the test
  cases[], guards[]

Per case
  id, note, gallery (the gallery file name or null), option (the exact JSON fed,
  animation false included; null for a gallery case: load
  examples/advchart/gallery/<gallery>.json and set animation false),
  animationForced, random (null, or {forest, variant, box}),
  palette   ecModel.option.color (the global palette setDefault copies; inject it
            as the option's `color` when the option names none)
  textStyle ecModel.option.textStyle (fontFamily 'Microsoft YaHei' here)
  ground    {background (zr.getBackgroundColor()), isDark}
  series[]  one per treemap series (every case has exactly one)

Per series
  seriesIndex, name (the option name or null)
  resolved  box {x, y, width, height} (hex) + boxText (dec); sortKeyPresent,
            sortValue (the fed value, null when absent or null), sortMode
            ('desc' | 'asc' | null: no sort, which also disables visibleMin);
            squareRatio (hex); leafDepth (always null in M1); visibleMin (the
            series value, dec); level0PaletteDefaulted (setDefault put the
            palette on levels[0]); levels (the level list AFTER setDefault)
  rows[]    every SeriesData row, dataIndex order = pre-order of
            {name: series.name, children: data} in the WRITTEN order (row 0 =
            the virtual root):
    index, name (store name: convertOptionIdName(name, '')), chainName (the
    chain name item -> levels[depth] -> series name as a string, or null: what
    a label shows without formatter and what a crumb shows ('' when null)),
    valueWritten (the fed item's value, absent when none), valueCompleted
    (after completeTreeValue; an array keeps its tail), value (node.getValue()),
    depth, height (leaf 1), parent (row or null), children (rows, WRITTEN
    order),
    layout    null (never laid out: visibleMin-removed, under a hidden or
              all-zero parent) or {x, y, width, height, area, borderWidth,
              upperHeight, upperLabelHeight (hex; LOCAL to the parent's
              origin), isLeafRoot, isInView, invisible, isAboveViewRoot
              (booleans, null when unset)} + layoutText (dec)
    viewChildren  rows in SORTED order after the visibleMin filter ([] when the
                  node was never squarified: TreeNode's initial value)
    filteredByVisibleMin  the children rows cut by visibleMin (sorted order)
    paletteIndex  k when the parent's colour list mapped list[k % n] to this
                  row, else null
    colour    null (not visited by the visual: no layout, invisible) or
              {source 'item' | 'level' | 'designated' | 'series' | 'none', value,
              mappedFrom (the parent row whose list mapped it, else null)}
    stroke    the border colour visual (visited rows) or null
    fill      the fill visual for a visited row WITHOUT viewChildren (null =
              undefined: the content rect draws no fill), else null
    T         null (no group, or a group with no transform) or [tx, ty] (hex):
              the accumulated group transform both rects carry; TText (dec)
    groupLocalDropped  true when the 5e-5 rule dropped a NON-ZERO local offset (exact
              zeros are dropped too, harmlessly: x + T = T; they read false)
    label     null (no content rect, or no label Text) or {rawText (null |
              string, before truncation), ignore, transform (6 hex or null),
              z2, width, height (hex: the label box after padding; null when
              ignored), padding (normalised [t, r, b, l]; the raw chain value
              when ignored), isTruncated, lines [the kept, truncated lines]}.
              A Text exists when the label shows in ANY state (setLabelStyle):
              label.show false on a level or a deep item still leaves an
              IGNORED Text (emphasis.label.show falls back to the series' label
              show), while on a depth-1 item with its own label it removes the
              Text (Series.fillDataTextStyle copies show into emphasis only for
              the top-level data items). An ignored Text is never painted but
              still takes a z2.
  elements[] zrender's display list for this series in PAINT order:
    kind 'bg' | 'content' | 'tspan' | 'crumb' | 'crumbText', row (the node's
    dataIndex; for crumbs the crumb's node), z, z2, zlevel, transform (6 hex or
    null), fill, stroke, lineWidth, lineJoin, opacity,
    bg / content: shape {x, y, width, height, r} (hex)
    crumb:        points [[x, y] hex]
    tspan / crumbText: text, x, y (hex), textAlign, textBaseline, font; a
                  tspan's host label (raw text, box, isTruncated, the kept
                  line count) is rows[row].label
  breadcrumb null (breadcrumb.show false) or
    target (row), targetRule ('findTarget' | 'fallbackRoot'), availableWidth
    (hex), height, emptyItemWidth, totalWidth (hex, before collapse),
    items[] root first: {row, text (the chain name), measuredWidth (hex,
      '12px sans-serif' unless breadcrumb.itemStyle.textStyle sets a font),
      itemWidth (hex, after collapse), collapsed, head, tail, points (hex),
      bbox {x, y, width, height} (hex), label ({x, y} hex, or null when the
      crumb has no text)}
    unionRect {x, y, width, height} (hex), groupX, groupY (hex) + groupText (dec)
  labelStats {tspans, truncated, ellipsis, dropped}

Guards[] one per mutation of the transcription (ref.js's mutants): id,
  mutation, red (the number of recorded checks the mutated transcription gets
  wrong over the whole fixture), cases (how many cases change), sample (the
  first few), ok (red > 0). ref.js's `lt` mutant ('<=' -> '<' in the squarify
  row loop) is NOT a guard: it never terminates (Infinity < Infinity is false
  on a zero-area row, the same child is retried forever).

-----------------------------------------------------------------------------
The transcription (a port of the wf76 ref.js re-implementation) takes as INPUTS
only the series option as fed, the canvas size, the global palette and the
global textStyle font family, and must reproduce EVERY recorded row, element and
breadcrumb field bit for bit (Object.is); any difference stops the run and
nothing is written.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-treemap.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');

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
function zrMerge(target, source, overwrite) {
  if (!isObject(source) || !isObject(target)) return overwrite ? zrClone(source) : target;
  for (const key in source) {
    if (hasOwn(source, key) && key !== '__proto__') {
      const t = target[key];
      const s = source[key];
      if (isObject(s) && isObject(t) && !isArray(s) && !isArray(t)) zrMerge(t, s, overwrite);
      else if (overwrite || !(key in target)) target[key] = zrClone(s);
    }
  }
  return target;
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
// platform.ts measureText without a canvas: px from the font ('12' without px), mono = px * length,
// else the sum over UTF-16 units of ratio * px (codes 32..126) or px (anything else)
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
function charW(font, code) { return code >= 0 && code <= 127 ? measure(String.fromCharCode(code), font) : measure('\u56fd', font); }
// the estimator in use is this one: every char at 1px, and sample strings through a zrender Text
function checkMeasurer() {
  RATIO.forEach((r, i) => {
    const w = new echarts.graphic.Text({ style: { text: String.fromCharCode(FIRST_CODE + i), font: '1px sans-serif' } }).getBoundingRect().width;
    must(Object.is(w, r), 'char code ' + (FIRST_CODE + i) + ': the table says ' + r + ', a 1px Text measures ' + w);
  });
  const samples = [];
  for (const font of ['12px sans-serif', 'normal normal 12px Microsoft YaHei', 'normal normal 14px Microsoft YaHei']) {
    for (const t of ['a', '...', '\u56fd', 'nodeB', 'Elephant', 'LongNameAbcdefghijk', '\u4e2d\u6587', 'x y', 'W', 'A rather long series name for crumbs']) {
      const w = new echarts.graphic.Text({ style: { text: t, font } }).getBoundingRect().width;
      must(Object.is(w, measure(t, font)), JSON.stringify(t) + ' @ ' + font + ': a Text measures ' + w + ', the rule ' + measure(t, font));
      samples.push({ text: t, font, width: hex(w), widthText: dec(w) });
    }
  }
  return {
    firstCode: FIRST_CODE, lastCode: LAST_CODE, fontSize: DEFAULT_FONT_SIZE, ratio: RATIO.map(hex), ratioText: RATIO.map(dec),
    rule: "px = the number before 'px' in the font (else 12); a font containing 'mono' measures px * length; otherwise the sum, over UTF-16 units left to right, of ratio[code - 32] * px for codes 32..126 and px for any other unit. A label's line height is measure('\u56fd') = px. Upstream measures the breadcrumb text in '12px sans-serif' (zrender DEFAULT_FONT) but draws it in the chart font.",
    samples,
  };
}

// ============================================================================
// The transcription (ref.js, extended to every recorded field; mutants as switches)
// ============================================================================
const TM_DEFAULTS = {
  left: 20, top: 50, right: 20, bottom: 50, sort: true, squareRatio: 0.5 * (1 + Math.sqrt(5)), leafDepth: null, drillDownIcon: '\u25b6',
  breadcrumb: { show: true, height: 22, left: 'center', bottom: 15, emptyItemWidth: 25, itemStyle: { color: '#e8ebf0', textStyle: { color: '#54555a' } }, emphasis: { itemStyle: { color: '#f4f7fd' } } },
  label: { show: true, distance: 0, padding: 5, position: 'inside', color: '#fff', overflow: 'truncate' },
  upperLabel: { show: false, position: [0, '50%'], height: 20, overflow: 'truncate', verticalAlign: 'middle' },
  itemStyle: { color: null, colorAlpha: null, colorSaturation: null, borderWidth: 0, gapWidth: 0, borderColor: '#fff', borderColorSaturation: null },
  visualDimension: 0, visualMin: null, visualMax: null, color: [], colorAlpha: null, colorSaturation: null, colorMappingBy: 'index',
  visibleMin: 10, childrenVisibleMin: null, levels: [],
};
// the merged keys the transcription reads (checked against upstream's own merged option)
const READ_KEYS = ['sort', 'squareRatio', 'leafDepth', 'breadcrumb', 'label', 'upperLabel', 'itemStyle', 'color', 'visibleMin', 'childrenVisibleMin', 'colorMappingBy', 'name'];

function parsePct(v, base) {                         // util/number.ts parsePercent (layout flavour)
  if (v === 'center' || v === 'middle') v = '50%';
  else if (v === 'left' || v === 'top') v = '0%';
  else if (v === 'right' || v === 'bottom') v = '100%';
  if (typeof v === 'string') return /%$/.test(v.trim()) ? parseFloat(v) / 100 * base + 0 : parseFloat(v);
  return v == null ? NaN : +v;
}
function layoutRect(p, cw, ch) {                     // util/layout.ts getLayoutRect, margin 0, no aspect
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
function mergeBox(user) {                            // util/layout.ts mergeLayoutParam, layoutMode 'box'
  const def = { left: 20, right: 20, top: 50, bottom: 50 };
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
function completeTreeValue(n) {                      // TreemapSeries.ts completeTreeValue (post-order, mutates)
  let sum = 0;
  for (const c of (n.children || [])) { completeTreeValue(c); let cv = c.value; if (isArray(cv)) cv = cv[0]; sum += cv; }
  let v = n.value; if (isArray(v)) v = v[0];
  if (v == null || isNaN(v)) v = sum;
  if (v < 0) v = 0;
  isArray(n.value) ? n.value[0] = v : n.value = v;
}
function formatTpl(tpl, params) {                    // util/format.ts formatTpl, one series, first occurrence only
  const vars = ['seriesName', 'name', 'value'];
  const alias = ['a', 'b', 'c'];
  for (let i = 0; i < 3; i++) tpl = tpl.replace('{' + alias[i] + '}', '{' + alias[i] + '0}');
  for (let k = 0; k < 3; k++) tpl = tpl.replace('{' + alias[k] + '0}', params[vars[k]]);
  return tpl;
}
const EPS = 5e-5;
const around0 = v => !(v > EPS || v < -EPS);

// so: the series option as fed; env: {W, H, palette, fontFamily}; mut: a mutant name or null
function transcribe(soIn, env, mut) {
  const M = k => mut === k;
  const so = zrClone(soIn);
  const S = zrMerge(zrClone(so), TM_DEFAULTS, false);
  const seriesName = so.name == null ? 'series\u00000' : String(so.name);
  const root = { name: so.name, children: S.data };
  completeTreeValue(root);
  // setDefault (TreemapSeries.ts): the global palette on levels[0] unless ANY level defines a colour
  const levels = S.levels || [];
  let hasColor = false;
  for (const l of levels) {
    const mc = pathGet(l, ['color']);
    if (pathGet(l, ['itemStyle', 'color']) || (mc && mc !== 'none')) hasColor = true;
  }
  if (!levels[0]) levels[0] = {};
  const level0PaletteDefaulted = !hasColor && !M('nodefault');
  if (level0PaletteDefaulted) levels[0].color = env.palette.slice();
  // rows: pre-order over the written order
  const rows = [];
  (function walk(item, parent, depth) {
    const n = { item, parent, depth, idx: rows.length, children: [] };
    rows.push(n);
    for (const c of (item.children || [])) n.children.push(walk(c, n, depth + 1));
    n.height = 1 + n.children.reduce((m, c) => Math.max(m, c.height), 0);
    return n;
  })(root, null, 0);
  const designated = {};
  function get(n, p) {                               // item -> levels[depth] -> designated -> series
    let v = pathGet(n.item, p); if (v != null) return v;
    const lv = levels[n.depth];
    if (lv) { v = pathGet(lv, p); if (v != null) return v; }
    v = pathGet({ itemStyle: designated }, p); if (v != null) return v;
    return pathGet(S, p);
  }
  const val = n => { const v = n.item.value; return isArray(v) ? v[0] : v; };
  const storeName = n => (n.item.name == null ? '' : String(n.item.name));
  const chainName = n => { const v = get(n, ['name']); return v == null ? null : String(v); };

  // ---- box
  const boxParams = mergeBox(so);
  const box = layoutRect(boxParams, env.W, env.H);
  // ---- sort
  let sort = S.sort;
  if (sort && sort !== 'asc' && sort !== 'desc') sort = 'desc';
  if (M('sortfalse') && (sort === false || sort == null || sort === 0 || sort === '')) sort = 'desc';
  const orderByOf = () => (sort === 'asc' || sort === 'desc' ? sort : null);
  const squareRatio = S.squareRatio;
  const leafDepth = S.leafDepth;
  rows[0].layout = { x: 0, y: 0, width: box.width, height: box.height, area: box.width * box.height };
  function worst(row, rfl, ratio) {
    let areaMax = 0; let areaMin = Infinity;
    for (const c of row) { const a = c.layout.area; if (a) { a < areaMin && (areaMin = a); a > areaMax && (areaMax = a); } }
    const sq = row.area * row.area;
    const f = M('f') ? rfl * (rfl * ratio) : rfl * rfl * ratio;
    return sq ? Math.max((f * areaMax) / sq, sq / (f * areaMin)) : Infinity;
  }
  function position(row, rfl, rect, hg, flush) {
    const h = M('side') ? (rfl === rect.height ? 1 : 0) : (rfl === rect.width ? 0 : 1);
    const xy = ['x', 'y']; const wh = ['width', 'height'];
    const i1 = 1 - h;
    let last = rect[xy[h]];
    let rol = rfl ? row.area / rfl : 0;
    if (flush || rol > rect[wh[i1]]) rol = rect[wh[i1]];
    for (let i = 0; i < row.length; i++) {
      const n = row[i];
      const step = rol ? n.layout.area / rol : 0;
      const lay = {};
      const wh1 = lay[wh[i1]] = Math.max(rol - 2 * hg, 0);
      const remain = M('remain') ? rect[xy[h]] + (rect[wh[h]] - last) : rect[xy[h]] + rect[wh[h]] - last;
      const mod = M('last') ? (remain < step ? remain : step) : ((i === row.length - 1 || remain < step) ? remain : step);
      const wh0 = lay[wh[h]] = Math.max(mod - 2 * hg, 0);
      lay[xy[i1]] = rect[xy[i1]] + Math.min(hg, wh1 / 2);
      lay[xy[h]] = last + Math.min(hg, wh0 / 2);
      last += mod;
      Object.assign(n.layout, lay);
    }
    rect[xy[i1]] += rol;
    rect[wh[i1]] -= rol;
  }
  function initChildren(n, totalArea, hideChildren, depth) {
    const orderBy = orderByOf();
    const over = leafDepth != null && leafDepth <= depth;
    if (hideChildren && !over) return (n.viewChildren = []);
    const vc = n.children.slice();
    if (orderBy) {
      vc.sort((a, b) => {
        const d = orderBy === 'asc' ? val(a) - val(b) : val(b) - val(a);
        return d === 0 ? (orderBy === 'asc' ? a.idx - b.idx : (M('tie') ? a.idx - b.idx : b.idx - a.idx)) : d;
      });
    }
    let sum = 0; for (const c of vc) sum += val(c);
    if (sum === 0) return (n.viewChildren = []);
    if (orderBy && !M('novismin')) {
      const vm = get(n, ['visibleMin']);
      const len = vc.length; let del = len;
      for (let i = len - 1; i >= 0; i--) {
        const v = val(vc[orderBy === 'asc' ? len - i - 1 : i]);
        if (v / sum * totalArea < vm) { del = i; if (!M('sumfix')) sum -= v; }
      }
      const cut = orderBy === 'asc' ? vc.splice(0, len - del) : vc.splice(del, len - del);
      n.filtered = cut.map(c => c.idx);
    }
    if (sum === 0) return (n.viewChildren = []);
    for (const c of vc) c.layout = { area: M('area') ? totalArea * val(c) / sum : val(c) / sum * totalArea };
    if (over) { if (vc.length) n.layout.isLeafRoot = true; vc.length = 0; }
    n.viewChildren = vc;
    return vc;
  }
  function squarify(n, hideChildren, depth) {
    let width = n.layout.width; let height = n.layout.height;
    const bw = get(n, ['itemStyle', 'borderWidth']);
    const hg = get(n, ['itemStyle', 'gapWidth']) / 2;
    const ulh = get(n, ['upperLabel', 'show']) ? get(n, ['upperLabel', 'height']) : 0;
    const uh = Math.max(bw, ulh);
    const lo = bw - hg; const lou = uh - hg;
    Object.assign(n.layout, { borderWidth: bw, upperHeight: uh, upperLabelHeight: ulh });
    width = Math.max(width - 2 * lo, 0);
    height = M('height') ? Math.max(height - (lo + lou), 0) : Math.max(height - lo - lou, 0);
    const totalArea = width * height;
    const vc = initChildren(n, totalArea, hideChildren, depth);
    if (!vc.length) return;
    const rect = { x: lo, y: lou, width, height };
    let rfl = Math.min(width, height);
    let best = Infinity;
    const row = []; row.area = 0;
    for (let i = 0; i < vc.length;) {
      const c = vc[i];
      row.push(c); row.area += c.layout.area;
      const score = worst(row, rfl, squareRatio);
      if (score <= best) { i++; best = score; } else {
        if (M('recompute')) { row.pop(); row.area = row.reduce((s, r) => s + r.layout.area, 0); } else row.area -= row.pop().layout.area;
        position(row, rfl, rect, hg, false);
        rfl = Math.min(rect.width, rect.height);
        row.length = row.area = 0; best = Infinity;
      }
    }
    if (row.length) position(row, rfl, rect, hg, true);
    if (!hideChildren) { const cvm = get(n, ['childrenVisibleMin']); if (cvm != null && totalArea < cvm) hideChildren = true; }
    for (const c of vc) squarify(c, hideChildren, depth + 1);
  }
  squarify(rows[0], false, 0);
  // prunning (first frame: view root = tree root at (0, 0), viewAbovePath empty)
  function intersects(a, b) {                        // zrender BoundingRect.intersect (no mtv)
    const ax0 = a.x; const ax1 = a.x + a.width; const ay0 = a.y; const ay1 = a.y + a.height;
    const nb = { x: b.x, y: b.y, width: b.width, height: b.height };
    if (nb.width < 0) { nb.x += nb.width; nb.width = -nb.width; }
    if (nb.height < 0) { nb.y += nb.height; nb.height = -nb.height; }
    const bx0 = nb.x; const bx1 = nb.x + nb.width; const by0 = nb.y; const by1 = nb.y + nb.height;
    if (ax0 > ax1 || ay0 > ay1 || bx0 > bx1 || by0 > by1) return false;
    return !(ax1 < bx0 || bx1 < ax0 || ay1 < by0 || by1 < ay0);
  }
  (function prune(n, clip) {
    n.layout.isInView = true;
    n.layout.invisible = !intersects(clip, n.layout);
    const cc = { x: clip.x - n.layout.x, y: clip.y - n.layout.y, width: clip.width, height: clip.height };
    for (const c of (n.viewChildren || [])) prune(c, cc);
  })(rows[0], { x: -box.x, y: -box.y, width: env.W, height: env.H });

  // ---- visual (treemapVisual.ts travelTree)
  const calcColor = v => { const c = v.color; return (c != null && c !== 'none') ? c : undefined; };
  (function travel(n, dv, mappedFrom, k) {
    if (!n.layout || n.layout.invisible || !n.layout.isInView) return;
    const visuals = Object.assign({}, dv);
    let source = 'none';
    for (const key of ['color', 'colorAlpha', 'colorSaturation']) {
      designated[key] = dv[key];
      const v = get(n, ['itemStyle', key]);
      designated[key] = null;
      v != null && (visuals[key] = v);
    }
    if (pathGet(n.item, ['itemStyle', 'color']) != null) source = 'item';
    else if (levels[n.depth] && pathGet(levels[n.depth], ['itemStyle', 'color']) != null) source = 'level';
    else if (dv.color != null) source = 'designated';
    else if (pathGet(S, ['itemStyle', 'color']) != null) source = 'series';
    n.colour = { source, value: visuals.color == null ? null : visuals.color, mappedFrom: source === 'designated' ? mappedFrom : null };
    n.paletteIndex = mappedFrom != null ? k : null;
    n.stroke = get(n, ['itemStyle', 'borderColor']);
    n.visited = true;
    const vc = n.viewChildren;
    if (!vc || !vc.length) { n.fill = calcColor(visuals); return; }
    const range = get(n, ['color']);
    const mapping = (isArray(range) && range.length) ? range : null;
    vc.forEach((c, i) => {
      const cv = Object.assign({}, M('inherit') ? dv : visuals);
      if (mapping) cv.color = mapping[(M('index') ? c.idx : i) % mapping.length];
      travel(c, cv, mapping ? n.idx : null, mapping ? i : null);
    });
  })(rows[0], {}, null, null);
  // a designated colour inherited (not mapped here) keeps mappedFrom null

  // ---- elements (traversal order), then a stable sort by (zlevel, z, z2)
  const els = [];
  let maxZ2 = -Infinity;
  const family = env.fontFamily;
  function composeT(parent, x, y) {                 // zrender Transformable.updateTransform, translate only
    const need = M('eps') ? true : !(around0(x) && around0(y));
    if (!need) return { T: parent ? parent.slice() : null, dropped: true };
    if (!parent) return { T: [0 + (0 + x), 0 + (0 + y)], dropped: false };
    return { T: [x + parent[0], y + parent[1]], dropped: false };
  }
  const m6T = T => (T ? [1, 0, 0, 1, T[0], T[1]] : null);
  const stat = { tspans: 0, truncated: 0, ellipsis: 0, dropped: 0 };
  function labelLines(text, cw, ch, font, padding) {
    const width = Math.max(cw - padding[1] - padding[3], 0);
    const height = Math.max(ch - padding[0] - padding[2], 0);
    let lines = text ? text.split('\n') : [];
    const lh = measure('\u56fd', font);
    let contentHeight = lines.length * lh;
    let isTruncated = false;
    if (contentHeight > height && !M('nolinedrop')) {
      const lc = Math.floor(height / lh);
      isTruncated = isTruncated || lines.length > lc;
      if (lines.length > lc) stat.dropped++;
      lines = lines.slice(0, lc);
      contentHeight = lines.length * lh;
    }
    if (text) {
      const containerWidth = Math.max(0, width - 1);
      let contentWidth = containerWidth;
      const asc = measure('a', font);
      for (let i = 0; i < (M('minchar') ? 0 : 2) && contentWidth >= asc; i++) contentWidth -= asc;
      let ell = '...'; let ellW = measure('...', font);
      if (ellW > contentWidth) { ell = ''; ellW = 0; }
      contentWidth = containerWidth - ellW;
      lines = lines.map(line => {
        if (!containerWidth) return '';
        let lw = measure(line, font);
        if (lw <= containerWidth) return line;
        for (let j = 0; ; j++) {
          if (lw <= contentWidth || j >= 2) { line += ell; break; }
          let sub;
          if (j === 0) { let w = 0; let i = 0; for (const len = line.length; i < len && w < contentWidth; i++) w += charW(font, line.charCodeAt(i)); sub = i; } else sub = lw > 0 ? Math.floor(line.length * contentWidth / lw) : 0;
          line = line.substr(0, sub); lw = measure(line, font);
        }
        isTruncated = true;
        stat.truncated++;
        if (ell) stat.ellipsis++;
        return line;
      });
    }
    return { lines, lh, contentHeight, width, height, isTruncated };
  }
  (function render(n, parentT, depth) {
    if (!n.layout || !n.layout.isInView) return;
    if (n.layout.invisible) return;                  // giveGraphic creates nothing: no group, no subtree
    const ct = composeT(parentT, n.layout.x || 0, n.layout.y || 0);
    const T = ct.T;
    n.T = T;
    n.groupLocalDropped = ct.dropped && !((n.layout.x || 0) === 0 && (n.layout.y || 0) === 0);
    const w = n.layout.width; const h = n.layout.height; const bw = n.layout.borderWidth;
    const r = get(n, ['itemStyle', 'borderRadius']) || 0;
    const isParent = n.viewChildren && n.viewChildren.length;
    const z2bg = depth * 100 + 20;
    els.push({ kind: 'bg', row: n.idx, z: 0, z2: z2bg, zlevel: 0, transform: m6T(T), fill: n.stroke, stroke: null, lineWidth: null, lineJoin: null, opacity: 1, shape: { x: 0, y: 0, width: w, height: h, r } });
    maxZ2 = Math.max(z2bg, maxZ2);
    n.label = null;
    if (!isParent) {
      const cw = Math.max(w - 2 * bw, 0); const ch = Math.max(h - 2 * bw, 0);
      const z2c = depth * 100 + 30;
      els.push({ kind: 'content', row: n.idx, z: 0, z2: z2c, zlevel: 0, transform: m6T(T), fill: n.fill === undefined ? null : n.fill, stroke: null, lineWidth: null, lineJoin: null, opacity: 1, shape: { x: bw, y: bw, width: cw, height: ch, r } });
      maxZ2 = Math.max(z2c, maxZ2);
      // setLabelStyle: a Text exists when the label shows in ANY state; the emphasis show falls back to the
      // normal show only on a depth-1 item with a label (Series.fillDataTextStyle) and on the series itself
      const showNormal = !!get(n, ['label', 'show']);
      const emphShow = (() => {
        const it = n.item;
        if (n.depth === 1 && it.label && typeof it.label === 'object') {
          const e = pathGet(it, ['emphasis', 'label']);
          if (!(e && hasOwn(e, 'show')) && hasOwn(it.label, 'show')) { if (it.label.show != null) return it.label.show; }
        }
        let v = pathGet(it, ['emphasis', 'label', 'show']); if (v != null) return v;
        if (levels[n.depth]) { v = pathGet(levels[n.depth], ['emphasis', 'label', 'show']); if (v != null) return v; }
        const se = pathGet(so, ['emphasis', 'label']);
        return se && hasOwn(se, 'show') ? se.show : S.label.show;
      })();
      const anyShow = showNormal || !!emphShow || !!get(n, ['blur', 'label', 'show']) || !!get(n, ['select', 'label', 'show']);
      if (anyShow && !showNormal) {
        const fmt0 = get(n, ['label', 'formatter']);
        const t0 = typeof fmt0 === 'string' ? formatTpl(fmt0, { seriesName, name: storeName(n), value: n.item.value }) : null;
        n.label = { rawText: t0, ignore: true, transform: null, z2: M('z2') ? z2c + 2 : maxZ2 + 2, width: null, height: null, padding: json(get(n, ['label', 'padding'])), isTruncated: false, lines: [] };
      }
      if (showNormal) {
        const fmt = get(n, ['label', 'formatter']);
        let text = typeof fmt === 'string' ? formatTpl(fmt, { seriesName, name: storeName(n), value: n.item.value }) : undefined;
        if (text == null) text = chainName(n);
        const fsz = get(n, ['label', 'fontSize']) || 12;
        const font = 'normal normal ' + fsz + 'px ' + family;
        const tx = T ? T[0] : 0; const ty = T ? T[1] : 0;
        const rx = M('ordx') ? bw + (tx + cw / 2) : (bw * 1 + tx) + cw / 2;
        const ry = (bw * 1 + ty) + ch / 2;
        const LT = composeT(null, rx, ry).T;
        let pad = get(n, ['label', 'padding']);
        pad = isArray(pad) ? (pad.length === 2 ? [pad[0], pad[1], pad[0], pad[1]] : pad.length === 3 ? [pad[0], pad[1], pad[2], pad[1]] : pad) : [pad, pad, pad, pad];
        const L = labelLines(text, cw, ch, font, pad);
        const z2l = M('z2') ? z2c + 2 : maxZ2 + 2;
        n.label = { rawText: text == null ? null : text, ignore: false, transform: m6T(LT), z2: z2l, width: L.width, height: L.height, padding: pad, isTruncated: L.isTruncated, lines: L.lines.slice() };
        let y = 0 - L.contentHeight / 2 + L.lh / 2;
        const fill = get(n, ['label', 'color']);
        for (const line of L.lines) {
          els.push({ kind: 'tspan', row: n.idx, z: 0, z2: z2l, zlevel: 0, transform: m6T(LT), fill, stroke: null, lineWidth: 1, lineJoin: null, opacity: 1, text: line, x: 0 + pad[3] / 2 - pad[1] / 2, y, textAlign: 'center', textBaseline: 'middle', font });
          stat.tspans++;
          y += L.lh;
        }
      }
    }
    for (const c of (n.viewChildren || [])) render(c, T, depth + 1);
  })(rows[0], composeT(null, box.x, box.y).T, 0);

  // ---- breadcrumb (TreemapView._renderBreadcrumb + Breadcrumb.ts)
  const bc = S.breadcrumb;
  let crumb = null;
  if (bc.show) {
    let target; let targetRule = 'findTarget';
    const px = env.W / 2; const py = env.H / 2;
    (function find(n) {
      if (!n.layout || n.layout.invisible) return;  // no background element: nothing below it has one either
      const qx = M('global') ? px - (n.T ? n.T[0] : 0) : px; const qy = M('global') ? py - (n.T ? n.T[1] : 0) : py;
      if (0 <= qx && qx <= 0 + n.layout.width && 0 <= qy && qy <= 0 + n.layout.height) { target = n; for (const c of (n.viewChildren || [])) find(c); }
    })(rows[0]);
    if (!target) { target = rows[0]; targetRule = 'fallbackRoot'; }
    const tsFont = pathGet(bc, ['itemStyle', 'textStyle', 'fontSize']) != null ? pathGet(bc, ['itemStyle', 'textStyle', 'fontSize']) + 'px sans-serif' : '12px sans-serif';
    const list = [];
    let total = 0;
    for (let n = target; n; n = n.parent) {
      const nm = get(n, ['name']);
      const text = nm == null ? '' : String(nm);
      const tw = text ? Math.max(...text.split('\n').map(l => measure(l, tsFont))) : 0;
      const iw = Math.max(tw + 8 * 2, bc.emptyItemWidth);
      total += iw + 8;
      list.push({ n, text, tw, width: iw });
    }
    const totalWidth = total;
    const avail = layoutRect({ left: bc.left, right: bc.right, top: bc.top, bottom: bc.bottom }, env.W, env.H);
    let lastX = 0; const items = [];
    for (let i = list.length - 1; i >= 0; i--) {
      let iw = list[i].width; let text = list[i].text; let collapsed = false;
      if (total > avail.width) { total -= iw - bc.emptyItemWidth; iw = bc.emptyItemWidth; text = null; collapsed = true; }
      const head = i === list.length - 1; const tail = i === 0; const x = lastX; const y = 0; const hh = bc.height;
      const pts = [[head ? x : x - 5, y], [x + iw, y], [x + iw, y + hh], [head ? x : x - 5, y + hh]];
      !tail && pts.splice(2, 0, [x + iw + 5, y + hh / 2]);
      !head && pts.push([x, y + hh / 2]);
      items.push({ row: list[i].n.idx, text, chainText: list[i].text, measuredWidth: list[i].tw, itemWidth: iw, collapsed, head, tail, points: pts });
      lastX += iw + 8;
    }
    let R = null;
    for (const p of items) {
      let x0 = Infinity; let y0 = Infinity; let x1 = -Infinity; let y1 = -Infinity;
      for (const [qx, qy] of p.points) { x0 = Math.min(x0, qx); y0 = Math.min(y0, qy); x1 = Math.max(x1, qx); y1 = Math.max(y1, qy); }
      p.bbox = { x: x0 * 1 + 0, y: y0 * 1 + 0, width: (x1 - x0) * 1, height: (y1 - y0) * 1 };
      if (!R) R = Object.assign({}, p.bbox);
      const ux = Math.min(p.bbox.x, R.x); const uy = Math.min(p.bbox.y, R.y);
      R.width = M('union') ? Math.max(x1, R.x + R.width) - ux : Math.max(p.bbox.x + p.bbox.width, R.x + R.width) - ux;
      R.height = Math.max(p.bbox.y + p.bbox.height, R.y + R.height) - uy;
      R.x = ux; R.y = uy;
    }
    const pos = layoutRect({ width: R.width, height: R.height, left: bc.left, right: bc.right, top: bc.top, bottom: bc.bottom }, env.W, env.H);
    const gx = 0 + (pos.x - R.x); const gy = 0 + (pos.y - R.y);
    const GT = composeT(null, gx, gy).T;
    const crumbFill = pathGet(bc, ['itemStyle', 'color']);
    const inkFill = pathGet(bc, ['itemStyle', 'textStyle', 'color']);
    const crumbFont = 'normal normal ' + (pathGet(bc, ['itemStyle', 'textStyle', 'fontSize']) || 12) + 'px ' + family;
    for (const p of items) {
      els.push({ kind: 'crumb', row: p.row, z: 0, z2: 100000, zlevel: 0, transform: m6T(GT), fill: crumbFill, stroke: null, lineWidth: 1, lineJoin: 'bevel', opacity: 1, points: p.points });
      p.label = null;
      if (p.text) {
        const tx = (p.bbox.x * 1 + (GT ? GT[0] : 0)) + p.bbox.width / 2;
        const ty = (p.bbox.y * 1 + (GT ? GT[1] : 0)) + p.bbox.height / 2;
        p.label = { x: tx, y: ty };
        const lines = p.text.split('\n');
        const lh = measure('\u56fd', crumbFont);
        let y = 0 - lines.length * lh / 2 + lh / 2;
        const LT = m6T(composeT(null, tx, ty).T);
        for (const line of lines) {
          els.push({ kind: 'crumbText', row: p.row, z: 0, z2: 100002, zlevel: 0, transform: LT, fill: inkFill, stroke: null, lineWidth: 1, lineJoin: null, opacity: 1, text: line, x: 0, y, textAlign: 'center', textBaseline: 'middle', font: crumbFont });
          y += lh;
        }
      }
    }
    crumb = { target: target.idx, targetRule, availableWidth: avail.width, height: bc.height, emptyItemWidth: bc.emptyItemWidth, totalWidth, items, unionRect: R, groupX: gx, groupY: gy };
  }
  const elements = els.map((e, i) => [e, i]).sort((a, b) => (a[0].zlevel - b[0].zlevel) || (a[0].z - b[0].z) || (a[0].z2 - b[0].z2) || (a[1] - b[1])).map(a => a[0]);

  const sortPresent = hasOwn(so, 'sort');
  return {
    resolved: {
      box, sortKeyPresent: sortPresent, sortValue: sortPresent ? json(so.sort) : null, sortMode: orderByOf(), squareRatio, leafDepth: leafDepth == null ? null : leafDepth,
      visibleMin: S.visibleMin, level0PaletteDefaulted, levels: zrClone(levels),
    },
    rows: rows.map(n => ({
      index: n.idx, name: storeName(n), chainName: chainName(n), valueCompleted: zrClone(n.item.value), value: val(n), depth: n.depth, height: n.height,
      parent: n.parent ? n.parent.idx : null, children: n.children.map(c => c.idx),
      layout: n.layout ? layoutOf(n.layout) : null,
      viewChildren: n.viewChildren ? n.viewChildren.map(c => c.idx) : [],
      filteredByVisibleMin: n.filtered || [],
      paletteIndex: n.visited ? n.paletteIndex : null,
      colour: n.visited ? n.colour : null,
      stroke: n.visited ? n.stroke : null,
      fill: n.visited && !(n.viewChildren && n.viewChildren.length) ? (n.fill === undefined ? null : n.fill) : null,
      T: n.T || null, groupLocalDropped: !!n.groupLocalDropped,
      label: n.label || null,
    })),
    elements,
    breadcrumb: crumb,
    labelStats: stat,
  };
}
function layoutOf(L) {
  const o = {};
  for (const k of ['x', 'y', 'width', 'height', 'area', 'borderWidth', 'upperHeight', 'upperLabelHeight']) o[k] = L[k] === undefined ? null : L[k];
  for (const k of ['isLeafRoot', 'isInView', 'invisible', 'isAboveViewRoot']) o[k] = L[k] === undefined ? null : L[k];
  return o;
}

// ============================================================================
// Reading upstream
// ============================================================================
function ecInner(el, key) { for (const k of Object.keys(el)) if (k.indexOf('__ec_inner_') === 0 && el[k] && key in el[k]) return el[k]; return null; }
function runChart(E, option, fn) {
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
function styleOf(el) {
  const s = el.style;
  const g = k => (s[k] === undefined ? null : s[k]);
  return { fill: g('fill'), stroke: g('stroke'), lineWidth: g('lineWidth'), lineJoin: g('lineJoin'), opacity: g('opacity') };
}
function readTreemap(chart, fedSeries) {
  const ec = chart.getModel();
  const zr = chart.getZr();
  const list = zr.storage.getDisplayList(true);
  const sm = ec.getSeriesByIndex(0);
  must(sm && sm.subType === 'treemap', 'series 0 is not a treemap');
  const view = chart.getViewOfSeriesModel(sm);
  const data = sm.getData();
  const tree = data.tree;
  const store = view._storage;
  // the fed values, pre-order over the written order
  const written = [];
  (function walk(item) { written.push(item); for (const c of (item.children || [])) walk(c); })({ name: fedSeries.name, children: fedSeries.data || [] });
  must(written.length === data.count(), 'row count ' + data.count() + ' vs ' + written.length + ' fed nodes');
  const kindOf = new Map();
  const rows = [];
  for (let i = 0; i < data.count(); i++) {
    const node = tree.getNodeByDataIndex(i);
    must(node.dataIndex === i && node.getRawIndex() === i, 'row ' + i + ': dataIndex / rawIndex');
    const L = node.getLayout();
    const g = store.nodeGroup[i];
    const bg = store.background[i];
    const ct = store.content[i];
    if (bg) kindOf.set(bg, { kind: 'bg', row: i });
    if (ct) kindOf.set(ct, { kind: 'content', row: i });
    const visited = !!(L && L.isInView && !L.invisible);
    const st = data.getItemVisual(i, 'style');
    const isParent = node.viewChildren && node.viewChildren.length;
    let label = null;
    const t = ct && ct.getTextContent();
    if (t) {
      const kids = t.childrenRef();
      for (const k of kids) kindOf.set(k, { kind: 'tspan', row: i });
      label = { rawText: t.style.text == null ? null : t.style.text, ignore: !!t.ignore, transform: m6(t.transform), z2: t.z2, width: json(t.style.width), height: json(t.style.height),
        padding: json(t.style.padding), isTruncated: !!t.isTruncated, lines: kids.map(k => k.style.text) };
      must(!t.invisible, 'row ' + i + ': an invisible label Text');
    }
    const raw = data.getRawDataItem(i);
    rows.push({
      index: i, name: node.name, valueCompleted: i === 0 ? json(node.getValue()) : json(raw.value), value: node.getValue(), depth: node.depth, height: node.height,
      parent: node.parentNode ? node.parentNode.dataIndex : null, children: node.children.map(c => c.dataIndex),
      layout: L ? layoutOf(L) : null,
      viewChildren: node.viewChildren ? node.viewChildren.map(c => c.dataIndex) : null,
      stroke: visited ? json(st.stroke) : null,
      fill: visited && !isParent ? json(st.fill) : null,
      T: g && g.transform ? [g.transform[4], g.transform[5]] : null,
      label,
      valueWritten: written[i].value,
      hasWrittenValue: hasOwn(written[i], 'value'),
      hasGroup: !!g,
    });
    must(!g || (bg && (!isParent) === !!ct), 'row ' + i + ': a group without its rects');
    must(!ct || !isParent, 'row ' + i + ': a parent with a content rect');
    if (g) {
      must(!g.transform === !(bg.transform), 'row ' + i + ': rect / group transform');
      must(!bg.transform || (bg.transform[4] === g.transform[4] && bg.transform[5] === g.transform[5]), 'row ' + i + ': the background does not carry the group transform');
    }
  }
  // breadcrumb
  const bcGroup = view._breadcrumb ? view._breadcrumb.group : null;
  let breadcrumb = null;
  if (bcGroup && bcGroup.children().length) {
    const items = bcGroup.children().map((pg, k) => {
      must(pg.type === 'polygon', 'a breadcrumb child is a ' + pg.type);
      const ed = ecInner(pg, 'eventData');
      must(ed && ed.eventData.selfType === 'breadcrumb', 'crumb ' + k + ': no breadcrumb eventData');
      const row = ed.eventData.nodeData.dataIndex;
      kindOf.set(pg, { kind: 'crumb', row });
      const t = pg.getTextContent();
      let label = null;
      if (t) {
        for (const kk of t.childrenRef()) kindOf.set(kk, { kind: 'crumbText', row });
        if (t.style.text != null && t.style.text !== '') label = { x: t.transform ? t.transform[4] : 0, y: t.transform ? t.transform[5] : 0 };
      }
      return { row, text: t && t.style.text != null ? t.style.text : null, points: pg.shape.points.map(p => [p[0], p[1]]), label };
    });
    breadcrumb = { target: items[items.length - 1].row, items, groupX: bcGroup.x, groupY: bcGroup.y };
  }
  // the display list: every element must be one of ours
  const elements = list.map((el, i) => {
    const k = kindOf.get(el);
    must(k, 'display list #' + i + ': an unexpected ' + el.type + ' (z2 ' + el.z2 + ')');
    const e = Object.assign({ kind: k.kind, row: k.row, z: el.z, z2: el.z2, zlevel: el.zlevel, transform: m6(el.transform) }, styleOf(el));
    if (el.type === 'rect') {
      must(k.kind === 'bg' || k.kind === 'content', 'a rect of kind ' + k.kind);
      e.shape = { x: el.shape.x, y: el.shape.y, width: el.shape.width, height: el.shape.height, r: el.shape.r };
    } else if (el.type === 'polygon') {
      e.points = el.shape.points.map(p => [p[0], p[1]]);
    } else if (el.type === 'tspan') {
      Object.assign(e, { text: el.style.text, x: el.style.x, y: el.style.y, textAlign: json(el.style.textAlign), textBaseline: json(el.style.textBaseline), font: json(el.style.font) });
    } else must(false, 'an element of type ' + el.type);
    return e;
  });
  must(elements.filter(e => e.kind === 'bg').length === rows.filter(r => r.hasGroup).length, 'not every group painted its background');
  return {
    name: fedSeries.name == null ? null : String(fedSeries.name),
    box: { x: sm.layoutInfo.x, y: sm.layoutInfo.y, width: sm.layoutInfo.width, height: sm.layoutInfo.height },
    // setDefault also copies aria.decal.decals onto levels[0].decal (drawn only with aria decals on): not recorded
    levelsAfter: (json(sm.option.levels) || []).map(l => { if (l && typeof l === 'object') delete l.decal; return l; }),
    merged: sm.option,
    rows, elements, breadcrumb,
  };
}

// the fields both sides produce, in one shape (raw numbers); compared with Object.is
function upstreamView(u) {
  return {
    box: u.box,
    levels: u.levelsAfter,
    rows: u.rows.map(r => ({ index: r.index, name: r.name, valueCompleted: r.valueCompleted, value: r.value, depth: r.depth, height: r.height, parent: r.parent, children: r.children,
      layout: r.layout, viewChildren: r.viewChildren, stroke: r.stroke, fill: r.fill, T: r.T, label: r.label })),
    elements: u.elements,
    breadcrumb: u.breadcrumb,
  };
}
function transcribedView(t) {
  return {
    box: t.resolved.box,
    levels: t.resolved.levels,
    rows: t.rows.map(r => ({ index: r.index, name: r.name, valueCompleted: r.valueCompleted, value: r.value, depth: r.depth, height: r.height, parent: r.parent, children: r.children,
      layout: r.layout, viewChildren: r.viewChildren, stroke: r.stroke, fill: r.fill, T: r.T, label: r.label })),
    elements: t.elements.map(e => {
      const o = { kind: e.kind, row: e.row, z: e.z, z2: e.z2, zlevel: e.zlevel, transform: e.transform, fill: e.fill, stroke: e.stroke, lineWidth: e.lineWidth, lineJoin: e.lineJoin, opacity: e.opacity };
      if (e.shape) o.shape = e.shape;
      if (e.points) o.points = e.points;
      if (e.text !== undefined) Object.assign(o, { text: e.text, x: e.x, y: e.y, textAlign: e.textAlign, textBaseline: e.textBaseline, font: e.font });
      return o;
    }),
    breadcrumb: t.breadcrumb ? {
      target: t.breadcrumb.target,
      items: t.breadcrumb.items.map(p => ({ row: p.row, text: p.text, points: p.points, label: p.label })),
      groupX: t.breadcrumb.groupX, groupY: t.breadcrumb.groupY,
    } : null,
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
// M1 only: none of these may appear anywhere in a case's series option
const M2PLUS = ['colorSaturation', 'borderColorSaturation', 'colorAlpha', 'upperLabel', 'leafDepth', 'colorMappingBy', 'visualDimension', 'visualMin', 'visualMax', 'decal'];
function m1Violations(o, where, out) {
  if (isArray(o)) { o.forEach((x, i) => m1Violations(x, where + '[' + i + ']', out)); return out; }
  if (!isObject(o)) return out;
  for (const k of Object.keys(o)) {
    if (M2PLUS.includes(k) && o[k] != null) out.push(where + '.' + k);
    m1Violations(o[k], where + '.' + k, out);
  }
  return out;
}

function recordCase(def, withProd) {
  const opt = def.gallery ? gallery(def.gallery) : zrClone(def.option);
  const animationForced = opt.animation !== false;
  opt.animation = false;
  const optionText = JSON.stringify(opt);
  const fed = JSON.parse(optionText);
  must(isArray(fed.series) ? fed.series.length === 1 : !!fed.series, 'one treemap series per case');
  const fedSeries = [].concat(fed.series)[0];
  must(fedSeries.type === 'treemap', 'not a treemap');
  const viol = m1Violations(fedSeries, 'series[0]', []);
  must(!viol.length, 'an M2+ key: ' + viol.join(', '));
  must(!(isArray(fedSeries.color) && fedSeries.color.length), 'a series-level colour list (M6)');
  // the sort key as fed, BEFORE any JSON round trip
  const src = def.gallery ? fedSeries : [].concat(def.option.series)[0];
  const sortKeyPresent = hasOwn(src, 'sort');
  const rec = runChart(echarts, JSON.parse(optionText), chart => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const u = readTreemap(chart, fedSeries);
    for (const k of READ_KEYS) {
      const want = zrMerge(zrClone(fedSeries), TM_DEFAULTS, false)[k];
      must(JSON.stringify(json(u.merged[k])) === JSON.stringify(json(want)), 'the merged option ' + k + ' is not the fed option over the defaults: ' + JSON.stringify(u.merged[k]) + ' vs ' + JSON.stringify(want));
    }
    delete u.merged;
    return { palette: json(ec.option.color), textStyle: json(ec.option.textStyle), ground: { background: json(zr.getBackgroundColor()), isDark: !!zr.isDarkMode() }, u };
  });
  if (withProd) {
    const p = runChart(PROD, JSON.parse(optionText), chart => readTreemap(chart, fedSeries));
    delete p.merged;
    const a = JSON.stringify(flat(upstreamView(rec.u), 's', {}));
    const b = JSON.stringify(flat(upstreamView(p), 's', {}));
    must(a === b, 'the production build records differently');
  }
  const env = { W, H, palette: rec.palette, fontFamily: rec.textStyle.fontFamily };
  must(typeof env.fontFamily === 'string', 'no global fontFamily');
  return { def, optionText, animationForced, sortKeyPresent, fedSeries, env, rec };
}

// ============================================================================
// The cases
// ============================================================================
const D1 = () => [
  { name: 'A', children: [{ name: 'A1', value: 4 }, { name: 'A2', value: 2 }] },
  { name: 'B', value: 10, children: [{ name: 'B1', value: 3 }, { name: 'B2', value: 5, children: [{ name: 'B21', value: 5 }] }] },
  { name: 'C', value: 3 },
];
const TIES = () => [{ name: 'p', value: 5 }, { name: 'q', value: 5 }, { name: 'r', value: 5 }];
const one = (series, extra) => Object.assign({ animation: false, series: [Object.assign({ type: 'treemap' }, series)] }, extra || {});
const BORDER_LEVELS = () => [{ itemStyle: { borderWidth: 3, gapWidth: 4, borderColor: '#333' } }, { itemStyle: { borderWidth: 2, gapWidth: 2 } }, { itemStyle: { borderWidth: 1, gapWidth: 1 } }];
const ELEVEN = () => ['n0', 'n1', 'n2', 'n3', 'n4', 'n5', 'n6', 'n7', 'n8', 'n9', 'n10'].map((name, i) => ({ name, value: 30 - i }));

const CASES = [
  // ---- D1 family ----
  { id: 'D1-default', note: 'D1 (upstream.md 2.5): desc B, A, C; palette by sorted index, inherited; label z2 332', option: one({ data: D1() }) },
  { id: 'D1-asc', note: "sort 'asc': C, A, B; asc ties lower dataIndex first", option: one({ data: D1(), sort: 'asc' }) },
  { id: 'D1-sort-false', note: 'sort false: written order, visibleMin off', option: one({ data: D1(), sort: false }) },
  { id: 'D1-sort-null', note: 'sort null PRESENT: no sort (absent would be desc)', option: one({ data: D1(), sort: null }) },
  { id: 'D1-sort-foo', note: "sort 'foo' (truthy, not asc): desc", option: one({ data: D1(), sort: 'foo' }) },
  { id: 'D1-sort-zero', note: 'sort 0 (falsy): no sort; values 1 then 9 stack along y (rfl 500 != 760)', option: one({ data: [{ name: 'a', value: 1 }, { name: 'b', value: 9 }], sort: 0 }) },
  { id: 'D1-sort-desc-two', note: "sort 'desc' on (1, 9): b first, 684 x 500 then a 76 x 500", option: one({ data: [{ name: 'a', value: 1 }, { name: 'b', value: 9 }], sort: 'desc' }) },
  { id: 'D1-ties-desc', note: 'three equal leaves p, q, r: desc ties put the HIGHER dataIndex first (r, q, p)', option: one({ data: TIES() }) },
  { id: 'D1-ties-asc', note: 'three equal leaves: asc keeps p, q, r', option: one({ data: TIES(), sort: 'asc' }) },
  { id: 'D1-ties-nested', note: 'ties on two levels, plus a tie across a parent and a leaf', option: one({ data: [{ name: 'x', value: 6, children: [{ name: 'x1', value: 2 }, { name: 'x2', value: 2 }, { name: 'x3', value: 2 }] }, { name: 'y', value: 6 }, { name: 'z', value: 6, children: [{ name: 'z1', value: 3 }, { name: 'z2', value: 3 }] }] }) },
  { id: 'D1-border', note: 'levels border / gap [3 4 #333, 2 2, 1 1]: insets, (h - lo) - lou, the root background #333', option: one({ data: D1(), levels: BORDER_LEVELS() }) },
  { id: 'D1-border-series', note: 'series itemStyle borderWidth 2 gapWidth 3 borderColor #444 (every depth)', option: one({ data: D1(), itemStyle: { borderWidth: 2, gapWidth: 3, borderColor: '#444' } }) },
  { id: 'D1-border-item', note: 'an item borderWidth 6 / gapWidth 5 / borderColor on B, a borderRadius 4 on the series', option: one({ data: (() => { const d = D1(); d[1].itemStyle = { borderWidth: 6, gapWidth: 5, borderColor: 'blue' }; return d; })(), itemStyle: { borderRadius: 4 } }) },
  // ---- values ----
  { id: 'V-zero-tiny', note: 'zero and tiny values with the default sort: removed by visibleMin 10, siblings grow', option: one({ data: [{ name: 'big', value: 100 }, { name: 'z', value: 0 }, { name: 'tiny', value: 0.001 }, { name: 'mid', value: 20 }] }) },
  { id: 'V-zero-tiny-nosort', note: 'the same with sort false: slivers stay (0-high z, 0.0253-wide tiny with an empty tspan)', option: one({ data: [{ name: 'big', value: 100 }, { name: 'z', value: 0 }, { name: 'tiny', value: 0.001 }, { name: 'mid', value: 20 }], sort: false }) },
  { id: 'V-zero-tiny-asc', note: 'the same with asc: the cut from the front', option: one({ data: [{ name: 'big', value: 100 }, { name: 'z', value: 0 }, { name: 'tiny', value: 0.001 }, { name: 'mid', value: 20 }], sort: 'asc' }) },
  { id: 'V-allzero', note: 'every value 0: the root has no viewChildren, drawn as a leaf with fill undefined and the series name as label', option: one({ name: 'S', data: [{ name: 'z', value: 0 }, { name: 'y', value: 0 }] }) },
  { id: 'V-allzero-children', note: 'a parent whose children are all 0: drawn as a leaf in its palette colour', option: one({ data: [{ name: 'P', value: 5, children: [{ name: 'p1', value: 0 }, { name: 'p2', value: 0 }] }, { name: 'Q', value: 5 }] }) },
  { id: 'V-parent-above-sum', note: 'P value 10 with children 1 and 1: the children still fill P (380 x 250 each)', option: one({ data: [{ name: 'P', value: 10, children: [{ name: 'p1', value: 1 }, { name: 'p2', value: 1 }] }, { name: 'Q', value: 10 }] }) },
  { id: 'V-negative-array', note: 'a negative value clamped to 0, an array value [7, 3] (value = 7, {c} would print 7,3), a missing parent value summed', option: one({ data: [{ name: 'neg', value: -4 }, { name: 'arr', value: [7, 3] }, { name: 'sum', children: [{ name: 's1', value: 2 }, { name: 's2', value: 5 }] }] }) },
  { id: 'V-empty', note: 'data []: only the virtual root, sum 0: a leaf with no fill', option: one({ data: [] }) },
  // ---- colours ----
  { id: 'C-level-list', note: "levels[1].color ['#111', '#222']: palette suppressed; depth-1 leaves fill undefined (no fill), depth-2 children mapped by sorted index", option: one({ data: [{ name: 'a', value: 3, children: [{ name: 'a1', value: 1 }, { name: 'a2', value: 2 }, { name: 'a3', value: 1.5 }] }, { name: 'b', value: 2 }], levels: [{}, { color: ['#111', '#222'] }] }) },
  { id: 'C-level0-list', note: "levels[0].color ['#123', 'red'] (user list replaces the palette; two entries wrap)", option: one({ data: D1(), levels: [{ color: ['#123', 'red'] }] }) },
  { id: 'C-empty-list', note: 'levels [{}, {color: []}]: an EMPTY list still counts as a colour define; nothing maps, nothing is filled', option: one({ data: D1(), levels: [{}, { color: [] }] }) },
  { id: 'C-level-itemcolor', note: "levels[1].itemStyle.color '#aa3344': suppresses the palette and paints every depth-1 node, inherited below", option: one({ data: D1(), levels: [{}, { itemStyle: { color: '#aa3344' } }] }) },
  { id: 'C-item-parent', note: "an item colour '#123456' on a parent is inherited; a child's own 'red' wins", option: one({ data: [{ name: 'a', value: 5, itemStyle: { color: '#123456' }, children: [{ name: 'a1', value: 2 }, { name: 'a2', value: 3, itemStyle: { color: 'red' } }] }, { name: 'b', value: 4 }] }) },
  { id: 'C-series-color', note: "series itemStyle.color '#abcdef' loses to the palette-designated colour at depth >= 1", option: one({ data: D1(), itemStyle: { color: '#abcdef' } }) },
  { id: 'C-series-color-nopalette', note: "series itemStyle.color '#abcdef' with the palette suppressed by levels[2].color: depth-1 nodes take the series colour", option: one({ data: D1(), itemStyle: { color: '#abcdef' }, levels: [{}, {}, { color: ['#010101', '#020202'] }] }) },
  { id: 'C-eleven', note: 'eleven roots: n9 wraps to palette[0], n10 to palette[1]', option: one({ data: ELEVEN() }) },
  { id: 'C-eleven-cut', note: 'eleven roots with a zero among them: visibleMin removes it and shifts the later indices', option: one({ data: (() => { const d = ELEVEN(); d.splice(3, 0, { name: 'zero', value: 0 }); return d; })() }) },
  { id: 'C-user-palette', note: "a top-level color ['#f00', '#0f0', '#00f'] is the global palette setDefault copies", option: one({ data: D1() }, { color: ['#f00', '#0f0', '#00f'] }) },
  { id: 'C-border-level-colors', note: 'border colours per level and per item', option: one({ data: (() => { const d = D1(); d[0].children[0].itemStyle = { borderColor: '#000', borderWidth: 3 }; return d; })(), levels: [{ itemStyle: { borderColor: '#333', borderWidth: 2, gapWidth: 2 } }, { itemStyle: { borderColor: 'red', borderWidth: 4 } }] }) },
  // ---- names and labels ----
  { id: 'L-nameless-named-series', note: "nameless nodes under series name 'Ser': labels and crumbs fall back to 'Ser'; {b} stays ''", option: one({ name: 'Ser', data: [{ name: 'Alpha', value: 3, children: [{ value: 1 }, { name: 'q', value: 2 }] }, { value: 1 }] }) },
  { id: 'L-nameless-unnamed', note: 'nameless nodes, unnamed series: no text (a Text with no tspans)', option: one({ data: [{ value: 3 }, { value: 2, children: [{ value: 1 }, { value: 1 }] }] }) },
  { id: 'L-level-name', note: "levels[1].name 'LevelOne' names the nameless depth-1 nodes", option: one({ name: 'Ser', data: [{ value: 3 }, { name: 'own', value: 2 }], levels: [{}, { name: 'LevelOne' }] }) },
  { id: 'L-formatter-b', note: "formatter '{b}': a nameless leaf gets an empty label", option: one({ name: 'Ser', data: [{ value: 3 }, { name: 'nm', value: 2 }], label: { formatter: '{b}' } }) },
  { id: 'L-formatter-bc', note: "formatter '{b}:{c}' (the completed raw value, an array printed 7,3) and an item formatter '{a}!'", option: one({ name: 'Ser', data: [{ name: 'A', children: [{ name: 'a1', value: 4 }] }, { name: 'arr', value: [7, 3] }, { name: 'B', value: 2, label: { formatter: '{a}!' } }], label: { formatter: '{b}:{c}' } }) },
  { id: 'L-show-false', note: 'label.show false on an item and on levels[2]', option: one({ data: (() => { const d = D1(); d[2].label = { show: false }; return d; })(), levels: [{}, {}, { label: { show: false } }] }) },
  { id: 'L-fontsize', note: 'label fontSize 14 on the series, 20 on levels[2], label colour #000 on an item', option: one({ data: (() => { const d = D1(); d[2].label = { color: '#000' }; return d; })(), label: { fontSize: 14 }, levels: [{}, {}, { label: { fontSize: 20 } }] }) },
  { id: 'L-narrow', note: "narrow cells: 'Elephantine' cut with and without the ellipsis, down to '' (containerWidth 0)", option: one({ data: [{ name: 'Elephantine', value: 200 }, { name: 'Elephantine2', value: 9 }, { name: 'Elephantine3', value: 5 }, { name: 'Elephantine4', value: 3 }, { name: 'Elephantine5', value: 2 }, { name: 'Elephantine6', value: 1.2 }, { name: 'Elephantine7', value: 0.7 }, { name: 'Elephantine8', value: 0.45 }], left: 20, right: 20, top: 50, height: 500, squareRatio: 1 }) },
  { id: 'L-short', note: 'short cells: line drop (ch < 22 at 12px drops the only line; isTruncated with no tspan)', option: one({ data: [{ name: 'tall', value: 300 }, { name: 'short1', value: 4 }, { name: 'short2', value: 3 }, { name: 'short3', value: 2 }], top: 50, bottom: 50, left: 300, right: 300, sort: false }) },
  { id: 'L-cjk-newline', note: "a CJK name, a 'two\\nlines' name (the second line dropped in a short cell, kept in a tall one), a name with an astral character", option: one({ data: [{ name: '\u4e2d\u6587\u6807\u7b7e\u5f88\u957f\u5f88\u957f\u5f88\u957f', value: 6 }, { name: 'two\nlines', value: 5 }, { name: 'tw\no', value: 0.4 }, { name: 'emoji\ud83d\ude00face', value: 1.5 }, { name: '\u56fd', value: 0.3 }] }) },
  { id: 'L-newline-short', note: "'a\\nb\\nc' in cells of heights that keep 3, 2, 1, 0 lines", option: one({ data: [{ name: 'a\nb\nc', value: 60 }, { name: 'd\ne\nf', value: 30 }, { name: 'g\nh\ni', value: 5 }, { name: 'j\nk\nl', value: 2.4 }], sort: false, left: 20, right: 700 }) },
  // ---- visibility options ----
  { id: 'O-childrenVisibleMin', note: 'childrenVisibleMin 40000, visibleMin 50: grandchildren of small parents hidden (drawn as leaves)', option: one({ data: [{ name: 'big', value: 40, children: [{ name: 'b1', value: 20, children: [{ name: 'b11', value: 10 }, { name: 'b12', value: 10 }] }, { name: 'b2', value: 20 }] }, { name: 'small', value: 4, children: [{ name: 's1', value: 2, children: [{ name: 's11', value: 1 }, { name: 's12', value: 1 }] }, { name: 's2', value: 2 }] }], childrenVisibleMin: 40000, visibleMin: 50 }) },
  { id: 'O-visibleMin-300', note: 'visibleMin 300 + squareRatio 1: more children cut, the running sum shrinks', option: one({ data: Array.from({ length: 14 }, (_, i) => ({ name: 'k' + i, value: [900, 400, 200, 90, 60, 30, 12, 9, 6, 4, 2, 1.5, 1, 0.5][i] })), visibleMin: 300, squareRatio: 1 }) },
  { id: 'O-visibleMin-level', note: 'visibleMin on levels[1] (the depth-1 parents cut their children) and on an item', option: one({ data: [{ name: 'A', value: 50, visibleMin: 5000, children: [{ name: 'a1', value: 40 }, { name: 'a2', value: 9 }, { name: 'a3', value: 1 }] }, { name: 'B', value: 50, children: [{ name: 'b1', value: 40 }, { name: 'b2', value: 9 }, { name: 'b3', value: 1 }] }], levels: [{}, { visibleMin: 2000 }] }) },
  { id: 'O-squareRatio-1', note: 'squareRatio 1 on D1', option: one({ data: D1(), squareRatio: 1 }) },
  // ---- boxes ----
  { id: 'B-square', note: 'left 150 right 150: a 500 x 500 box (the rfl === rect.width tie runs the row along x)', option: one({ data: [{ name: 'a', value: 4 }, { name: 'b', value: 4 }, { name: 'c', value: 1 }, { name: 'd', value: 1 }], left: 150, right: 150 }) },
  { id: 'B-square-D1', note: 'D1 in the 500 x 500 box', option: one({ data: D1(), left: 150, right: 150 }) },
  { id: 'B-tiny-border', note: 'levels borderWidth 3e-5 / 2e-5, gapWidth 1e-5: local offsets <= 5e-5 dropped (the group copies its parent transform)', option: one({ data: D1(), levels: [{ itemStyle: { borderWidth: 0.00003 } }, { itemStyle: { borderWidth: 0.00002, gapWidth: 0.00001 } }] }) },
  { id: 'B-offcanvas', note: 'a box partly off the canvas (left -500, width 900, top 350, height 600): invisible nodes get no element and no colour', option: one({ data: D1().concat([{ name: 'D', value: 7, children: [{ name: 'D1', value: 3 }, { name: 'D2', value: 4 }] }, { name: 'E', value: 2 }]), left: -500, width: 900, top: 350, height: 600 }) },
  { id: 'B-offcanvas-all', note: 'the box entirely off the canvas (left 900): the root is invisible, nothing drawn, the crumb falls back to the root', option: one({ data: D1(), left: 900, width: 300 }) },
  { id: 'B-percent', note: "percent box {left '5%', width '70%', top 10, height 300}", option: one({ data: D1(), left: '5%', top: 10, width: '70%', height: 300 }) },
  { id: 'B-right-bottom', note: "right '30%', bottom 5, top '40%'", option: one({ data: D1(), right: '30%', bottom: 5, top: '40%' }) },
  // ---- breadcrumb ----
  { id: 'K-collapse', note: 'long level / series names: the crumbs exceed the canvas width and collapse from the root side', option: one({ name: 'A rather long series name for crumbs, much longer than that', data: [{ name: 'An even longer first level name that goes on and on', value: 10, children: [{ name: 'Second level with a long long long name too', value: 10, children: [{ name: 'Third level name, still quite long indeed', value: 10 }] }] }], breadcrumb: { emptyItemWidth: 60 } }) },
  { id: 'K-options', note: 'breadcrumb emptyItemWidth 40, height 30, left 10, a box off the default', option: one({ data: D1(), left: '5%', top: 10, width: '70%', height: 300, breadcrumb: { emptyItemWidth: 40, height: 30, left: 10 } }) },
  { id: 'K-right-top', note: "breadcrumb left 'right', top 5 (no bottom key: merged defaults keep bottom 15)", option: one({ data: D1(), breadcrumb: { left: 'right', top: 5, height: 18 } }) },
  { id: 'K-hidden', note: 'breadcrumb show false: no crumb', option: one({ data: D1(), breadcrumb: { show: false } }) },
  { id: 'K-names-levels', note: "series name + levels names: the root crumb and nameless crumbs show them", option: one({ name: 'A rather long series name for crumbs', data: [{ value: 10, children: [{ value: 8, children: [{ name: 'leaf', value: 8 }] }, { value: 1 }] }], breadcrumb: { emptyItemWidth: 60 }, levels: [{ name: 'LevelZeroName' }, { name: 'Level one default name' }] }) },
  { id: 'K-centre-boundary', note: 'two siblings meeting exactly at x = 400 (both 380 wide at 20 + 380): the centre hits both, the LAST in pre-order wins', option: one({ data: [{ name: 'L', value: 1, children: [{ name: 'L1', value: 1 }] }, { name: 'R', value: 1, children: [{ name: 'R1', value: 1 }] }], sort: false }) },
  { id: 'K-centre-boundary-desc', note: 'the same with desc ties (R first in sorted order, L last)', option: one({ data: [{ name: 'L', value: 1, children: [{ name: 'L1', value: 1 }] }, { name: 'R', value: 1, children: [{ name: 'R1', value: 1 }] }] }) },
  { id: 'K-narrow-box', note: 'a box 300 wide: the root fails w >= W / 2, the breadcrumb falls back to the root', option: one({ data: D1(), left: 250, right: 250 }) },
  { id: 'K-local-not-global', note: 'D1: the centre lies in B1 globally, but B1 is only 150 wide locally; the crumbs are root > B', option: one({ data: D1() }) },
];

// ---- ref.js random families (its generator, M1 variants only) ----
function randomCases(nForests) {
  let seed = 424242;
  const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
  const ri = n => Math.floor(rnd() * n);
  const NAMES = ['a', 'bb', 'Cat', 'dog', 'Elephant', 'LongNameAbcdefghijk', '\u4e2d\u6587', 'x y', 'W', 'm'];
  function genNode(depth, maxDepth, itemStyles) {
    const n = {};
    const t0 = rnd();
    if (t0 < 0.9) n.name = NAMES[ri(NAMES.length)] + (rnd() < 0.6 ? String(ri(40)) : '');
    else if (t0 < 0.93) n.name = 'two\nlines';
    const k = depth < maxDepth ? ri(depth === 0 ? 7 : 5) : 0;
    if (k > 0 && rnd() < 0.8) {
      n.children = [];
      for (let i = 0; i < k; i++) n.children.push(genNode(depth + 1, maxDepth, itemStyles));
      if (rnd() < 0.2) n.value = ri(60);
    } else {
      const t = rnd();
      n.value = t < 0.06 ? 0 : t < 0.09 ? -ri(5) : t < 0.13 ? undefined : t < 0.18 ? [ri(20) + 1, ri(9)] : t < 0.3 ? +(rnd() * 30).toFixed(3) : ri(40) + 1;
      if (n.value === undefined) delete n.value;
    }
    if (itemStyles && rnd() < 0.12) {
      n.itemStyle = {};
      const u = rnd();
      if (u < 0.3) n.itemStyle.color = ['#123456', 'red', '#ffeecc'][ri(3)];
      else if (u < 0.55) n.itemStyle.borderWidth = ri(6);
      else if (u < 0.8) n.itemStyle.gapWidth = ri(7);
      else n.itemStyle.borderColor = ['#000', 'blue'][ri(2)];
    }
    if (itemStyles && rnd() < 0.03) n.label = { show: false };
    return n;
  }
  function genForest() {
    const n = 1 + ri(7);
    const out = [];
    const md = 1 + ri(4);
    const itemStyles = rnd() < 0.5;
    for (let i = 0; i < n; i++) out.push(genNode(1, md, itemStyles));
    return out;
  }
  // ref.js's 16 variants; v6 (leafDepth, M4) and v9 (upperLabel, M3) are left out of the fixture
  // (their generator calls still run, so the sequence matches ref.js)
  const VARIANTS = [
    () => ({}),
    () => ({ sort: 'asc' }),
    () => ({ sort: false }),
    () => ({ levels: [{ itemStyle: { borderWidth: 3, gapWidth: 4, borderColor: '#333' } }, { itemStyle: { borderWidth: 2, gapWidth: 2, borderColor: '#aaa' } }, { itemStyle: { gapWidth: 1 } }] }),
    () => ({ squareRatio: 1, visibleMin: 300 }),
    () => ({ childrenVisibleMin: 40000, visibleMin: 50 }),
    () => ({ leafDepth: 1 + ri(2) }),
    () => ({ left: '5%', top: 10, width: '70%', height: 300, breadcrumb: { emptyItemWidth: 40, height: 30, left: 10 } }),
    () => ({ levels: [{ color: ['#111111', '#222222', '#333333'] }, { color: ['red', 'green'] }] }),
    () => ({ upperLabel: { show: true, height: 20 }, levels: [{ upperLabel: { show: false } }] }),
    () => ({ name: 'Ser', label: { fontSize: 14, formatter: '{b}!' } }),
    () => ({ levels: [{}, { itemStyle: { color: '#aa3344' } }] }),
    () => ({ sort: 'desc', itemStyle: { borderWidth: 1, gapWidth: 1 }, breadcrumb: { show: rnd() < 0.5 } }),
    () => ({ right: '30%', bottom: 5, top: '40%' }),
    () => ({ levels: [{ itemStyle: { borderWidth: 0.00003 } }, { itemStyle: { borderWidth: 0.00002, gapWidth: 0.00001 } }] }),
    () => ({ name: 'A rather long series name for crumbs', breadcrumb: { emptyItemWidth: 60 }, levels: [{ name: 'LevelZeroName' }, { name: 'Level one default name' }] }),
  ];
  const SKIP = new Set([6, 9]);
  // ref.js ran six canvas sizes; the fixture keeps 800 x 600 and varies the BOX instead
  const BOXES = [
    {},
    { left: 50, right: 90, top: 90, bottom: 90 },
    { left: 250, right: 250, top: 200, bottom: 200 },
    { top: 125, bottom: 125 },
    { left: 200, right: 200, top: 10, bottom: 10 },
    { left: 150, right: 150 },
  ];
  const out = [];
  for (let f = 0; f < nForests; f++) {
    const data = genForest();
    for (let v = 0; v < VARIANTS.length; v++) {
      const variant = VARIANTS[v]();
      if (SKIP.has(v)) continue;
      const hasBox = ['left', 'right', 'top', 'bottom', 'width', 'height'].some(k => k in variant);
      const b = hasBox ? null : (f + v) % BOXES.length;
      const opt = Object.assign({ type: 'treemap', data: zrClone(data) }, b == null ? {} : BOXES[b], variant);
      out.push({ id: 'R-f' + f + 'v' + v, note: 'ref.js random forest ' + f + ', variant ' + v + (b == null ? '' : ', box ' + b), option: { animation: false, series: [opt] }, random: { forest: f, variant: v, box: b } });
    }
  }
  return out;
}

// ============================================================================
// The guards: ref.js's mutants ('lt' omitted: it hangs)
// ============================================================================
const GUARDS = [
  ['nodefault', 'no palette on levels[0] (setDefault skipped)'],
  ['sortfalse', 'a falsy sort (false / null / 0) sorts desc'],
  ['f', '`rfl * (rfl * ratio)` instead of `(rfl * rfl) * ratio` in worst()'],
  ['side', '`rfl === rect.height ? 1 : 0` (a square rect runs vertically)'],
  ['remain', '`x + (w - last)` instead of `(x + w) - last`'],
  ['last', "the last item of a row takes `step`, not the remainder"],
  ['tie', 'desc ties by ascending dataIndex'],
  ['novismin', 'no visibleMin filter'],
  ['sumfix', 'visibleMin never reduces the running sum (compares, and shares the kept area, against the unreduced sum)'],
  ['area', '`A * v / sum` instead of `v / sum * A`'],
  ['height', '`h - (lo + lou)` instead of `(h - lo) - lou`'],
  ['recompute', 're-sum `row.area` after the pop (not the running subtraction)'],
  ['inherit', "children take the grandparent's visuals"],
  ['index', 'palette by dataIndex instead of the sorted, filtered index'],
  ['eps', 'the 5e-5 needLocalTransform rule ignored'],
  ['ordx', '`bw + (tx + cw / 2)` label anchor'],
  ['nolinedrop', 'lines taller than the label box kept'],
  ['minchar', 'no minChar reserve before the ellipsis check'],
  ['z2', 'label z2 = host z2 + 2 (not the running maximum)'],
  ['global', 'breadcrumb findTarget in transformed coordinates'],
  ['union', "breadcrumb union uses the polygon's maxX instead of bbox.x + bbox.width"],
];

// ============================================================================
// Output
// ============================================================================
function hexArr(a) { return a ? a.map(hexOrNull) : null; }
function emitSeries(c) {
  const u = c.rec.u;
  const t = c.tr;
  const R = t.resolved;
  const rows = u.rows.map((r, i) => {
    const tr = t.rows[i];
    const o = { index: r.index, name: r.name, chainName: tr.chainName };
    if (r.hasWrittenValue) o.valueWritten = json(r.valueWritten);
    Object.assign(o, { valueCompleted: dec(r.valueCompleted), value: dec(r.value), depth: r.depth, height: r.height, parent: r.parent, children: r.children });
    if (isArray(o.valueCompleted)) o.valueCompleted = r.valueCompleted.map(dec);
    if (r.layout) {
      const L = r.layout;
      o.layout = {};
      o.layoutText = {};
      for (const k of ['x', 'y', 'width', 'height', 'area', 'borderWidth', 'upperHeight', 'upperLabelHeight']) { o.layout[k] = hexOrNull(L[k]); o.layoutText[k] = dec(L[k]); }
      for (const k of ['isLeafRoot', 'isInView', 'invisible', 'isAboveViewRoot']) o.layout[k] = L[k];
    } else o.layout = null;
    Object.assign(o, {
      viewChildren: r.viewChildren, filteredByVisibleMin: tr.filteredByVisibleMin, paletteIndex: tr.paletteIndex, colour: tr.colour,
      stroke: r.stroke, fill: r.fill, T: hexArr(r.T), TText: r.T ? r.T.map(dec) : null, groupLocalDropped: tr.groupLocalDropped,
      label: r.label ? { rawText: r.label.rawText, ignore: r.label.ignore, transform: hexArr(r.label.transform), z2: r.label.z2, width: hexOrNull(r.label.width), height: hexOrNull(r.label.height), padding: r.label.padding,
        isTruncated: r.label.isTruncated, lines: r.label.lines } : null,
    });
    return o;
  });
  const elements = u.elements.map(e => {
    const o = { kind: e.kind, row: e.row, z: e.z, z2: e.z2, zlevel: e.zlevel, transform: hexArr(e.transform), fill: e.fill, stroke: e.stroke, lineWidth: e.lineWidth, lineJoin: e.lineJoin, opacity: e.opacity };
    if (e.shape) o.shape = { x: hex(e.shape.x), y: hex(e.shape.y), width: hex(e.shape.width), height: hex(e.shape.height), r: hex(e.shape.r) };
    if (e.points) o.points = e.points.map(p => p.map(hex));
    if (e.text !== undefined) Object.assign(o, { text: e.text, x: hex(e.x), y: hex(e.y), textAlign: e.textAlign, textBaseline: e.textBaseline, font: e.font });
    return o;
  });
  let breadcrumb = null;
  if (t.breadcrumb) {
    const B = t.breadcrumb;
    breadcrumb = {
      target: u.breadcrumb.target, targetRule: B.targetRule, availableWidth: hex(B.availableWidth), height: dec(B.height), emptyItemWidth: dec(B.emptyItemWidth), totalWidth: hex(B.totalWidth),
      items: B.items.map((p, k) => ({ row: u.breadcrumb.items[k].row, text: u.breadcrumb.items[k].text, chainText: p.chainText, measuredWidth: hex(p.measuredWidth), itemWidth: hex(p.itemWidth),
        collapsed: p.collapsed, head: p.head, tail: p.tail, points: u.breadcrumb.items[k].points.map(q => q.map(hex)),
        bbox: { x: hex(p.bbox.x), y: hex(p.bbox.y), width: hex(p.bbox.width), height: hex(p.bbox.height) },
        label: u.breadcrumb.items[k].label ? { x: hex(u.breadcrumb.items[k].label.x), y: hex(u.breadcrumb.items[k].label.y) } : null })),
      unionRect: { x: hex(B.unionRect.x), y: hex(B.unionRect.y), width: hex(B.unionRect.width), height: hex(B.unionRect.height) },
      groupX: hex(u.breadcrumb.groupX), groupY: hex(u.breadcrumb.groupY), groupText: [dec(u.breadcrumb.groupX), dec(u.breadcrumb.groupY)],
    };
  }
  return {
    seriesIndex: 0, name: u.name,
    resolved: {
      box: { x: hex(u.box.x), y: hex(u.box.y), width: hex(u.box.width), height: hex(u.box.height) }, boxText: { x: dec(u.box.x), y: dec(u.box.y), width: dec(u.box.width), height: dec(u.box.height) },
      sortKeyPresent: c.sortKeyPresent, sortValue: R.sortValue, sortMode: R.sortMode, squareRatio: hex(R.squareRatio), squareRatioText: dec(R.squareRatio), leafDepth: R.leafDepth,
      visibleMin: dec(R.visibleMin), level0PaletteDefaulted: R.level0PaletteDefaulted, levels: u.levelsAfter,
    },
    rows, elements, breadcrumb,
    labelStats: t.labelStats,
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
  module.exports = { transcribe, measure, TM_DEFAULTS };
} else try {
  const measureRec = checkMeasurer();
  const defs = CASES.concat(randomCases(NRANDOM));
  const ids = new Set();
  for (const d of defs) { must(!ids.has(d.id), 'duplicate id ' + d.id); ids.add(d.id); }
  defs.push({ id: 'G-simple', gallery: 'treemap-simple', note: 'examples/advchart/gallery/treemap-simple.json verbatim (animation forced false)' });
  // extra guard cases found by search (see below)
  for (const d of EXTRA()) defs.push(d);
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
      // transcribed extras agree with what upstream shows
      const ub = c.rec.u.breadcrumb; const tb = c.tr.breadcrumb;
      must(!ub === !tb, 'breadcrumb presence');
      if (tb) must(tb.target === ub.target, 'breadcrumb target');
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
  const rowOf = (id, name) => U(id).rows.find(r => r.name === name);
  const is = Object.is;
  {
    const L = n => rowOf('D1-default', n).layout;
    must(is(L('A').x, 400) && is(L('A').height, 333.3333333333333) && is(L('A2').y, 222.22222222222223) && is(L('C').height, 166.66666666666669), 'D1-default: layout anchors');
    must(rowOf('D1-default', 'B1').T[0] === 270 && rowOf('D1-default', 'A2').T[1] === 272.22222222222223, 'D1-default: T anchors');
    const lbl = U('D1-default').rows.filter(r => r.label).map(r => r.label.z2);
    must(lbl.every(z => z === 332), 'D1-default: every label z2 332');
    must(rowOf('D1-default', 'B').fill === null && rowOf('D1-default', 'B1').fill === '#5070dd' && rowOf('D1-default', 'A1').fill === '#b6d634' && rowOf('D1-default', 'C').fill === '#505372', 'D1-default: colours');
    const bc = U('D1-default').breadcrumb;
    must(bc.groupX === 371 && bc.groupY === 563 && bc.items.length === 2 && bc.items[1].row === 4, 'D1-default: breadcrumb root > B at (371, 563)');
    const bB = rowOf('D1-border', 'B');
    must(bB.T[0] === 23 && bB.T[1] === 53 && is(bB.layout.width, 394.94736842105266) && bB.layout.height === 494, 'D1-border: B');
    const tq = U('D1-ties-desc').rows[0].viewChildren;
    must(tq.join(',') === '3,2,1' && U('D1-ties-asc').rows[0].viewChildren.join(',') === '1,2,3', 'ties: r, q, p / p, q, r');
    const g = U('G-simple');
    const gB = g.rows.find(r => r.name === 'nodeB');
    must(is(gB.layout.width, 506.6666666666667) && g.rows.find(r => r.name === 'nodeAb').layout.area === 75999.99999999999, 'G-simple: layout');
    must(g.breadcrumb.items.length === 4 && is(g.breadcrumb.groupX, 289.03999999999996) && g.breadcrumb.groupY === 563, 'G-simple: breadcrumb');
    must(g.elements.filter(e => e.kind === 'bg').length === 7 && g.elements.filter(e => e.kind === 'content').length === 3 && g.elements.filter(e => e.kind === 'tspan').length === 3, 'G-simple: 7 bg, 3 content, 3 labels');
    must(rowOf('D1-sort-null', 'A').layout.x === 0, 'D1-sort-null: written order');
    must(U('V-allzero').rows[0].label.lines.join() === 'S' && U('V-allzero').rows[0].fill === null, 'V-allzero: the root as a leaf');
    must(U('B-offcanvas').rows.some(r => r.layout && r.layout.invisible), 'B-offcanvas: invisible nodes');
    must(byId['K-narrow-box'].tr.breadcrumb.targetRule === 'fallbackRoot', 'K-narrow-box: fallback root');
    must(byId['K-collapse'].tr.breadcrumb.items.some(p => p.collapsed), 'K-collapse: collapsed crumbs');
    must(recs.some(c => c.tr.rows.some(r => r.groupLocalDropped && r.T)), 'no group dropped its local offset');
  }
  // the cases carry what the Pascal test needs
  const counts = { cases: recs.length, rows: 0, elements: 0, rects: 0, tspans: 0, crumbs: 0, crumbTexts: 0, labels: 0 };
  for (const c of recs) {
    counts.rows += c.rec.u.rows.length;
    counts.elements += c.rec.u.elements.length;
    for (const e of c.rec.u.elements) {
      if (e.kind === 'bg' || e.kind === 'content') counts.rects++;
      else if (e.kind === 'tspan') counts.tspans++;
      else if (e.kind === 'crumb') counts.crumbs++;
      else counts.crumbTexts++;
    }
    counts.labels += c.rec.u.rows.filter(r => r.label).length;
    counts.truncatedLines = (counts.truncatedLines || 0) + c.tr.labelStats.truncated;
    counts.ellipsisLines = (counts.ellipsisLines || 0) + c.tr.labelStats.ellipsis;
    counts.labelsLosingLines = (counts.labelsLosingLines || 0) + c.tr.labelStats.dropped;
    counts.invisibleRows = (counts.invisibleRows || 0) + c.rec.u.rows.filter(r => r.layout && r.layout.invisible).length;
    counts.visibleMinCuts = (counts.visibleMinCuts || 0) + c.tr.rows.reduce((a, r) => a + r.filteredByVisibleMin.length, 0);
    counts.localOffsetsDropped = (counts.localOffsetsDropped || 0) + c.tr.rows.filter(r => r.groupLocalDropped).length;
    counts.collapsedCrumbs = (counts.collapsedCrumbs || 0) + (c.tr.breadcrumb ? c.tr.breadcrumb.items.filter(p => p.collapsed).length : 0);
    counts.fallbackRoot = (counts.fallbackRoot || 0) + (c.tr.breadcrumb && c.tr.breadcrumb.targetRule === 'fallbackRoot' ? 1 : 0);
    counts.ignoredLabels = (counts.ignoredLabels || 0) + c.rec.u.rows.filter(r => r.label && r.label.ignore).length;
  }
  // guards
  const guards = GUARDS.map(([id, mutation]) => {
    let red = 0; const changed = [];
    for (const c of recs) {
      let b;
      try { b = flat(transcribedView(transcribe(c.fedSeries, c.env, id)), 's', {}); } catch (e) { b = { threw: String(e.message) }; }
      const n = diffFlat(c.flatUp, b).length;
      if (n) { red += n; changed.push(c.def.id); }
    }
    return { id, mutation, red, cases: changed.length, sample: changed.slice(0, 6), ok: red > 0 };
  });
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version + ' (V8 ' + process.versions.v8 + ')',
    W, H, seed: SEED, tz: 'UTC',
    api: {
      update: "echarts.init(null, null, {renderer: 'svg', ssr: true, width: 800, height: 600}); setOption (animation false); zr.storage.getDisplayList(true); no animation frame is ever stepped",
      model: "sm.getData(): data.tree.getNodeByDataIndex(i) {name, depth, height, parentNode, children, viewChildren, getValue(), getLayout()}, getRawDataItem(i) (after completeTreeValue), getItemVisual(i, 'style') {fill, stroke}; sm.layoutInfo; sm.option.levels (after setDefault)",
      view: "chart.getViewOfSeriesModel(sm)._storage {nodeGroup, background, content}[rawIndex]; content.getTextContent() (the label Text: style.text / width / height / padding, isTruncated, transform, z2, childrenRef() TSpans); view._breadcrumb.group (x, y, the Polygon children with their eventData.nodeData and their Text)",
      paint: 'zr.storage.getDisplayList(true): every element must be a background, content, label TSpan, crumb polygon or crumb TSpan of the one series',
      production: 'every hand-written and gallery case records identically through dist/echarts.min.js',
    },
    notes: [
      'Rows: row i = the i-th node of a PRE-ORDER walk of {name: series.name, children: data} in the WRITTEN order; row 0 is the virtual root. completeTreeValue (post-order, a missing / null / NaN parent value takes the children sum, an explicit parent value is kept, v < 0 -> 0, an array value uses and writes back [0]). Sorting never reorders rows: viewChildren is a sorted, filtered copy.',
      "Option chain: item -> levels[depth] -> designated (the parent's colour, during the visual only) -> series merged over defaultOption. It includes name: chainName is what the label (without formatter) and the crumb show. levels[0] belongs to the virtual root. setDefault puts a COPY of the global palette on levels[0].color unless any level has a truthy itemStyle.color or a truthy color other than 'none' (an empty list counts).",
      "Sort: absent -> true -> desc; a truthy non-'asc' value -> desc; falsy (false, null, 0, '') -> no sort AND no visibleMin. Desc ties: higher dataIndex first; asc ties: lower first.",
      'Layout (all LOCAL to the parent origin, no rounding): see upstream.md 2.2-2.3. visibleMin (parent chain, default 10) cuts from the smallest with a running, reduced sum; kept children share the reduced sum. childrenVisibleMin hides grandchildren. Invisible (outside the canvas clip) nodes get no group, no element, no colour.',
      "Transforms: T(root group) = (layoutInfo.x, layoutInfo.y); T(child) = (x + T.x, y + T.y); a group whose local |x| and |y| are both <= 5e-5 copies its parent's transform (groupLocalDropped). A label Text's transform is [1, 0, 0, 1, (bw + T.x) + cw / 2, (bw + T.y) + ch / 2] (same 5e-5 rule, no parent); its TSpans copy it.",
      "Colour: travelTree over viewChildren in sorted order; a node's colour = item itemStyle.color > levels[depth].itemStyle.color > the designated (parent-mapped or inherited) colour > series itemStyle.color. The parent's chain `color` list (non-empty array) maps child k to list[k % n]. stroke = the chain borderColor ('#fff' default) and becomes the BACKGROUND rect fill; only nodes without viewChildren get a fill (undefined = no fill: the content rect has fill null).",
      "Elements: per visible node a background rect (z2 depth*100+20, shape (0, 0, w, h, r)) and, without viewChildren, a content rect (z2 depth*100+30, shape (bw, bw, max(w-2bw,0), max(h-2bw,0), r)); r = itemStyle.borderRadius || 0. The label Text z2 = the running maximum z2 over the pre-order walk + 2. Paint order = a stable sort by (zlevel, z, z2) over creation order: backgrounds and contents by depth band, labels, crumbs (100000), crumb texts (100002).",
      "Label text: the chain formatter (formatTpl {a} series name, {b} store name, {c} the completed raw value) else the chain name; null or '' -> a Text with no TSpan. Box: width = max(cw - pad[1] - pad[3], 0), height likewise; lines beyond floor(height / lineHeight) dropped (lineHeight = measure('\u56fd')); each line through zrender truncateSingleLine with minChar 2 and '...' (dropped when it does not fit), containerWidth = max(0, width - 1), '' for containerWidth 0. isTruncated: lines dropped or any line cut. The TSpan x = pad[3]/2 - pad[1]/2 (0), y from (0 - n*lh/2) + lh/2 accumulated.",
      "Breadcrumb (frame 1): target = the last node in pre-order (descending only into hits) whose UNTRANSFORMED background (0, 0, w, h) contains (W/2, H/2), else the root (fallbackRoot). Items root first: width max(measure(text, '12px sans-serif') + 16, emptyItemWidth), gap 8, arrow 5; collapse to emptyItemWidth without text from the root side while the total exceeds getLayoutRect({left, right, top, bottom}).width. The group is placed by positionElement on the zrender union of the polygon bboxes; crumb texts at (bbox.x + gx) + bbox.width / 2, (bbox.y + gy) + bbox.height / 2.",
      "Colours are upstream's literals: palette (ecModel.option.color) '#5070dd' .. '#3fbe95', border / label '#fff', crumb '#e8ebf0', crumb ink '#54555a'. A theme-driven port must inject these, never compare theme colours against them.",
      'M1 only: no case sets colorSaturation, borderColorSaturation, colorAlpha, upperLabel, leafDepth, colorMappingBy, visualDimension / visualMin / visualMax, decal or a series-level color list (checked; a case that did would stop the run). ref.js variants 6 (leafDepth) and 9 (upperLabel) are skipped.',
      "Not recorded: hover / emphasis, drill-down, zoom / roam, animations, the second-frame breadcrumb (which would use the previous frame's transforms).",
    ],
    measure: measureRec,
    counts,
    cases: recs.map(c => ({
      id: c.def.id, note: c.def.note, gallery: c.def.gallery || null, option: c.def.gallery ? null : JSON.parse(c.optionText), animationForced: c.animationForced,
      random: c.def.random || null, palette: c.rec.palette, textStyle: c.rec.textStyle, ground: c.rec.ground, series: [emitSeries(c)],
    })),
    guards,
  };
  const text = fmt(out, '') + '\n';
  must(!text.includes('\\u0000'), 'the fixture holds a \\u0000');
  console.error = quiet.error;
  console.warn = quiet.warn;
  guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.id + ': red ' + g.red + ' in ' + g.cases + ' cases'));
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

// Two of ref.js's mutants survive its random data (upstream.md 8): these cases were found by a search over
// the transcription (mutated vs not) and make them go red; the dist records them like any other case.
function EXTRA() {
  return [
    { id: 'X-guard-f', note: "found by search: squareRatio 0.75, sort false, a 500 x 500 box -- `(rfl * rfl) * ratio` and `rfl * (rfl * ratio)` differ in the last bit and flip one `score <= best`, so the row split changes", option: one({ data: [{ name: 'k0', value: 3 }, { name: 'k1', value: 11 }, { name: 'k2', value: 6 }, { name: 'k3', value: 8 }, { name: 'k4', value: 14 }], squareRatio: 0.75, sort: false, left: 150, right: 150 }) },
    { id: 'X-guard-union', note: "found by search: breadcrumb emptyItemWidth 40.52 with a tail crumb 'mGEDfE' -- the tail bbox's x + width is not its maxX (x0 = 43.52 is below maxX / 2), so zrender's union width differs from maxX in the last bit and moves the group", option: one({ data: [{ name: 'mGEDfE', value: 1 }], breadcrumb: { emptyItemWidth: 40.52 } }) },
  ];
}
