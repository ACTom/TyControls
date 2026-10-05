/*
Upstream's own answers for the TREEMAP series, first static frame (batches M1,
M2 colour saturation, M3 upper labels, M4 drill-down, M5 value-mapped colour,
M6 multi-series / id mapping / alpha / label positions):
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
them. M2 adds treemapVisual.ts buildVisualMapping / mapVisual (a colorSaturation
range mapped linearly by value over the parent's dataExtent), calculateColor and
the borderColorSaturation stroke through zrender color.ts modifyHSL (LIGHTNESS),
and visual/style.ts dataStyleTask (the raw item itemStyle color / borderColor /
opacity override the visual). M3 adds the header Text renderBackground gives a
parent's background rect (prepareText with an upperLabelRect, setLabelStyle,
Element.updateInnerText's inside / outside default colours, ZRText layout). M4
adds leafDepth (isLeafRoot parents drawn as leaves, TreemapView addDrillDownIcon,
the breadcrumb on the view root); M5 the linear colour mapping (colorMappingBy
other than 'index' / 'id': VisualMapping linear + zrender fastLerp), statistic()
over visualDimension (the 'value' shortcut, scalar values, NaN) and visualMin /
visualMax; M6 colorMappingBy 'id' (SeriesData ids, TreemapSeries.mapIdToIndex),
colorAlpha ranges and values (zrender modifyAlpha), a series-level colour list,
the 'inside*' label positions (calculateTextPosition), the RICH text layout any
label.rich switches on (parseRichText / _updateRichTexts), and several series
with a legend (LegendModel's selectedMode 'single' first frame).

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
ORACLE_RANDOM=<n> sets the number of M1 random forests, ORACLE_RANDOM_M23=<n>
the number of M2 / M3 random forests, ORACLE_RANDOM_M456=<n> the number of
M4-M6 random forests, defaults below).

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
            collapsedCrumbs, fallbackRoot, ignoredLabels; over the M2 / M3 cases:
            casesM2, casesM3, saturatedColours, saturationMappedRows,
            borderSaturatedRows, rawItemOverrides, upperHeaders, upperTspans,
            upperTruncatedLines, upperDroppedLines, upperColour_outside /
            _inside / _option; over the M4-M6 cases: casesM4 / M5 / M6,
            leafRoots, drillIconLabels, ignoredIconLabels, crumbOnLeafDepthRoot,
            linearColourRows, linearColourNone, idMappedRows, alphaMappedRows,
            alphaColours, richLabels, labelsNotInside, filteredSeries): minimums
            for the test
  cases[], guards[]

Per case
  id, batch (ONLY on the M2-M6 cases: 'M2' .. 'M6'; a case without it is M1),
  note, gallery (the gallery file name or null), option (the exact JSON fed,
  animation false included; null for a gallery case: load
  examples/advchart/gallery/<gallery>.json and set animation false),
  animationForced, random (null, or {forest, variant, box}; the M2 / M3 random
  families add family 'M23'),
  palette   ecModel.option.color (the global palette setDefault copies; inject it
            as the option's `color` when the option names none)
  textStyle ecModel.option.textStyle (fontFamily 'Microsoft YaHei' here)
  ground    {background (zr.getBackgroundColor()), isDark}: an INPUT of the M3
            header colours (the outside fill and stroke, the inside stroke)
  series[]  one per DRAWN treemap series (seriesIndex says which; every case but
            some M6 ones has exactly one series; a legend may filter series out)
  M6 cases only:
  legend    null or {selectedMode, data (legend item names), selectedFed (the
            option's legend.selected), selected (after LegendModel init)}: in
            'single' mode the FIRST legend item not explicitly false is selected
            and every other one deselected (a `true` elsewhere does not win); a
            series missing from legend.data stays shown
  seriesList[] every series of the option: {seriesIndex, name, legendSelected,
            filtered (ecModel.isSeriesFiltered: no layout, no visual, no element),
            drawn, styleFill (seriesStyleTask's colour: the series' own `color`
            list, else the GLOBAL palette slot by series name -- one per series,
            filtered ones included; never drawn by a treemap)}

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
    M2 / M3 cases only (after label):
    dataExtent  null or [min, max] (hex) + dataExtentText: statistic() over the
              SORTED children BEFORE the visibleMin cut (getValue(0))
    opacity   the node style's opacity (series itemStyle.opacity, then a raw
              item itemStyle.opacity) or null: the labels' default opacity
    visual    null (not visited) or the transcription's account of the colour:
              {colorSaturation (the node's visual, dec, + colorSaturationHex),
              saturationSource ('item' | 'level' | 'mapped' | 'inherited' |
              'series' | 'none'), saturationMappedFrom (the parent row whose range
              mapped it), borderColorSaturation (the chain value or null),
              mapping (the map THIS node gives its children: null or {type
              'colorSaturation', dataExtent (hex) + dataExtentText, range [r0, r1]}),
              fillBeforeRawItem, strokeBeforeRawItem (the treemap visual's own
              colours), rawItem (null or the raw itemStyle {color, borderColor,
              opacity} dataStyleTask applied)}
    upperLabel  null (no header Text) or {rawText, transform (6 hex) +
              transformText, z2, width, height (hex: the text box after padding),
              padding (normalised or null), isTruncated, lines, layoutRect {x, y,
              width, height} (hex, LOCAL to the node: {bw, 0, w - 2bw (NOT clamped),
              upperHeight}) + layoutRectText, anchor {x, y} (hex: the text origin
              before the 5e-5 rule), textAlign, verticalAlign, colourRule
              ('outside' | 'inside' | 'option'), fill, stroke}
    M4 / M5 / M6 cases only (after upperLabel):
    id        the SeriesData id (item id as a string; else the name, its k-th
              repeat suffixed '__ec__' + k counting only rows without an id, row 0
              named by the series name), or null for a generated one ('e' + two NUL
              characters + dataIndex: no id and no name); idSource 'item' | 'name' |
              'nameRepeat' | 'generated'
    visual4   null (not visited) or {colorAlpha (dec) + colorAlphaHex, alphaSource
              ('item' | 'level' | 'mapped' | 'inherited' | 'series' | 'none'),
              alphaMappedFrom, idIndex (mapIdToIndex's answer when the parent maps
              by id), mappedInput (null or {value, normalized} dec + hex: the
              child value getValue(visualDimension) and linearMap(value, extent,
              [0, 1], clamp) when the parent maps linearly), mapping (the map THIS
              node gives: null or {type 'color' | 'colorAlpha' | 'colorSaturation',
              method 'category' | 'linear', by, dimension, dataExtent (hex, after
              visualMin / visualMax) + dataExtentText, list | range})}
    labelInfo null or {position, distance, textAlign, verticalAlign, anchor {x, y}
              (hex: calculateTextPosition over the globalised content rect) +
              anchorText, layout ('plain' | 'rich'), drillIcon}
  elements[] zrender's display list for this series in PAINT order (elements of
    other components, e.g. a gallery title, are left out):
    kind 'bg' | 'content' | 'tspan' | 'upper' | 'crumb' | 'crumbText', row (the node's
    dataIndex; for crumbs the crumb's node), z, z2, zlevel, transform (6 hex or
    null), fill, stroke, lineWidth, lineJoin, opacity,
    bg / content: shape {x, y, width, height, r} (hex)
    crumb:        points [[x, y] hex]
    tspan / crumbText: text, x, y (hex), textAlign, textBaseline, font; a
                  tspan's host label (raw text, box, isTruncated, the kept
                  line count) is rows[row].label
    upper:        the same fields for a header line (M3; its Text hangs off the
                  BACKGROUND rect; host record rows[row].upperLabel)
  breadcrumb null (breadcrumb.show false) or
    target (row), targetRule ('findTarget' | 'fallbackRoot' | 'leafDepthViewRoot':
    a series leafDepth puts the target on the view root), availableWidth
    (hex), height, emptyItemWidth, totalWidth (hex, before collapse),
    items[] root first: {row, text (the chain name), measuredWidth (hex,
      '12px sans-serif' unless breadcrumb.itemStyle.textStyle sets a font),
      itemWidth (hex, after collapse), collapsed, head, tail, points (hex),
      bbox {x, y, width, height} (hex), label ({x, y} hex, or null when the
      crumb has no text)}
    unionRect {x, y, width, height} (hex), groupX, groupY (hex) + groupText (dec)
  labelStats {tspans, truncated, ellipsis, dropped}
  upperStats {headers, tspans, truncated, ellipsis, dropped} and foreignElements
            (display-list elements of other components -- a title, a legend,
            another series -- left out): M2-M6 only

Guards[] one per mutation of the transcription (ref.js's mutants): id,
  mutation, red (the number of recorded checks the mutated transcription gets
  wrong over the whole fixture), cases (how many cases change), sample (the
  first few), ok (red > 0). ref.js's `lt` mutant ('<=' -> '<' in the squarify
  row loop) is NOT a guard: it never terminates (Infinity < Infinity is false
  on a zero-area row, the same child is retried forever).

-----------------------------------------------------------------------------
The transcription (a port of the wf76 / wf77 ref.js re-implementations) takes as
INPUTS only the series option as fed, the canvas size, the global palette, the
global textStyle font family and the ground, and must reproduce EVERY recorded
row, element and breadcrumb field bit for bit (Object.is); any difference stops
the run and nothing is written.

Refused (a case that uses them stops the run): in M1 cases any of
colorSaturation, borderColorSaturation, colorAlpha, upperLabel, leafDepth,
colorMappingBy, visualDimension, visualMin, visualMax, decal; in M2 / M3 cases
still colorAlpha, leafDepth, colorMappingBy, visualDimension, visualMin,
visualMax, decal (M4+), a series-level color list (M6), an upperLabel key other
than show / height / color / fontSize / formatter / padding / position ([x, y] or
'inside') / opacity / verticalAlign ('middle') / overflow ('truncate'), a
non-numeric colorSaturation, and any colour NAME the transcription's parser does
not list (transparent, red, green, blue, white, black). In M4 / M5 / M6 cases:
decal, a content-label key other than show / formatter / fontSize / color /
padding / position ('inside*') / distance / opacity / rich / overflow ('truncate'),
{style|...} markup in a rich label text, a visualDimension other than a
non-negative integer or 'value', non-numeric visualMin / visualMax / colorAlpha /
value entries, an unparsable colour in a linear colour list, a legend or several
series outside M6.
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
const READ_KEYS = ['sort', 'squareRatio', 'leafDepth', 'breadcrumb', 'label', 'upperLabel', 'itemStyle', 'color', 'visibleMin', 'childrenVisibleMin', 'colorMappingBy', 'name',
  'colorSaturation', 'colorAlpha', 'visualDimension', 'visualMin', 'visualMax', 'drillDownIcon'];

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

// ---------- zrender tool/color.ts, the parts the treemap visual and the label colours reach (M2 / M3) ----------
// Colour NAMES are transcribed only for the ones the cases use; any other name stops the run (refused).
const CSS_NAMES = { transparent: [0, 0, 0, 0], red: [255, 0, 0, 1], green: [0, 128, 0, 1], blue: [0, 0, 255, 1], white: [255, 255, 255, 1], black: [0, 0, 0, 1] };
function clampCssByte(i) { i = Math.round(i); return i < 0 ? 0 : i > 255 ? 255 : i; }
function clampCssFloat(f) { return f < 0 ? 0 : f > 1 ? 1 : f; }
function parseCssInt(s) { return (s.length && s.charAt(s.length - 1) === '%') ? clampCssByte(parseFloat(s) / 100 * 255) : clampCssByte(parseInt(s, 10)); }
function parseCssFloat(s) { return (s.length && s.charAt(s.length - 1) === '%') ? clampCssFloat(parseFloat(s) / 100) : clampCssFloat(parseFloat(s)); }
function parseColour(c) {                            // color.parse: [r, g, b, a] or undefined
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
  }
  throw new OracleError('a colour the transcription does not parse: ' + JSON.stringify(c));
}
function cssHueToRgb(m1, m2, h) {
  if (h < 0) h += 1; else if (h > 1) h -= 1;
  if (h * 6 < 1) return m1 + (m2 - m1) * h * 6;
  if (h * 2 < 1) return m2;
  if (h * 3 < 2) return m1 + (m2 - m1) * (2 / 3 - h) * 6;
  return m1;
}

// the legend's first frame (LegendModel init): selectedMode 'single' selects the FIRST legend item (legend.data
// order) that is not explicitly `false` in legend.selected and deselects every other one (a `true` elsewhere
// does not win); a series whose name is missing from legend.data stays shown; without a legend every series
// is drawn. Returns, per series of the option, whether it is drawn (not filtered).
function legendDrawn(option, mut) {
  const M = k => mut === k;
  const series = [].concat(option.series);
  const lg = option.legend ? [].concat(option.legend)[0] : null;
  if (!lg) return series.map(() => true);
  const names = lg.data ? lg.data.map(d => (d && typeof d === 'object' ? d.name : d)) : series.map(s => s.name);
  const sel = Object.assign({}, lg.selected || {});
  const isSel = nm => !(hasOwn(sel, nm) && !sel[nm]);
  if (lg.selectedMode === 'single') {
    let chosen = null;
    if (M('legendfirst')) chosen = Object.keys(sel).find(k => sel[k]) || names[0];
    else for (const nm of names) if (isSel(nm)) { chosen = nm; break; }
    if (chosen == null) chosen = names[0];
    for (const nm of names) sel[nm] = nm === chosen;
  }
  return series.map(s => !(hasOwn(sel, s.name) && !sel[s.name]));
}

// so: the series option as fed; env: {W, H, palette, fontFamily, ground, batch}; mut: a mutant name or null
function transcribe(soIn, env, mut) {
  const M = k => mut === k;
  // M4 / M5 / M6 cases record more (visual mappings, ids, label placement); M1-M3 cases keep their fields
  const ext4 = env.batch === 'M4' || env.batch === 'M5' || env.batch === 'M6';
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
  // M5: TreeNode.getValue(dim) = store.get(getDimensionIndex(dim || 'value'), idx). The store has dimMax
  // dimensions (the longest value array over ALL nodes, the root included, after completeTreeValue); the
  // original-format getter returns a SCALAR value whole for every dimension; null / undefined / '' parse to
  // NaN; a dimension at or past dimMax reads NaN.
  let dimMax = 1;
  (function dm(it) { dimMax = Math.max(dimMax, isArray(it.value) ? it.value.length : 1); for (const c of (it.children || [])) dm(c); })(root);
  const parseDataValue = x => ((x == null || x === '') ? NaN : Number(x));
  const getV = (n, dim) => {
    if (!dim || dim === 'value') return val(n);
    must(typeof dim === 'number' && dim >= 0 && Math.floor(dim) === dim, 'visualDimension ' + JSON.stringify(dim) + ' is not transcribed');
    if (!M('dimmax') && dim >= dimMax) return NaN;
    const v = n.item.value;
    return parseDataValue(isArray(v) ? v[dim] : (M('scalardim') ? undefined : v));
  };
  const storeName = n => (n.item.name == null ? '' : String(n.item.name));
  const chainName = n => { const v = get(n, ['name']); return v == null ? null : String(v); };
  const ground = env.ground || { background: 'transparent', isDark: false };

  // ---- zrender color.ts (M2): modifyHSL(c, null, null, l) = parse -> rgba2hsla -> l -> hsla2rgba -> 'rgba(r,g,b,a)'
  function hsla2rgba(hsla) {
    const h = M('hmod') ? parseFloat(hsla[0]) / 360 : (((parseFloat(hsla[0]) % 360) + 360) % 360) / 360;
    const s = parseCssFloat(hsla[1]); const l = parseCssFloat(hsla[2]);
    const m2 = l <= 0.5 ? l * (s + 1) : l + s - l * s;
    const m1 = l * 2 - m2;
    const cb = M('floor') ? (v => Math.max(0, Math.min(255, Math.floor(v)))) : clampCssByte;
    const out = [cb(cssHueToRgb(m1, m2, h + 1 / 3) * 255), cb(cssHueToRgb(m1, m2, h) * 255), cb(cssHueToRgb(m1, m2, h - 1 / 3) * 255), 1];
    if (hsla.length === 4) out[3] = hsla[3];
    return out;
  }
  function rgba2hsla(rgba) {
    const R = rgba[0] / 255; const G = rgba[1] / 255; const B = rgba[2] / 255;
    const vMin = Math.min(R, G, B); const vMax = Math.max(R, G, B); const delta = vMax - vMin;
    const L = (vMax + vMin) / 2;
    let Hh; let S;
    if (delta === 0) { Hh = 0; S = 0; } else {
      S = L < 0.5 ? delta / (vMax + vMin) : delta / (2 - vMax - vMin);
      const dR = (((vMax - R) / 6) + (delta / 2)) / delta; const dG = (((vMax - G) / 6) + (delta / 2)) / delta; const dB = (((vMax - B) / 6) + (delta / 2)) / delta;
      if (R === vMax) Hh = dB - dG; else if (G === vMax) Hh = (1 / 3) + dR - dB; else if (B === vMax) Hh = (2 / 3) + dG - dR;
      if (Hh < 0) Hh += 1;
      if (Hh > 1) Hh -= 1;
    }
    const out = [Hh * 360, S, L];
    if (rgba[3] != null) out.push(rgba[3]);
    return out;
  }
  const rgbaText = a => 'rgba(' + a[0] + ',' + a[1] + ',' + a[2] + ',' + a[3] + ')';
  function modifyLightness(colour, l) {
    const arr = parseColour(colour);
    if (!colour) return undefined;
    must(arr, 'modifyHSL of an unparsable colour ' + JSON.stringify(colour) + ' (upstream throws)');
    const hsla = rgba2hsla(arr);
    hsla[2] = parseCssFloat(l);
    return rgbaText(hsla2rgba(hsla));
  }
  function lum(colour, bgLum) { const a = parseColour(colour); return a ? (0.299 * a[0] + 0.587 * a[1] + 0.114 * a[2]) * a[3] / 255 + (1 - a[3]) * bgLum : 0; }
  function linearMap(v, d, r) {                      // util/number.ts linearMap(v, d, r, clamp = true)
    const d0 = d[0]; const d1 = d[1]; const r0 = r[0]; const r1 = r[1];
    const sd = d1 - d0; const sr = r1 - r0;
    if (sd === 0) return M('midpoint') ? r0 : (sr === 0 ? r0 : (r0 + r1) / 2);
    if (sd > 0) { if (v <= d0) return r0; else if (v >= d1) return r1; } else if (v >= d0) return r0; else if (v <= d1) return r1;
    return (v - d0) / sd * sr + r0;
  }

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
    // statistic(): over the sorted children, BEFORE visibleMin, by the parent's visualDimension chain: [NaN, NaN]
    // without children; the STRING 'value' with a sort takes [last, first] of the sorted list (reversed for
    // asc); otherwise [min, max] of getValue(dim) (NaN values never enter; [Infinity, -Infinity] when all NaN)
    const dim = get(n, ['visualDimension']);
    let ext;
    if (!vc.length) ext = [NaN, NaN];
    else if (dim === 'value' && orderBy) { ext = [val(vc[vc.length - 1]), val(vc[0])]; orderBy === 'asc' && ext.reverse(); }
    else {
      ext = [Infinity, -Infinity];
      for (const c of (M('extpost') ? [] : vc)) { const v = getV(c, dim); v < ext[0] && (ext[0] = v); v > ext[1] && (ext[1] = v); }
    }
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
    if (M('extpost')) for (const c of vc) { const v = val(c); v < ext[0] && (ext[0] = v); v > ext[1] && (ext[1] = v); }
    if (over) { if (vc.length) n.layout.isLeafRoot = true; vc.length = 0; }
    n.viewChildren = vc;
    n.layout.dataExtent = ext;
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
  const defined = v => ((v != null && v !== 'none') ? v : undefined);        // getValueVisualDefine
  function calcColor(v) {                                                     // calculateColor
    let c = defined(v.color);
    if (c) {
      const a = defined(v.colorAlpha); const s = defined(v.colorSaturation);
      if (M('satnull') ? s != null : s) c = modifyLightness(c, s);          // truthy: a saturation of 0 changes nothing
      if (M('alphanull') ? a != null : a) c = modifyAlpha(c, a);           // M6: after the saturation; truthy (0 changes nothing)
      return c;
    }
    return undefined;
  }
  // zrender modifyAlpha: the PARSED channels with a = clamp(alpha, 0, 1) as 'rgba(r,g,b,a)'; undefined when the
  // colour does not parse (no HSL round trip, no rounding)
  function modifyAlpha(colour, alpha) {
    const arr = parseColour(colour);
    if (arr && alpha != null) { arr[3] = clampCssFloat(alpha); return rgbaText(arr); }
    return undefined;
  }
  // zrender fastLerp (VisualMapping linear colour): value = t * (n - 1); left = floor, right = ceil, p = value - left;
  // channels Math.round(l + (r - l) * p) clamped to 0..255, alpha clamp(l + (r - l) * p, 0, 1) unrounded;
  // undefined when t is not within [0, 1] (NaN included) -> no colour
  function fastLerp(t, colors) {
    if (!(colors && colors.length) || !(t >= 0 && t <= 1)) return undefined;
    const value = t * (colors.length - 1);
    const li = Math.floor(value); const ri = Math.ceil(value);
    const lc = colors[li]; const rc = colors[ri];
    const p = value - li;
    const lerp = (a, b) => (M('lerp') ? a * (1 - p) + b * p : a + (b - a) * p);
    const cb = M('lerpfloor') ? (v => Math.max(0, Math.min(255, Math.floor(v)))) : clampCssByte;
    return rgbaText([cb(lerp(lc[0], rc[0])), cb(lerp(lc[1], rc[1])), cb(lerp(lc[2], rc[2])), clampCssFloat(lerp(lc[3], rc[3]))]);
  }
  // M6: SeriesData ids (dataIndex order): an item id (string, or a number as a string) is kept; otherwise the
  // name (row 0: the series name), from its k-th occurrence suffixed '__ec__' + k (counted only over the rows
  // without an id); a row with neither is 'e\0\0' + dataIndex
  const idText = v => (typeof v === 'string' ? v : typeof v === 'number' ? v + '' : null);
  {
    const repeat = {};
    for (const n of rows) {
      let id = idText(n.item.id);
      n.idSource = 'item';
      const nm = idText(n.depth === 0 ? so.name : n.item.name);
      if (id == null && nm != null) { const k = repeat[nm] = (repeat[nm] || 0) + 1; id = nm; n.idSource = 'name'; if (k > 1 && !M('iddup')) { id += '__ec__' + k; n.idSource = 'nameRepeat'; } }
      if (id == null) { id = 'e\u0000\u0000' + n.idx; n.idSource = 'generated'; }
      n.id = id;
    }
  }
  // TreemapSeries.mapIdToIndex: one map per series model, indices in FIRST-SEEN order over the whole visual
  // traversal (pre-order: a child's index is taken right before its own subtree is visited)
  let idIndexMap = new Map();
  const mapIdToIndex = id => { let k = idIndexMap.get(id); if (k == null) idIndexMap.set(id, k = idIndexMap.size); return k; };
  const rangeOf = (n, name) => { const r = get(n, [name]); return (isArray(r) && r.length) ? { name, range: r } : null; };
  const by0 = nn => get(nn, ['colorMappingBy']);
  (function travel(n, dv, mappedFrom, k, satFrom, x4) {
    if (!n.layout || n.layout.invisible || !n.layout.isInView) return;
    const visuals = Object.assign({}, dv);
    let source = 'none';
    for (const key of ['color', 'colorAlpha', 'colorSaturation']) {
      designated[key] = dv[key];
      const v = get(n, ['itemStyle', key]);
      designated[key] = null;
      v != null && (visuals[key] = v);
    }
    n.visual = {
      colorSaturation: visuals.colorSaturation == null ? null : visuals.colorSaturation,
      saturationSource: pathGet(n.item, ['itemStyle', 'colorSaturation']) != null ? 'item'
        : levels[n.depth] && pathGet(levels[n.depth], ['itemStyle', 'colorSaturation']) != null ? 'level'
        : dv.colorSaturation != null ? (satFrom != null ? 'mapped' : 'inherited')
        : pathGet(S, ['itemStyle', 'colorSaturation']) != null ? 'series' : 'none',
      saturationMappedFrom: satFrom != null && pathGet(n.item, ['itemStyle', 'colorSaturation']) == null && !(levels[n.depth] && pathGet(levels[n.depth], ['itemStyle', 'colorSaturation']) != null) ? satFrom : null,
      borderColorSaturation: null, dataExtent: null, mapping: null, fillBeforeRawItem: null, strokeBeforeRawItem: null, rawItem: null,
    };
    if (pathGet(n.item, ['itemStyle', 'color']) != null) source = 'item';
    else if (levels[n.depth] && pathGet(levels[n.depth], ['itemStyle', 'color']) != null) source = 'level';
    else if (dv.color != null) source = 'designated';
    else if (pathGet(S, ['itemStyle', 'color']) != null) source = 'series';
    n.colour = { source, value: visuals.color == null ? null : visuals.color, mappedFrom: source === 'designated' ? mappedFrom : null };
    n.paletteIndex = mappedFrom != null ? k : null;
    if (ext4) {
      // M6 alpha: item itemStyle.colorAlpha > levels[depth].itemStyle.colorAlpha > mapped / inherited > series
      const itemA = pathGet(n.item, ['itemStyle', 'colorAlpha']) != null;
      const levelA = !!(levels[n.depth] && pathGet(levels[n.depth], ['itemStyle', 'colorAlpha']) != null);
      n.visual4 = {
        colorAlpha: visuals.colorAlpha == null ? null : visuals.colorAlpha,
        alphaSource: itemA ? 'item' : levelA ? 'level' : dv.colorAlpha != null ? (x4 && x4.alphaFrom != null ? 'mapped' : 'inherited') : pathGet(S, ['itemStyle', 'colorAlpha']) != null ? 'series' : 'none',
        alphaMappedFrom: x4 && x4.alphaFrom != null && !itemA && !levelA ? x4.alphaFrom : null,
        mappedInput: x4 && x4.input ? x4.input : null,
        idIndex: x4 && x4.idIndex != null ? x4.idIndex : null,
        mapping: null,
      };
    }
    n.stroke = get(n, ['itemStyle', 'borderColor']);
    // borderColorSaturation (item > level > series itemStyle): the stroke becomes the node colour (after its own
    // saturation) at that LIGHTNESS, or null when the node has no colour
    const bcs = get(n, ['itemStyle', 'borderColorSaturation']);
    if (bcs != null) {
      const c = M('bcsraw') ? defined(visuals.color) : calcColor(visuals);
      n.stroke = c != null ? modifyLightness(c, bcs) : null;
      n.visual.borderColorSaturation = bcs;
    }
    n.visited = true;
    const vc = n.viewChildren;
    if (!vc || !vc.length) { n.fill = calcColor(visuals); return; }
    n.visual.dataExtent = n.layout.dataExtent.slice();
    // buildVisualMapping: this node's chain `color` list; else, when it has a colour, its colorAlpha / colorSaturation range
    const rv = rangeOf(n, 'color') || (visuals.color != null && visuals.color !== 'none' && (M('alpharange') ? (rangeOf(n, 'colorSaturation') || rangeOf(n, 'colorAlpha')) : (rangeOf(n, 'colorAlpha') || rangeOf(n, 'colorSaturation'))));
    let mapping = null;
    if (rv) {
      const ext = n.layout.dataExtent.slice();
      const vmin = M('novmm') ? null : get(n, ['visualMin']); const vmax = M('novmm') ? null : get(n, ['visualMax']);
      vmin != null && vmin < ext[0] && (ext[0] = vmin);
      vmax != null && vmax > ext[1] && (ext[1] = vmax);
      const by = M('byvalue') && by0(n) === 'value' ? 'index' : by0(n);
      if (rv.name === 'color' && (by === 'index' || by === 'id')) {
        mapping = { type: 'color', list: rv.range, by };                               // category, loop: list[k % n]
        if (ext4) n.visual4.mapping = { type: 'color', method: 'category', by, list: json(rv.range) };
      } else if (rv.name === 'color') {
        // M5 linear colour (colorMappingBy anything but 'index' / 'id'): every entry of the list parsed
        // (normalizeVisualRange keeps them all, no pairing for colour); fastLerp over the normalised value
        mapping = { type: 'color', linear: true, ext, parsed: rv.range.map(x => parseColour(x)) };
        must(mapping.parsed.every(Boolean), 'an unparsable colour in a linear colour list (upstream: [0,0,0,1] with a warning)');
        if (ext4) n.visual4.mapping = { type: 'color', method: 'linear', by, dimension: json(get(n, ['visualDimension'])), dataExtent: ext.slice(), list: json(rv.range) };
      } else {
        must(rv.range.every(x => typeof x === 'number'), 'a non-numeric ' + rv.name + ' range');
        const vis = rv.range.slice(0, 2); if (vis.length === 1) vis[1] = vis[0];      // normalizeVisualRange; linear uses [0], [1]
        mapping = { type: rv.name, ext, vis };
        if (rv.name === 'colorSaturation') n.visual.mapping = { type: 'colorSaturation', dataExtent: ext.slice(), range: vis.slice() };
        if (ext4) n.visual4.mapping = { type: rv.name, method: 'linear', dimension: json(get(n, ['visualDimension'])), dataExtent: ext.slice(), range: vis.slice() };
      }
    }
    const vdim = get(n, ['visualDimension']);
    const perParent = M('idperparent') ? new Map() : null;
    vc.forEach((c, i) => {
      const cv = Object.assign({}, M('inherit') ? dv : visuals);
      let sf = null;
      const x4 = {};
      let pk = null;
      if (mapping && mapping.type === 'color' && !mapping.linear) {
        let kk;
        if (mapping.by === 'index' || M('idasindex')) kk = M('index') ? c.idx : i;
        else if (perParent) { kk = perParent.get(c.id); if (kk == null) perParent.set(c.id, kk = perParent.size); }
        else kk = mapIdToIndex(c.id);
        if (mapping.by === 'id') x4.idIndex = kk;
        cv.color = mapping.list[kk % mapping.list.length];
        pk = kk;
      } else if (mapping) {
        const value = M('dim0') ? val(c) : getV(c, vdim);           // child.getValue(visualDimension)
        const t = linearMap(value, mapping.ext, [0, 1]);
        x4.input = { value, normalized: t };
        if (mapping.linear) cv.color = fastLerp(t, mapping.parsed);
        else {
          cv[mapping.type] = linearMap(t, [0, 1], mapping.vis);
          if (mapping.type === 'colorSaturation') sf = n.idx; else x4.alphaFrom = n.idx;
        }
      }
      const colourMapped = mapping && mapping.type === 'color';
      travel(c, cv, colourMapped ? n.idx : null, colourMapped && !mapping.linear ? pk : null, sf, x4);
    });
  })(rows[0], {}, null, null, null, null);
  // a designated colour inherited (not mapped here) keeps mappedFrom null
  // seriesStyleTask: the series itemStyle.opacity (only) reaches every style; then dataStyleTask (4500) extends each
  // style with the RAW item itemStyle: color -> fill, borderColor -> stroke, opacity -> opacity (after the visual)
  for (const n of rows) {
    n.opacity = pathGet(so, ['itemStyle', 'opacity']);
    const raw = n.item.itemStyle;
    if (n.visual) { n.visual.fillBeforeRawItem = n.fill === undefined ? null : n.fill; n.visual.strokeBeforeRawItem = n.stroke; }
    if (raw && isObject(raw) && !M('nodatastyle')) {
      if (n.visual) n.visual.rawItem = { color: json(raw.color), borderColor: json(raw.borderColor), opacity: json(raw.opacity) };
      if (raw.color != null) n.fill = raw.color;
      if (raw.borderColor != null) n.stroke = raw.borderColor;
      if (raw.opacity != null) n.opacity = raw.opacity;
    }
  }

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
  const statMain = stat;
  const ustat = { headers: 0, tspans: 0, truncated: 0, ellipsis: 0, dropped: 0 };
  function labelLines(text, cw, ch, font, padding, sink) {
    const stat = sink || statMain;
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
  // ---- M6: zrender's RICH text layout. Any `label.rich` makes ZRText use _updateRichTexts even for text without
  // {style|...} markup (markup is refused): parseRichText gives one token per '\n' piece; a line is dropped
  // (with all after it) when the accumulated line heights + its own exceed the box height; a token is truncated
  // only when it is WIDER than the box (truncateText2: '' for a zero width, else containerWidth = width - 1,
  // minChar 2, '...'); then boxX / boxY = adjustTextX / Y(0, OUTER size = box + padding, align / verticalAlign),
  // xLeft = boxX + pad[3], lineTop = boxY + pad[0]; a token is placed at xLeft ('left'), xLeft + width
  // ('right') or xLeft + (width - lineWidth) / 2 + tokenWidth / 2 ('center'), y = lineTop + lineHeight / 2.
  function richLayout(text, cw, ch, font, padding, align, vAlign) {
    const width = Math.max(cw - padding[1] - padding[3], 0);
    const height = Math.max(ch - padding[0] - padding[2], 0);
    const str = text != null ? text + '' : '';
    const out = { lines: [], tokens: [], width, height, isTruncated: false };
    if (!str) return out;
    must(!/\{([a-zA-Z0-9_]+)\|([^}]*)\}/.test(str), 'rich markup in a label text is not transcribed: ' + JSON.stringify(str));
    let lines = str.split('\n').map(p => ({ text: p, width: measure(p, font) }));
    const lh = measure('国', font);
    let calcH = 0;
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i];
      if (M('richdrop') ? calcH > height : calcH + lh > height) {
        const before = lines.length;
        lines = lines.slice(0, i);
        out.isTruncated = out.isTruncated || lines.length < before;
        stat.dropped++;
        break;
      }
      if (M('richtrunc') ? width - 1 < t.width : width < t.width) {
        if (!width) t.text = '';
        else {
          const containerWidth = Math.max(0, width - 1);
          let contentWidth = containerWidth;
          const asc = measure('a', font);
          for (let k = 0; k < 2 && contentWidth >= asc; k++) contentWidth -= asc;
          let ell = '...'; let ellW = measure('...', font);
          if (ellW > contentWidth) { ell = ''; ellW = 0; }
          contentWidth = containerWidth - ellW;
          let line = t.text;
          if (!containerWidth) line = '';
          else {
            let lw = measure(line, font);
            if (lw > containerWidth) {
              for (let j = 0; ; j++) {
                if (lw <= contentWidth || j >= 2) { line += ell; break; }
                let sub;
                if (j === 0) { let w = 0; let q = 0; for (const len = line.length; q < len && w < contentWidth; q++) w += charW(font, line.charCodeAt(q)); sub = q; } else sub = lw > 0 ? Math.floor(line.length * contentWidth / lw) : 0;
                line = line.substr(0, sub); lw = measure(line, font);
              }
              out.isTruncated = true;
              stat.truncated++;
              if (ell) stat.ellipsis++;
            }
          }
          t.text = line;
        }
        t.width = measure(t.text, font);
      }
      t.lineHeight = lh;
      calcH += lh;
    }
    const outerWidth = width + (padding[1] + padding[3]);
    const outerHeight = M('richouter') ? calcH + (padding[0] + padding[2]) : height + (padding[0] + padding[2]);
    const boxX = align === 'right' ? 0 - outerWidth : align === 'center' ? 0 - outerWidth / 2 : 0;
    const boxY = vAlign === 'middle' ? 0 - outerHeight / 2 : vAlign === 'bottom' ? 0 - outerHeight : 0;
    const xLeft = boxX + padding[3];
    let lineTop = boxY + padding[0];
    const xRight = xLeft + width;
    for (const t of lines) {
      let x; let a;
      if (!align || align === 'left') { x = xLeft; a = 'left'; } else if (align === 'right') { x = xRight; a = 'right'; } else {
        const lx = xLeft + (width - (xLeft - xLeft) - (xRight - xRight) - t.width) / 2;
        x = lx + t.width / 2; a = 'center';
      }
      out.tokens.push({ text: t.text, x, y: lineTop + t.lineHeight / 2, align: a });
      lineTop += t.lineHeight;
    }
    out.lines = lines.map(t => t.text);
    return out;
  }
  // ---- M3: the upper label (TreemapView renderBackground -> prepareText(bg, borderColour, opacity, upperLabelRect))
  const pctOf = (v, max) => (typeof v === 'string' ? (v.lastIndexOf('%') >= 0 ? parseFloat(v) / 100 * max : parseFloat(v)) : v);   // zrender contain/text parsePercent
  const normCss = v => (typeof v === 'number' ? [v, v, v, v] : v.length === 2 ? [v[0], v[1], v[0], v[1]] : v.length === 3 ? [v[0], v[1], v[2], v[1]] : v);
  function insideTextFill(pathFill) {                // Path.getInsideTextFill: by the luminance of the background fill
    if (M('insidefill')) return '#333';
    if (pathFill !== 'none') {
      if (typeof pathFill === 'string') { const l = lum(pathFill, 0); return l > 0.5 ? '#333' : l > 0.2 ? '#eee' : '#ccc'; }
      if (pathFill) return '#ccc';
    }
    return '#333';
  }
  function insideTextStroke(pathFill, textFill) {    // Path.getInsideTextStroke: the background colour when label and mode agree
    if (typeof pathFill === 'string') { const darkLabel = lum(textFill, 0) < 0.4; if (ground.isDark === darkLabel) return pathFill; }
    return undefined;
  }
  function outsideTextStroke() {                     // Element.getOutsideStroke: the canvas background over white (black in dark mode)
    let arr = typeof ground.background === 'string' && parseColour(ground.background);
    if (!arr) arr = [255, 255, 255, 1];
    const alpha = arr[3];
    for (let i = 0; i < 3; i++) arr[i] = M('bgalpha') ? arr[i] : arr[i] * alpha + (ground.isDark && !M('nodark') ? 0 : 255) * (1 - alpha);
    arr[3] = 1;
    return rgbaText(arr);
  }
  function upper(n, T, w, bw, depth) {
    const uh = n.layout.upperHeight;
    const rect = { x: bw, y: 0, width: w - 2 * bw, height: M('upperulh') ? n.layout.upperLabelHeight : uh };      // NOT clamped
    // text: upperLabel.formatter, else (getFormattedLabel) label.formatter, else the chain name
    const fmt = get(n, ['upperLabel', 'formatter']) || (M('upperfmt') ? null : get(n, ['label', 'formatter']));
    let text = typeof fmt === 'string' ? formatTpl(fmt, { seriesName, name: storeName(n), value: n.item.value }) : undefined;
    if (text == null) text = chainName(n);
    const fsz = get(n, ['upperLabel', 'fontSize']) || 12;
    const font = 'normal normal ' + fsz + 'px ' + family;
    const padOpt = get(n, ['upperLabel', 'padding']);
    const pad = normCss(padOpt || 0);
    // the layout rect through the background's transform (BoundingRect.applyTransform: a negative width flips)
    let gx; let gy; let gw; let gh;
    if (T) {
      gx = rect.x * 1 + T[0]; gy = rect.y * 1 + T[1]; gw = rect.width * 1; gh = rect.height * 1;
      if (gw < 0 && !M('nonorm')) { gx += gw; gw = -gw; }
      if (gh < 0) { gy += gh; gh = -gh; }
    } else { gx = rect.x; gy = rect.y; gw = rect.width; gh = rect.height; }
    const position = get(n, ['upperLabel', 'position']);
    let x; let y; let cAlign; let cV;
    if (isArray(position)) { x = gx + pctOf(position[0], gw); y = gy + pctOf(position[1], gh); cAlign = null; cV = null; }
    else if (position === 'inside') { x = gx + gw / 2; y = gy + gh / 2; cAlign = 'center'; cV = 'middle'; }
    else must(false, 'upperLabel.position ' + JSON.stringify(position) + ' is not transcribed');
    const LT = composeT(null, x, y).T;
    const L = labelLines(text, rect.width, rect.height, font, pad, ustat);
    const align = cAlign || 'left';
    const vAlign = get(n, ['upperLabel', 'verticalAlign']) || cV || 'top';
    must(vAlign === 'middle', 'upperLabel verticalAlign ' + vAlign + ' is not transcribed');
    let ty = 0 - L.contentHeight / 2 + L.lh / 2;
    const tx = padOpt ? (align === 'center' ? 0 + pad[3] / 2 - pad[1] / 2 : 0 + pad[3]) : 0;
    // colour: an option colour ('inherit' -> the border colour) is used as is and gets no stroke; otherwise the
    // default fill / stroke of the text position: 'inside' by the background's luminance, anything else 'outside'
    const colorOpt = get(n, ['upperLabel', 'color']);
    const inheritColor = n.stroke;
    let styleFill = colorOpt;
    if (styleFill === 'inherit' || styleFill === 'auto') styleFill = inheritColor || null;
    // Element.updateInnerText: inside = a string position containing 'inside' AND canBeInsideText() = Path.hasFill()
    // (the background fill, i.e. the border colour, is neither null nor 'none'); otherwise the outside rule
    const bgHasFill = n.stroke != null && n.stroke !== 'none';
    const inside = M('arrayinside') ? bgHasFill : !M('upperinside') && typeof position === 'string' && position.indexOf('inside') >= 0 && (bgHasFill || M('nohasfill'));
    let dFill; let dStroke;
    if (inside) { dFill = insideTextFill(n.stroke); dStroke = insideTextStroke(n.stroke, dFill); }
    else {
      const of = colorOpt === 'inherit' ? (inheritColor || null) : 'auto';
      dFill = (of == null || of === 'auto') ? (ground.isDark && !M('nodark') ? '#ccc' : '#333') : of;
      dStroke = outsideTextStroke();
    }
    dFill = dFill || '#000';
    const useDefault = styleFill == null;
    const fillIn = useDefault ? dFill : styleFill;
    const fill = (fillIn == null || fillIn === 'none') ? null : fillIn;
    const strokeIn = (useDefault || M('autostroke')) ? dStroke : null;
    const stroke = (strokeIn == null || strokeIn === 'transparent' || strokeIn === 'none') ? null : strokeIn;
    const uop = get(n, ['upperLabel', 'opacity']);
    const opacity = uop != null ? uop : (n.opacity != null ? n.opacity : 1);
    const z2 = M('z2') ? depth * 100 + 22 : maxZ2 + 2;
    n.upperLabel = {
      rawText: text == null ? null : text, transform: m6T(LT), z2, width: L.width, height: L.height, padding: padOpt == null ? null : (padOpt ? pad : padOpt), isTruncated: L.isTruncated, lines: L.lines.slice(),
      layoutRect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }, anchor: { x, y }, textAlign: align, verticalAlign: vAlign,
      colourRule: useDefault ? (inside ? 'inside' : 'outside') : 'option', fill, stroke,
    };
    ustat.headers++;
    for (const line of L.lines) {
      els.push({ kind: 'upper', row: n.idx, z: 0, z2, zlevel: 0, transform: m6T(LT), fill, stroke, lineWidth: stroke ? 2 : 1, lineJoin: null, opacity, text: line, x: tx, y: ty, textAlign: align, textBaseline: 'middle', font });
      ustat.tspans++;
      ty += L.lh;
    }
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
    n.upperLabel = null;
    // renderBackground(group, bg, isParent && upperLabelHeight): only a PARENT whose chain upperLabel.show gave a
    // non-zero upperLabelHeight carries a header Text on its background
    if (M('upperleaf') ? n.layout.upperLabelHeight : (isParent && n.layout.upperLabelHeight)) upper(n, T, w, bw, depth);
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
        let t0 = typeof fmt0 === 'string' ? formatTpl(fmt0, { seriesName, name: storeName(n), value: n.item.value }) : null;
        // M4: addDrillDownIcon runs on the IGNORED Text too (its text is the formatter's, never the chain name)
        if (t0 != null && n.layout.isLeafRoot && !M('noicon') && !M('iconignored') && S.drillDownIcon) t0 = S.drillDownIcon + ' ' + t0;
        n.label = { rawText: t0, ignore: true, transform: null, z2: M('z2') ? z2c + 2 : maxZ2 + 2, width: null, height: null, padding: json(get(n, ['label', 'padding'])), isTruncated: false, lines: [] };
      }
      if (showNormal) {
        const fmt = get(n, ['label', 'formatter']);
        let text = typeof fmt === 'string' ? formatTpl(fmt, { seriesName, name: storeName(n), value: n.item.value }) : undefined;
        if (text == null) text = chainName(n);
        // M4 addDrillDownIcon: a leaf root's text (any non-null text, '' included) gets the series' OWN
        // drillDownIcon + ' ' when that icon is truthy
        let iconed = false;
        if (text != null && n.layout.isLeafRoot && !M('noicon') && S.drillDownIcon) { text = S.drillDownIcon + ' ' + text; iconed = true; }
        const fsz = get(n, ['label', 'fontSize']) || 12;
        const font = 'normal normal ' + fsz + 'px ' + family;
        const tx = T ? T[0] : 0; const ty = T ? T[1] : 0;
        // the layout rect = the content rect through the group transform; calculateTextPosition (M6: every
        // 'inside*' position; distance = label.distance, treemap default 0)
        const position = get(n, ['label', 'position']);
        const distance = get(n, ['label', 'distance']);
        let rx; let ry; let align; let vAlign;
        if (position === 'inside' || M('itlinside')) {
          rx = M('ordx') ? bw + (tx + cw / 2) : (bw * 1 + tx) + cw / 2;
          ry = (bw * 1 + ty) + ch / 2;
          align = 'center'; vAlign = 'middle';
        } else {
          const d = distance != null ? distance : 5;
          rx = bw * 1 + tx; ry = bw * 1 + ty; align = 'left'; vAlign = 'top';
          switch (position) {
            case 'insideLeft': rx += d; ry += ch / 2; vAlign = 'middle'; break;
            case 'insideRight': rx += cw - d; ry += ch / 2; align = 'right'; vAlign = 'middle'; break;
            case 'insideTop': rx += cw / 2; ry += d; align = 'center'; break;
            case 'insideBottom': rx += cw / 2; ry += ch - d; align = 'center'; vAlign = 'bottom'; break;
            case 'insideTopLeft': rx += d; ry += d; break;
            case 'insideTopRight': rx += cw - d; ry += d; align = 'right'; break;
            case 'insideBottomLeft': rx += d; ry += ch - d; vAlign = 'bottom'; break;
            case 'insideBottomRight': rx += cw - d; ry += ch - d; align = 'right'; vAlign = 'bottom'; break;
            default: must(false, 'label.position ' + JSON.stringify(position) + ' is not transcribed');
          }
        }
        const LT = composeT(null, rx, ry).T;
        let pad = get(n, ['label', 'padding']);
        pad = isArray(pad) ? (pad.length === 2 ? [pad[0], pad[1], pad[0], pad[1]] : pad.length === 3 ? [pad[0], pad[1], pad[2], pad[1]] : pad) : [pad, pad, pad, pad];
        const rich = get(n, ['label', 'rich']);
        const isRich = !!rich && isObject(rich) && !M('norich');
        const L = isRich ? richLayout(text, cw, ch, font, pad, align, vAlign) : labelLines(text, cw, ch, font, pad);
        const z2l = M('z2') ? z2c + 2 : maxZ2 + 2;
        n.label = { rawText: text == null ? null : text, ignore: false, transform: m6T(LT), z2: z2l, width: L.width, height: L.height, padding: pad, isTruncated: L.isTruncated, lines: L.lines.slice() };
        if (ext4) n.labelInfo = { position: json(position), distance: json(distance), textAlign: align, verticalAlign: vAlign, anchor: { x: rx, y: ry }, layout: isRich ? 'rich' : 'plain', drillIcon: iconed };
        const fill = get(n, ['label', 'color']);
        // the label opacity: label.opacity, else the node style's opacity (defaultOpacity), else the TSpan default 1
        const lop = get(n, ['label', 'opacity']);
        const opacity = lop != null ? lop : (n.opacity != null && !M('noopacity') ? n.opacity : 1);
        if (isRich) {
          for (const t of L.tokens) {
            els.push({ kind: 'tspan', row: n.idx, z: 0, z2: z2l, zlevel: 0, transform: m6T(LT), fill, stroke: null, lineWidth: 1, lineJoin: null, opacity, text: t.text, x: t.x, y: t.y, textAlign: t.align, textBaseline: 'middle', font });
            stat.tspans++;
          }
        } else {
          // ZRText plain: y = adjustTextY(0, contentHeight, verticalAlign) + lh / 2 (+ pad[0] for top, - pad[2]
          // for bottom); x = getTextXForPadding(0, align, pad)
          let y = (vAlign === 'middle' ? 0 - L.contentHeight / 2 : vAlign === 'bottom' ? 0 - L.contentHeight : 0) + L.lh / 2;
          if (vAlign === 'top') y += pad[0]; else if (vAlign === 'bottom') y -= pad[2];
          const x = align === 'right' ? 0 - pad[1] : align === 'center' ? 0 + pad[3] / 2 - pad[1] / 2 : 0 + pad[3];
          for (const line of L.lines) {
            els.push({ kind: 'tspan', row: n.idx, z: 0, z2: z2l, zlevel: 0, transform: m6T(LT), fill, stroke: null, lineWidth: 1, lineJoin: null, opacity, text: line, x, y, textAlign: align, textBaseline: 'middle', font });
            stat.tspans++;
            y += L.lh;
          }
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
    if (leafDepth != null && !M('ldcrumb')) {
      // M4: seriesModel.get('leafDepth', true) != null -> the target is the view root (the tree root on frame 1)
      target = rows[0]; targetRule = 'leafDepthViewRoot';
    } else {
      (function find(n) {
        if (!n.layout || n.layout.invisible) return;  // no background element: nothing below it has one either
        const qx = M('global') ? px - (n.T ? n.T[0] : 0) : px; const qy = M('global') ? py - (n.T ? n.T[1] : 0) : py;
        if (0 <= qx && qx <= 0 + n.layout.width && 0 <= qy && qy <= 0 + n.layout.height) { target = n; for (const c of (n.viewChildren || [])) find(c); }
      })(rows[0]);
      if (!target) { target = rows[0]; targetRule = 'fallbackRoot'; }
    }
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
      // M2 / M3 extras (emitted for batch cases only)
      dataExtent: n.layout && n.layout.dataExtent ? n.layout.dataExtent.slice() : null,
      opacity: n.visited ? (n.opacity === undefined ? null : n.opacity) : null,
      visual: n.visited ? n.visual : null,
      upperLabel: n.upperLabel || null,
      // M4-M6 extras (emitted for M4 / M5 / M6 cases only)
      id: n.id, idSource: n.idSource,
      visual4: n.visited && n.visual4 ? n.visual4 : null,
      labelInfo: n.labelInfo || null,
    })),
    elements,
    breadcrumb: crumb,
    labelStats: stat,
    upperStats: ustat,
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
function readTreemap(chart, fedSeries, si) {
  si = si || 0;
  const ec = chart.getModel();
  const zr = chart.getZr();
  const list = zr.storage.getDisplayList(true);
  const sm = ec.getSeriesByIndex(si);
  must(sm && sm.subType === 'treemap', 'series ' + si + ' is not a treemap');
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
    let upperLabel = null;
    const bt = bg && bg.getTextContent();
    if (bt) {
      const kids = bt.childrenRef();
      for (const k of kids) kindOf.set(k, { kind: 'upper', row: i });
      const lr = bg.textConfig && bg.textConfig.layoutRect;
      must(lr, 'row ' + i + ': a background Text without a layoutRect');
      must(!bt.invisible && !bt.ignore, 'row ' + i + ': an invisible or ignored upper label');
      upperLabel = { rawText: bt.style.text == null ? null : bt.style.text, transform: m6(bt.transform), z2: bt.z2, width: json(bt.style.width), height: json(bt.style.height),
        padding: json(bt.style.padding), isTruncated: !!bt.isTruncated, lines: kids.map(k => k.style.text), layoutRect: { x: lr.x, y: lr.y, width: lr.width, height: lr.height } };
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
      dataExtent: L && L.dataExtent ? L.dataExtent.slice() : null,
      opacity: visited ? json(st.opacity) : null,
      upperLabel,
      valueWritten: written[i].value,
      hasWrittenValue: hasOwn(written[i], 'value'),
      hasGroup: !!g,
      id: data.getId(i),
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
  // the display list: every element under the series view must be one of ours; anything else (a gallery title)
  // belongs to another component and is left out
  const ours = new Set();
  (function walk(g) {
    for (const c of g.childrenRef()) {
      if (c.isGroup) walk(c); else ours.add(c);
      const t = c.getTextContent && c.getTextContent();
      if (t) for (const k of t.childrenRef()) ours.add(k);
    }
  })(view.group);
  const foreign = list.filter(el => !ours.has(el)).length;
  const elements = list.filter(el => ours.has(el)).map((el, i) => {
    const k = kindOf.get(el);
    must(k, 'display list #' + i + ': an unexpected ' + el.type + ' (z2 ' + el.z2 + ')');
    const e = Object.assign({ kind: k.kind, row: k.row, z: el.z, z2: el.z2, zlevel: el.zlevel, transform: m6(el.transform) }, styleOf(el));
    if (el.type === 'rect') {
      must(k.kind === 'bg' || k.kind === 'content', 'a rect of kind ' + k.kind);
      e.shape = { x: el.shape.x, y: el.shape.y, width: el.shape.width, height: el.shape.height, r: el.shape.r };
    } else if (el.type === 'polygon') {
      e.points = el.shape.points.map(p => [p[0], p[1]]);
    } else if (el.type === 'tspan') {
      must(k.kind === 'tspan' || k.kind === 'upper' || k.kind === 'crumbText', 'a tspan of kind ' + k.kind);
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
    rows, elements, breadcrumb, foreign,
  };
}

// the fields both sides produce, in one shape (raw numbers); compared with Object.is
function upstreamView(u) {
  return {
    box: u.box,
    levels: u.levelsAfter,
    rows: u.rows.map(r => ({ index: r.index, name: r.name, valueCompleted: r.valueCompleted, value: r.value, depth: r.depth, height: r.height, parent: r.parent, children: r.children,
      layout: r.layout, viewChildren: r.viewChildren, stroke: r.stroke, fill: r.fill, T: r.T, label: r.label, dataExtent: r.dataExtent, opacity: r.opacity, upperLabel: r.upperLabel, id: r.id })),
    elements: u.elements,
    breadcrumb: u.breadcrumb,
  };
}
function transcribedView(t) {
  return {
    box: t.resolved.box,
    levels: t.resolved.levels,
    rows: t.rows.map(r => ({ index: r.index, name: r.name, valueCompleted: r.valueCompleted, value: r.value, depth: r.depth, height: r.height, parent: r.parent, children: r.children,
      layout: r.layout, viewChildren: r.viewChildren, stroke: r.stroke, fill: r.fill, T: r.T, label: r.label, dataExtent: r.dataExtent, opacity: r.opacity,
      upperLabel: r.upperLabel ? { rawText: r.upperLabel.rawText, transform: r.upperLabel.transform, z2: r.upperLabel.z2, width: r.upperLabel.width, height: r.upperLabel.height,
        padding: r.upperLabel.padding, isTruncated: r.upperLabel.isTruncated, lines: r.upperLabel.lines, layoutRect: r.upperLabel.layoutRect } : null, id: r.id })),
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
// M1 cases: none of these may appear anywhere in the series option
const M2PLUS = ['colorSaturation', 'borderColorSaturation', 'colorAlpha', 'upperLabel', 'leafDepth', 'colorMappingBy', 'visualDimension', 'visualMin', 'visualMax', 'decal'];
// M2 / M3 cases: still refused (M4+), anywhere in the series option
const M4PLUS = ['colorAlpha', 'leafDepth', 'colorMappingBy', 'visualDimension', 'visualMin', 'visualMax', 'decal'];
// the upperLabel keys the transcription follows (position: [x, y] or 'inside'; verticalAlign: 'middle'; overflow: 'truncate')
const UPPER_KEYS = ['show', 'height', 'color', 'fontSize', 'formatter', 'padding', 'position', 'opacity', 'verticalAlign', 'overflow'];
function m1Violations(o, where, out, list) {
  list = list || M2PLUS;
  if (isArray(o)) { o.forEach((x, i) => m1Violations(x, where + '[' + i + ']', out, list)); return out; }
  if (!isObject(o)) return out;
  for (const k of Object.keys(o)) {
    if (list.includes(k) && o[k] != null) out.push(where + '.' + k);
    if (list !== M2PLUS && k === 'upperLabel' && isObject(o[k])) {
      const u = o[k];
      for (const kk of Object.keys(u)) if (!UPPER_KEYS.includes(kk)) out.push(where + '.upperLabel.' + kk);
      if (u.position != null && !(u.position === 'inside' || (isArray(u.position) && u.position.length === 2))) out.push(where + '.upperLabel.position');
      if (u.verticalAlign != null && u.verticalAlign !== 'middle') out.push(where + '.upperLabel.verticalAlign');
      if (u.overflow != null && u.overflow !== 'truncate') out.push(where + '.upperLabel.overflow');
      if (u.height != null && typeof u.height !== 'number') out.push(where + '.upperLabel.height (not a number)');
    }
    if (list !== M2PLUS && k === 'colorSaturation' && o[k] != null && !(typeof o[k] === 'number' || (isArray(o[k]) && o[k].every(x => typeof x === 'number')))) out.push(where + '.colorSaturation (not numeric)');
    m1Violations(o[k], where + '.' + k, out, list);
  }
  return out;
}

// M4 / M5 / M6 cases: still refused anywhere in a series option
const M7PLUS = ['decal'];
// the content-label keys the transcription follows in M4-M6 cases (position: 'inside*'; rich: a style map that
// only switches the layout, markup refused; overflow 'truncate')
const LABEL_KEYS = ['show', 'formatter', 'fontSize', 'color', 'padding', 'position', 'distance', 'opacity', 'rich', 'overflow'];
const INSIDE_POSITIONS = ['inside', 'insideLeft', 'insideRight', 'insideTop', 'insideBottom', 'insideTopLeft', 'insideTopRight', 'insideBottomLeft', 'insideBottomRight'];
function m4Violations(o, where, out) {
  m1Violations(o, where, out, M7PLUS);
  (function walk(v, w) {
    if (isArray(v)) { v.forEach((x, i) => walk(x, w + '[' + i + ']')); return; }
    if (!isObject(v)) return;
    for (const k of Object.keys(v)) {
      const x = v[k];
      if (k === 'label' && isObject(x) && !w.endsWith('emphasis') && !w.endsWith('blur') && !w.endsWith('select')) {
        for (const kk of Object.keys(x)) if (!LABEL_KEYS.includes(kk)) out.push(w + '.label.' + kk);
        if (x.position != null && !INSIDE_POSITIONS.includes(x.position)) out.push(w + '.label.position');
        if (x.overflow != null && x.overflow !== 'truncate') out.push(w + '.label.overflow');
      }
      if (k === 'visualDimension' && x != null && !(x === 'value' || (typeof x === 'number' && x >= 0 && Math.floor(x) === x))) out.push(w + '.visualDimension');
      if ((k === 'visualMin' || k === 'visualMax') && x != null && typeof x !== 'number') out.push(w + '.' + k);
      if ((k === 'colorAlpha' || k === 'colorSaturation') && x != null && !(typeof x === 'number' || (isArray(x) && x.every(y => typeof y === 'number')))) out.push(w + '.' + k + ' (not numeric)');
      if (k === 'value' && isArray(x) && !x.every(y => y == null || typeof y === 'number')) out.push(w + '.value (not numeric)');
      if (k !== 'rich') walk(x, w + '.' + k);               // rich styles only switch the layout (markup is refused)
    }
  })(o, where);
  return out;
}

function recordCase(def, withProd) {
  const opt = def.gallery ? gallery(def.gallery) : zrClone(def.option);
  const animationForced = opt.animation !== false;
  opt.animation = false;
  const optionText = JSON.stringify(opt);
  const fed = JSON.parse(optionText);
  const ext4 = def.batch === 'M4' || def.batch === 'M5' || def.batch === 'M6';
  const fedList = [].concat(fed.series);
  must(fedList.length >= 1 && (fedList.length === 1 || def.batch === 'M6'), 'one treemap series per case (several: M6 only)');
  fedList.forEach((s, i) => must(s && s.type === 'treemap', 'series ' + i + ' is not a treemap'));
  must(!fed.legend || def.batch === 'M6', 'a legend outside M6');
  fedList.forEach((s, i) => {
    const viol = ext4 ? m4Violations(s, 'series[' + i + ']', []) : m1Violations(s, 'series[' + i + ']', [], def.batch ? M4PLUS : M2PLUS);
    must(!viol.length, (ext4 ? 'a key not transcribed: ' : def.batch ? 'an M4+ key: ' : 'an M2+ key: ') + viol.join(', '));
    must(ext4 || !(isArray(s.color) && s.color.length), 'a series-level colour list (M6)');
  });
  const fedSeries = fedList[0];
  // the sort key as fed, BEFORE any JSON round trip
  const srcList = def.gallery ? fedList : [].concat(def.option.series);
  const sortKeyPresent = hasOwn(srcList[0], 'sort');
  const readAll = (E, chart) => {
    const ec = chart.getModel();
    const lg = ec.getComponent('legend');
    const seriesList = fedList.map((s, i) => {
      const sm = ec.getSeriesByIndex(i);
      const st = sm.getData().getVisual('style');
      return { seriesIndex: i, name: s.name == null ? null : String(s.name), legendSelected: lg ? lg.isSelected(sm.name) : null, filtered: ec.isSeriesFiltered(sm), styleFill: json(st && st.fill) };
    });
    const us = [];
    seriesList.forEach(sl => {
      if (sl.filtered) return;
      const u = readTreemap(chart, fedList[sl.seriesIndex], sl.seriesIndex);
      u.seriesIndex = sl.seriesIndex;
      us.push(u);
    });
    seriesList.forEach(sl => { sl.drawn = us.some(u => u.seriesIndex === sl.seriesIndex && u.elements.length > 0); });
    const legend = lg ? { selectedMode: json(lg.option.selectedMode), data: lg.getData().map(m => m.get('name')), selectedFed: json([].concat(fed.legend)[0].selected), selected: json(lg.option.selected) } : null;
    return { us, seriesList, legend };
  };
  const rec = runChart(echarts, JSON.parse(optionText), chart => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const all = readAll(echarts, chart);
    for (const u of all.us) {
      for (const k of READ_KEYS) {
        const want = zrMerge(zrClone(fedList[u.seriesIndex]), TM_DEFAULTS, false)[k];
        must(JSON.stringify(json(u.merged[k])) === JSON.stringify(json(want)), 'the merged option ' + k + ' is not the fed option over the defaults: ' + JSON.stringify(u.merged[k]) + ' vs ' + JSON.stringify(want));
      }
      delete u.merged;
      must(!u.foreign || def.gallery || fedList.length > 1 || fed.legend, 'elements of another component in a hand-written case');
    }
    must(all.us.length >= 1, 'no treemap series is drawn');
    return { palette: json(ec.option.color), textStyle: json(ec.option.textStyle), ground: { background: json(zr.getBackgroundColor()), isDark: !!zr.isDarkMode() }, u: all.us[0], us: all.us, seriesList: all.seriesList, legend: all.legend };
  });
  if (withProd) {
    const p = runChart(PROD, JSON.parse(optionText), chart => readAll(PROD, chart));
    p.us.forEach(u => delete u.merged);
    const a = JSON.stringify(rec.us.map(u => flat(upstreamView(u), 's', {})).concat([rec.seriesList, rec.legend]));
    const b = JSON.stringify(p.us.map(u => flat(upstreamView(u), 's', {})).concat([p.seriesList, p.legend]));
    must(a === b, 'the production build records differently');
  }
  const env = { W, H, palette: rec.palette, fontFamily: rec.textStyle.fontFamily, ground: rec.ground, batch: def.batch };
  must(typeof env.fontFamily === 'string', 'no global fontFamily');
  return { def, optionText, animationForced, sortKeyPresent, fedSeries, fedList, fed, env, rec, srcList };
}
// the transcription of a whole case: which series the legend lets draw, then each drawn series
function transcribeCase(c, mut) {
  const drawn = legendDrawn(c.fed, mut);
  const trs = [];
  drawn.forEach((d, i) => { if (d) { const t = transcribe(c.fedList[i], c.env, mut); t.seriesIndex = i; trs.push(t); } });
  return { drawn, trs };
}
function caseViewUp(c) {
  const o = { drawn: c.rec.seriesList.map(s => !s.filtered) };
  c.rec.us.forEach(u => { o['s' + u.seriesIndex] = upstreamView(u); });
  return o;
}
function caseViewTr(t) {
  const o = { drawn: t.drawn };
  t.trs.forEach(x => { o['s' + x.seriesIndex] = transcribedView(x); });
  return o;
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
  // M2
  ['extpost', 'M2: the saturation dataExtent taken AFTER the visibleMin cut (upstream: before)'],
  ['satnull', 'M2: calculateColor applies a colorSaturation of 0 (upstream: truthiness, 0 changes nothing)'],
  ['midpoint', 'M2: a degenerate dataExtent (min == max) maps to range[0] (upstream: linearMap gives 0.5, the middle of the range)'],
  ['bcsraw', "M2: borderColorSaturation applied to the node's raw colour (upstream: to calculateColor, after its own saturation)"],
  ['nodatastyle', "M2: no dataStyleTask (the raw item itemStyle color / borderColor / opacity would not override the visual)"],
  ['noopacity', "M2: the content label ignores the node style's opacity"],
  ['hmod', 'M2: hsla2rgba takes h = H / 360 without ((H % 360) + 360) % 360'],
  ['floor', 'M2: hsla2rgba truncates the channels (upstream: Math.round, then clamp)'],
  // M3
  ['upperleaf', 'M3: a header on every node with an upperLabelHeight, leaves included (upstream: parents only)'],
  ['upperulh', 'M3: the header rect height is upperLabelHeight (upstream: upperHeight = max(borderWidth, upperLabelHeight))'],
  ['upperfmt', 'M3: no label.formatter fallback for the header text'],
  ['nonorm', 'M3: a negative header rect width is not flipped by BoundingRect.applyTransform'],
  ['upperinside', "M3: position 'inside' coloured by the outside rule"],
  ['arrayinside', "M3: the default position [0, '50%'] coloured by the inside (luminance) rule"],
  ['insidefill', "M3: the inside fill ignores the background's luminance"],
  ['nohasfill', "M3: 'inside' used over a background with no fill (upstream: Path.canBeInsideText is hasFill, so the outside rule applies)"],
  ['autostroke', 'M3: an option colour keeps the auto stroke'],
  ['nodark', 'M3: dark mode ignored in the outside colour'],
  ['bgalpha', "M3: the outside stroke ignores the background's alpha (no blend over white)"],
  // M4
  ['noicon', 'M4: no drillDownIcon prefix on leaf roots'],
  ['iconignored', 'M4: the ignored label Text of a leaf root gets no icon'],
  ['ldcrumb', 'M4: with leafDepth the breadcrumb target is still found by findTarget (upstream: the view root)'],
  // M5
  ['scalardim', 'M5: a scalar value reads NaN at dimensions > 0 (upstream: the scalar answers every dimension)'],
  ['dimmax', 'M5: a dimension past the stored ones reads the value (upstream: NaN)'],
  ['byvalue', "M5: colorMappingBy 'value' maps the colour list by index"],
  ['lerp', 'M5: fastLerp as a * (1 - p) + b * p (upstream: a + (b - a) * p)'],
  ['lerpfloor', 'M5: fastLerp truncates the channels (upstream: Math.round, then clamp)'],
  ['dim0', 'M5: the mapped value ignores visualDimension (reads dimension 0)'],
  ['novmm', 'M5: visualMin / visualMax do not widen the extent'],
  // M6
  ['alphanull', 'M6: calculateColor applies a colorAlpha of 0 (upstream: truthiness)'],
  ['alpharange', 'M6: a colorSaturation range wins over a colorAlpha range (upstream: alpha first)'],
  ['iddup', "M6: repeated names keep the bare name as id (upstream: '__ec__' + k)"],
  ['idasindex', "M6: colorMappingBy 'id' maps by the sorted index"],
  ['idperparent', "M6: mapIdToIndex restarts for every parent (upstream: one map per series)"],
  ['legendfirst', "M6: legend 'single' picks the first explicitly selected item (upstream: the first not explicitly false)"],
  ['norich', 'M6: a label.rich keeps the plain text layout'],
  ['richtrunc', 'M6: the rich layout truncates like the plain one (upstream: only a token wider than the box)'],
  ['richdrop', 'M6: the rich line drop ignores the current line height'],
  ['richouter', 'M6: the rich box is placed by its content height (upstream: the outer box = height + padding)'],
  ['itlinside', "M6: every label position is treated as 'inside'"],
];

// ============================================================================
// Output
// ============================================================================
function hexArr(a) { return a ? a.map(hexOrNull) : null; }
function emitSeries(c, sk) {
  const u = c.rec.us[sk];
  const t = c.tc.trs[sk];
  const ext4 = c.def.batch === 'M4' || c.def.batch === 'M5' || c.def.batch === 'M6';
  const numOut = v => (v == null ? null : dec(v));
  const hexOut = v => (typeof v === 'number' ? hex(v) : null);
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
    if (c.def.batch) {
      // M2: dataExtent (hex [min, max] over the sorted children before visibleMin), the node style opacity,
      // and the transcription's account of the colour (visual); M3: the header Text on the background
      const ext = r.dataExtent;
      o.dataExtent = ext ? ext.map(hex) : null;
      o.dataExtentText = ext ? ext.map(dec) : null;
      o.opacity = r.opacity;
      const v = tr.visual;
      o.visual = v ? {
        colorSaturation: v.colorSaturation == null ? null : dec(v.colorSaturation), colorSaturationHex: typeof v.colorSaturation === 'number' ? hex(v.colorSaturation) : null,
        saturationSource: v.saturationSource, saturationMappedFrom: v.saturationMappedFrom, borderColorSaturation: v.borderColorSaturation,
        mapping: v.mapping ? { type: v.mapping.type, dataExtent: v.mapping.dataExtent.map(hex), dataExtentText: v.mapping.dataExtent.map(dec), range: v.mapping.range } : null,
        fillBeforeRawItem: v.fillBeforeRawItem, strokeBeforeRawItem: v.strokeBeforeRawItem, rawItem: v.rawItem,
      } : null;
      const ul = r.upperLabel; const tu = tr.upperLabel;
      o.upperLabel = ul ? {
        rawText: ul.rawText, transform: hexArr(ul.transform), transformText: ul.transform ? ul.transform.map(dec) : null, z2: ul.z2, width: hexOrNull(ul.width), height: hexOrNull(ul.height), padding: ul.padding,
        isTruncated: ul.isTruncated, lines: ul.lines,
        layoutRect: { x: hex(ul.layoutRect.x), y: hex(ul.layoutRect.y), width: hex(ul.layoutRect.width), height: hex(ul.layoutRect.height) },
        layoutRectText: { x: dec(ul.layoutRect.x), y: dec(ul.layoutRect.y), width: dec(ul.layoutRect.width), height: dec(ul.layoutRect.height) },
        anchor: { x: hex(tu.anchor.x), y: hex(tu.anchor.y) }, textAlign: tu.textAlign, verticalAlign: tu.verticalAlign, colourRule: tu.colourRule, fill: tu.fill, stroke: tu.stroke,
      } : null;
    }
    if (ext4) {
      // M4-M6: the SeriesData id (null for a generated 'e' + NUL + NUL + dataIndex id), the alpha visual, the input of a
      // linear mapping, the id index, the map this node gives its children, the content label placement
      o.id = tr.idSource === 'generated' ? null : tr.id;
      o.idSource = tr.idSource;
      const v4 = tr.visual4;
      o.visual4 = v4 ? {
        colorAlpha: numOut(v4.colorAlpha), colorAlphaHex: hexOut(v4.colorAlpha), alphaSource: v4.alphaSource, alphaMappedFrom: v4.alphaMappedFrom, idIndex: v4.idIndex,
        mappedInput: v4.mappedInput ? { value: dec(v4.mappedInput.value), valueHex: hex(v4.mappedInput.value), normalized: dec(v4.mappedInput.normalized), normalizedHex: hex(v4.mappedInput.normalized) } : null,
        mapping: v4.mapping ? Object.assign({}, v4.mapping, v4.mapping.dataExtent ? { dataExtent: v4.mapping.dataExtent.map(hex), dataExtentText: v4.mapping.dataExtent.map(dec) } : {}) : null,
      } : null;
      const li = tr.labelInfo;
      o.labelInfo = li ? { position: li.position, distance: li.distance, textAlign: li.textAlign, verticalAlign: li.verticalAlign, anchor: { x: hex(li.anchor.x), y: hex(li.anchor.y) }, anchorText: { x: dec(li.anchor.x), y: dec(li.anchor.y) }, layout: li.layout, drillIcon: li.drillIcon } : null;
    }
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
    seriesIndex: u.seriesIndex, name: u.name,
    resolved: {
      box: { x: hex(u.box.x), y: hex(u.box.y), width: hex(u.box.width), height: hex(u.box.height) }, boxText: { x: dec(u.box.x), y: dec(u.box.y), width: dec(u.box.width), height: dec(u.box.height) },
      sortKeyPresent: hasOwn(c.srcList[u.seriesIndex], 'sort'), sortValue: R.sortValue, sortMode: R.sortMode, squareRatio: hex(R.squareRatio), squareRatioText: dec(R.squareRatio), leafDepth: R.leafDepth,
      visibleMin: dec(R.visibleMin), level0PaletteDefaulted: R.level0PaletteDefaulted, levels: u.levelsAfter,
    },
    rows, elements, breadcrumb,
    labelStats: t.labelStats,
    ...(c.def.batch ? { upperStats: t.upperStats, foreignElements: u.foreign } : {}),
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
const NRANDOM_M23 = +(process.env.ORACLE_RANDOM_M23 || 6);
const NRANDOM_M456 = +(process.env.ORACLE_RANDOM_M456 || 4);
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
  // ---- M2 / M3 (appended: the M1 cases above keep their ids and content) ----
  for (const d of M23_CASES()) defs.push(d);
  defs.push({ id: 'G-disk', batch: 'M2', gallery: 'treemap-disk', note: 'examples/advchart/gallery/treemap-disk.json verbatim (animation forced false; its title is another component and is left out): levels[2] colorSaturation [0.35, 0.5] and borderColorSaturation 0.6, visibleMin 300, formatter {b}' });
  defs.push({ id: 'G-show-parent', batch: 'M3', gallery: 'treemap-show-parent', note: 'examples/advchart/gallery/treemap-show-parent.json verbatim (animation forced false; title left out): upperLabel height 30 on the series, hidden on levels[0], plus the disk colours' });
  for (const d of randomCasesM23(NRANDOM_M23)) defs.push(d);
  // ---- M4 / M5 / M6 (appended: every case above keeps its id and content) ----
  for (const d of M456_CASES()) defs.push(d);
  defs.push({ id: 'G-drill-down', batch: 'M4', gallery: 'treemap-drill-down', note: "examples/advchart/gallery/treemap-drill-down.json verbatim (animation forced false; its title -- left: 'leafDepth', which getLayoutRect parses to NaN and treats as 0 -- is another component and is left out): leafDepth 2 (leaf roots with the drill icon, the crumb on the root), visibleMin 300, colorSaturation / borderColorSaturation per level" });
  defs.push({ id: 'G-visual', batch: 'M5', gallery: 'treemap-visual', note: "examples/advchart/gallery/treemap-visual.json verbatim (animation forced false; title left out): levels[1].color ['#942e38', '#aaa', '#269f3c'] with colorMappingBy 'value' over visualDimension 3, visualMin -100 / visualMax 100 widening every extent; depth-1 nodes have no colour (the root has no list)" });
  defs.push({ id: 'G-obama', batch: 'M6', gallery: 'treemap-obama', note: "examples/advchart/gallery/treemap-obama.json verbatim (animation forced false; title and legend left out): three treemap series, the legend in selectedMode 'single' selects '2012Budget' (the first item), so only series 0 draws; its levels[0] colorMappingBy 'id' over the default palette (levels[0].color null is overwritten by setDefault); label.position 'insideTopLeft' with a label.rich, so the RICH layout; the harvested JSON lost the label formatter functions, so the labels are the chain names" });
  for (const d of randomCasesM456(NRANDOM_M456)) defs.push(d);
  // ---- gaps found by the Pascal mutation run (M2 / M3, appended) ----
  for (const d of GAP_CASES()) defs.push(d);
  { const seen = new Set(); for (const d of defs) { must(!seen.has(d.id), 'duplicate id ' + d.id); seen.add(d.id); } }
  const recs = [];
  let checks = 0;
  for (const d of defs) {
    let c;
    try {
      c = recordCase(d, !d.id.startsWith('R-'));
      c.tc = transcribeCase(c, null);
      c.tr = c.tc.trs[0];
      const a = flat(caseViewUp(c), 'c', {});
      const b = flat(caseViewTr(c.tc), 'c', {});
      const df = diffFlat(a, b);
      checks += Object.keys(a).length;
      must(!df.length, 'the transcription differs from upstream at ' + df.length + ' fields: ' + df.slice(0, +(process.env.ORACLE_NDIFF || 6)).map(x => JSON.stringify(x)).join('; '));
      // transcribed extras agree with what upstream shows
      c.rec.us.forEach((u, k) => {
        const ub = u.breadcrumb; const tb = c.tc.trs[k].breadcrumb;
        must(!ub === !tb, 'breadcrumb presence');
        if (tb) must(tb.target === ub.target, 'breadcrumb target');
      });
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
    // M2 / M3 anchors (upstream.md in wf77)
    const disk = U('G-disk');
    must(disk.rows.some(r => r.stroke === 'rgba(194,221,85,1)'), "G-disk: #b6d634 at borderColorSaturation 0.6 gives 'rgba(194,221,85,1)'");
    must(disk.foreign > 0 && U('G-show-parent').foreign > 0, 'the gallery titles were left out');
    const ch = n => rowOf('M2-bcs-chained', n);
    must(ch('A').stroke === 'rgba(179,212,43,1)' && ch('A1').fill === 'rgba(209,229,128,1)' && ch('A1').stroke === 'rgba(178,212,43,1)', 'M2-bcs-chained: the border re-parses the saturated rgba()');
    must(ch('B1').fill === '#123456' && ch('B1').stroke === 'red' && ch('B21').fill === 'rgba(41,81,214,1)', 'M2-bcs-chained: raw item colours win; one child maps to the middle (0.5)');
    must(rowOf('M2-sat-levels', 'A1').fill === 'rgba(224,238,170,1)' && rowOf('M2-sat-levels', 'B21').fill === 'rgba(170,185,238,1)', 'M2-sat-levels: fills');
    must(is(rowOf('M2-sat-levels', 'B').dataExtent[0], 0), "M2-sat-levels: B's extent keeps the cut zero");
    must(rowOf('M2-sat-fixed', 'A2').fill === '#b6d634' && rowOf('M2-sat-fixed', 'C').stroke === 'rgba(0,0,0,1)' && rowOf('M2-sat-fixed', 'A1').fill === 'rgba(240,246,213,1)', 'M2-sat-fixed: saturation 0 changes nothing, borderColorSaturation 0 is black, the item 0.9 wins');
    must(rowOf('M2-bcs', '').stroke === null, 'M2-bcs: the colourless root has a null border');
    const hd = U('M3-default').elements.find(e => e.kind === 'upper' && e.text === 'B');
    must(hd && hd.transform[4] === 24 && hd.transform[5] === 80 && hd.fill === '#333' && hd.stroke === 'rgba(255,255,255,1)' && hd.lineWidth === 2 && hd.textAlign === 'left' && hd.z2 === 122, 'M3-default: the header of B');
    const insideRows = byId['M3-inside'].tr.rows.filter(r => r.upperLabel).map(r => r.upperLabel.fill + '/' + r.upperLabel.stroke).join(' ');
    must(insideRows === '#ccc/#222 #eee/#777 #333/null #eee/#777 #333/null', "M3-inside: fills by luminance: " + insideRows);
    must(U('M3-bg-alpha').elements.some(e => e.kind === 'upper' && e.stroke === 'rgba(127.5,127.5,127.5,1)'), 'M3-bg-alpha: the half-transparent background blended over white');
    must(U('M3-dark').elements.some(e => e.kind === 'upper' && e.fill === '#ccc' && e.stroke === 'rgba(27,27,27,1)'), 'M3-dark: outside colours in dark mode');
    must(U('M3-formatter-fallback').elements.some(e => e.kind === 'upper' && e.text === 'L:') && U('M3-formatter-fallback').elements.some(e => e.kind === 'upper' && e.text === 'L:Ser'), 'M3-formatter-fallback: label.formatter reaches the header');
    must(U('M3-negative-width').rows.some(r => r.upperLabel && r.upperLabel.layoutRect.width < 0), 'M3-negative-width: a negative header rect');
    must(U('M3-levels').rows.every(r => !r.upperLabel || r.viewChildren.length), 'M3-levels: headers on parents only');
    // M4 / M5 / M6 anchors (wf79 upstream.md)
    const T = (id, sk) => byId[id].tc.trs[sk || 0];
    const trow = (id, nm, sk) => T(id, sk).rows.find(r => r.name === nm);
    const texts = id => U(id).elements.filter(e => e.kind === 'tspan').map(e => e.text);
    must(texts('M4-leafDepth-1').join('|') === '\u25b6 B|\u25b6 A|C' && U('M4-leafDepth-1').breadcrumb.items.length === 1 && T('M4-leafDepth-1').breadcrumb.targetRule === 'leafDepthViewRoot', 'M4-leafDepth-1: leaf roots with icons, the crumb on the root');
    must(rowOf('M4-leafDepth-0', 'S').label.lines[0] === '\u25b6 S' && rowOf('M4-leafDepth-0', 'S').fill === null, 'M4-leafDepth-0: the root as leaf root');
    must(!trow('M4-cvm-hides-first', 'a1').layout.isLeafRoot && trow('M4-cvm-leafDepth-wins', 'a1').layout.isLeafRoot, 'M4-cvm: leafDepth beats the hide only at or past its depth');
    must(texts('M4-icon-nameless').join('|') === '\u25b6 n|\u25b6 ' && texts('M4-icon-empty').indexOf('Beta') >= 0 && texts('M4-icon-custom').indexOf('>> Beta') >= 0, 'M4-icon: the prefix rules');
    must(rowOf('M4-icon-ignored', 'Beta').label.ignore && rowOf('M4-icon-ignored', 'Beta').label.rawText === '\u25b6 FBeta', 'M4-icon-ignored: the ignored Text carries the icon');
    must(rowOf('M5-value-dim0', 'a2').fill === 'rgba(166,145,147,1)' && rowOf('M5-value-dim0', 'C').fill === null, 'M5-value-dim0: fastLerp');
    must(rowOf('M5-nan', 'p1').fill === null && rowOf('M5-nan', 'q1').fill === 'rgba(128,128,128,1)', 'M5-nan: NaN gives no colour, except over a degenerate extent (0.5)');
    must(rowOf('M5-series-linear', 'C').fill === 'rgba(80,112,221,1)' && rowOf('M5-alpha-colours', 'a2').fill === 'rgba(51,204,0,0.4415686274509804)', 'M5: the palette mapped linearly; the alpha lerped unrounded');
    must(rowOf('M5-scalar-dims', 'R').fill === 'rgba(240,240,240,1)' && rowOf('M5-past-dimmax', 'R').fill === null, 'M5: a scalar answers every stored dimension, NaN past them');
    must(['b1', 'b21', 'a11', 'Gamma'].map(nm => trow('M6-id-series', nm).visual4.idIndex).join() === '1,3,7,10' && rowOf('M6-id-series', 'Gamma').fill === '#b6d634', 'M6-id-series: one pre-order counter per series');
    must(T('M6-id-dup').rows.map(r => r.id).slice(0, 5).join() === 'x,x__ec__2,x__ec__3,y,x__ec__4' && T('M6-id-dup').rows[5].visual4.idIndex === T('M6-id-dup').rows[3].visual4.idIndex, 'M6-id-dup: ids and a shared index');
    must(rowOf('M6-alpha-item', 'Alpha').stroke === 'rgba(179,212,43,0.3)' && rowOf('M6-alpha-item', 'b1').fill === '#5070dd', 'M6-alpha-item: alpha through the border; 0 changes nothing');
    must(rowOf('M6-alpha-dim', 'b1').fill === '#5070dd', 'M6-alpha-dim: a NaN alpha is falsy');
    const itl = U('M6-insideTopLeft').elements.find(e => e.kind === 'tspan');
    must(itl.x === 5 && itl.y === 11 && itl.textAlign === 'left', 'M6-insideTopLeft: x 5, y 11, left');
    must(U('M6-inside-rich').elements.filter(e => e.kind === 'tspan').every(e => e.y < -100), 'M6-inside-rich: the rich layout puts the text at the top');
    must(rowOf('M6-snug-plain', 'Elephant').label.isTruncated && !rowOf('M6-snug-rich', 'Elephant').label.isTruncated, 'M6-snug: plain truncates, rich keeps');
    const drawnOf = id => byId[id].rec.seriesList.filter(s => !s.filtered).map(s => s.seriesIndex).join();
    must(drawnOf('M6-legend-single') === '0' && drawnOf('M6-legend-selected-true') === '0' && drawnOf('M6-legend-false-first') === '1' && drawnOf('M6-legend-missing') === '0,1' && drawnOf('M6-legend-multiple') === '0,2' && drawnOf('G-obama') === '0' && drawnOf('M6-obama-growth') === '2', 'M6: the legend single-mode rule');
    must(U('G-drill-down').foreign > 0 && U('G-visual').foreign > 0 && U('G-obama').foreign > 0, 'the gallery titles / legend were left out');
    must(trow('M2-series-itemstyle-sat', 'A1').visual.saturationSource === 'mapped' && trow('M2-series-itemstyle-sat', 'C').visual.colorSaturation === 0.3 && trow('M2-series-itemstyle-sat', 'D1').visual.colorSaturation === 0.3, 'M2-series-itemstyle-sat: mapped beats the series value; unmapped leaves keep it');
    must(U('M3-upper-padding-truncate').rows.some(r => r.upperLabel && r.upperLabel.isTruncated), 'M3-upper-padding-truncate: the padding truncates the header');
  }
  // the cases carry what the Pascal test needs
  const c0f = id => byId[id].rec.seriesList.filter(sl => sl.filtered).length;
  const counts = { cases: recs.length, rows: 0, elements: 0, rects: 0, tspans: 0, crumbs: 0, crumbTexts: 0, labels: 0 };
  for (const c0 of recs) for (let sk = 0; sk < c0.rec.us.length; sk++) {
    const c = { def: c0.def, rec: { u: c0.rec.us[sk] }, tr: c0.tc.trs[sk], first: sk === 0 };
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
    if (c.def.batch) {
      const bump = (k, v) => { counts[k] = (counts[k] || 0) + v; };
      if (c.first) bump('cases' + c.def.batch, 1);
      const vis = c.tr.rows.filter(r => r.visual);
      bump('saturatedColours', vis.filter(r => r.visual.colorSaturation != null && !(r.viewChildren && r.viewChildren.length) && typeof r.fill === 'string' && r.fill.indexOf('rgba(') === 0).length);
      bump('saturationMappedRows', vis.filter(r => r.visual.saturationMappedFrom != null).length);
      bump('borderSaturatedRows', vis.filter(r => r.visual.borderColorSaturation != null).length);
      bump('rawItemOverrides', vis.filter(r => r.visual.rawItem).length);
      bump('upperHeaders', c.tr.upperStats.headers);
      bump('upperTspans', c.tr.upperStats.tspans);
      bump('upperTruncatedLines', c.tr.upperStats.truncated);
      bump('upperDroppedLines', c.tr.upperStats.dropped);
      for (const k of ['outside', 'inside', 'option']) bump('upperColour_' + k, c.tr.rows.filter(r => r.upperLabel && r.upperLabel.colourRule === k).length);
      if (c.def.batch === 'M4' || c.def.batch === 'M5' || c.def.batch === 'M6') {
        const v4 = c.tr.rows.filter(r => r.visual4);
        bump('leafRoots', c.tr.rows.filter(r => r.layout && r.layout.isLeafRoot).length);
        bump('drillIconLabels', c.tr.rows.filter(r => r.labelInfo && r.labelInfo.drillIcon).length);
        bump('ignoredIconLabels', c.tr.rows.filter(r => r.label && r.label.ignore && r.layout && r.layout.isLeafRoot && r.label.rawText != null).length);
        bump('crumbOnLeafDepthRoot', c.tr.breadcrumb && c.tr.breadcrumb.targetRule === 'leafDepthViewRoot' ? 1 : 0);
        bump('linearColourRows', v4.filter(r => r.visual4.mappedInput && r.colour && r.colour.mappedFrom != null && r.paletteIndex == null).length);
        bump('linearColourNone', v4.filter(r => r.visual4.mappedInput && r.colour && r.colour.value == null).length);
        bump('idMappedRows', v4.filter(r => r.visual4.idIndex != null).length);
        bump('alphaMappedRows', v4.filter(r => r.visual4.alphaMappedFrom != null).length);
        bump('alphaColours', v4.filter(r => r.visual4.colorAlpha && !(r.viewChildren && r.viewChildren.length) && typeof r.fill === 'string' && r.fill.indexOf('rgba(') === 0).length);
        bump('richLabels', c.tr.rows.filter(r => r.labelInfo && r.labelInfo.layout === 'rich').length);
        bump('labelsNotInside', c.tr.rows.filter(r => r.labelInfo && r.labelInfo.position !== 'inside').length);
        if (c.first) bump('filteredSeries', c0f(c.def.id));
      }
    }
  }
  // guards
  const guards = GUARDS.map(([id, mutation]) => {
    let red = 0; const changed = [];
    for (const c of recs) {
      let b;
      try { b = flat(caseViewTr(transcribeCase(c, id)), 'c', {}); } catch (e) { b = { threw: String(e.message) }; }
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
      paint: "zr.storage.getDisplayList(true), restricted to the elements under the series view's group (a gallery title is another component): every one must be a background, content, label TSpan, header ('upper') TSpan, crumb polygon or crumb TSpan of the one series",
      header: 'background.getTextContent() (the upper label Text: style.text / width / height / padding, isTruncated, transform, z2, childrenRef() TSpans) and background.textConfig.layoutRect',
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
      'M1 cases (no batch field): none sets colorSaturation, borderColorSaturation, colorAlpha, upperLabel, leafDepth, colorMappingBy, visualDimension / visualMin / visualMax, decal or a series-level color list (checked; a case that did would stop the run). ref.js variants 6 (leafDepth) and 9 (upperLabel) are skipped there. M2 / M3 cases (batch field) may set colorSaturation, borderColorSaturation and upperLabel, and still refuse colorAlpha, leafDepth, colorMappingBy, visualDimension / visualMin / visualMax, decal and a series-level color list.',
      "M2 saturation: a parent maps its children when its chain `color` is not a non-empty list, it has a colour (visuals.color not null / 'none'), and its chain colorSaturation (item colorSaturation > levels[depth].colorSaturation > series colorSaturation) is a non-empty array: child visual = linearMap(linearMap(child.getValue(), dataExtent, [0, 1], clamp), [0, 1], [range[0], range[1] (= range[0] for a one-entry range)], clamp); dataExtent = [min, max] over the sorted children BEFORE the visibleMin cut; min == max gives 0.5, the middle of the range. The child's itemStyle.colorSaturation chain (item > level) wins over the mapped value, which wins over the series itemStyle.colorSaturation; the value is inherited by descendants that are not remapped.",
      "M2 colours: calculateColor = the colour, then (if colorSaturation is TRUTHY: 0 changes nothing) zrender modifyHSL(colour, null, null, s), which sets HSL LIGHTNESS: parse -> rgba2hsla -> l = clamp(s, 0, 1) -> hsla2rgba (h = ((H % 360) + 360) % 360 / 360; channels Math.round(x * 255) clamped to 0..255; alpha kept) -> 'rgba(r,g,b,a)'. borderColorSaturation (chain, != null) makes the stroke modifyHSL(calculateColor(visuals), null, null, bcs) (0 is black), or null without a colour. Then dataStyleTask: a raw item itemStyle color / borderColor / opacity replace fill / stroke / opacity.",
      "M3 headers: only a PARENT (viewChildren) whose upperLabelHeight (show ? height : 0 on its chain) is non-zero gets a header Text on its BACKGROUND; a leaf keeps its content label (its content rect is inset by bw only, the reserved strip is ignored). Text: upperLabel.formatter, else label.formatter, else the chain name. Rect {bw, 0, w - 2bw, upperHeight} through the background transform (a negative width flips); position [x, y] (default [0, '50%']): left / middle at (rect.x + x, rect.y + y%); 'inside': centre / middle. Width max(rect.width - pad, 0), height max(upperHeight - pad, 0), the label truncation / line drop. z2 = running max + 2. Colour: an option colour ('inherit' = the border colour) as is, no stroke; otherwise 'inside' over a filled background: #333 (lum > 0.5) / #eee (> 0.2) / #ccc, stroke = the background colour when (lum(fill) < 0.4) == dark mode; anything else (the default array position, or an unfilled background): #333 (#ccc in dark mode) with a 2px stroke = the canvas background blended over white (black in dark mode). Opacity: upperLabel.opacity, else the node style opacity.",
      "M4 leafDepth: squarify depth counts from the view root (0); a node at depth >= leafDepth with laid-out children becomes isLeafRoot, its children get only {area} (no x / y, never drawn) and it is drawn as a leaf. leafDepth wins over childrenVisibleMin only at or past its depth (initChildren: `hideChildren && !overLeafDepth`). A leaf root's label text (any non-null text, '' included, the IGNORED Text of a hidden label too) gets the series' own drillDownIcon + ' ' when the icon is truthy; headers never get it. With a series leafDepth the breadcrumb target is the view root (the root alone on frame 1).",
      "M5 linear colour: a parent whose chain `color` list maps with a colorMappingBy other than 'index' / 'id' maps child value v = getValue(visualDimension of the PARENT chain) as t = linearMap(v, extent, [0, 1], clamp) (a degenerate extent gives 0.5 for anything, NaN included), then zrender fastLerp: value = t * (n - 1), l = floor, r = ceil, p = value - l, channel = clamp(Math.round(L + (R - L) * p), 0, 255), alpha = clamp(L_a + (R_a - L_a) * p, 0, 1) unrounded, 'rgba(r,g,b,a)'; t outside [0, 1] or NaN gives NO colour. extent = statistic() over the sorted children before visibleMin by the parent's visualDimension ([last, first] for the STRING 'value' with a sort, reversed for asc; else [min, max], NaN skipped), then visualMin < extent[0] and visualMax > extent[1] widen it. getValue(dim): a scalar value answers every stored dimension, null is NaN, a dimension past the longest value array is NaN.",
      "M6: colorMappingBy 'id' maps list[mapIdToIndex(child id) % n], one first-seen map per series over the pre-order visual traversal (a child's index is taken right before its subtree). colorAlpha ranges map like colorSaturation (linear, paired, clamped) and win over a colorSaturation range on the same parent; calculateColor applies modifyAlpha after the saturation when the alpha is TRUTHY (0 and NaN change nothing): the parsed channels with a = clamp(alpha, 0, 1). A series-level colour list maps below the root at every depth (the root keeps its levels[0] palette). Label positions 'inside*': calculateTextPosition over the content rect (distance = label.distance, 0 by default); plain tspans at x = getTextXForPadding(0, align, pad), y = adjustTextY(0, contentHeight, verticalAlign) + lh / 2 (+ pad[0] top, - pad[2] bottom). Any label.rich switches to the RICH layout: a token is truncated only when wider than the box; the box is placed by the OUTER size (box + padding), so 'inside' text sits at the top.",
      "M6 legend: LegendModel in selectedMode 'single' selects the first legend item that is not explicitly false and deselects the others; filtered series have no layout, no visual and no element; a name missing from legend.data stays shown. seriesStyleTask still gives every series (filtered too) a colour: its own `color` list's first entry, else the global palette by series name.",
      "Not recorded: hover / emphasis, drill-down clicks, zoom / roam, animations, the second-frame breadcrumb (which would use the previous frame's transforms), rich-text markup, label align / verticalAlign / lineHeight overrides.",
    ],
    measure: measureRec,
    counts,
    cases: recs.map(c => ({
      id: c.def.id, ...(c.def.batch ? { batch: c.def.batch } : {}), note: c.def.note, gallery: c.def.gallery || null, option: c.def.gallery ? null : JSON.parse(c.optionText), animationForced: c.animationForced,
      random: c.def.random || null, palette: c.rec.palette, textStyle: c.rec.textStyle, ground: c.rec.ground, series: c.rec.us.map((u, k) => emitSeries(c, k)),
      ...(c.def.batch === 'M6' ? { legend: c.rec.legend, seriesList: c.rec.seriesList } : {}),
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

// ============================================================================
// M2 (colour saturation) and M3 (upper labels): hand cases, then the random families
// ============================================================================
function M23_CASES() {
  // D2: D1 with a third A child and a zero B child (cut by visibleMin, yet inside B's dataExtent)
  const D2 = () => [
    { name: 'A', children: [{ name: 'A1', value: 4 }, { name: 'A2', value: 2 }, { name: 'A3', value: 1 }] },
    { name: 'B', value: 10, children: [{ name: 'B1', value: 3 }, { name: 'B2', value: 5, children: [{ name: 'B21', value: 5 }] }, { name: 'B3', value: 0 }] },
    { name: 'C', value: 3 },
  ];
  // D3: a nameless parent, raw item colour / border colour / opacity
  const D3 = () => [
    { name: 'A', itemStyle: { opacity: 0.5 }, children: [{ name: 'A1', value: 4 }, { value: 2 }] },
    { value: 10, children: [{ name: 'B1', value: 3, itemStyle: { color: '#123456', borderColor: 'red' } }, { name: 'B2', value: 5, itemStyle: { borderColor: '#0f0' }, children: [{ name: 'B21', value: 5 }] }] },
    { name: 'C', value: 3 },
  ];
  // D4: three levels of parents, for headers
  const D4 = () => [
    { name: 'Alpha', children: [{ name: 'a1', value: 6, children: [{ name: 'a11', value: 4 }, { name: 'a12', value: 2 }] }, { name: 'a2', value: 3 }] },
    { name: 'Beta', children: [{ name: 'b1', value: 5 }, { name: 'b2 with a rather long name', value: 4, children: [{ name: 'b21', value: 3 }, { name: 'b22', value: 1 }] }] },
    { name: 'Gamma', value: 4 },
  ];
  const m2 = (id, note, option) => ({ id, batch: 'M2', note, option });
  const m3 = (id, note, option) => ({ id, batch: 'M3', note, option });
  return [
    // ---- M2: colorSaturation ----
    m2('M2-sat-levels', "levels[0].colorSaturation [0.3, 0.6] (loses to the palette list at the root) and levels[1].colorSaturation [0.2, 0.8]: A1/A2/A3 by value over A's extent [1, 4]; B's extent [0, 5] includes the visibleMin-cut B3; B21 inherits B2's 0.8", one({ data: D2(), levels: [{ colorSaturation: [0.3, 0.6] }, { colorSaturation: [0.2, 0.8] }] })),
    m2('M2-sat-series', 'series colorSaturation [0.3, 0.7]: every parent below the root maps its children; B2 (one child, extent [5, 5]) maps to the middle 0.5', one({ data: D2(), colorSaturation: [0.3, 0.7] })),
    m2('M2-sat-reversed', 'levels[1].colorSaturation [0.8, 0.2]: a reversed range (bigger values darker)', one({ data: D2(), levels: [{}, { colorSaturation: [0.8, 0.2] }] })),
    m2('M2-sat-single', 'series colorSaturation [0.45]: a one-entry range is paired [0.45, 0.45]; a three-entry range on levels[2] uses only its first two', one({ data: D4(), colorSaturation: [0.45], levels: [{}, {}, { colorSaturation: [0.2, 0.6, 0.9] }] })),
    m2('M2-sat-equal-extent', 'children of equal value: dataExtent min == max, linearMap returns 0.5 and the colour gets the middle of the range', one({ data: [{ name: 'P', children: [{ name: 'p1', value: 2 }, { name: 'p2', value: 2 }, { name: 'p3', value: 2 }] }, { name: 'Q', children: [{ name: 'q1', value: 7 }] }], colorSaturation: [0.2, 0.9] })),
    m2('M2-sat-fixed', "levels[1].itemStyle.colorSaturation 0.25; an item's own 0.9 wins over a mapped value; an item 0 changes nothing (calculateColor tests truthiness) while the level borderColorSaturation 0 makes black borders", one({ data: (() => { const d = D2(); d[0].children[0].itemStyle = { colorSaturation: 0.9 }; d[0].children[1].itemStyle = { colorSaturation: 0 }; return d; })(), levels: [{}, { itemStyle: { colorSaturation: 0.25, borderColorSaturation: 0, borderWidth: 2 } }, { colorSaturation: [0.3, 0.7] }] })),
    m2('M2-sat-item-range', "an item-level colorSaturation range [0.6, 0.3] on the parent A maps A's children; B has none", one({ data: (() => { const d = D2(); d[0].colorSaturation = [0.6, 0.3]; return d; })() })),
    m2('M2-sat-color-wins', 'levels[1] has both a color list and a colorSaturation range: the colour list wins (depth-2 colours by index); the item-level saturation 0.4 of levels[0] is inherited', one({ data: D2(), levels: [{ itemStyle: { colorSaturation: 0.4 } }, { color: ['#c23531', '#2f4554', '#61a0a8'], colorSaturation: [0.2, 0.8] }] })),
    m2('M2-sat-no-colour', 'palette suppressed by levels[2].color: depth-1 nodes have no colour, so their colorSaturation range maps nothing; depth-2 parents map their list', one({ data: D4(), levels: [{}, { colorSaturation: [0.2, 0.8] }, { color: ['#111', '#999'] }] })),
    m2('M2-bcs', 'series itemStyle borderWidth 3, borderColorSaturation 0.6: the root has no colour so its stroke (and background fill) is null; everyone else a lighter border', one({ data: D2(), itemStyle: { borderWidth: 3, borderColorSaturation: 0.6 } })),
    m2('M2-bcs-extremes', 'borderColorSaturation 0 (black) on levels[1], 1 (white) on levels[2], 0.35 on an item', one({ data: (() => { const d = D4(); d[2].itemStyle = { borderColorSaturation: 0.35 }; return d; })(), levels: [{ itemStyle: { gapWidth: 2 } }, { itemStyle: { borderWidth: 4, borderColorSaturation: 0 } }, { itemStyle: { borderWidth: 2, borderColorSaturation: 1 } }] })),
    m2('M2-bcs-chained', 'series colorSaturation [0.3, 0.7] plus borderColorSaturation 0.5: the border re-reads the ALREADY modified rgba() string (rgba(209,229,128,1) gives rgba(178,212,43,1) while the unmodified #b6d634 gives 179)', one({ name: 'Ser', data: D3(), colorSaturation: [0.3, 0.7], itemStyle: { borderWidth: 3, borderColorSaturation: 0.5 } })),
    m2('M2-raw-item', "dataStyleTask: an item's raw itemStyle color / borderColor replace the saturated fill / the saturated border; a raw opacity reaches the node's labels", one({ data: (() => { const d = D3(); d[2].itemStyle = { opacity: 0.4 }; return d; })(), colorSaturation: [0.3, 0.7], itemStyle: { borderWidth: 2, borderColorSaturation: 0.4 } })),
    m2('M2-series-opacity', 'series itemStyle.opacity 0.8 reaches every label (seriesStyleTask); an item opacity 0.3 wins for its own; label.opacity 0.9 on levels[2] wins over both', one({ data: (() => { const d = D2(); d[2].itemStyle = { opacity: 0.3 }; return d; })(), itemStyle: { opacity: 0.8 }, levels: [{}, {}, { label: { opacity: 0.9 } }] })),
    m2('M2-alpha-hex', "colours with alpha through modifyHSL: '#d48265cc' keeps a = 0.8 (204 / 255), '#abc' short hex, rgb(), rgba(...,0.5)", one({ data: D2(), levels: [{ color: ['#d48265cc', '#abc', 'rgb(97,160,168)', 'rgba(200,40,90,0.5)'] }, { colorSaturation: [0.25, 0.75] }], itemStyle: { borderWidth: 1, borderColorSaturation: 0.9 } })),
    m2('M2-named', 'named colours through modifyHSL: red, blue, green; a grey levels[2] colour (delta 0: hue and saturation 0)', one({ data: D4(), levels: [{ color: ['red', 'blue', 'green'] }, { colorSaturation: [0.1, 0.9] }, { itemStyle: { color: '#808080' }, colorSaturation: [0.3, 0.6] }] })),
    m2('M2-asc', "sort 'asc': the extent is over the ascending children, the same min / max", one({ data: D2(), sort: 'asc', colorSaturation: [0.3, 0.7] })),
    m2('M2-nosort', 'sort false: no visibleMin, the zero child is laid out and mapped to the range start', one({ data: D2(), sort: false, colorSaturation: [0.3, 0.7] })),
    m2('M2-disk-mini', 'the gallery disk configuration on D4', one({ name: 'Disk Usage', data: D4(), visibleMin: 300, label: { show: true, formatter: '{b}' }, itemStyle: { borderColor: '#fff' }, levels: [{ itemStyle: { borderWidth: 0, gapWidth: 5 } }, { itemStyle: { gapWidth: 1 } }, { colorSaturation: [0.35, 0.5], itemStyle: { gapWidth: 1, borderColorSaturation: 0.6 } }] })),
    m2('X-guard-hmod', "found by search: '#000507' at lightness 0.35 -- hsla2rgba's ((H % 360) + 360) % 360 rounds H + 360; without it the green channel is 127, upstream 128", one({ data: [{ name: 'h', value: 3, itemStyle: { color: '#000507', colorSaturation: 0.35 } }, { name: 'k', value: 2, itemStyle: { color: '#00233f', colorSaturation: 0.45 } }] })),
    // ---- M3: upperLabel ----
    m3('M3-default', 'upperLabel show on the series, borderWidth 2: every parent (the root included, no text: unnamed) gets a header at (bw + T.x, T.y + 10), left / middle, #333 with a 2px rgba(255,255,255,1) stroke; leaves keep their centre label', one({ data: D2(), upperLabel: { show: true }, itemStyle: { borderWidth: 2 } })),
    m3('M3-levels', 'levels[0] upperLabel show false, levels[1] height 30, levels[2] show false; a depth-3 leaf with show reserves a strip but draws no header', one({ data: D4().concat([{ name: 'Delta', children: [{ name: 'd1', children: [{ name: 'd11', value: 3, children: [{ name: 'd111', value: 3 }] }] }] }]), upperLabel: { show: true }, levels: [{ upperLabel: { show: false } }, { upperLabel: { height: 30 } }, { upperLabel: { show: false } }] })),
    m3('M3-bw-over-height', 'upperLabel height 10 under borderWidth 14: upperHeight = 14, the header rect is 14 tall', one({ name: 'Ser', data: D4(), upperLabel: { show: true, height: 10 }, itemStyle: { borderWidth: 14, borderColor: '#5070dd' } })),
    m3('M3-height-zero', 'upperLabel show true with height 0 on levels[1]: no header, no reserve there', one({ data: D4(), upperLabel: { show: true }, levels: [{}, { upperLabel: { height: 0 } }] })),
    m3('M3-formatter-fallback', "no upperLabel formatter: the header takes label.formatter 'L:{b}' ({b} = '' for the nameless parent, the series name at the root); an upperLabel formatter '{b} ({c})' on levels[2]", one({ name: 'Ser', data: D3(), label: { formatter: 'L:{b}' }, upperLabel: { show: true }, levels: [{}, {}, { upperLabel: { formatter: '{b} ({c})' } }] })),
    m3('M3-colour-option', "upperLabel colour '#fff' (no auto stroke, lineWidth 1), 'inherit' on levels[1] (the border colour '#555')", one({ data: D4(), upperLabel: { show: true, color: '#fff' }, itemStyle: { borderWidth: 2 }, levels: [{ itemStyle: { borderColor: '#333' } }, { upperLabel: { color: 'inherit' }, itemStyle: { borderColor: '#555' } }] })),
    m3('M3-inside', "position 'inside': the fill by the background luminance (#ddd: #333; #777: #eee with a #777 stroke; #222: #ccc with a #222 stroke), centred in the header rect", one({ name: 'Root', data: D4(), upperLabel: { show: true, position: 'inside' }, levels: [{ itemStyle: { borderColor: '#222', borderWidth: 1 } }, { itemStyle: { borderColor: '#777', borderWidth: 4 } }, { itemStyle: { borderColor: '#ddd', borderWidth: 3 } }] })),
    m3('M3-inside-bcs', "position 'inside' over saturation borders, the root's null (no colour, background fill null: #333, no stroke)", one({ name: 'Root', data: D4(), upperLabel: { show: true, position: 'inside', height: 24 }, itemStyle: { borderWidth: 2, borderColorSaturation: 0.3 }, levels: [{}, { colorSaturation: [0.2, 0.8] }] })),
    m3('M3-position', "positions [4, '30%'] on the series and ['10%', 7] on levels[1]", one({ data: D4(), upperLabel: { show: true, height: 25, position: [4, '30%'] }, levels: [{}, { upperLabel: { position: ['10%', 7] } }] })),
    m3('M3-padding', "padding [2, 8] on the series (x = 8, width - 16), 6 with position 'inside' on levels[1]", one({ data: D4(), upperLabel: { show: true, padding: [2, 8] }, itemStyle: { borderWidth: 1 }, levels: [{}, { upperLabel: { padding: 6, position: 'inside' } }] })),
    m3('M3-dark', "backgroundColor '#1b1b1b' (dark mode): outside #ccc with a rgba(27,27,27,1) stroke; 'inside' on levels[1] flips the stroke rule", one({ data: D4(), upperLabel: { show: true }, levels: [{}, { upperLabel: { position: 'inside' }, itemStyle: { borderColor: '#777', borderWidth: 3 } }] }, { backgroundColor: '#1b1b1b' })),
    m3('M3-bg-alpha', "backgroundColor 'rgba(0,0,0,0.5)' (lum 0.5 over white: light): the outside stroke is rgba(127.5,127.5,127.5,1)", one({ data: D4(), upperLabel: { show: true } }, { backgroundColor: 'rgba(0,0,0,0.5)' })),
    m3('M3-truncate', "long names in narrow headers (truncation with and without '...'); 'two\\nlines' keeps both lines in a 30-high strip", one({ data: [{ name: 'two\nlines', children: [{ name: 'x', value: 3 }, { name: 'y', value: 2 }] }, { name: 'LongNameAbcdefghijk', value: 1.2, children: [{ name: 'z', value: 1 }] }, { name: 'Elephantine and more', value: 0.6, children: [{ name: 'w', value: 1 }] }, { name: '中文标签', value: 0.4, children: [{ name: 'v', value: 1 }] }, { name: 'tw\no', children: [{ name: 'u', value: 5 }] }], upperLabel: { show: true, height: 30 }, levels: [{ upperLabel: { show: false } }, {}], squareRatio: 1 })),
    m3('M3-truncate-20', "the same names in the default 20-high strip: a second line is dropped", one({ data: [{ name: 'two\nlines', children: [{ name: 'x', value: 3 }, { name: 'y', value: 2 }] }, { name: 'LongNameAbcdefghijk', value: 1.2, children: [{ name: 'z', value: 1 }] }, { name: 'Elephantine and more', value: 0.6, children: [{ name: 'w', value: 1 }] }, { name: 'tw\no', children: [{ name: 'u', value: 5 }] }], upperLabel: { show: true }, levels: [{ upperLabel: { show: false } }, {}], squareRatio: 1 })),
    m3('M3-negative-width', 'sort false (no visibleMin): a narrow parent with borderWidth 30 keeps its 0-area children, so it is a parent whose header rect width w - 60 is negative; applyTransform flips it', one({ data: [{ name: 'wide', value: 95, children: [{ name: 'w1', value: 1 }] }, { name: 'thin', value: 5, children: [{ name: 't1', value: 1 }, { name: 't2', value: 1 }] }], sort: false, upperLabel: { show: true }, levels: [{}, { itemStyle: { borderWidth: 30 } }], left: 0, right: 0 })),
    m3('M3-root-untransformed', 'box at (0, 0): the root group has no transform, so the root header layoutRect is used untransformed', one({ name: 'Root', data: D4(), left: 0, top: 0, upperLabel: { show: true }, itemStyle: { borderWidth: 1 } })),
    m3('M3-opacity-font', 'upperLabel opacity 0.7 on levels[1], an item opacity 0.5 on a parent (its header), fontSize 16 on levels[2]', one({ data: (() => { const d = D4(); d[1].itemStyle = { opacity: 0.5 }; return d; })(), upperLabel: { show: true, height: 24 }, levels: [{}, { upperLabel: { opacity: 0.7 } }, { upperLabel: { fontSize: 16 } }] })),
    m3('M3-show-parent-mini', 'the gallery show-parent configuration on D4', one({ name: 'Disk Usage', data: D4(), visibleMin: 300, label: { show: true, formatter: '{b}' }, upperLabel: { show: true, height: 30 }, itemStyle: { borderColor: '#fff' }, levels: [{ itemStyle: { borderColor: '#777', borderWidth: 0, gapWidth: 1 }, upperLabel: { show: false } }, { itemStyle: { borderColor: '#555', borderWidth: 5, gapWidth: 1 }, emphasis: { itemStyle: { borderColor: '#ddd' } } }, { colorSaturation: [0.35, 0.5], itemStyle: { borderWidth: 5, gapWidth: 1, borderColorSaturation: 0.6 } }] })),
  ];
}

// random M2 / M3 families: ref.js's generator with item-level M2 / M3 options, on its own seed (the M1 families above
// keep their sequence)
function randomCasesM23(nForests) {
  let seed = 770077;
  const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
  const ri = n => Math.floor(rnd() * n);
  const NAMES = ['a', 'bb', 'Cat', 'dog', 'Elephant', 'LongNameAbcdefghijk', '中文', 'x y', 'W', 'm'];
  function genNode(depth, maxDepth, extras) {
    const n = {};
    const t0 = rnd();
    if (t0 < 0.9) n.name = NAMES[ri(NAMES.length)] + (rnd() < 0.6 ? String(ri(40)) : '');
    else if (t0 < 0.93) n.name = 'two\nlines';
    const k = depth < maxDepth ? ri(5) : 0;
    if (k > 0 && rnd() < 0.8) {
      n.children = [];
      for (let i = 0; i < k; i++) n.children.push(genNode(depth + 1, maxDepth, extras));
      if (rnd() < 0.2) n.value = ri(60);
    } else {
      const t = rnd();
      n.value = t < 0.06 ? 0 : t < 0.09 ? -ri(5) : t < 0.13 ? undefined : t < 0.18 ? [ri(20) + 1, ri(9)] : t < 0.3 ? +(rnd() * 30).toFixed(3) : ri(40) + 1;
      if (n.value === undefined) delete n.value;
    }
    if (extras && rnd() < 0.25) {
      const u = rnd();
      n.itemStyle = {};
      if (u < 0.2) n.itemStyle.colorSaturation = +(rnd()).toFixed(2);
      else if (u < 0.35) n.itemStyle.borderColorSaturation = [0, 0.25, 0.5, 0.8, 1][ri(5)];
      else if (u < 0.45) n.colorSaturation = [0.1 + ri(5) / 10, 0.9 - ri(3) / 10];
      else if (u < 0.55) n.itemStyle.opacity = 0.5;
      else if (u < 0.7) n.upperLabel = { show: rnd() < 0.5, height: [0, 12, 26][ri(3)] };
      else if (u < 0.8) n.upperLabel = { color: ['#fff', 'inherit'][ri(2)] };
      else if (u < 0.9) n.itemStyle.borderColor = ['#222', '#777', '#ddd', 'rgba(10,20,30,0.5)'][ri(4)];
      else n.itemStyle.color = ['#8a2be2', '#ff994d', 'rgb(1,200,90)'][ri(3)];
    }
    return n;
  }
  function genForest() {
    const n = 1 + ri(6);
    const md = 2 + ri(3);
    const extras = rnd() < 0.7;
    const out = [];
    for (let i = 0; i < n; i++) out.push(genNode(1, md, extras));
    return out;
  }
  const VARIANTS = [
    ['M2', () => ({ colorSaturation: [0.3, 0.7] })],
    ['M2', () => ({ levels: [{ itemStyle: { borderWidth: 0, gapWidth: 5 } }, { colorSaturation: [0.2, 0.8], itemStyle: { gapWidth: 1 } }, { colorSaturation: [0.35, 0.5], itemStyle: { gapWidth: 1, borderColorSaturation: 0.6 } }] })],
    ['M2', () => ({ itemStyle: { borderWidth: 2, borderColorSaturation: 0.4 }, levels: [{}, { colorSaturation: [0.8, 0.2] }, { itemStyle: { colorSaturation: 0.5 } }] })],
    ['M2', () => ({ sort: 'asc', colorSaturation: [0.45], levels: [{ color: ['#c23531', '#2f4554', 'rgb(97,160,168)', '#d48265cc'] }, { itemStyle: { borderColorSaturation: 0.9, borderWidth: 3 } }] })],
    ['M2', () => ({ sort: false, colorSaturation: [0.2, 0.9], itemStyle: { opacity: 0.8, borderWidth: 1, borderColorSaturation: 0 } })],
    ['M3', () => ({ upperLabel: { show: true }, itemStyle: { borderWidth: 2 }, levels: [{ upperLabel: { show: false } }] })],
    ['M3', () => ({ upperLabel: { show: true, height: 30 }, levels: [{ itemStyle: { borderColor: '#777', borderWidth: 0, gapWidth: 1 }, upperLabel: { show: false } }, { itemStyle: { borderColor: '#555', borderWidth: 5, gapWidth: 1 } }, { colorSaturation: [0.35, 0.5], itemStyle: { borderWidth: 5, gapWidth: 1, borderColorSaturation: 0.6 } }] })],
    ['M3', () => ({ name: 'Ser', upperLabel: { show: true, height: 10, color: '#fff', fontSize: 14, formatter: '{b}:{c}' }, itemStyle: { borderWidth: 14, borderColor: '#5070dd' }, label: { formatter: 'L {b}' } })],
    ['M3', () => ({ upperLabel: { show: true, position: 'inside', padding: [2, 8] }, levels: [{ itemStyle: { borderColor: '#222', borderWidth: 1 } }, { itemStyle: { borderColor: '#777', borderWidth: 4 } }, { itemStyle: { borderColor: '#ddd', borderWidth: 3 } }, { itemStyle: { borderColorSaturation: 0.3, borderWidth: 2 } }] })],
    ['M3', () => ({ upperLabel: { show: true, height: 25, position: [4, '30%'] }, label: { formatter: '{b}' }, levels: [{}, { upperLabel: { show: true, height: 18 } }, { upperLabel: { show: false } }] })],
    ['M3', () => ({ upperLabel: { show: true }, itemStyle: { borderWidth: 1, borderColor: 'rgba(0,0,0,0.3)' } }), { backgroundColor: '#1b1b1b' }],
  ];
  const BOXES = [{}, { left: 50, right: 90, top: 90, bottom: 90 }, { left: 250, right: 250, top: 200, bottom: 200 }, { top: 125, bottom: 125 }, { left: 150, right: 150 }];
  const out = [];
  for (let f = 0; f < nForests; f++) {
    const data = genForest();
    for (let v = 0; v < VARIANTS.length; v++) {
      const [batch, mk, extra] = VARIANTS[v];
      const b = (f + v) % BOXES.length;
      const opt = Object.assign({ type: 'treemap', data: zrClone(data) }, BOXES[b], mk());
      out.push({ id: 'R23-f' + f + 'v' + v, batch, note: 'M2 / M3 random forest ' + f + ', variant ' + v + ', box ' + b, option: Object.assign({ animation: false, series: [opt] }, extra || {}), random: { family: 'M23', forest: f, variant: v, box: b } });
    }
  }
  return out;
}

// ============================================================================
// M4 (drill-down), M5 (value-mapped colour), M6 (multi-series): hand cases, then the random families
// ============================================================================
function M456_CASES() {
  const D1x = D1;
  const D4 = () => [
    { name: 'Alpha', children: [{ name: 'a1', value: 6, children: [{ name: 'a11', value: 4 }, { name: 'a12', value: 2 }] }, { name: 'a2', value: 3 }] },
    { name: 'Beta', children: [{ name: 'b1', value: 5 }, { name: 'b2', value: 4, children: [{ name: 'b21', value: 3 }, { name: 'b22', value: 1 }] }] },
    { name: 'Gamma', value: 4 },
  ];
  // value arrays [size, dim1, dim2] with a null
  const V = () => [
    { name: 'A', value: [10, 1, -50], children: [{ name: 'a1', value: [6, 5, -80] }, { name: 'a2', value: [3, 2, 20] }, { name: 'a3', value: [1, 9, 100] }] },
    { name: 'B', value: [8, 4, 0], children: [{ name: 'b1', value: [5, null, 60] }, { name: 'b2', value: [3, 7, -10] }] },
    { name: 'C', value: [2, 3, 150] },
  ];
  const RGB3 = ['#942e38', '#aaa', '#269f3c'];
  const C6 = ['#c23531', '#314656', '#61a0a8', '#dd8668', '#91c7ae', '#6e7074'];
  const byValue = list => [{}, { color: list, colorMappingBy: 'value' }];
  const m4 = (id, note, option) => ({ id, batch: 'M4', note, option });
  const m5 = (id, note, option) => ({ id, batch: 'M5', note, option });
  const m6 = (id, note, option) => ({ id, batch: 'M6', note, option });
  const three = (extraSeries, legend) => ({ animation: false, legend, series: ['S0', 'S1', 'S2'].map(nm => Object.assign({ type: 'treemap', name: nm, data: D4() }, extraSeries || {})) });
  // a leaf whose label box is exactly 0.5 wider than its text: the plain layout truncates (containerWidth =
  // width - 1), the rich layout keeps it (it truncates only a token WIDER than the box)
  const snug = rich => {
    const nm = 'Elephant';
    const w = measure(nm, 'normal normal 12px Microsoft YaHei');
    return one({ data: [{ name: nm, value: 1 }], left: 20, width: w + 10.5, top: 50, height: 200, label: rich ? { rich: { r: {} } } : {} });
  };
  const obama = sel => { const o = gallery('treemap-obama'); o.legend.selected = sel; return o; };
  return [
    // ---- M4: leafDepth ----
    m4('M4-leafDepth-1', "leafDepth 1 on D1: A and B are leaf roots (drawn as leaves with '\u25b6 ' labels, their children keep only {area}); the crumb is the root alone (findTarget would give root > B)", one({ data: D1x(), leafDepth: 1 })),
    m4('M4-leafDepth-2', "leafDepth 2 on D4: a1 and b2 are leaf roots; levels[2] label formatter '{b}' gets the icon too", one({ data: D4(), leafDepth: 2, levels: [{}, {}, { label: { formatter: '{b}' } }] })),
    m4('M4-leafDepth-0', "leafDepth 0: the root itself is the leaf root ('\u25b6 S', no colour: fill null); the crumb is 'S'", one({ name: 'S', data: D4(), leafDepth: 0 })),
    m4('M4-cvm-leafDepth-wins', 'childrenVisibleMin 200000 hides the children of Alpha / Beta, but leafDepth 2 has priority there: a1 and b2 are still leaf roots with icons', one({ data: D4(), leafDepth: 2, childrenVisibleMin: 200000 })),
    m4('M4-cvm-hides-first', 'childrenVisibleMin 200000 with leafDepth 3: at depth 2 the hide wins (a1, b2 are plain leaves, no icon, no isLeafRoot)', one({ data: D4(), leafDepth: 3, childrenVisibleMin: 200000 })),
    m4('M4-icon-custom', "drillDownIcon '>>': '>> Beta'", one({ data: D4(), leafDepth: 1, drillDownIcon: '>>' })),
    m4('M4-icon-empty', "drillDownIcon '' (falsy): leaf roots keep their plain text", one({ data: D4(), leafDepth: 1, drillDownIcon: '' })),
    m4('M4-icon-nameless', "unnamed series, nameless leaf roots: without a formatter the text is null (no icon, no tspan); an item formatter '{b}' gives '' and so '\u25b6 '", one({ data: [{ value: 3, children: [{ value: 1 }, { value: 2 }] }, { name: 'n', value: 2, children: [{ value: 2 }] }, { value: 1.5, label: { formatter: '{b}' }, children: [{ value: 1 }] }], leafDepth: 1 })),
    m4('M4-icon-ignored', "levels[1] label show false with formatter 'F{b}': the IGNORED Texts of the leaf roots carry '\u25b6 FBeta', Gamma (a plain leaf) 'FGamma'", one({ data: D4(), leafDepth: 1, levels: [{}, { label: { show: false, formatter: 'F{b}' } }] })),
    m4('M4-upper', 'leafDepth 2 with upperLabel: a leaf root reserves the header strip in its layout but draws its content label (with the icon), no header', one({ data: D4(), leafDepth: 2, upperLabel: { show: true }, itemStyle: { borderWidth: 2 } })),
    m4('M4-visibleMin', "a leaf root whose zero child was cut by visibleMin (only p1 gets {area}); an all-zero sibling is cut at the root", one({ data: [{ name: 'P', children: [{ name: 'p1', value: 100 }, { name: 'p0', value: 0 }] }, { name: 'Z', children: [{ name: 'z0', value: 0 }] }, { name: 'Q', value: 5 }], leafDepth: 1 })),
    m4('M4-sat-bcs', 'leafDepth 1 with a series colorSaturation range and levels[1] borderColorSaturation 0.5: leaf roots map nothing, they keep their palette colour and get the saturated border', one({ data: D4(), leafDepth: 1, colorSaturation: [0.3, 0.7], levels: [{}, { itemStyle: { borderColorSaturation: 0.5, borderWidth: 2 } }] })),
    m4('M4-drill-down-mini', 'the gallery drill-down configuration on a small tree', one({ name: 'option', visibleMin: 300, leafDepth: 2, data: D4().concat([{ name: 'Delta', children: [{ name: 'd1', value: 2, children: [{ name: 'd11', value: 1 }, { name: 'd12', value: 1 }] }, { name: 'd2', value: 1 }] }]), levels: [{ itemStyle: { borderColor: '#555', borderWidth: 4, gapWidth: 4 } }, { colorSaturation: [0.3, 0.6], itemStyle: { borderColorSaturation: 0.7, gapWidth: 2, borderWidth: 2 } }, { colorSaturation: [0.3, 0.5], itemStyle: { borderColorSaturation: 0.6, gapWidth: 1 } }, { colorSaturation: [0.3, 0.5] }] })),
    // ---- M5: colorMappingBy 'value' ----
    m5('M5-value-dim0', "levels[1].color ['#942e38', '#aaa', '#269f3c'] with colorMappingBy 'value' (dimension 0): a2 (3 over [1, 6]) -> t 0.4 -> 0.8 between entries 0 and 1 -> rgba(166,145,147,1); depth-1 nodes have no colour (C: fill null)", one({ data: V(), levels: byValue(RGB3) })),
    m5('M5-dim2', 'visualDimension 2 (the extents and the mapped values read value[2])', one({ data: V(), visualDimension: 2, levels: byValue(RGB3) })),
    m5('M5-dim2-minmax', 'visualMin -100 / visualMax 100 widen every extent that does not reach them (B [-10, 60] -> [-100, 100]); A [-80, 100] keeps its max', one({ data: V(), visualDimension: 2, visualMin: -100, visualMax: 100, levels: byValue(RGB3) })),
    m5('M5-nan', 'visualDimension 1 with null entries: NaN never enters the extent; over [4, 7] a NaN normalises to NaN and fastLerp gives no colour (fill null); over a degenerate [6, 6] linearMap returns 0.5 for anything, NaN included (rgba(128,128,128,1))', one({ data: [{ name: 'P', children: [{ name: 'p1', value: [5, null] }, { name: 'p2', value: [3, 7] }, { name: 'p3', value: [2, 4] }] }, { name: 'Q', children: [{ name: 'q1', value: [4, null] }, { name: 'q2', value: [3, 6] }] }], visualDimension: 1, levels: byValue(['#000', '#fff']) })),
    m5('M5-value-string', "visualDimension 'value' (the string) with the default sort: statistic takes [last, first] of the sorted children", one({ data: V(), visualDimension: 'value', levels: byValue(['#000', '#fff']) })),
    m5('M5-value-string-asc', "visualDimension 'value' with sort 'asc': [last, first] reversed", one({ data: V(), sort: 'asc', visualDimension: 'value', levels: byValue(['#000', '#fff']) })),
    m5('M5-one-colour', "a one-colour list ['#123456'] by value: every child rgba(18,52,86,1) (fastLerp over one colour)", one({ data: V(), levels: byValue(['#123456']) })),
    m5('M5-alpha-colours', "colours with alpha: 'rgba(255,0,0,0.2)', '#00ff0080' (a = 128 / 255), 'blue'; the alpha lerps unrounded (0.4415686274509804)", one({ data: V(), levels: byValue(['rgba(255,0,0,0.2)', '#00ff0080', 'blue']) })),
    m5('M5-root-linear', "levels[0].color ['#000', '#fff'] by value: the ROOT maps its children linearly (A white, B rgba(191,191,191,1), C black), their children inherit", one({ data: V(), levels: [{ color: ['#000', '#fff'], colorMappingBy: 'value' }] })),
    m5('M5-series-linear', "series color ['#000', '#fff'] with colorMappingBy 'value': the root's palette (levels[0]) is mapped linearly too (C gets rgba(80,112,221,1)), every parent below maps black to white", one({ data: V(), color: ['#000', '#fff'], colorMappingBy: 'value' })),
    m5('M5-dim-absent', 'visualDimension 9 (past the 3 stored dimensions): every value NaN, extents [Infinity, -Infinity], no mapped colour', one({ data: V(), visualDimension: 9, levels: byValue(['#000', '#fff']) })),
    m5('M5-scalar-dims', 'a SCALAR value answers every dimension: P (no value: completed to the scalar 5) and R (3) read 5 and 3 at dimension 2 in the root mapping', one({ data: [{ name: 'P', children: [{ name: 'p1', value: [3, 1, -20] }, { name: 'p2', value: [2, 1, 30] }] }, { name: 'Q', value: [4, 1, -30] }, { name: 'R', value: 3 }], visualDimension: 2, levels: [{ color: ['#000', '#fff'], colorMappingBy: 'value' }] })),
    m5('M5-past-dimmax', 'dimension 3 with 3 stored dimensions: NaN even for the scalar R (a dimension past the store reads NaN before the scalar rule)', one({ data: [{ name: 'P', children: [{ name: 'p1', value: [3, 1, -20] }, { name: 'p2', value: [2, 1, 30] }] }, { name: 'Q', value: [4, 1, -30] }, { name: 'R', value: 3 }], visualDimension: 3, levels: [{ color: ['#000', '#fff'], colorMappingBy: 'value' }] })),
    m5('M5-visualmin-inside', 'visualMin 2 / visualMax 3 only widen where they fall outside: A [1, 6] unchanged, B [3, 5] -> [2, 5]', one({ data: V(), visualMin: 2, visualMax: 3, levels: byValue(['#000', '#fff']) })),
    m5('M5-sat-dim', 'a colorSaturation range mapped by visualDimension 1 with visualMin -10 (the same linear map, another dimension)', one({ data: V(), visualDimension: 1, visualMin: -10, levels: [{}, { colorSaturation: [0.2, 0.8] }] })),
    m5('M5-visual-mini', 'the gallery visual configuration on a small four-dimension tree', one({ name: 'ALL', top: 80, label: { show: true, formatter: '{b}' }, itemStyle: { borderColor: 'black' }, visualMin: -100, visualMax: 100, visualDimension: 3, levels: [{ itemStyle: { borderWidth: 3, borderColor: '#333', gapWidth: 3 } }, { color: RGB3, colorMappingBy: 'value', itemStyle: { gapWidth: 1 } }], data: [{ name: 'H', value: [120, null, null, 0], children: [{ name: 'h1', value: [100, 90, 3.1, 40.1] }, { name: 'h2', value: [20, 25, -1.5, -20] }] }, { name: 'D', value: [80, null, null, 0], children: [{ name: 'd1', value: [50, 55, -9, -120] }, { name: 'd2', value: [30, 20, 50, 250] }, { name: 'd3', value: [5, 5, 0, 0] }] }] })),
    // ---- M6: colorMappingBy 'id', colorAlpha, series colour list, label positions, rich, legend ----
    m6('M6-id-root', "levels[0] colour list with colorMappingBy 'id': the root maps its children by mapIdToIndex (Beta 0, Alpha 1, Gamma 2: first-seen = sorted order here)", one({ data: D4(), levels: [{ color: C6, colorMappingBy: 'id' }] })),
    m6('M6-id-series', "series color list + colorMappingBy 'id': ONE counter per series over the pre-order visual traversal (Beta 0, b1 1, b2 2, b21 3, b22 4, Alpha 5, a1 6, a11 7, a12 8, a2 9, Gamma 10); the root maps the palette, deeper parents the series list", one({ data: D4(), color: C6, colorMappingBy: 'id' })),
    m6('M6-id-dup', "ids: series 'x' (the root's id 'x'), then 'x' -> 'x__ec__2', 'x__ec__3'; an explicit id 'y' shares the index of the name 'y'; a nameless row gets 'e' NUL NUL + dataIndex", one({ name: 'x', data: [{ name: 'x', value: 5, children: [{ name: 'x', value: 2 }, { name: 'y', value: 3 }] }, { name: 'x', value: 4 }, { id: 'y', name: 'z', value: 3 }, { value: 2 }], color: C6, colorMappingBy: 'id' })),
    m6('M6-id-numeric', "numeric ids and names become strings ('7'); a row with its own id does not count its name ({id: 'k', name: 'w'} then {name: 'w'} gives 'w', not 'w__ec__2')", one({ data: [{ id: 7, name: 'w', value: 4 }, { name: 'w', value: 3 }, { name: 7, value: 2 }, { name: 'q', value: 1.5 }], levels: [{ color: C6, colorMappingBy: 'id' }] })),
    m6('M6-series-color-index', "series color ['#111', '#222', '#333'] (index): every parent below the root maps it, restarting at 0", one({ data: D4(), color: ['#111', '#222', '#333'] })),
    m6('M6-alpha-ranges', 'levels[1].colorAlpha [0.5, 1] maps depth-2 alpha (a truthy 1 still rewrites #5070dd as rgba(80,112,221,1)); levels[2].colorAlpha [0.2] is paired [0.2, 0.2]', one({ data: D4(), levels: [{}, { colorAlpha: [0.5, 1] }, { colorAlpha: [0.2] }] })),
    m6('M6-alpha-item', 'itemStyle.colorAlpha: 0.3 on Alpha (its border: modifyHSL of rgba(...,0.3) keeps 0.3), 0 on b1 (falsy: #5070dd unchanged), 0.6 on levels[2] (inherited below); root border null (no colour)', one({ data: (() => { const d = D4(); d[0].itemStyle = { colorAlpha: 0.3 }; d[1].children[0].itemStyle = { colorAlpha: 0 }; return d; })(), levels: [{}, {}, { itemStyle: { colorAlpha: 0.6 } }], itemStyle: { borderColorSaturation: 0.5, borderWidth: 2 } })),
    m6('M6-alpha-vs-sat', 'series colorAlpha [0.4, 0.9] and colorSaturation [0.3, 0.7]: a parent maps only ONE of them, the alpha (colour list > alpha > saturation)', one({ data: D4(), colorSaturation: [0.3, 0.7], colorAlpha: [0.4, 0.9] })),
    m6('M6-alpha-hex', "modifyAlpha keeps the parsed channels and replaces the alpha: '#d48265cc' -> rgba(212,130,101,0.8), 'rgba(10,20,30,0.5)' -> 0.1 / 0.8; '#abc' (never alpha-mapped) stays '#abc'", one({ data: D4(), levels: [{ color: ['#d48265cc', 'rgba(10,20,30,0.5)', '#abc'] }, { colorAlpha: [0.1, 0.8] }] })),
    m6('M6-alpha-dim', "colorAlpha [0.3, 1] mapped by visualDimension 1: b1's null reads NaN, over B's extent [4, 7] the alpha is NaN, which is FALSY, so b1 keeps its plain '#5070dd' (no rgba; B ties A at 10 and sorts first); the other children get rgba(...,a)", one({ data: (() => { const d = V(); d[1].children.push({ name: 'b3', value: [2, 4, 5] }); d[1].value = [10, 4, 0]; return d; })(), visualDimension: 1, levels: [{}, { colorAlpha: [0.3, 1] }] })),
    m6('M6-insideTopLeft', "label.position 'insideTopLeft': the Text at (bw + T.x) + 0, (bw + T.y) + 0 (distance 0), tspans left / top at x = pad[3] = 5, y = lh / 2 + pad[0] = 11", one({ data: D4(), label: { position: 'insideTopLeft' }, itemStyle: { borderWidth: 2 } })),
    m6('M6-insideTopLeft-rich', "the same with a label.rich: the RICH layout, which for 'insideTopLeft' lands on the same x / y", one({ data: D4(), label: { position: 'insideTopLeft', rich: { a: { fontSize: 20 } } }, itemStyle: { borderWidth: 2 } })),
    m6('M6-inside-rich', "label.rich with the default 'inside': the rich layout puts the text at the TOP of the box (boxY = -(height + 10) / 2, y = boxY + 5 + lh / 2), x picks up float noise from the centring", one({ data: D4(), label: { rich: { a: { fontSize: 20 } } }, itemStyle: { borderWidth: 2 } })),
    m6('M6-positions', "positions per level: insideBottomRight with distance 4 on levels[1], insideTop with padding [2, 8] on levels[2], insideLeft on an item", one({ data: (() => { const d = D4(); d[1].children[0].label = { position: 'insideLeft' }; return d; })(), itemStyle: { borderWidth: 1 }, levels: [{}, { label: { position: 'insideBottomRight', distance: 4 } }, { label: { position: 'insideTop', padding: [2, 8] } }] })),
    m6('M6-snug-plain', "a label box 0.5 wider than 'Elephant': the plain layout truncates it (containerWidth = width - 1)", snug(false)),
    m6('M6-snug-rich', "the same with a label.rich: the rich layout keeps 'Elephant' (it truncates only a token WIDER than the box)", snug(true)),
    m6('M6-legend-single', "three series and a legend in selectedMode 'single' with no selection: the first legend item S0 is selected, S1 and S2 are filtered (no layout, no elements)", three(null, { data: ['S0', 'S1', 'S2'], selectedMode: 'single' })),
    m6('M6-legend-selected-true', "selected {S2: true} does NOT pick S2: 'single' selects the first legend item that is not explicitly false (S0)", three(null, { data: ['S0', 'S1', 'S2'], selectedMode: 'single', selected: { S2: true } })),
    m6('M6-legend-false-first', 'selected {S0: false}: S1 is the first not-false item and is the one drawn', three({ colorMappingBy: 'id', color: C6 }, { data: ['S0', 'S1', 'S2'], selectedMode: 'single', selected: { S0: false } })),
    m6('M6-legend-missing', "legend.data ['S1', 'S2'] in 'single' mode: S1 is selected, S2 filtered, and S0 (not in the legend) stays drawn: two series draw", three(null, { data: ['S1', 'S2'], selectedMode: 'single' })),
    m6('M6-legend-multiple', "a legend in the default (multiple) mode with {S1: false}: S0 and S2 draw", three(null, { data: ['S0', 'S1', 'S2'], selected: { S1: false } })),
    m6('M6-two-series', "two drawn series side by side, each with its own id map (the second's indices start at 0 again) and its own levels[0] palette copy", { animation: false, series: [Object.assign({ type: 'treemap', name: 'L', data: D4(), right: '50%', colorMappingBy: 'id', color: C6 }), Object.assign({ type: 'treemap', name: 'R', data: D4(), left: '50%', colorMappingBy: 'id', color: C6, levels: [{}, { colorAlpha: [0.4, 1] }] })] }),
    m6('M6-obama-growth', "the gallery obama option with legend.selected {2012Budget: false, 2011Budget: false}: 'Growth' draws -- levels[0] colour list by id, levels[1].colorAlpha [0.5, 1] over visualDimension 2 (a null growth gives NaN, a falsy alpha: the colour stays)", obama({ '2012Budget': false, '2011Budget': false })),
  ];
}

// the M4-M6 random families: ref.js's genForest3 / VARIANTS3 (wf79) on their own seeds
function randomCasesM456(nForests) {
  const mkRng = s0 => { const r = { s: s0 }; r.rnd = () => { r.s = (r.s * 1103515245 + 12345) & 0x7fffffff; return r.s / 0x7fffffff; }; r.ri = n => Math.floor(r.rnd() * n); return r; };
  const NAMES = ['a', 'bb', 'Cat', 'dog', 'Elephant', 'LongNameAbcdefghijk', '中文', 'x y', 'W', 'm'];
  function genNode(depth, maxDepth, r) {
    const n = {};
    const t0 = r.rnd();
    if (t0 < 0.85) n.name = NAMES[r.ri(NAMES.length)] + (r.rnd() < 0.5 ? String(r.ri(12)) : '');
    else if (t0 < 0.88) n.name = 'two\nlines';
    if (r.rnd() < 0.3) n.id = 'id' + r.ri(8);
    const k = depth < maxDepth ? r.ri(5) : 0;
    const arr = () => { const a = [r.ri(40) + 1]; const m = r.ri(4); for (let i = 0; i < m; i++) { const u = r.rnd(); a.push(u < 0.12 ? null : u < 0.5 ? r.ri(200) - 100 : +(r.rnd() * 50 - 25).toFixed(2)); } return a; };
    if (k > 0 && r.rnd() < 0.8) {
      n.children = [];
      for (let i = 0; i < k; i++) n.children.push(genNode(depth + 1, maxDepth, r));
      const u = r.rnd();
      if (u < 0.25) n.value = arr(); else if (u < 0.35) n.value = r.ri(60);
    } else {
      const t = r.rnd();
      n.value = t < 0.05 ? 0 : t < 0.08 ? undefined : t < 0.6 ? arr() : t < 0.7 ? +(r.rnd() * 30).toFixed(3) : r.ri(40) + 1;
      if (n.value === undefined) delete n.value;
    }
    if (r.rnd() < 0.2) {
      const u = r.rnd();
      n.itemStyle = {};
      if (u < 0.25) n.itemStyle.colorAlpha = [0, 0.3, 0.75, 1][r.ri(4)];
      else if (u < 0.4) n.colorAlpha = [0.2 + r.ri(4) / 10, 1 - r.ri(3) / 10];
      else if (u < 0.5) n.itemStyle.colorSaturation = +(r.rnd()).toFixed(2);
      else if (u < 0.6) n.itemStyle.color = ['#8a2be2', '#ff994d80', 'rgb(1,200,90)', 'rgba(20,40,60,0.4)'][r.ri(4)];
      else if (u < 0.7) n.itemStyle.borderColorSaturation = [0, 0.5, 0.8][r.ri(3)];
      else if (u < 0.8) { n.color = [['#000', '#fff'], ['#c23531', '#2f4554', '#61a0a8'], ['#123456']][r.ri(3)]; if (r.rnd() < 0.5) n.colorMappingBy = ['value', 'id', 'index'][r.ri(3)]; }
      else if (u < 0.9) { n.visualMin = -r.ri(50); n.visualMax = r.ri(80); }
      else n.label = { show: r.rnd() < 0.7, formatter: '{b}' };
    }
    return n;
  }
  const VARIANTS = [
    ['M4', r => ({ leafDepth: 1, levels: [{}, { label: { formatter: '{b}' } }] })],
    ['M4', r => ({ leafDepth: 2, childrenVisibleMin: 30000, itemStyle: { borderWidth: 1 } })],
    ['M4', r => ({ leafDepth: 3, childrenVisibleMin: 60000, upperLabel: { show: true }, drillDownIcon: '>>', itemStyle: { borderWidth: 2 } })],
    ['M4', r => { const o = { leafDepth: r.ri(2), name: 'Ser', drillDownIcon: ['', '\u25b6', '+'][r.ri(3)], label: { show: r.rnd() < 0.8 } }; if (r.rnd() < 0.5) o.label.formatter = 'F{b}'; return o; }],
    ['M5', r => ({ visualDimension: 1, visualMin: -5, visualMax: 30, levels: [{}, { color: ['#942e38', '#aaa', '#269f3c'], colorMappingBy: 'value' }] })],
    ['M5', r => ({ color: ['#000', '#fff'], colorMappingBy: 'value', visualDimension: r.ri(3) })],
    ['M5', r => ({ sort: 'asc', visualDimension: 'value', levels: [{ color: ['#123', 'rgba(200,100,50,0.5)', '#abcdef80'], colorMappingBy: 'value' }, { colorSaturation: [0.3, 0.7] }] })],
    ['M5', r => ({ visualDimension: 2, levels: [{ itemStyle: { borderWidth: 2, gapWidth: 2 } }, { color: ['red', 'blue'], colorMappingBy: 'value', visualMin: -100 }, { color: ['#111111', '#eeeeee'], colorMappingBy: 'value', visualMax: 100 }] })],
    ['M6', r => ({ color: ['#c23531', '#314656', '#61a0a8', '#dd8668', '#91c7ae', '#6e7074'], colorMappingBy: 'id' })],
    ['M6', r => ({ visualDimension: 1, levels: [{}, { colorAlpha: [0.5, 1] }, { colorAlpha: [0.2] }] })],
    ['M6', r => ({ colorAlpha: [0.3, 0.9], colorSaturation: [0.2, 0.8], itemStyle: { borderWidth: 2, borderColorSaturation: 0.6 }, levels: [{}, { itemStyle: { colorAlpha: 0.7 } }] })],
    ['M6', r => ({ label: { position: 'insideTopLeft', rich: { a: { fontSize: 20 } } }, itemStyle: { borderWidth: 2 }, levels: [{ itemStyle: { borderWidth: 3, gapWidth: 3 }, colorMappingBy: 'id' }, { itemStyle: { gapWidth: 1 } }] })],
    ['M6', r => { const lb = { position: INSIDE_POSITIONS[r.ri(9)], padding: [[2, 8], 5, [1, 2, 3, 4], 0][r.ri(4)], distance: r.ri(3) * 3 }; if (r.rnd() < 0.5) lb.rich = { x: {} }; lb.fontSize = [12, 14][r.ri(2)]; return { label: lb }; }],
    ['M6', r => ({ levels: [{ color: ['#5070dd', '#b6d634', '#505372'], colorMappingBy: 'id' }, { color: ['#111', '#222', '#333', '#444'], colorMappingBy: 'id' }, { colorAlpha: [0.4, 0.8] }] })],
    ['M6', r => ({ MULTI: { legend: { selectedMode: 'single', selected: r.rnd() < 0.5 ? { S0: false } : {} }, n: 3 }, colorMappingBy: 'id', color: ['#c23531', '#314656', '#61a0a8'] })],
    ['M6', r => ({ MULTI: { n: 2, second: { left: '50%', colorAlpha: [0.4, 1] } }, right: '50%', levels: [{}, { colorAlpha: [0.5, 0.9] }] })],
  ];
  const BOXES = [{}, { left: 50, right: 90, top: 90, bottom: 90 }, { left: 250, right: 250, top: 200, bottom: 200 }, { top: 125, bottom: 125 }, { left: 150, right: 150 }];
  const r0 = mkRng(797979);
  const out = [];
  for (let f = 0; f < nForests; f++) {
    const n = 1 + r0.ri(6); const md = 1 + r0.ri(4);
    const data = []; for (let i = 0; i < n; i++) data.push(genNode(1, md, r0));
    for (let v = 0; v < VARIANTS.length; v++) {
      const [batch, mk] = VARIANTS[v];
      const r = mkRng(1000 * f + v + 1);
      const vo = mk(r);
      const multi = vo.MULTI; delete vo.MULTI;
      const hasBox = ['left', 'right', 'top', 'bottom', 'width', 'height'].some(k => k in vo);
      const b = hasBox || multi ? null : (f + v) % BOXES.length;
      let option;
      if (multi) {
        const series = [];
        for (let k = 0; k < multi.n; k++) series.push(Object.assign({ type: 'treemap', name: 'S' + k, data: zrClone(data) }, zrClone(vo), k === 1 && multi.second ? multi.second : {}));
        option = { animation: false, series };
        if (multi.legend) option.legend = Object.assign({ data: series.map(s => s.name) }, multi.legend);
      } else option = { animation: false, series: [Object.assign({ type: 'treemap', data: zrClone(data) }, b == null ? {} : BOXES[b], vo)] };
      out.push({ id: 'R456-f' + f + 'v' + v, batch, note: 'M4-M6 random forest ' + f + ', variant ' + v + (b == null ? '' : ', box ' + b), option, random: { family: 'M456', forest: f, variant: v, box: b } });
    }
  }
  return out;
}

// gaps the Pascal mutation run found (appended after everything else)
function GAP_CASES() {
  const D2 = () => [
    { name: 'A', children: [{ name: 'A1', value: 4 }, { name: 'A2', value: 2 }, { name: 'A3', value: 1 }] },
    { name: 'B', value: 10, children: [{ name: 'B1', value: 3 }, { name: 'B2', value: 5, children: [{ name: 'B21', value: 5 }] }, { name: 'B3', value: 0 }] },
    { name: 'C', value: 3 },
    { name: 'D', value: 4, color: ['#aa0000', '#00aa00'], children: [{ name: 'D1', value: 3 }, { name: 'D2', value: 1 }] },
  ];
  const long = 'LongNameAbcdefghijk and more';
  const lw = measure(long, 'normal normal 12px Microsoft YaHei');
  return [
    { id: 'M2-series-itemstyle-sat', batch: 'M2', note: "series itemStyle.colorSaturation 0.3 with levels[1].colorSaturation [0.4, 0.8]: the chain is item > level > DESIGNATED > series, so A's and B's children take the mapped value (the series 0.3 loses), while C (a depth-1 leaf: the root maps colours, not saturation) and D's children (D maps its own colour list) keep 0.3 -- through the root's visuals (the root reads the series value first and hands it down)", option: one({ data: D2(), itemStyle: { colorSaturation: 0.3 }, levels: [{}, { colorSaturation: [0.4, 0.8] }] }) },
    { id: 'M3-upper-padding-truncate', batch: 'M3', note: "upperLabel padding [0, 30, 0, 30] on a parent exactly 20 wider than its name: the header text box is w - 2bw - pad[1] - pad[3] = name width - 40, so the name is truncated (without the padding it would fit: containerWidth = name width + 19)", option: one({ data: [{ name: long, children: [{ name: 'x', value: 1 }] }], left: 20, width: lw + 20, upperLabel: { show: true, padding: [0, 30, 0, 30] }, levels: [{ upperLabel: { show: false } }] }) },
  ];
}
