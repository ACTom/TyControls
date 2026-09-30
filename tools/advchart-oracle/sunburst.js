/*
Upstream's own answers for the SUNBURST series: the data model, the layout, the
colour visual, every sector and every label exactly as
chart/sunburst/SunburstSeries.ts (getInitialData: the virtual root named after
the series name, completeTreeValue BEFORE the tree is built -- it mutates the
option objects and concatenates string values with JS '+' --, the level-model
wrap item -> levels[depth] -> series), data/Tree.ts (createTree, pre-order data
indices, depth / height), chart/sunburst/sunburstLayout.ts (centre / radius on
the whole canvas, the unit angle, initChildren's in-place sort, renderNode's
`end - start` accumulator, levels[d].radius / r0 / r), sunburstVisual.ts (the
palette keyed by the depth-1 ancestor, lazily consumed in SORTED pre-order from
one scope shared by every sunburst series, lift by depth), SunburstView.ts
(which nodes become pieces, the group order), SunburstPiece.ts (the Sector
shape incl. getSectorCornerRadius' precedence bug, lineJoin 'bevel', the label
anchor / align / rotation / flip / minAngle), zrender roundSector.buildPath +
PathProxy (the sector path commands) and zrender's attached-text rules
(Element.updateInnerText, Path.getInsideTextFill / Stroke, Element.getOutside*
, ZRText._updatePlainTexts) build them.

Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) at 800 x 600
(every gallery file: examples/advchart/gallery/index.json gives no size) with
Math.random replaced by the port's xorshift32 (seed 2463534242, reset before
each chart) and process.env.TZ = 'UTC' set inside this script before anything
touches Date (checked: a script that runs under another zone stops). EVERY case
is rendered with `animation: false`: an option that does not say so (the
gallery files) gets it set before setOption and the case records
animationForced true -- without it every sector would sit at shape.r = r0 (the
'expansion' start) since nothing here steps an animation frame. After setOption
it runs zr.storage.getDisplayList(true) (every element's update: transforms,
updateInnerText, TSpan layout) and reads the live models, views and the display
list. Every chart is disposed in a finally. Every case is recorded from the
DEVELOPMENT build (dist/echarts.js) and must record identically through the
PRODUCTION build (dist/echarts.min.js).

  node tools/advchart-oracle/sunburst.js

writes tests/fixtures/advchart-sunburst.json (ORACLE_OUT overrides;
ORACLE_DUMP=<file> also writes the record before the checks, for debugging).

-----------------------------------------------------------------------------
Numbers are plain JSON numbers written by JSON.stringify (shortest round-trip
form). Values JSON has no form for:
  null        NaN in a number field (e.g. a label anchor whose r is undefined:
              align 'middle'), or an undefined value inside an array
  "-0" / "Infinity" / "-Infinity"   those doubles, as strings (the writer counts
              them and prints the count; startAngle 0 gives a "-0" geometry
              startAngle)
  an absent key   upstream holds undefined
A colour is a css string exactly as upstream holds it (or null).

Top level
  source, W, H, seed, tz ('UTC'), api {...}, notes[], cases[], guards[]
  cases[]  one per chart:
    id, note, gallery (file name or null), option (as fed, animation false
    included; null for a gallery case: load examples/advchart/gallery/<gallery>
    .json, set animation false when animationForced, and feed it VERBATIM
    otherwise), animationForced (bool), productionBuild (always false here),
    devError (null)
    ground     {background (zr.getBackgroundColor()), isDark (zr.isDarkMode())}
    textStyle  ecModel.option.textStyle (the global text style; fontFamily
               'Microsoft YaHei' on this Windows machine)
    palette    ecModel.option.color (the global palette the series fall back to)
    paintRuns  the WHOLE display list in paint order, run-length encoded:
               [{owner, index, type, group, zlevel, z, z2, n}]. owner 'series'
               (index = series index, type 'sunburst', group 'sector' (a piece's
               Sector) | 'label' (a label's TSpan) | 'labelBg' (a label's
               background Rect) | 'mark' (anything else)), 'component' (e.g.
               title, visualMap: group 'mark' / 'label'), 'other'
    series[]   one per series, series order:
      seriesIndex, type 'sunburst', name (the option name as a string, or
      null: upstream's default 'series\u0000<i>' is NOT written),
      option   the series keys the layout reads, as upstream holds them after
               the default merge: center, radius, startAngle, minAngle,
               clockwise, sort (null when present-null / present-undefined;
               'desc' when ABSENT), sortKeyPresent, stillShowZeroSum,
               renderLabelForZeroData, nodeClick, levels (count)
      geometry TRANSCRIBED intermediates (every row layout below reproduces
               from them bit for bit): width, height, size (= min), cx, cy, r0,
               r (series radius), startAngle ((-deg) * (PI / 180)), minAngle
               (deg * (PI / 180)), dir (1 | -1), sum (the view root's value),
               validDataCount, unitRadian (PI / (sum || count) * 2), rings
               (view root height - 1), rPerLevel ((r - r0) / (rings || 1)),
               viewRoot (0), rollup (false)
      dimensions  ['value', 'value0', ...]
      rows[]   EVERY SeriesData row, data-index order = pre-order of
               {name: series name, children: data} in the WRITTEN order:
        index, name (convertOptionIdName: '' for none, a number stringified;
        row 0 = the series option name or ''),
        valueWritten (json of the fed item's `value` key; absent when none),
        valueCompleted (the item's value after completeTreeValue: may be a
        concatenated STRING such as "053" or an array whose [0] was replaced),
        values [one per dimension] (the store: a scalar fills EVERY dim, an array
        fills dim k with element k; null / missing / non-numeric -> NaN), value
        (node.getValue(): dim 'value'), depth, height (leaf 1), parent (data
        index or null), children [data indices in the SORTED order = layout /
        draw / palette order], childrenWritten [data indices in option order],
        layout (null for row 0 undrilled, else {angle, startAngle, endAngle,
        clockwise, cx, cy, r0, r}), drawn (a piece exists), notDrawn (null |
        'virtualRoot' | 'zeroValue': !value and renderLabelForZeroData false),
        piece (index into pieces[] or null),
        fill (data.getItemVisual(i, 'style').fill: AFTER visualMap if any),
        colour TRANSCRIBED (checked: colour.fill === fill, or for a visualMap
        chart === the fill of the same chart rendered without the visualMap
        component): {source 'item' | 'level' | 'series' (the first itemStyle.color
        found on the chain item -> levels[depth] -> series) | 'palette' |
        'root' ('#86878c', tokens.color.neutral50), fill (the sunburstVisual
        fill), paletteKey (depth-1 ancestor name || its dataIndex + ''),
        paletteIndex (the index taken from the palette when this key was FIRST
        requested; the key cache is shared by all sunburst series), paletteFrom
        ('series' own color list | 'global'), base (the palette colour),
        lift ((depth - 1) / (treeHeight - 1) * 0.5, null at depth 1)}, and
        visualMapFill (bool: a visualMap overwrote the fill)
      pieces[]  the view group's children in order = the sectors' paint order
               (pre-order over the SORTED tree from the view root, zero-valued
               nodes skipped unless renderLabelForZeroData):
        row, shape {cx, cy, r0, r, startAngle, endAngle, clockwise,
        cornerRadius (0 or the resolved [4] array: getSectorCornerRadius --
        percent of `shape.r || (0 - shape.r0) || 0`, i.e. of r)}, commands (the
        built PathProxy, decoded M L A Z; A = cx, cy, rx, ry, startAngle, sweep,
        0, clockwise 1 / anticlockwise 0 -- startAngle is normalizeArcAngles'
        modPI2 (rounded to 1e-8 of PI) and the sweep follows it), style (own
        keys, 'blend' dropped), ink {fill, stroke, lineWidth, opacity, lineJoin,
        lineDash}, z, z2 (2), zlevel, silent, paint (display-list index)
        label  (every piece has one):
          text (null: no text -- empty name and no formatter), ignore,
          hiddenBy (TRANSCRIBED: null | 'show' | 'minAngle'), minAngle
          (label.minAngle / 180 * PI, null when unset), x, y (the anchor: final
          global -- the label has no parent transform and no origin), rotation,
          transform (the TSpans' parent m6, null when ignored or identity),
          align, verticalAlign (the style's: after the flip), position, rotate,
          distance (the chain values as upstream reads them), font, padding,
          style {fill, stroke, lineWidth, opacity} (the label's OWN style keys,
          null = absent: fill only for a concrete label.color), textConfig
          {inside, outsideFill}, inkDefault (null when ignored, else
          _innerTextDefaultStyle {fill, stroke, autoStroke}), ink (null, or what
          the TSpans draw: {fill, stroke, lineWidth, opacity}), tspans [{text,
          x, y, textAlign, textBaseline}] (TEXT WIDTHS are zrender's node
          measureText estimate), background (null or {shape, style, paint}),
          z, z2 (4), zlevel, silent, paint (the first TSpan's index or null)
  guards[]  one per mutation of the transcription: id, mutation, named,
            changed, ok (named is a subset of changed), differs

-----------------------------------------------------------------------------
The transcription (checked against every recorded series, Object.is on every
field it produces) takes as INPUTS only: each series option as fed merged over
SunburstSeriesModel.defaultOption with zrender merge semantics (a present null
/ undefined key blocks the default; checked against upstream's own option on the
keys read), the canvas size, the global palette (ecModel.option.color), the
global textStyle, the zr background colour and dark-mode flag, and -- for a
visualMap chart only -- the recorded sector fills (visualMap is not
transcribed). It reproduces: the rows (completeTreeValue incl. the string
concatenation, the store parse, pre-order, depth, height, sorted / written
children), the sort (desc / asc tie rules, null / absent), the layout (centre,
radius, unit angle, zero-sum, minAngle, the accumulator, level radii), the
colour visual (chain, palette scope, lift), the pieces (order, skip rule), the
Sector shape (corner radius), the path commands (roundSector + normalizeArcAngles),
the sector style, and every label (text incl. a string formatter, ignore /
minAngle, anchor, align after the flip, rotation with the double normalise,
verticalAlign, own style, textConfig, the inside / outside default fill and
stroke incl. dark mode and the background blend, the TSpan ink, the transform).
Fonts, TSpan positions and backgrounds are RECORDED, not transcribed.
Self-checks (any failure: nothing is written, exit 1): TZ is UTC; the
transcription reproduces every recorded series; an extra sweep of random
forests x option variants (not written) through upstream and the transcription
agrees; upstream.md's anchor numbers; within a series the paint order is all
sectors (group order) then all labels; the display list is sorted by
(zlevel, z, z2); the production build records every case identically; every
guard is ok; two generations in the process give identical bytes.
*/
'use strict';
process.env.TZ = 'UTC';
if (new Date(2017, 0, 1).getTimezoneOffset() !== 0 || new Date(2017, 6, 1).getTimezoneOffset() !== 0
  || new Date(2017, 0, 1).getTime() !== Date.UTC(2017, 0, 1)) {
  console.log('FAILED: process.env.TZ = \'UTC\' did not take effect (offset ' + new Date(2017, 0, 1).getTimezoneOffset() + ')');
  process.exit(1);
}
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const PROD_PATH = DIST.replace(/echarts(\.min)?\.js$/, 'echarts.min.js');
const PROD = require(PROD_PATH);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-sunburst.json');
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
  if (ArrayBuffer.isView(source)) return Array.from(source);
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
const retrieve2 = (a, b) => (a != null ? a : b);
const json = v => (v === undefined ? null : typeof v === 'function' ? '(function)' : zrClone(v));
const m6 = t => (t ? Array.from(t).slice(0, 6) : null);
const rect4 = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });

// ============================================================================
// The transcription (with the guards' mutations as switches)
// ============================================================================

// SunburstSeriesModel.defaultOption on the keys the transcription reads
const DEFAULTS = {
  z: 2, center: ['50%', '50%'], radius: [0, '75%'], clockwise: true, startAngle: 90, minAngle: 0, stillShowZeroSum: true, nodeClick: 'rootToNode',
  renderLabelForZeroData: false,
  label: { rotate: 'radial', show: true, opacity: 1, align: 'center', position: 'inside', distance: 5, silent: true },
  itemStyle: { borderWidth: 1, borderColor: 'white', borderType: 'solid', shadowBlur: 0, shadowColor: 'rgba(0, 0, 0, 0.2)', shadowOffsetX: 0, shadowOffsetY: 0, opacity: 1 },
  data: [], sort: 'desc',
};
const mergedOption = opt => zrMerge(zrClone(opt), DEFAULTS, false);
const READ_KEYS = ['z', 'zlevel', 'center', 'radius', 'clockwise', 'startAngle', 'minAngle', 'stillShowZeroSum', 'nodeClick', 'renderLabelForZeroData', 'label', 'itemStyle', 'sort', 'levels', 'name', 'color'];

// ---- util/number.ts parsePositionOption (parsePercent) ----
function parsePercent(option, percentBase, percentOffset) {
  switch (option) {
    case 'center': case 'middle': option = '50%'; break;
    case 'left': case 'top': option = '0%'; break;
    case 'right': case 'bottom': option = '100%'; break;
  }
  if (typeof option === 'string') {
    if (/%$/.test(option.trim())) return parseFloat(option) / 100 * percentBase + (percentOffset || 0);
    return parseFloat(option);
  }
  return option == null ? NaN : +option;
}
// zrender contain/text.ts parsePercent (corner radius)
function zrParsePercent(value, maxValue) {
  if (typeof value === 'string') {
    if (value.lastIndexOf('%') >= 0) return parseFloat(value) / 100 * maxValue;
    return parseFloat(value);
  }
  return value;
}
const PI = Math.PI;
const PI2 = Math.PI * 2;
const RADIAN = Math.PI / 180;
function normalizeRadian(a) { a %= PI2; if (a < 0) a += PI2; return a; }
const aroundZero = v => v > -1e-4 && v < 1e-4;

// ---- zrender tool/color.ts parse / lift / lum on the colours this fixture uses ----
const NAMED = { white: [255, 255, 255, 1], black: [0, 0, 0, 1], red: [255, 0, 0, 1], transparent: [0, 0, 0, 0], green: [0, 128, 0, 1], blue: [0, 0, 255, 1],
  orange: [255, 165, 0, 1], gray: [128, 128, 128, 1], lightsteelblue: [176, 196, 222, 1], none: null };
const clampByte = v => { v = Math.round(v); return v < 0 ? 0 : v > 255 ? 255 : v; };
const clampAlpha = v => (v < 0 ? 0 : v > 1 ? 1 : v);
function parseColor(c) {
  if (typeof c !== 'string') return null;
  const s = c.replace(/ /g, '').toLowerCase();
  if (hasOwn(NAMED, s)) return NAMED[s] ? NAMED[s].slice() : null;
  let m;
  if ((m = /^#([0-9a-f]{3})$/.exec(s))) return [0, 1, 2].map(i => parseInt(m[1][i] + m[1][i], 16)).concat(1);
  if ((m = /^#([0-9a-f]{6})$/.exec(s))) return [0, 2, 4].map(i => parseInt(m[1].substr(i, 2), 16)).concat(1);
  if ((m = /^(rgba?)\(([^)]*)\)$/.exec(s))) {
    const p = m[2].split(',');
    const ch = p.slice(0, 3).map(x => clampByte(/%$/.test(x) ? parseFloat(x) / 100 * 255 : parseFloat(x)));
    return ch.concat(p.length === 4 ? clampAlpha(parseFloat(p[3])) : 1);
  }
  must(false, 'the transcription cannot parse the colour ' + JSON.stringify(c));
  return null;
}
function lift(color, level) {
  const a = parseColor(color);
  if (!a) return undefined;
  for (let i = 0; i < 3; i++) {
    a[i] = level < 0 ? a[i] * (1 - level) | 0 : ((255 - a[i]) * level + a[i]) | 0;
    if (a[i] > 255) a[i] = 255; else if (a[i] < 0) a[i] = 0;
  }
  return 'rgba(' + a.join(',') + ')';
}
function lum(color, bgLum) {
  const a = parseColor(color);
  return a ? (0.299 * a[0] + 0.587 * a[1] + 0.114 * a[2]) * a[3] / 255 + (1 - a[3]) * bgLum : 0;
}

// Model.get through a chain of plain option objects: the first level whose path resolves non-null wins
function mget(levels, p) {
  const pa = isArray(p) ? p : [p];
  for (const lv of levels) {
    let o = lv;
    for (const k of pa) {
      o = o && typeof o === 'object' ? o[k] : null;
      if (o == null) break;
    }
    if (o != null) return o;
  }
  return undefined;
}
function mgetIdx(levels, p) {
  for (let i = 0; i < levels.length; i++) if (mget([levels[i]], p) != null) return i;
  return -1;
}
const nameOf = n => (n == null ? '' : String(n)); // convertOptionIdName(name, '')
const storeFloat = v => (v == null || v === '' ? NaN : Number(v));
function formatTpl(tpl, params) {
  const vars = ['seriesName', 'name', 'value'];
  const alias = ['a', 'b', 'c'];
  for (let i = 0; i < vars.length; i++) tpl = tpl.replace('{' + alias[i] + '}', '{' + alias[i] + '0}');
  for (let k = 0; k < vars.length; k++) tpl = tpl.replace('{' + alias[k] + '0}', params[vars[k]]);
  return tpl;
}

// ---- zrender core/matrix.ts + Transformable (rotation + translate only) ----
function rotateM(a, rad) {
  const aa = a[0]; const ac = a[2]; const atx = a[4]; const ab = a[1]; const ad = a[3]; const aty = a[5];
  const st = Math.sin(rad);
  const ct = Math.cos(rad);
  return [aa * ct + ab * st, -aa * st + ab * ct, ac * ct + ad * st, -ac * st + ct * ad, ct * (atx - 0) + st * (aty - 0) + 0, ct * (aty - 0) - st * (atx - 0) + 0];
}
const notAroundZero = v => v > 5e-5 || v < -5e-5;
function labelTransform(x, y, rotation) {
  if (!(notAroundZero(rotation) || notAroundZero(x) || notAroundZero(y))) return null;
  let m = [1, 0, 0, 1, 0, 0];
  if (rotation) m = rotateM(m, rotation);
  m[4] += x;
  m[5] += y;
  return m;
}

// ---- zrender graphic/helper/roundSector.ts + PathProxy (moveTo / lineTo / arc / closePath) ----
function modPI2(radian) {
  const n = Math.round(radian / PI * 1e8) / 1e8;
  return (n % 2) * PI;
}
function sectorPath(shape, mut) {
  const cmds = [];
  const M = (x, y) => cmds.push({ cmd: 'M', args: [x, y] });
  const L = (x, y) => cmds.push({ cmd: 'L', args: [x, y] });
  const A = (cx, cy, r, s, e, anticlockwise) => {
    let ns = mut.arcNoModPI2 ? s : modPI2(s);
    if (ns < 0) ns += PI2;
    const delta0 = ns - s;
    let ne = e + delta0;
    if (!anticlockwise && ne - ns >= PI2) ne = ns + PI2;
    else if (anticlockwise && ns - ne >= PI2) ne = ns - PI2;
    else if (!anticlockwise && ns > ne) ne = ns + (PI2 - modPI2(ns - ne));
    else if (anticlockwise && ns < ne) ne = ns - (PI2 - modPI2(ne - ns));
    cmds.push({ cmd: 'A', args: [cx, cy, r, r, ns, ne - ns, 0, anticlockwise ? 0 : 1] });
  };
  const e = 1e-4;
  const mathMax = Math.max;
  const mathMin = Math.min;
  let radius = mathMax(shape.r, 0);
  let innerRadius = mathMax(shape.r0 || 0, 0);
  const hasRadius = radius > 0;
  const hasInnerRadius = innerRadius > 0;
  if (!hasRadius && !hasInnerRadius) return cmds;
  if (!hasRadius) { radius = innerRadius; innerRadius = 0; }
  if (innerRadius > radius) { const tmp = radius; radius = innerRadius; innerRadius = tmp; }
  const startAngle = shape.startAngle;
  const endAngle = shape.endAngle;
  if (isNaN(startAngle) || isNaN(endAngle)) return cmds;
  const cx = shape.cx;
  const cy = shape.cy;
  const clockwise = !!shape.clockwise;
  let arc = Math.abs(endAngle - startAngle);
  const mod = arc > PI2 && arc % PI2;
  if (mod > e) arc = mod;
  if (!(radius > e)) M(cx, cy);
  else if (arc > PI2 - e) {
    M(cx + radius * Math.cos(startAngle), cy + radius * Math.sin(startAngle));
    A(cx, cy, radius, startAngle, endAngle, !clockwise);
    if (innerRadius > e) {
      M(cx + innerRadius * Math.cos(endAngle), cy + innerRadius * Math.sin(endAngle));
      A(cx, cy, innerRadius, endAngle, startAngle, clockwise);
    }
  } else {
    let icrStart; let icrEnd; let ocrStart; let ocrEnd; let ocrMax; let icrMax; let limitedOcrMax; let limitedIcrMax; let xre; let yre; let xirs; let yirs;
    const xrs = radius * Math.cos(startAngle);
    const yrs = radius * Math.sin(startAngle);
    const xire = innerRadius * Math.cos(endAngle);
    const yire = innerRadius * Math.sin(endAngle);
    const hasArc = arc > e;
    if (hasArc) {
      const cornerRadius = shape.cornerRadius;
      if (cornerRadius) {
        let arr;
        if (isArray(cornerRadius)) {
          const len = cornerRadius.length;
          arr = !len ? cornerRadius : len === 1 ? [cornerRadius[0], cornerRadius[0], 0, 0] : len === 2 ? [cornerRadius[0], cornerRadius[0], cornerRadius[1], cornerRadius[1]]
            : len === 3 ? cornerRadius.concat(cornerRadius[2]) : cornerRadius;
        } else arr = [cornerRadius, cornerRadius, cornerRadius, cornerRadius];
        [icrStart, icrEnd, ocrStart, ocrEnd] = arr;
      }
      const halfRd = Math.abs(radius - innerRadius) / 2;
      const ocrs = mathMin(halfRd, ocrStart);
      const ocre = mathMin(halfRd, ocrEnd);
      const icrs = mathMin(halfRd, icrStart);
      const icre = mathMin(halfRd, icrEnd);
      limitedOcrMax = ocrMax = mathMax(ocrs, ocre);
      limitedIcrMax = icrMax = mathMax(icrs, icre);
      if (ocrMax > e || icrMax > e) {
        xre = radius * Math.cos(endAngle);
        yre = radius * Math.sin(endAngle);
        xirs = innerRadius * Math.cos(startAngle);
        yirs = innerRadius * Math.sin(startAngle);
        if (arc < PI) {
          const it = intersect(xrs, yrs, xirs, yirs, xre, yre, xire, yire);
          if (it) {
            const x0 = xrs - it[0];
            const y0 = yrs - it[1];
            const x1 = xre - it[0];
            const y1 = yre - it[1];
            const a = 1 / Math.sin(Math.acos((x0 * x1 + y0 * y1) / (Math.sqrt(x0 * x0 + y0 * y0) * Math.sqrt(x1 * x1 + y1 * y1))) / 2);
            const b = Math.sqrt(it[0] * it[0] + it[1] * it[1]);
            limitedOcrMax = mathMin(ocrMax, (radius - b) / (a + 1));
            limitedIcrMax = mathMin(icrMax, (innerRadius - b) / (a - 1));
          }
        }
      }
    }
    if (!hasArc) M(cx + xrs, cy + yrs);
    else if (limitedOcrMax > e) {
      const crStart = mathMin(ocrStart, limitedOcrMax);
      const crEnd = mathMin(ocrEnd, limitedOcrMax);
      const ct0 = cornerTangents(xirs, yirs, xrs, yrs, radius, crStart, clockwise);
      const ct1 = cornerTangents(xre, yre, xire, yire, radius, crEnd, clockwise);
      M(cx + ct0.cx + ct0.x0, cy + ct0.cy + ct0.y0);
      if (limitedOcrMax < ocrMax && crStart === crEnd) {
        A(cx + ct0.cx, cy + ct0.cy, limitedOcrMax, Math.atan2(ct0.y0, ct0.x0), Math.atan2(ct1.y0, ct1.x0), !clockwise);
      } else {
        if (crStart > 0) A(cx + ct0.cx, cy + ct0.cy, crStart, Math.atan2(ct0.y0, ct0.x0), Math.atan2(ct0.y1, ct0.x1), !clockwise);
        A(cx, cy, radius, Math.atan2(ct0.cy + ct0.y1, ct0.cx + ct0.x1), Math.atan2(ct1.cy + ct1.y1, ct1.cx + ct1.x1), !clockwise);
        if (crEnd > 0) A(cx + ct1.cx, cy + ct1.cy, crEnd, Math.atan2(ct1.y1, ct1.x1), Math.atan2(ct1.y0, ct1.x0), !clockwise);
      }
    } else {
      M(cx + xrs, cy + yrs);
      A(cx, cy, radius, startAngle, endAngle, !clockwise);
    }
    if (!(innerRadius > e) || !hasArc) L(cx + xire, cy + yire);
    else if (limitedIcrMax > e) {
      const crStart = mathMin(icrStart, limitedIcrMax);
      const crEnd = mathMin(icrEnd, limitedIcrMax);
      const ct0 = cornerTangents(xire, yire, xre, yre, innerRadius, -crEnd, clockwise);
      const ct1 = cornerTangents(xrs, yrs, xirs, yirs, innerRadius, -crStart, clockwise);
      L(cx + ct0.cx + ct0.x0, cy + ct0.cy + ct0.y0);
      if (limitedIcrMax < icrMax && crStart === crEnd) {
        A(cx + ct0.cx, cy + ct0.cy, limitedIcrMax, Math.atan2(ct0.y0, ct0.x0), Math.atan2(ct1.y0, ct1.x0), !clockwise);
      } else {
        if (crEnd > 0) A(cx + ct0.cx, cy + ct0.cy, crEnd, Math.atan2(ct0.y0, ct0.x0), Math.atan2(ct0.y1, ct0.x1), !clockwise);
        A(cx, cy, innerRadius, Math.atan2(ct0.cy + ct0.y1, ct0.cx + ct0.x1), Math.atan2(ct1.cy + ct1.y1, ct1.cx + ct1.x1), clockwise);
        if (crStart > 0) A(cx + ct1.cx, cy + ct1.cy, crStart, Math.atan2(ct1.y1, ct1.x1), Math.atan2(ct1.y0, ct1.x0), !clockwise);
      }
    } else {
      L(cx + xire, cy + yire);
      A(cx, cy, innerRadius, endAngle, startAngle, clockwise);
    }
  }
  cmds.push({ cmd: 'Z', args: [] });
  return cmds;
}
function intersect(x0, y0, x1, y1, x2, y2, x3, y3) {
  const dx10 = x1 - x0;
  const dy10 = y1 - y0;
  const dx32 = x3 - x2;
  const dy32 = y3 - y2;
  let t = dy32 * dx10 - dx32 * dy10;
  if (t * t < 1e-4) return undefined;
  t = (dx32 * (y0 - y2) - dy32 * (x0 - x2)) / t;
  return [x0 + t * dx10, y0 + t * dy10];
}
function cornerTangents(x0, y0, x1, y1, radius, cr, clockwise) {
  const x01 = x0 - x1;
  const y01 = y0 - y1;
  const lo = (clockwise ? cr : -cr) / Math.sqrt(x01 * x01 + y01 * y01);
  const ox = lo * y01;
  const oy = -lo * x01;
  const x11 = x0 + ox;
  const y11 = y0 + oy;
  const x10 = x1 + ox;
  const y10 = y1 + oy;
  const x00 = (x11 + x10) / 2;
  const y00 = (y11 + y10) / 2;
  const dx = x10 - x11;
  const dy = y10 - y11;
  const d2 = dx * dx + dy * dy;
  const r = radius - cr;
  const s = x11 * y10 - x10 * y11;
  const d = (dy < 0 ? -1 : 1) * Math.sqrt(Math.max(0, r * r * d2 - s * s));
  let cx0 = (s * dy - dx * d) / d2;
  let cy0 = (-s * dx - dy * d) / d2;
  const cx1 = (s * dy + dx * d) / d2;
  const cy1 = (-s * dx + dy * d) / d2;
  const dx0 = cx0 - x00;
  const dy0 = cy0 - y00;
  const dx1 = cx1 - x00;
  const dy1 = cy1 - y00;
  if (dx0 * dx0 + dy0 * dy0 > dx1 * dx1 + dy1 * dy1) { cx0 = cx1; cy0 = cy1; }
  return { cx: cx0, cy: cy0, x0: -ox, y0: -oy, x1: cx0 * (radius / r - 1), y1: cy0 * (radius / r - 1) };
}

// SunburstSeries.ts completeTreeValue: post-order, JS '+', mutates the items
function completeTreeValue(n, mut) {
  let sum = 0;
  (n.children || []).forEach(c => {
    completeTreeValue(c, mut);
    let cv = c.value;
    if (isArray(cv)) cv = cv[0];
    sum = mut.sumNumeric ? sum + storeFloat(cv) : sum + cv;
  });
  let v = n.value;
  if (isArray(v)) v = v[0];
  if (v == null || isNaN(v)) v = sum;
  if (!mut.negativeKept && v < 0) v = 0;
  if (isArray(n.value)) n.value[0] = v; else n.value = v;
}

// ---- one chart: every sunburst series, one palette scope ----
// inp: {series: [{S, seriesIndex, fills (visualMap charts: the recorded row fills)}], env {W, H, palette, textStyle, background, isDark}}
function transcribeChart(inp, mut) {
  const env = inp.env;
  const sharedScope = { idx: 0, map: {} };
  // the layout stage runs for every series, then the visual stage for every series (the order is immaterial: disjoint trees)
  return inp.series.map(si => transcribeSeries(si, env, mut.scopePerSeries ? { idx: 0, map: {} } : sharedScope, mut));
}

function transcribeSeries(inp, env, scope, mut) {
  const S = inp.S;
  const seriesName = S.name != null ? String(S.name) : 'series\u0000' + inp.seriesIndex;
  // ---- data model ----
  const nodes = [];
  let dimMax = 1;
  const rootItem = { name: S.name, children: zrClone(S.data) };
  const writtenItems = [];
  (function walk(it) { writtenItems.push(it); (it.children || []).forEach(walk); })(zrClone(rootItem));
  completeTreeValue(rootItem, mut);
  function mk(item, parent, depth) {
    const nd = { item, parent, depth, children: [], idx: nodes.length, name: nameOf(item.name) };
    const v = item.value;
    dimMax = Math.max(dimMax, isArray(v) ? v.length : 1);
    nodes.push(nd);
    (item.children || []).forEach(c => nd.children.push(mk(c, nd, depth + 1)));
    nd.height = 1 + nd.children.reduce((h, c) => Math.max(h, c.height), 0);
    return nd;
  }
  const vroot = mk(rootItem, null, 0);
  const levelOpts = S.levels || [];
  nodes.forEach(n => {
    n.written = n.children.map(c => c.idx);
    n.values = [];
    for (let k = 0; k < dimMax; k++) n.values.push(storeFloat(isArray(n.item.value) ? n.item.value[k] : n.item.value));
    n.value = n.values[0];
    const lv = mut.levelOffByOne ? levelOpts[n.depth - 1] : levelOpts[n.depth];
    n.level = lv;
    n.chain = [n.item, lv, S];
  });
  // ---- layout (sunburstLayout.ts) ----
  let center = S.center;
  let radius = S.radius;
  if (!isArray(radius)) radius = [0, radius];
  if (!isArray(center)) center = [center, center];
  const width = env.W;
  const height = env.H;
  const size = mut.sizeMax ? Math.max(width, height) : Math.min(width, height);
  const cx = parsePercent(center[0], width);
  const cy = parsePercent(center[1], height);
  const r0 = parsePercent(radius[0], size / 2);
  const r = parsePercent(radius[1], size / 2);
  const startAngle = mut.startAngleNotNegated ? S.startAngle * RADIAN : -S.startAngle * RADIAN;
  const minAngle = mut.minAngleIgnored ? 0 : S.minAngle * RADIAN;
  const treeRoot = vroot;
  const rootDepth = treeRoot.depth;
  let sort = S.sort;
  if (mut.sortNullAsDesc && sort == null) sort = 'desc';
  const sortChildren = (children) => {
    const isAsc = sort === 'asc';
    const tieAsc = mut.ascTiesKept ? 1 : -1;
    return children.sort((a, b) => {
      const diff = (a.value - b.value) * (isAsc ? 1 : -1);
      return diff === 0 ? (a.idx - b.idx) * (isAsc ? tieAsc : 1) : diff;
    });
  };
  const initChildren = n => {
    const ch = n.children;
    n.children = sortChildren(ch);
    if (ch.length) n.children.forEach(initChildren);
  };
  if (sort != null) initChildren(treeRoot);
  let validDataCount = 0;
  treeRoot.children.forEach(c => { if (!isNaN(c.value)) validDataCount++; });
  const sum = treeRoot.value;
  const unitRadian = Math.PI / (sum || validDataCount) * 2;
  const rollup = treeRoot.depth > 0;
  const rings = treeRoot.height - (rollup ? -1 : 1);
  const rPerLevel = (r - r0) / (rings || 1);
  const clockwise = S.clockwise;
  const still = mut.stillIgnored ? false : S.stillShowZeroSum;
  const dir = clockwise || mut.dirIgnored ? 1 : -1;
  function renderNode(node, sa, parentAngle) {
    let ea = sa;
    let angle = 0;
    if (node !== vroot) {
      const value = node.value;
      const sibSum = node.parent ? node.parent.children.reduce((a, c) => a + c.value, 0) : 0;
      if (mut.childrenScaledToParent && node.parent !== vroot && sibSum) {
        angle = (sum === 0 && still) ? unitRadian : value / sibSum * parentAngle;
      } else angle = (sum === 0 && still) ? unitRadian : value * unitRadian;
      if (angle < minAngle) angle = minAngle;
      ea = sa + dir * angle;
      const depth = node.depth - rootDepth - (rollup ? -1 : 1);
      let rStart = r0 + rPerLevel * depth;
      let rEnd = mut.rEndFromStart ? rStart + rPerLevel : r0 + rPerLevel * (depth + 1);
      const lv = node.level;
      if (lv && !mut.levelRadiusIgnored) {
        let lr0 = lv.r0;
        let lr = lv.r;
        const lrad = lv.radius;
        if (lrad != null && !mut.levelR0Wins) { lr0 = lrad[0]; lr = lrad[1]; }
        if (lrad != null && mut.levelR0Wins) { if (lr0 == null) lr0 = lrad[0]; if (lr == null) lr = lrad[1]; }
        if (lr0 != null) rStart = parsePercent(lr0, size / 2);
        if (lr != null) rEnd = parsePercent(lr, size / 2);
      }
      node.L = { angle, startAngle: sa, endAngle: ea, clockwise, cx, cy, r0: rStart, r: rEnd };
    }
    if (node.children.length) {
      let sib = 0;
      let prevEnd = sa;
      node.children.forEach(c => {
        if (mut.nextFromPrevEnd) { renderNode(c, prevEnd, angle); prevEnd = c.L.endAngle; } else sib += renderNode(c, sa + sib, angle);
      });
    }
    return mut.returnAngle ? dir * angle : ea - sa;
  }
  renderNode(treeRoot, startAngle, 0);
  // ---- the colour visual (sunburstVisual.ts) ----
  const treeHeight = vroot.height;
  const ownPalette = S.color != null ? [].concat(S.color) : [];
  const visitColour = n => {
    const colourSrc = mgetIdx(n.chain.map(o => (o && typeof o === 'object' ? o.itemStyle : undefined)), 'color');
    let fill = colourSrc >= 0 ? mget([n.chain[colourSrc].itemStyle], 'color') : undefined;
    const c = { source: colourSrc === 0 ? 'item' : colourSrc === 1 ? 'level' : colourSrc === 2 ? 'series' : null, fill: undefined, paletteKey: null, paletteIndex: null, paletteFrom: null, base: null, lift: null };
    if (!fill) {
      if (n.depth === 0) { fill = '#86878c'; c.source = 'root'; } else {
        let cur = n;
        while (cur && cur.depth > 1) cur = cur.parent;
        const key = mut.paletteKeyByIndex ? String(cur.idx) : (cur.name || cur.idx + '');
        const pal = ownPalette.length ? ownPalette : env.palette;
        c.source = 'palette';
        c.paletteKey = key;
        c.paletteFrom = ownPalette.length ? 'series' : 'global';
        let base;
        if (hasOwn(scope.map, key)) { base = scope.map[key].color; c.paletteIndex = scope.map[key].index; } else {
          base = pal[scope.idx];
          c.paletteIndex = scope.idx;
          scope.map[key] = { color: base, index: scope.idx };
          scope.idx = (scope.idx + 1) % pal.length;
        }
        c.base = base;
        fill = base;
        if (n.depth > 1 && typeof fill === 'string' && !mut.noLift) {
          c.lift = mut.liftByParentHeight ? (n.depth - 1) / (n.parent.height) * 0.5 : (n.depth - 1) / (treeHeight - 1) * 0.5;
          fill = lift(fill, c.lift);
        }
      }
    }
    c.fill = fill;
    n.colour = c;
    // getItemStyle over the chain (item -> level -> series with the defaults)
    const is = n.chain.map(o => (o && typeof o === 'object' ? o.itemStyle : undefined));
    const st = {};
    const MAP = [['fill', 'color'], ['stroke', 'borderColor'], ['lineWidth', 'borderWidth'], ['opacity'], ['shadowBlur'], ['shadowOffsetX'], ['shadowOffsetY'], ['shadowColor'], ['lineDash', 'borderType'],
      ['lineDashOffset', 'borderDashOffset'], ['lineCap', 'borderCap'], ['lineJoin', 'borderJoin'], ['miterLimit', 'borderMiterLimit']];
    for (const [k, ok] of MAP) { const v = mget(is, ok || k); if (v != null) st[k] = v; }
    if (!st.fill) st.fill = fill;
    n.style = st;
  };
  const visitOrder = [];
  (function pre(n) { visitOrder.push(n); n.children.forEach(pre); })(vroot);
  if (mut.paletteWrittenOrder) nodes.forEach(visitColour); else visitOrder.forEach(visitColour);
  // visualMap (not transcribed): the recorded fill replaces the style fill
  nodes.forEach(n => { n.drawFill = inp.fills ? inp.fills[n.idx] : n.style.fill; });
  // ---- the pieces (SunburstView.ts) ----
  const rlfz = S.renderLabelForZeroData;
  const pieces = [];
  visitOrder.forEach(n => {
    if (n === vroot) return;
    if (!rlfz && !n.value && !mut.zeroDrawn) return;
    pieces.push(n);
  });
  // ---- per piece: shape, path, style, label ----
  const z = S.z || 0;
  const zlevel = S.zlevel || 0;
  const pieceRecs = pieces.map(n => {
    const Ly = n.L;
    const is = n.chain.map(o => (o && typeof o === 'object' ? o.itemStyle : undefined));
    const br = mget(is, 'borderRadius');
    let cornerRadius = 0;
    if (br != null) {
      const arr = isArray(br) ? br : [br, br, br, br];
      const dr = mut.cornerOfThickness ? Math.abs(Ly.r - Ly.r0) : Math.abs(Ly.r || 0 - Ly.r0 || 0);
      cornerRadius = arr.map(cr => zrParsePercent(cr, dr));
    }
    const shape = { cx: Ly.cx, cy: Ly.cy, r0: Ly.r0, r: Ly.r, startAngle: Ly.startAngle, endAngle: Ly.endAngle, clockwise: Ly.clockwise, cornerRadius };
    const style = Object.assign({}, n.style, { fill: n.drawFill, lineJoin: 'bevel' });
    const ink = { fill: style.fill, stroke: style.stroke, lineWidth: style.lineWidth, opacity: style.opacity, lineJoin: style.lineJoin, lineDash: style.lineDash };
    return { row: n.idx, shape, commands: sectorPath(shape, mut), ink, z, z2: 2, zlevel, label: transcribeLabel(n, Ly, style, S, seriesName, env, mut) };
  });
  const pieceOf = new Map();
  pieces.forEach((n, k) => pieceOf.set(n, k));
  const rows = nodes.map(n => ({ index: n.idx, name: n.name,
    valueWritten: hasOwn(writtenItems[n.idx], 'value') ? json(writtenItems[n.idx].value) : undefined, valueCompleted: json(n.item.value),
    values: n.values, value: n.value, depth: n.depth, height: n.height, parent: n.parent ? n.parent.idx : null,
    children: n.children.map(c => c.idx), childrenWritten: n.written, layout: n.L ? Object.assign({}, n.L) : null,
    drawn: pieceOf.has(n), notDrawn: pieceOf.has(n) ? null : n === vroot ? 'virtualRoot' : 'zeroValue', piece: pieceOf.has(n) ? pieceOf.get(n) : null,
    fill: n.drawFill, colour: n.colour, visualMapFill: !!inp.fills }));
  const geometry = { width, height, size, cx, cy, r0, r, startAngle, minAngle, dir, sum, validDataCount, unitRadian, rings, rPerLevel, viewRoot: 0, rollup };
  return { geometry, dimensions: dimMax, rows, pieces: pieceRecs };
}

function transcribeLabel(n, Ly, sectorStyle, S, seriesName, env, mut) {
  const lv = n.chain.map(o => (o && typeof o === 'object' ? o.label : undefined));
  const get = k => mget(lv, k);
  const angle = Ly.endAngle - Ly.startAngle;
  const midAngle = (Ly.startAngle + Ly.endAngle) / 2;
  const dx = Math.cos(midAngle);
  const dy = Math.sin(midAngle);
  const lmOpt = get('minAngle');
  const labelMinAngle = mut.labelMinAngleIgnored ? NaN : lmOpt / 180 * Math.PI;
  const show = get('show');
  const tooNarrow = labelMinAngle != null && Math.abs(angle) < labelMinAngle;
  const shown = !!(show && !tooNarrow);
  const hiddenBy = shown ? null : !show ? 'show' : 'minAngle';
  // text: getFormattedLabel(dataIndex, 'normal') || node.name
  const fmt = get('formatter');
  let text = typeof fmt === 'string' ? formatTpl(fmt, { seriesName, name: n.name, value: n.item.value }) : undefined;
  text = text || n.name;
  const position = get('position');
  const labelPadding = get('distance') || 0;
  let textAlign = get('align');
  const rotateType = get('rotate');
  const flipStart = Math.PI * 0.5;
  const flipEnd = Math.PI * 1.5;
  const mn = normalizeRadian(rotateType === 'tangential' && !mut.tangentialFlipOnMid ? Math.PI / 2 - midAngle : midAngle);
  let needsFlip = mn > flipStart && (mut.noFlipTolerance90 || !aroundZero(mn - flipStart)) && mn < flipEnd;
  if (mut.flipTolerance270 && aroundZero(mn - flipEnd)) needsFlip = false;
  let rr;
  if (position === 'outside') {
    rr = Ly.r + labelPadding;
    textAlign = needsFlip && !mut.outsideNoFlip ? 'right' : 'left';
  } else if (!textAlign || textAlign === 'center') {
    rr = (Ly.r0 === 0 && isAroundFull(angle) && !mut.fullDiscNotCentred) ? 0 : (Ly.r + Ly.r0) / 2;
    textAlign = 'center';
  } else if (textAlign === 'left') {
    rr = mut.leftRightSwapped ? Ly.r - labelPadding : Ly.r0 + labelPadding;
    textAlign = needsFlip ? 'right' : 'left';
  } else if (textAlign === 'right') {
    rr = mut.leftRightSwapped ? Ly.r0 + labelPadding : Ly.r - labelPadding;
    textAlign = needsFlip ? 'left' : 'right';
  }
  // ZRText normalizeStyle: 'middle' -> 'center' / 'center' -> 'middle', an invalid value -> 'left' / 'top'
  let verticalAlign = get('verticalAlign') || 'middle';
  if (textAlign === 'middle') textAlign = 'center';
  if (textAlign != null && !['left', 'center', 'right'].includes(textAlign)) textAlign = 'left';
  if (verticalAlign === 'center') verticalAlign = 'middle';
  if (!['top', 'middle', 'bottom'].includes(verticalAlign)) verticalAlign = 'top';
  const x = rr * dx + Ly.cx;
  const y = rr * dy + Ly.cy;
  let rotate = 0;
  if (rotateType === 'radial') rotate = normalizeRadian(-midAngle) + (needsFlip ? Math.PI : 0);
  else if (rotateType === 'tangential') rotate = normalizeRadian(Math.PI / 2 - midAngle) + (needsFlip ? Math.PI : 0);
  else if (typeof rotateType === 'number') rotate = rotateType * Math.PI / 180 + (mut.numberRotateFlips && needsFlip ? Math.PI : 0);
  if (mut.fullDiscNoRotation && Ly.r0 === 0 && isAroundFull(angle)) rotate = 0;
  const rotation = mut.rotationNormalizedOnce ? rotate : normalizeRadian(rotate);
  // the label's own style (createTextStyle, attached: no global colour)
  let fillColor = get('color');
  let strokeColor = get('textBorderColor');
  if (fillColor === 'inherit' || fillColor === 'auto') fillColor = null;
  if (strokeColor === 'inherit' || strokeColor === 'auto') strokeColor = null;
  const gts = env.textStyle || {};
  const lineWidth = retrieve2(get('textBorderWidth'), gts.textBorderWidth);
  const opacity = retrieve2(get('opacity'), gts.opacity);
  const style = { fill: fillColor != null ? fillColor : null, stroke: strokeColor != null ? strokeColor : null, lineWidth: lineWidth != null ? lineWidth : null, opacity: opacity != null ? opacity : null };
  const inside = position !== 'outside';
  const outsideFill = get('color') === 'inherit' ? sectorStyle.fill : null;
  let inkDefault = null;
  let ink = null;
  if (shown) {
    let tf;
    let ts;
    const pathFill = sectorStyle.fill;
    const hasFill = pathFill != null && pathFill !== 'none';
    if (inside && hasFill) {
      if (pathFill !== 'none') {
        if (typeof pathFill === 'string') { const l = lum(pathFill, 0); tf = l > 0.5 ? '#333' : l > 0.2 ? '#eee' : '#ccc'; } else tf = pathFill ? '#ccc' : '#333';
      } else tf = '#333';
      if (typeof pathFill === 'string') {
        const darkLabel = lum(tf, 0) < 0.4;
        if ((mut.strokeIgnoresDark ? false : env.isDark) === darkLabel) ts = pathFill;
      }
    } else {
      tf = outsideFill != null ? outsideFill : env.isDark ? '#ccc' : '#333';
      let bg = typeof env.background === 'string' && parseColor(env.background);
      if (!bg) bg = [255, 255, 255, 1];
      const alpha = bg[3];
      for (let i = 0; i < 3; i++) bg[i] = bg[i] * alpha + (env.isDark ? 0 : 255) * (1 - alpha);
      bg[3] = 1;
      ts = 'rgba(' + bg.join(',') + ')';
    }
    tf = tf || '#000';
    inkDefault = { fill: tf, stroke: ts === undefined ? null : ts, autoStroke: true };
    if (text) {
      const hasF = style.fill != null;
      const inkFill = hasF ? style.fill : tf;
      const hasS = style.stroke != null;
      const useDefaultStroke = !hasS && !hasF;
      let inkStroke = hasS ? style.stroke : useDefaultStroke ? (ts === undefined ? null : ts) : null;
      if (inkStroke === 'none' || inkStroke === 'transparent') inkStroke = null;
      ink = { fill: inkFill === 'none' ? null : inkFill, stroke: inkStroke, lineWidth: inkStroke ? (style.lineWidth || (useDefaultStroke ? 2 : 0)) : null, opacity: style.opacity };
    }
  }
  return { text: text ? text : null, ignore: !shown, hiddenBy, minAngle: lmOpt != null ? labelMinAngle : null, x, y, rotation,
    transform: shown ? labelTransform(x, y, rotation) : null, align: textAlign, verticalAlign, position, rotate: rotateType, distance: get('distance'),
    style, textConfig: { inside, outsideFill }, inkDefault, ink, z2: 4 };
}
const isAroundFull = angle => aroundZero(angle - 2 * Math.PI);

// ============================================================================
// Reading upstream
// ============================================================================
const seriesArray = option => (option.series == null ? [] : [].concat(option.series));

// ---- zrender PathProxy decode ----
const CMD_NAME = { 1: 'M', 2: 'L', 3: 'C', 4: 'Q', 5: 'A', 6: 'Z', 7: 'R' };
const CMD_ARGS = { 1: 2, 2: 2, 3: 6, 4: 4, 5: 8, 6: 0, 7: 4 };
function decode(data) {
  const out = [];
  for (let i = 0; i < data.length;) {
    const c = data[i++];
    must(CMD_NAME[c], 'an unknown path command ' + c);
    const n = CMD_ARGS[c];
    out.push({ cmd: CMD_NAME[c], args: Array.prototype.slice.call(data, i, i + n) });
    i += n;
  }
  return out;
}
const pathOf = el => {
  if (!el.path) el.getBoundingRect();
  if (!el.path.data || el.path.len() === 0) { el.path = null; el.getBoundingRect(); }
  return el.path && el.path.data ? Array.prototype.slice.call(el.path.data, 0, el.path.len()) : [];
};

function ownStyle(s) {
  const r = {};
  for (const k of Object.keys(s).sort()) {
    if (k === 'blend' && s.blend == null) continue;
    if (k === 'text') continue;
    const v = s[k];
    r[k] = v === undefined ? null : typeof v === 'object' && v !== null && !isArray(v) ? '(object)' : zrClone(v);
  }
  return r;
}

function readLabel(piece, displayIndex, classes) {
  const t = piece.getTextContent();
  must(t, 'a piece without a text content');
  const s = t.style;
  must(!s.rich, 'a rich label');
  const kids = t.childrenRef();
  const spans = kids.filter(k => k.type === 'tspan');
  const boxes = kids.filter(k => k.type === 'rect');
  must(kids.length === spans.length + boxes.length && boxes.length <= 1, 'a label with unexpected children');
  spans.forEach(k => classes.set(k, 'label'));
  boxes.forEach(k => classes.set(k, 'labelBg'));
  classes.set(t, 'label');
  const shown = !t.ignore && !t.invisible;
  let ink = null;
  if (shown && spans.length) {
    const inks = spans.map(sp => ({ fill: sp.style.fill == null ? null : sp.style.fill, stroke: sp.style.stroke || null, lineWidth: sp.style.stroke ? sp.style.lineWidth : null, opacity: sp.style.opacity }));
    must(inks.every(k => JSON.stringify(k) === JSON.stringify(inks[0])), 'TSpans with different inks');
    ink = inks[0];
  }
  const tc = piece.textConfig || {};
  must(tc.position == null && !tc.local && tc.layoutRect == null && tc.offset == null && tc.rotation == null, 'a sunburst label with a positioned textConfig');
  const ds = piece._innerTextDefaultStyle;
  const has = k => k in s;
  const p = shown && spans.length ? displayIndex.get(spans[0]) : undefined;
  let background = null;
  if (shown && boxes.length) {
    const b = boxes[0];
    const bp = displayIndex.get(b);
    background = { shape: rect4(b.shape), style: ownStyle(b.style), paint: bp === undefined ? null : bp };
  }
  const lm = piece.node.getModel().getModel('label');
  const lmin = lm.get('minAngle');
  return { text: s.text == null ? null : String(s.text), ignore: !!t.ignore, minAngle: lmin != null ? lmin / 180 * Math.PI : null,
    x: t.x, y: t.y, rotation: t.rotation, transform: shown ? m6(t.transform) : null,
    align: s.align, verticalAlign: s.verticalAlign, position: json(lm.get('position')), rotate: json(lm.get('rotate')), distance: json(lm.get('distance')),
    font: s.font == null ? null : s.font, padding: json(s.padding),
    style: { fill: has('fill') ? json(s.fill) : null, stroke: has('stroke') ? json(s.stroke) : null, lineWidth: has('lineWidth') ? json(s.lineWidth) : null, opacity: has('opacity') ? json(s.opacity) : null },
    textConfig: { inside: json(tc.inside), outsideFill: json(tc.outsideFill) },
    inkDefault: shown && ds ? { fill: json(ds.fill), stroke: json(ds.stroke), autoStroke: json(ds.autoStroke) } : null, ink,
    tspans: shown ? spans.map(sp => ({ text: sp.style.text, x: sp.style.x, y: sp.style.y, textAlign: sp.style.textAlign, textBaseline: sp.style.textBaseline })) : [],
    background, z: t.z, z2: t.z2, zlevel: t.zlevel, silent: !!t.silent, paint: p === undefined ? null : p };
}

const LAYOUT_KEYS = ['angle', 'startAngle', 'endAngle', 'clockwise', 'cx', 'cy', 'r0', 'r'];
function readSunburst(chart, sm, opt, displayIndex, classes) {
  const data = sm.getData();
  const tree = data.tree;
  const view = chart.getViewOfSeriesModel(sm);
  const g = view.group;
  must(!g.transform || g.transform.join() === '1,0,0,1,0,0', 'a transformed sunburst view group');
  must(!view.virtualPiece, 'a roll-up piece on the first render');
  must(sm.getViewRoot() === tree.root, 'the view root is not the virtual root');
  // the written items, pre-order (fresh from the fed option: upstream mutated its own copy)
  const written = [];
  (function walk(it) { written.push(it); (it.children || []).forEach(walk); })({ name: opt.name, children: zrClone(opt.data) || [] });
  must(written.length === data.count(), 'the row count is not the written node count');
  const kids = g.children();
  const pieceIndex = new Map();
  kids.forEach((p, k) => { must(p.node && p.node.piece === p, 'a group child that is not a sunburst piece'); pieceIndex.set(p, k); });
  const rows = [];
  for (let i = 0; i < data.count(); i++) {
    const node = tree.getNodeByDataIndex(i);
    must(node && node.dataIndex === i, 'row ' + i + ': no node');
    const raw = data.getRawDataItem(i);
    const L = data.getItemLayout(i);
    if (L) must(Object.keys(L).every(k => LAYOUT_KEYS.includes(k)), 'row ' + i + ': unexpected layout keys ' + Object.keys(L));
    const pc = node.piece && pieceIndex.has(node.piece) ? pieceIndex.get(node.piece) : null;
    const lay = L ? {} : null;
    if (L) LAYOUT_KEYS.forEach(k => { lay[k] = L[k]; });
    rows.push({ index: i, name: node.name, valueWritten: hasOwn(written[i], 'value') ? json(written[i].value) : undefined,
      valueCompleted: json(raw.value), values: data.dimensions.map(d => data.get(d, i)), value: node.getValue(), depth: node.depth, height: node.height,
      parent: node.parentNode ? node.parentNode.dataIndex : null, children: node.children.map(c => c.dataIndex),
      childrenWritten: node.children.map(c => c.dataIndex).sort((a, b) => a - b), layout: lay, drawn: pc != null,
      notDrawn: pc != null ? null : (node === tree.root ? 'virtualRoot' : !node.getValue() ? 'zeroValue' : 'unknown'), piece: pc,
      fill: json(data.getItemVisual(i, 'style').fill) });
  }
  const pieces = kids.map(p => {
    classes.set(p, 'sector');
    const sh = p.shape;
    const pp = displayIndex.get(p);
    return { row: p.node.dataIndex,
      shape: { cx: sh.cx, cy: sh.cy, r0: sh.r0, r: sh.r, startAngle: sh.startAngle, endAngle: sh.endAngle, clockwise: sh.clockwise, cornerRadius: json(sh.cornerRadius) },
      commands: decode(pathOf(p)), style: ownStyle(p.style),
      ink: { fill: json(p.style.fill), stroke: json(p.style.stroke), lineWidth: json(p.style.lineWidth), opacity: json(p.style.opacity), lineJoin: json(p.style.lineJoin), lineDash: json(p.style.lineDash) },
      z: p.z, z2: p.z2, zlevel: p.zlevel, silent: !!p.isSilent(), paint: pp === undefined ? null : pp,
      label: readLabel(p, displayIndex, classes) };
  });
  const oget = k => json(sm.option[k]);
  return { name: sm.name,
    option: { center: oget('center'), radius: oget('radius'), startAngle: oget('startAngle'), minAngle: oget('minAngle'), clockwise: oget('clockwise'), sort: oget('sort'),
      sortKeyPresent: hasOwn(opt, 'sort'), stillShowZeroSum: oget('stillShowZeroSum'), renderLabelForZeroData: oget('renderLabelForZeroData'), nodeClick: oget('nodeClick'),
      levels: (sm.option.levels || []).length },
    dimensions: data.dimensions.slice(), rows, pieces };
}

// the display list, run-length encoded by owner
function paintRuns(chart, list, classes) {
  const ec = chart.getModel();
  const owners = new Map();
  ec.eachComponent((mainType, cm) => {
    const v = chart.getViewOfComponentModel(cm);
    if (v && v.group) owners.set(v.group, { owner: 'component', index: cm.componentIndex, type: mainType });
  });
  ec.eachSeries(sm => {
    const v = chart.getViewOfSeriesModel(sm);
    if (v && v.group) owners.set(v.group, { owner: 'series', index: sm.seriesIndex, type: sm.subType });
  });
  const runs = [];
  let prev = null;
  list.forEach((el, i) => {
    let x = el;
    let viaHost = false;
    let o = null;
    let cls = null;
    while (x) {
      if (owners.has(x)) { o = owners.get(x); break; }
      if (cls == null && classes.has(x)) cls = classes.get(x);
      if (x.parent) x = x.parent;
      else if (x.__hostTarget) { viaHost = true; x = x.__hostTarget; } else x = null;
    }
    let rec;
    if (!o) rec = { owner: 'other', index: null, type: null, group: null };
    else if (o.owner === 'series') rec = { owner: 'series', index: o.index, type: o.type, group: cls || (viaHost ? 'label' : 'mark') };
    else rec = { owner: 'component', index: o.index, type: o.type, group: viaHost ? 'label' : 'mark' };
    Object.assign(rec, { zlevel: el.zlevel, z: el.z, z2: el.z2 });
    if (prev) must(prev.zlevel < el.zlevel || (prev.zlevel === el.zlevel && (prev.z < el.z || (prev.z === el.z && prev.z2 <= el.z2))), 'the display list is not sorted at ' + i);
    prev = el;
    const last = runs[runs.length - 1];
    if (last && ['owner', 'index', 'type', 'group', 'zlevel', 'z', 'z2'].every(k => last[k] === rec[k])) last.n++;
    else runs.push(Object.assign(rec, { n: 1 }));
  });
  return runs;
}

function runChart(E, option, fn, w, h) {
  rngState = SEED;
  const chart = E.init(null, null, { renderer: 'svg', ssr: true, width: w || W, height: h || H });
  try {
    chart.setOption(option);
    chart.getZr().storage.getDisplayList(true);
    return fn(chart);
  } finally {
    chart.dispose();
  }
}

const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));

function recordWith(E, def, optionText, side) {
  const input = JSON.parse(optionText);
  return runChart(E, JSON.parse(optionText), chart => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const list = zr.storage.getDisplayList(true);
    const displayIndex = new Map();
    list.forEach((el, i) => displayIndex.set(el, i));
    const classes = new Map();
    const ground = { background: json(zr.getBackgroundColor()), isDark: !!zr.isDarkMode() };
    const textStyle = json(ec.option.textStyle);
    const palette = json(ec.option.color);
    const hasVM = !!(ec.getComponent('visualMap'));
    const inputs = [];
    const series = seriesArray(input).map((opt, si) => {
      const sm = ec.getSeriesByIndex(si);
      must(sm && sm.subType === opt.type && opt.type === 'sunburst', 'series ' + si + ' is not a sunburst');
      must(!ec.isSeriesFiltered(sm), 'a filtered sunburst series');
      const S = mergedOption(opt);
      for (const k of READ_KEYS) {
        must(JSON.stringify(json(sm.option[k])) === JSON.stringify(json(S[k])), 'series ' + si + ': the option ' + k + ' is not the fed option over the defaults: ' + JSON.stringify(sm.option[k]) + ' vs ' + JSON.stringify(S[k]));
      }
      const rec = Object.assign({ seriesIndex: si, type: 'sunburst' }, readSunburst(chart, sm, opt, displayIndex, classes));
      if (opt.name == null) {
        must(rec.name === 'series\u0000' + si, 'series ' + si + ': default name ' + JSON.stringify(rec.name));
        rec.name = null;
      }
      inputs.push({ S, seriesIndex: si, fills: hasVM ? rec.rows.map(r => r.fill) : null });
      return rec;
    });
    must(series.length > 0, 'no sunburst series');
    side[def.id] = { series: inputs, env: { W, H, palette, textStyle, background: ground.background, isDark: ground.isDark }, hasVM };
    const runs = paintRuns(chart, list, classes);
    return { ground, textStyle, palette, paintRuns: runs, series };
  });
}

function recordCase(def, side) {
  const opt = def.gallery ? gallery(def.gallery) : zrClone(def.option);
  const animationForced = opt.animation !== false;
  opt.animation = false;
  const optionText = JSON.stringify(opt);
  const local = {};
  const base = recordWith(echarts, def, optionText, local);
  const p = recordWith(PROD, def, optionText, {});
  must(JSON.stringify(sanitize(p)) === JSON.stringify(sanitize(base)), 'the production build records differently');
  // a visualMap chart: the sunburstVisual fills, from the same option without the visualMap component
  if (local[def.id].hasVM) {
    const o2 = JSON.parse(optionText);
    delete o2.visualMap;
    local[def.id].preVisualMapFills = runChart(echarts, o2, chart => seriesArray(o2).map((s, si) => {
      const d = chart.getModel().getSeriesByIndex(si).getData();
      const out = [];
      for (let i = 0; i < d.count(); i++) out.push(d.getItemVisual(i, 'style').fill);
      return out;
    }));
  }
  Object.assign(side, local);
  return Object.assign({ id: def.id, note: def.note, gallery: def.gallery || null, option: def.gallery ? null : JSON.parse(optionText),
    animationForced, productionBuild: false, devError: null }, base);
}

// ============================================================================
// The cases
// ============================================================================
// D1 of upstream.md section 5: A {A1 4, A2 2}, B 10 {B1 3, B2 5 {B21 5}}, C 3 -> sum 19, height 4, 3 rings of 75
const D1 = () => [
  { name: 'A', children: [{ name: 'A1', value: 4 }, { name: 'A2', value: 2 }] },
  { name: 'B', value: 10, children: [{ name: 'B1', value: 3 }, { name: 'B2', value: 5, children: [{ name: 'B21', value: 5 }] }] },
  { name: 'C', value: 3 },
];
const TWO = () => [
  { name: 'P', children: [{ name: 'p1', value: 3 }, { name: 'p2', value: 5 }, { name: 'p3', value: 1 }] },
  { name: 'Q', children: [{ name: 'q1', value: 2 }, { name: 'q2', value: 2 }] },
  { name: 'R', value: 4 },
];
// ties on every level: equal siblings in written order
const TIES = () => [
  { name: 'x', value: 2 }, { name: 'y', children: [{ name: 'y1', value: 1 }, { name: 'y2', value: 1 }, { name: 'y3', value: 1 }] }, { name: 'z', value: 3 },
  { name: 'w', value: 2, children: [{ name: 'w1', value: 1 }, { name: 'w2', value: 1 }] }, { name: 'v', value: 1 },
];
const ROOTS = () => ['alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta', 'iota', 'kappa', 'lambda']
  .map((nm, i) => ({ name: nm, value: [5, 9, 2, 7, 3, 8, 1, 6, 4, 2.5, 11][i] }));
const one = (series, extra) => Object.assign({ animation: false, series: [].concat(series).map(s => Object.assign({ type: 'sunburst' }, s)) }, extra || {});

const CASES = [
  // ---- basics ----
  { id: 'B-2level', note: 'a 2-level tree, all defaults: P {p1 3, p2 5, p3 1}, Q {q1 2, q2 2}, R 4; parents summed (P 9, Q 4); desc sort (P, then Q before R by the dataIndex tie), 2 rings of 112.5 on radius [0, 75%] = [0, 225]', option: one({ data: TWO() }) },
  { id: 'B-3level', note: "upstream.md D1, all defaults: desc -> B (10, the explicit value > its children's 8: a gap), A (6, summed), C 3; 3 rings of 75; palette by the sorted roots (B #5070dd, A #b6d634, C #505372), lift 1/6 and 1/3", option: one({ data: D1() }) },
  { id: 'B-roots', note: '11 flat roots (values 5 9 2 7 3 8 1 6 4 2.5 11): one ring 0..225, desc; the 9-colour palette wraps (the 10th and 11th sorted roots take palette[0], palette[1])', option: one({ data: ROOTS() }) },
  { id: 'B-named', note: "a named series 'Family': row 0 (the virtual root) carries the name; the formatter '{a}' prints it", option: one({ name: 'Family', data: TWO(), label: { formatter: '{a}/{b}' } }) },
  // ---- sort ----
  { id: 'S-desc', note: "sort 'desc' explicit on the ties tree: equal siblings keep the written order (lower dataIndex first)", option: one({ data: TIES(), sort: 'desc' }) },
  { id: 'S-asc', note: "sort 'asc' on the ties tree: equal siblings are REVERSED (higher dataIndex first): v, then x / w (2) as w, x ..., y's children y3 y2 y1; the palette follows the sorted order", option: one({ data: TIES(), sort: 'asc' }) },
  { id: 'S-null', note: 'sort null (present): no sort at all, the written order; the palette in written pre-order', option: one({ data: TIES(), sort: null }) },
  { id: 'S-absent', note: "no sort key: the default 'desc' (identical to S-desc)", option: one({ data: TIES() }) },
  { id: 'S-function-dropped', note: "upstream wrote sort: function (a, b) {...}; the JSON harvest drops a function, so the key is ABSENT -> 'desc' (a port must not invent an order; a real comparator is not representable in JSON)", option: one({ data: D1() }) },
  { id: 'S-other', note: "sort 'foo' (any non-null value other than 'asc' sorts DESC)", option: one({ data: D1(), sort: 'foo' }) },
  { id: 'S-asc-D1', note: "upstream.md 5.3 sort 'asc' on D1: C, A (A2, A1), B (B1, B2 (B21)); A ends at 1.4054493450270125, A1 at ...127, B starts at ...122 (the end - start accumulator bits)", option: one({ data: D1(), sort: 'asc' }) },
  // ---- values ----
  { id: 'V-gap', note: "parent value larger than its children (G 20 {g1 3, g2 4}) next to H 10: the children fill 7 of G's 20 units, the rest of G's arc is a gap; H starts at G's end", option: one({ data: [{ name: 'G', value: 20, children: [{ name: 'g1', value: 3 }, { name: 'g2', value: 4 }] }, { name: 'H', value: 10 }], sort: null }) },
  { id: 'V-spill', note: "parent value smaller than its children (P 2 {p1 3, p2 3}) then Q 6: the children run PAST P's end and overlap Q's children-ring slot (no rescale)", option: one({ data: [{ name: 'P', value: 2, children: [{ name: 'p1', value: 3 }, { name: 'p2', value: 3 }] }, { name: 'Q', value: 6, children: [{ name: 'q1', value: 6 }] }], sort: null }) },
  { id: 'V-zero', note: 'zero values: Z 0 (a root), P {P0 0, P1 1}, Q 1 -> Z and P0 are laid out with zero angle but NOT drawn (notDrawn zeroValue); Z still consumes a palette entry', option: one({ data: [{ name: 'Z', value: 0 }, { name: 'P', children: [{ name: 'P0', value: 0 }, { name: 'P1', value: 1 }] }, { name: 'Q', value: 1 }] }) },
  { id: 'V-zero-render', note: 'the V-zero tree with renderLabelForZeroData true: the zero pieces ARE drawn (degenerate sectors) and their labels get anchors', option: one({ data: [{ name: 'Z', value: 0 }, { name: 'P', children: [{ name: 'P0', value: 0 }, { name: 'P1', value: 1 }] }, { name: 'Q', value: 1 }], renderLabelForZeroData: true }) },
  { id: 'V-string', note: "string values: S {s1 '5', s2 '3'} -> S's completed value is the STRING '053' (JS 0 + '5' + '3'), stored as 53; T [4, 99] (array: [0] is the value, dims value / value0); U '7' leaf; the virtual root is 0 + '053' + 4 + '7' = the STRING '005347' (stored as 5347) -> unitRadian 2 PI / 5347, every piece is thin; formatter '{b}: {c}' prints the completed raw value",
    option: one({ data: [{ name: 'S', children: [{ name: 's1', value: '5' }, { name: 's2', value: '3' }] }, { name: 'T', value: [4, 99] }, { name: 'U', value: '7' }], sort: null, label: { formatter: '{b}: {c}' } }) },
  { id: 'V-negative', note: 'negative values: N -3 becomes 0 (not drawn), M {m1 -2, m2 5} sums to 5 (the child is clamped BEFORE the parent sums it), K 4', option: one({ data: [{ name: 'N', value: -3 }, { name: 'M', children: [{ name: 'm1', value: -2 }, { name: 'm2', value: 5 }] }, { name: 'K', value: 4 }] }) },
  { id: 'V-missing', note: "values missing / null / '-' / 'abc' on leaves (all 0, not drawn), a leaf 6, a parent with null value {c 2} (summed to 2)", option: one({ data: [{ name: 'a' }, { name: 'b', value: null }, { name: 'd', value: '-' }, { name: 'e', value: 'abc' }, { name: 'f', value: 6 }, { name: 'g', value: null, children: [{ name: 'c', value: 2 }] }] }) },
  // ---- radius / center ----
  { id: 'R-number', note: 'radius 150 (a scalar = the OUTER radius, inner 0)', option: one({ data: D1(), radius: 150 }) },
  { id: 'R-percent', note: "radius '60%' (of min(800, 600) / 2 = 300 -> 180)", option: one({ data: D1(), radius: '60%' }) },
  { id: 'R-array', note: "radius ['20%', 260.5] -> [60, 260.5]: rPerLevel (260.5 - 60) / 3 not exact; ring ends r0 + rPerLevel * (d + 1)", option: one({ data: D1(), radius: ['20%', 260.5] }) },
  { id: 'R-array-odd', note: 'radius [9, 200.1]: rPerLevel = 63.7, the ring end r0 + rPerLevel * (d + 1) differs from rStart + rPerLevel in the last bit', option: one({ data: D1(), radius: [9, 200.1] }) },
  { id: 'R-levels', note: "upstream.md 5.3 levels: series radius [30, '90%'] (rPerLevel 80); levels[1] radius ['15%', '40%'] + itemStyle color #aa3344, levels[2] label rotate tangential, levels[3] radius [200, 260] + label outside",
    option: one({ data: D1(), radius: [30, '90%'], levels: [{}, { radius: ['15%', '40%'], itemStyle: { color: '#aa3344' } }, { label: { rotate: 'tangential' } }, { radius: [200, 260], label: { position: 'outside' } }] }) },
  { id: 'R-levels-r0r', note: "the deprecated levels[d].r0 / r: level 1 r0 '10%' only (r stays the ring value), level 2 r 170 only, level 3 r0 '60%' r '72%'",
    option: one({ data: D1(), levels: [{}, { r0: '10%' }, { r: 170 }, { r0: '60%', r: '72%' }] }) },
  { id: 'R-levels-both', note: "levels[1] has radius [20, 90] AND r0 50 / r 60: radius wins entirely; levels[2] radius [null, 160] (only r overridden, r0 null keeps the ring value); levels[0].radius is never read (no roll-up)",
    option: one({ data: D1(), levels: [{ radius: [1, 2] }, { radius: [20, 90], r0: 50, r: 60 }, { radius: [null, 160] }] }) },
  { id: 'C-px', note: 'center [300, 250] (px)', option: one({ data: D1(), center: [300, 250] }) },
  { id: 'C-percent', note: "center ['30%', '60%'] -> (240, 360): x of the WIDTH, y of the HEIGHT; radius '40%' of min / 2", option: one({ data: D1(), center: ['30%', '60%'], radius: '40%' }) },
  { id: 'C-scalar', note: "center '40%' (a scalar: used for BOTH x and y -> (320, 240)), radius [0, 100]", option: one({ data: D1(), center: '40%', radius: [0, 100] }) },
  { id: 'C-keywords', note: "center ['left', 'bottom'] -> (0, 600): parsePositionOption keywords", option: one({ data: D1(), center: ['left', 'bottom'], radius: [0, '50%'] }) },
  // ---- angles ----
  { id: 'A-90', note: 'startAngle 90 explicit (the default: -PI / 2, 12 o\'clock)', option: one({ data: D1(), startAngle: 90 }) },
  { id: 'A-0', note: "startAngle 0: (-0) * RADIAN = -0 (geometry startAngle '-0'); the first piece starts at -0 + 0 ... ", option: one({ data: D1(), startAngle: 0 }) },
  { id: 'A-m45', note: 'startAngle -45: +PI / 4 (4:30 o\'clock)', option: one({ data: D1(), startAngle: -45 }) },
  { id: 'A-405', note: 'startAngle 405: -405 * RADIAN (not normalised: angles beyond -2 PI; the label mid angles normalise)', option: one({ data: D1(), startAngle: 405 }) },
  { id: 'A-ccw', note: "upstream.md 5.2: clockwise false, startAngle 0, label align 'right' distance 8: B spans 0 -> -3.3069..., its label flips to 'left'", option: one({ data: D1(), clockwise: false, startAngle: 0, label: { align: 'right', distance: 8 } }) },
  { id: 'A-minAngle', note: 'minAngle 15 with tiny values (t1 0.1, t2 0.2 under a parent, s 0.5) and a zero Z: tiny pieces widen to 15 deg and NOTHING shrinks (the total exceeds 2 PI); the zero Z also takes 15 deg in the sibling sum but is not drawn',
    option: one({ data: [{ name: 'Big', value: 40, children: [{ name: 'b1', value: 39.7 }, { name: 't1', value: 0.1 }, { name: 't2', value: 0.2 }] }, { name: 'Z', value: 0 }, { name: 's', value: 0.5 }, { name: 'M', value: 10 }], minAngle: 15 }) },
  { id: 'F-flip-90', note: 'startAngle 89.997 on a single full disc root with 2 children: the root mid angle sits 5.2e-5 rad past PI / 2 -> inside the 1e-4 tolerance: NO flip (the centred disc label keeps rotation normalize(-mid))', option: one({ data: [{ name: 'Solo', children: [{ name: 'u', value: 1 }, { name: 'v', value: 1 }] }], startAngle: 89.997, sort: null }) },
  { id: 'F-flip-270', note: 'startAngle -89.995: the full disc mid angle sits 8.7e-5 rad BELOW 3 PI / 2 -> flipped (no tolerance at the top end); radial rotation', option: one({ data: [{ name: 'Solo', value: 1, children: [{ name: 'u', value: 1 }] }], startAngle: -89.995 }) },
  // ---- itemStyle ----
  { id: 'I-radius-px', note: 'itemStyle borderRadius 8 (all four corners)', option: one({ data: D1(), itemStyle: { borderRadius: 8 } }) },
  { id: 'I-radius-pct', note: "itemStyle borderRadius '20%': percent of shape.r (the precedence bug `r || 0 - r0 || 0`), not of r - r0: 15 on the r=75 ring, 30 on 150, 45 on 225", option: one({ data: D1(), itemStyle: { borderRadius: '20%' } }) },
  { id: 'I-radius-array', note: "borderRadius per level: series ['20%', 7] (2 entries -> [a, a, b, b] inner / outer), levels[2] [4, 8, '10%'] (3 entries), item B21 [12] (1 entry: [a, a, 0, 0]) with radius [30, '85%']",
    option: one({ data: (() => { const d = D1(); d[1].children[1].children[0].itemStyle = { borderRadius: [12] }; return d; })(), radius: [30, '85%'], itemStyle: { borderRadius: ['20%', 7] }, levels: [{}, {}, { itemStyle: { borderRadius: [4, 8, '10%'] } }] }) },
  { id: 'I-border', note: "series itemStyle borderColor '#123456', borderWidth 3, borderType 'dashed', opacity 0.8, shadowBlur 4; item C borderWidth 0", option: one({ data: (() => { const d = D1(); d[2].itemStyle = { borderWidth: 0 }; return d; })(), itemStyle: { borderColor: '#123456', borderWidth: 3, borderType: 'dashed', opacity: 0.8, shadowBlur: 4 } }) },
  { id: 'I-colours', note: "colours on the chain: levels[1] color #aa3344 (every root), item A2 color 'red', levels[2] borderColor '#000'; children still take the LIFTED palette colour of their depth-1 ancestor's NAME (the level colour does not reach them); B is sorted first so B2 asks palette[0] first",
    option: one({ data: (() => { const d = D1(); d[0].children[1].itemStyle = { color: 'red' }; return d; })(), levels: [{}, { itemStyle: { color: '#aa3344' } }, { itemStyle: { borderColor: '#000' } }] }) },
  { id: 'I-item-colour', note: "upstream probe lmin: 'big' #123456 with b1 (lifted palette[0]) and b2 'red' with b21 (lifted palette[0] again), 'small', a nameless root (palette key = its dataIndex), a second 'big' (same key: the cached colour); label.minAngle 15 hides narrow labels",
    option: one({ data: [{ name: 'big', value: 40, itemStyle: { color: '#123456' }, children: [{ name: 'b1', value: 30 }, { name: 'b2', value: 1, itemStyle: { color: 'red' }, children: [{ name: 'b21', value: 1 }] }] }, { name: 'small', value: 1 }, { value: 2 }, { name: 'big', value: 3 }], label: { minAngle: 15 } }) },
  { id: 'I-series-colour', note: "series itemStyle color '#ddd' (every node, the palette is never asked)", option: one({ data: D1(), itemStyle: { color: '#ddd' } }) },
  { id: 'I-palette', note: "a series color list ['#c23531', '#2f4554', '#61a0a8'] (the series' own palette) and a global color list on the chart that the series ignores", option: one({ data: ROOTS().slice(0, 5), color: ['#c23531', '#2f4554', '#61a0a8'] }, { color: ['#111111', '#222222'] }) },
  { id: 'I-global-palette', note: "a global color list ['#dd6b66', '#759aa0', '#e69d87', '#8dc1a9'] (no series list)", option: one({ data: D1() }, { color: ['#dd6b66', '#759aa0', '#e69d87', '#8dc1a9'] }) },
  // ---- labels ----
  { id: 'L-radial', note: "label rotate 'radial' explicit (the default)", option: one({ data: D1(), label: { rotate: 'radial' } }) },
  { id: 'L-tangential', note: "label rotate 'tangential': flip on normalize(PI / 2 - mid), not on mid", option: one({ data: D1(), label: { rotate: 'tangential' } }) },
  { id: 'L-number', note: "upstream.md 5.2: rotate 30 + align 'left': every rotation PI / 6 (no flip for numbers), but the flip still turns align left into right on A, A1, A2, C (anchor r0 + 5)", option: one({ data: D1(), label: { rotate: 30, align: 'left' } }) },
  { id: 'L-rotate0', note: 'rotate 0: every label horizontal, centred', option: one({ data: D1(), label: { rotate: 0 } }) },
  { id: 'L-rotate-none', note: "rotate 'none' (neither radial nor tangential nor a number): rotation 0", option: one({ data: D1(), label: { rotate: 'none' } }) },
  { id: 'L-align-left', note: "align 'left' distance 4 (radial)", option: one({ data: D1(), label: { align: 'left', distance: 4 } }) },
  { id: 'L-align-right', note: "align 'right' (distance 5 default), tangential", option: one({ data: D1(), label: { align: 'right', rotate: 'tangential' } }) },
  { id: 'L-align-center', note: "align 'center' explicit, distance 0", option: one({ data: D1(), label: { align: 'center', distance: 0 } }) },
  { id: 'L-align-middle', note: "align 'middle' (unknown): r stays undefined -> the anchor x / y are NaN (null in the fixture); the style align stays 'middle'", option: one({ data: TWO(), label: { align: 'middle' } }) },
  { id: 'L-outside', note: "upstream.md 5.2: position 'outside' + color 'inherit', radius ['20%', '60%']: r + distance, align left / right by the flip; fill = the sector colour (outsideFill), stroke = the background blend (rgba(255,255,255,1)) width 2", option: one({ data: D1(), radius: ['20%', '60%'], label: { position: 'outside', color: 'inherit' } }) },
  { id: 'L-outside-plain', note: "position 'outside' without a colour, distance 10, padding 3 (the ZRText box padding; offset [10, 20] and labelLine are IGNORED): fill '#333'", option: one({ data: D1(), radius: [0, '50%'], label: { position: 'outside', distance: 10, padding: 3, offset: [10, 20] }, labelLine: { show: true } }) },
  { id: 'L-position-other', note: "position 'insideTop' (anything but 'outside' is inside)", option: one({ data: D1(), label: { position: 'insideTop' } }) },
  { id: 'L-minAngle', note: 'label.minAngle 30 on D1: labels on sectors narrower than 30 deg hidden (hiddenBy minAngle; anchor still computed); levels[3].label.minAngle 0 re-shows B21', option: one({ data: D1(), label: { minAngle: 30 }, levels: [{}, {}, {}, { label: { minAngle: 0 } }] }) },
  { id: 'L-show', note: 'label.show false on the series, levels[2] show true, item B21 show false: only depth-2 labels', option: one({ data: (() => { const d = D1(); d[1].children[1].children[0].label = { show: false }; return d; })(), label: { show: false }, levels: [{}, {}, { label: { show: true } }] }) },
  { id: 'L-show-item', note: 'label.show false on the item A and on levels[3]', option: one({ data: (() => { const d = D1(); d[0].label = { show: false }; return d; })(), levels: [{}, {}, {}, { label: { show: false } }] }) },
  { id: 'L-formatter', note: "formatter '{b}: {c}' (the completed raw value: A's summed 6, B's explicit 10); a level-2 formatter '{b}' and an item formatter 'X' on C", option: one({ data: (() => { const d = D1(); d[2].label = { formatter: 'X' }; return d; })(), label: { formatter: '{b}: {c}' }, levels: [{}, {}, { label: { formatter: '{b}' } }] }) },
  { id: 'L-style', note: "label color '#0f0' (no auto stroke), textBorderColor '#000' width 3 on levels[2], fontSize 15, fontWeight bold, verticalAlign 'top', opacity 0.7", option: one({ data: D1(), label: { color: '#0f0', fontSize: 15, fontWeight: 'bold', verticalAlign: 'top', opacity: 0.7 }, levels: [{}, {}, { label: { textBorderColor: '#000', textBorderWidth: 3 } }] }) },
  { id: 'L-nameless', note: 'nameless nodes: no text (text unset -> no TSpan), palette keyed by the dataIndex', option: one({ data: [{ value: 1, children: [{ value: 1 }] }, { value: 2 }, { name: '', value: 1 }] }) },
  // ---- misc ----
  { id: 'X-fulldisc', note: "a single root with one child, radius ['0', '80%'], center [300, '40%'] (upstream.md circle): the root disc label at the CENTRE (r0 === 0 and angle ~ 2 PI) yet rotated normalize(-PI / 2) = 3 PI / 2; the child ring label at 6 o'clock", option: one({ data: [{ name: 'Only', value: 5, children: [{ name: 'k', value: 5 }] }], radius: ['0', '80%'], center: [300, '40%'] }) },
  { id: 'X-fullring', note: 'a single root on radius [60, 200]: a full RING (r0 60): the label on the ring at the mid angle, not the centre', option: one({ data: [{ name: 'Ring', value: 3 }], radius: [60, 200] }) },
  { id: 'X-nodeClick', note: 'nodeClick false: no effect on the first render (identical to B-3level)', option: one({ data: D1(), nodeClick: false }) },
  { id: 'X-two-series', note: "two sunbursts sharing ONE palette scope: series 0 (a, b) takes palette[0], [1]; series 1 (c, a, d): c takes palette[2], a the CACHED palette[0], d palette[3]", option: one([{ center: ['25%', '50%'], radius: [0, '30%'], data: [{ name: 'a', value: 1, children: [{ name: 'a1', value: 1 }] }, { name: 'b', value: 1 }] }, { center: ['75%', '50%'], radius: [0, '30%'], data: [{ name: 'c', value: 3 }, { name: 'a', value: 2 }, { name: 'd', value: 1 }] }]) },
  { id: 'X-dark', note: "darkMode true on D1: inside labels on light fills ('#333') now get the sector-coloured stroke, '#eee' / '#ccc' lose it; outside (levels[3]) fill '#ccc', stroke the blend toward black", option: one({ data: D1(), levels: [{}, {}, {}, { label: { position: 'outside' } }] }, { darkMode: true }) },
  { id: 'X-dark-bg', note: "backgroundColor '#100c2a' (auto dark mode): outside labels' stroke = the opaque background", option: one({ data: D1(), radius: [0, '60%'], label: { position: 'outside' } }, { backgroundColor: '#100c2a' }) },
  { id: 'X-allzero', note: 'every value 0, defaults: every node angle = unitRadian = 2 PI / 2 (children overflow) but NOTHING is drawn', option: one({ data: [{ name: 'z', children: [{ name: 'z1', value: 0 }, { name: 'z2', value: 0 }] }, { name: 'y', value: 0 }] }) },
  { id: 'X-allzero-render', note: 'every value 0 with renderLabelForZeroData: all drawn, each child as wide as a whole root (PI)', option: one({ data: [{ name: 'z', children: [{ name: 'z1', value: 0 }, { name: 'z2', value: 0 }, { name: 'z3', value: 0 }] }, { name: 'y', value: 0 }], renderLabelForZeroData: true, sort: null }) },
  { id: 'X-allzero-nostill', note: 'every value 0, stillShowZeroSum false, renderLabelForZeroData true: every angle 0 * unitRadian = 0', option: one({ data: [{ name: 'z1', value: 0 }, { name: 'z2', value: 0 }], stillShowZeroSum: false, renderLabelForZeroData: true }) },
  { id: 'X-empty', note: 'data []: only the virtual root row (value 0), no pieces; unitRadian PI / 0 * 2 = Infinity', option: one({ data: [] }) },
];
for (const [name, note] of [
  ['sunburst-simple', "sunburst-simple.json verbatim: 2 roots, 13 nodes, radius [0, '90%'], label rotate radial"],
  ['sunburst-borderRadius', 'sunburst-borderRadius.json verbatim: radius [60, 90%], itemStyle borderRadius 7 borderWidth 2, label show false'],
  ['sunburst-monochrome', "sunburst-monochrome.json verbatim: sort null, series itemStyle color '#ddd' + node colours, no names (no labels)"],
  ['sunburst-label-rotate', 'sunburst-label-rotate.json verbatim: top-level silent, sort null, levels radial / tangential / 0, label colour + text border; no names and the formatter dropped -> no text'],
  ['sunburst-drink', 'sunburst-drink.json verbatim: title component, sort null, levels r0 / r percents, tangential / align right / outside + padding 3; 110 nodes'],
  ['sunburst-visualMap', "sunburst-visualMap.json verbatim: continuous visualMap overwrites every fill (incl. the item 'red'); the sunburstVisual fill recorded in colour.fill"],
]) CASES.push({ id: 'G-' + name.replace(/^sunburst-/, ''), gallery: name, note: note + ' (examples/advchart/gallery; animation forced false)' });

// ============================================================================
// The guards
// ============================================================================
const GUARDS = [
  { id: 'next-from-prev-end', mutation: "the next sibling starts at the previous sibling's endAngle (not parentStart + the summed end - start)", mut: { nextFromPrevEnd: true }, named: ['S-asc-D1'] },
  { id: 'return-angle', mutation: 'renderNode returns dir * angle instead of endAngle - startAngle', mut: { returnAngle: true }, named: ['G-drink'] },
  { id: 'children-scaled', mutation: "children's angles scaled to fill the parent's arc (value / sum of siblings * parent angle)", mut: { childrenScaledToParent: true }, named: ['V-gap', 'V-spill', 'B-3level'] },
  { id: 'no-lift', mutation: 'no lift by depth: every node takes its ancestor palette colour as is', mut: { noLift: true }, named: ['B-3level', 'B-2level', 'G-simple'] },
  { id: 'lift-by-parent-height', mutation: "the lift ratio from the parent's height instead of the whole tree's height", mut: { liftByParentHeight: true }, named: ['B-3level'] },
  { id: 'palette-written-order', mutation: 'the palette consumed in the WRITTEN pre-order (the visual before the sort)', mut: { paletteWrittenOrder: true }, named: ['B-3level', 'S-asc'] },
  { id: 'palette-key-by-index', mutation: 'the palette keyed by the depth-1 dataIndex (same-named roots do not share)', mut: { paletteKeyByIndex: true }, named: ['I-item-colour', 'X-two-series'] },
  { id: 'scope-per-series', mutation: 'a palette scope per series (the cursor and the name cache not shared)', mut: { scopePerSeries: true }, named: ['X-two-series'] },
  { id: 'flip-tolerance-270', mutation: 'the 1e-4 flip tolerance also at 3 PI / 2', mut: { flipTolerance270: true }, named: ['F-flip-270'] },
  { id: 'no-flip-tolerance-90', mutation: 'no 1e-4 flip tolerance at PI / 2', mut: { noFlipTolerance90: true }, named: ['F-flip-90'] },
  { id: 'asc-ties-kept', mutation: "sort 'asc' keeps tied siblings in dataIndex order (not reversed)", mut: { ascTiesKept: true }, named: ['S-asc'] },
  { id: 'sort-null-as-desc', mutation: "sort null treated as the default 'desc'", mut: { sortNullAsDesc: true }, named: ['S-null', 'G-drink', 'G-monochrome'] },
  { id: 'size-max', mutation: 'percent radius against max(w, h) / 2 instead of min', mut: { sizeMax: true }, named: ['B-3level', 'R-percent', 'C-percent'] },
  { id: 'start-angle-not-negated', mutation: 'startAngle * RADIAN without the minus', mut: { startAngleNotNegated: true }, named: ['A-m45', 'A-405', 'B-3level'] },
  { id: 'dir-ignored', mutation: 'clockwise false ignored (dir always 1)', mut: { dirIgnored: true }, named: ['A-ccw'] },
  { id: 'min-angle-ignored', mutation: 'the series minAngle ignored', mut: { minAngleIgnored: true }, named: ['A-minAngle'] },
  { id: 'still-ignored', mutation: 'stillShowZeroSum ignored (zero sum -> 0 angles)', mut: { stillIgnored: true }, named: ['X-allzero-render'] },
  { id: 'zero-drawn', mutation: 'zero-valued nodes drawn without renderLabelForZeroData', mut: { zeroDrawn: true }, named: ['V-zero', 'V-missing'] },
  { id: 'r-end-from-start', mutation: 'the ring end rStart + rPerLevel instead of r0 + rPerLevel * (depth + 1)', mut: { rEndFromStart: true }, named: ['R-array-odd'] },
  { id: 'level-radius-ignored', mutation: 'levels[d].radius / r0 / r ignored', mut: { levelRadiusIgnored: true }, named: ['R-levels', 'R-levels-r0r', 'G-drink'] },
  { id: 'level-r0-wins', mutation: 'levels[d].r0 / r win over levels[d].radius', mut: { levelR0Wins: true }, named: ['R-levels-both'] },
  { id: 'level-off-by-one', mutation: 'levels[depth - 1] instead of levels[depth] (levels[0] as the first ring)', mut: { levelOffByOne: true }, named: ['R-levels', 'L-show', 'G-label-rotate'] },
  { id: 'corner-of-thickness', mutation: 'a percent borderRadius of r - r0 (the precedence bug fixed)', mut: { cornerOfThickness: true }, named: ['I-radius-pct', 'I-radius-array'] },
  { id: 'arc-no-modpi2', mutation: "the path arc start angle not rounded by normalizeArcAngles' modPI2", mut: { arcNoModPI2: true }, named: ['B-3level'] },
  { id: 'tangential-flip-on-mid', mutation: "'tangential' flips on the mid angle (not on PI / 2 - mid)", mut: { tangentialFlipOnMid: true }, named: ['L-tangential'] },
  { id: 'number-rotate-flips', mutation: 'a numeric rotate adds PI when flipped', mut: { numberRotateFlips: true }, named: ['L-number'] },
  { id: 'rotation-normalized-once', mutation: 'the rotation not normalised a second time (radial + PI can exceed 2 PI)', mut: { rotationNormalizedOnce: true }, named: ['B-3level'] },
  { id: 'full-disc-not-centred', mutation: 'a full disc label on (r + r0) / 2 instead of the centre', mut: { fullDiscNotCentred: true }, named: ['X-fulldisc'] },
  { id: 'full-disc-no-rotation', mutation: 'the centred full-disc label not rotated', mut: { fullDiscNoRotation: true }, named: ['X-fulldisc'] },
  { id: 'left-right-swapped', mutation: "align 'left' anchored at r - distance and 'right' at r0 + distance", mut: { leftRightSwapped: true }, named: ['L-align-left', 'L-align-right', 'A-ccw'] },
  { id: 'outside-no-flip', mutation: "an outside label always 'left'", mut: { outsideNoFlip: true }, named: ['L-outside'] },
  { id: 'label-min-angle-ignored', mutation: 'label.minAngle ignored', mut: { labelMinAngleIgnored: true }, named: ['L-minAngle', 'I-item-colour'] },
  { id: 'stroke-ignores-dark', mutation: 'the inside auto stroke rule ignores dark mode', mut: { strokeIgnoresDark: true }, named: ['X-dark'] },
  { id: 'sum-numeric', mutation: "completeTreeValue sums numbers (no JS string concatenation)", mut: { sumNumeric: true }, named: ['V-string'] },
  { id: 'negative-kept', mutation: 'negative values not clamped to 0 in completeTreeValue', mut: { negativeKept: true }, named: ['V-negative'] },
];

// ============================================================================
// Checks
// ============================================================================
function flat(v, pre, out) {
  if (v === null || v === undefined || typeof v !== 'object') { out[pre] = v; return out; }
  if (isArray(v)) { out[pre + '#'] = v.length; v.forEach((x, i) => flat(x, pre + '[' + i + ']', out)); return out; }
  for (const k of Object.keys(v)) if (v[k] !== undefined) flat(v[k], pre + '.' + k, out);
  return out;
}
function diffFlat(a, b) {
  const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))));
  return keys.filter(k => !Object.is(a[k], b[k])).map(k => ({ field: k, upstream: a[k] === undefined ? '(absent)' : a[k], mutated: b[k] === undefined ? '(absent)' : b[k] }));
}
// the recorded fields the transcription produces, in the transcription's shape
function upstreamView(sr) {
  return {
    dimensions: sr.dimensions.length,
    rows: sr.rows.map(r => ({ index: r.index, name: r.name, valueWritten: r.valueWritten, valueCompleted: r.valueCompleted, values: r.values, value: r.value, depth: r.depth, height: r.height,
      parent: r.parent, children: r.children, childrenWritten: r.childrenWritten, layout: r.layout, drawn: r.drawn, notDrawn: r.notDrawn, piece: r.piece, fill: r.fill })),
    pieces: sr.pieces.map(p => ({ row: p.row, shape: p.shape, commands: p.commands, ink: p.ink, z: p.z, z2: p.z2, zlevel: p.zlevel,
      label: { text: p.label.text, ignore: p.label.ignore, minAngle: p.label.minAngle, x: p.label.x, y: p.label.y, rotation: p.label.rotation, transform: p.label.transform,
        align: p.label.align, verticalAlign: p.label.verticalAlign, position: p.label.position, rotate: p.label.rotate, distance: p.label.distance, style: p.label.style,
        textConfig: p.label.textConfig, inkDefault: p.label.inkDefault, ink: p.label.ink, z2: p.label.z2 } })),
  };
}
function transcribedView(t) {
  return {
    dimensions: t.dimensions,
    rows: t.rows.map(r => ({ index: r.index, name: r.name, valueWritten: r.valueWritten, valueCompleted: r.valueCompleted, values: r.values, value: r.value, depth: r.depth, height: r.height,
      parent: r.parent, children: r.children, childrenWritten: r.childrenWritten, layout: r.layout, drawn: r.drawn, notDrawn: r.notDrawn, piece: r.piece, fill: r.fill })),
    pieces: t.pieces.map(p => ({ row: p.row, shape: p.shape, commands: p.commands, ink: p.ink, z: p.z, z2: p.z2, zlevel: p.zlevel,
      label: { text: p.label.text, ignore: p.label.ignore, minAngle: p.label.minAngle, x: p.label.x, y: p.label.y, rotation: p.label.rotation, transform: p.label.transform,
        align: p.label.align, verticalAlign: p.label.verticalAlign, position: p.label.position, rotate: p.label.rotate, distance: p.label.distance, style: p.label.style,
        textConfig: p.label.textConfig, inkDefault: p.label.inkDefault, ink: p.label.ink, z2: p.label.z2 } })),
  };
}
function runTranscription(inp, mut, strict) {
  try {
    return transcribeChart({ series: inp.series.map(s => ({ S: zrClone(s.S), seriesIndex: s.seriesIndex, fills: s.fills })), env: inp.env }, mut);
  } catch (e) {
    if (strict) throw e;
    return { threw: String(e.message) };
  }
}
function chartDiffs(series, inp, mut) {
  const t = runTranscription(inp, mut, !Object.keys(mut).length);
  if (t.threw) return series.map(() => [{ field: 'threw', upstream: null, mutated: t.threw }]);
  return series.map((sr, k) => diffFlat(flat(upstreamView(sr), 's', {}), flat(transcribedView(t[k]), 's', {})));
}

// the random sweep: random forests x option variants through upstream and the transcription (not written)
function sweep() {
  let s = 2463534242;
  const rnd = () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
  const ri = n => Math.floor(rnd() * n);
  const NAMES = ['a', 'b', 'c', 'd', 'e', 'x', 'y'];
  const gen = (depth, maxDepth) => {
    const n = {};
    if (rnd() < 0.9) n.name = NAMES[ri(NAMES.length)] + (rnd() < 0.7 ? String(ri(30)) : '');
    const k = depth < maxDepth ? ri(depth === 1 ? 5 : 4) : 0;
    if (k > 0) {
      n.children = [];
      for (let i = 0; i < k; i++) n.children.push(gen(depth + 1, maxDepth));
      if (rnd() < 0.25) n.value = ri(40);
    } else {
      const t = rnd();
      if (t < 0.08) n.value = 0; else if (t < 0.12) n.value = -ri(5); else if (t < 0.16) { /* none */ } else if (t < 0.2) n.value = [ri(20) + 1, ri(9)]; else n.value = ri(20) + 1;
    }
    if (rnd() < 0.08) n.itemStyle = { color: ['#123456', 'red', '#ffeecc', 'rgb(10,200,30)'][ri(4)] };
    if (rnd() < 0.05) n.label = { align: ['left', 'right', 'center'][ri(3)] };
    return n;
  };
  const variants = [{}, { sort: 'asc' }, { sort: null }, { clockwise: false, startAngle: 37 }, { startAngle: -123.4, minAngle: 4, renderLabelForZeroData: true },
    { radius: ['12%', '88%'], center: ['40%', 310.5], label: { rotate: 'tangential' } }, { radius: 150, center: '45%', label: { rotate: 33, align: 'left', distance: 7 } },
    { label: { align: 'right', minAngle: 12 }, clockwise: false, itemStyle: { borderRadius: ['15%', 6] } }, { label: { position: 'outside', color: 'inherit' }, radius: [20, '55%'] },
    { levels: [{}, { radius: ['10%', '35%'], itemStyle: { color: '#aa3344' } }, { label: { rotate: 'tangential', align: 'left' } }, { r0: '60%', r: 250, label: { position: 'outside' } }] },
    { stillShowZeroSum: false, renderLabelForZeroData: true, label: { rotate: 'none' } }];
  let checks = 0;
  for (let t = 0; t < 40; t++) {
    const data = [];
    const nr = 1 + ri(6);
    const md = 1 + ri(4);
    for (let i = 0; i < nr; i++) data.push(gen(1, md));
    if (t % 13 === 5) data.forEach(function z(n) { if ('value' in n) n.value = 0; (n.children || []).forEach(z); });
    variants.forEach((v, vi) => {
      const opt = Object.assign({ type: 'sunburst', data: zrClone(data) }, zrClone(v));
      const option = { animation: false, series: [opt] };
      if (vi % 5 === 3) option.darkMode = true;
      runChart(echarts, option, chart => {
        const zr = chart.getZr();
        const list = zr.storage.getDisplayList(true);
        const di = new Map();
        list.forEach((el, i) => di.set(el, i));
        const sm = chart.getModel().getSeriesByIndex(0);
        const sr = readSunburst(chart, sm, opt, di, new Map());
        const inp = { series: [{ S: mergedOption(opt), seriesIndex: 0, fills: null }],
          env: { W, H, palette: json(chart.getModel().option.color), textStyle: json(chart.getModel().option.textStyle), background: json(zr.getBackgroundColor()), isDark: !!zr.isDarkMode() } };
        const d = chartDiffs([sr], inp, {})[0];
        must(!d.length, 'sweep forest ' + t + ' variant ' + vi + ': the transcription differs at ' + d.slice(0, 4).map(x => JSON.stringify(x)).join('; '));
        checks++;
      });
    });
  }
  return checks;
}

function check(g) {
  const { out, side } = g;
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    const sd = side[c.id];
    const diffs = chartDiffs(c.series, sd, {});
    diffs.forEach((d, k) => must(!d.length, c.id + '/' + k + ': the transcription differs at ' + d.slice(0, +(process.env.ORACLE_NDIFF || 4)).map(x => JSON.stringify(x)).join('; ')));
    // the transcribed colour record: its fill is upstream's sunburstVisual fill
    const t = runTranscription(sd, {}, true);
    c.series.forEach((sr, k) => {
      sr.geometry = t[k].geometry;
      sr.rows.forEach((r, i) => {
        const tr = t[k].rows[i];
        const want = sd.hasVM ? sd.preVisualMapFills[k][i] : r.fill;
        must(tr.colour.fill === want, c.id + '/' + k + ' row ' + i + ': the transcribed colour ' + tr.colour.fill + ' is not the sunburstVisual fill ' + want);
        r.colour = tr.colour;
        r.visualMapFill = !!sd.hasVM;
        const pc = r.piece;
        if (pc != null) sr.pieces[pc].label.hiddenBy = t[k].pieces[pc].label.hiddenBy;
      });
      // paint order inside one series: the sectors in group order, then the labels in group order
      const sp = sr.pieces.map(p => p.paint).filter(x => x != null);
      const lp = sr.pieces.map(p => p.label.paint).filter(x => x != null);
      const asc = a => a.every((x, i) => i === 0 || x > a[i - 1]);
      must(asc(sp) && asc(lp) && (!lp.length || !sp.length || Math.max(...sp) < Math.min(...lp)), c.id + '/' + k + ': the paint order is not sectors < labels in group order');
      must(sr.pieces.every(p => p.label.ignore || p.label.text == null || p.label.paint != null), c.id + '/' + k + ': a shown label with text is not painted');
    });
  }
  // anchors from upstream.md section 5
  const S0 = id => byId[id].series[0];
  const piece = (id, name) => S0(id).pieces.find(p => S0(id).rows[p.row].name === name);
  const is = (a, b) => Object.is(a, b);
  const d1 = id => S0(id).pieces.map(p => S0(id).rows[p.row].name).join(',');
  must(d1('B-3level') === 'B,B2,B21,B1,A,A1,A2,C', 'B-3level: piece order ' + d1('B-3level'));
  const pB = piece('B-3level', 'B');
  must(is(pB.shape.endAngle, 1.7361433085627804) && is(pB.label.x, 437.3719184877501) && is(pB.label.y, 303.09672545521244) && is(pB.label.rotation, 6.200511816295644) && pB.ink.fill === '#5070dd', 'B-3level: B');
  const pA = piece('B-3level', 'A');
  must(is(pA.label.x, 365.65850025043534) && is(pA.label.rotation, 0.4133674544197099) && pA.ink.fill === '#b6d634', 'B-3level: A (flipped)');
  must(piece('B-3level', 'B2').ink.fill === 'rgba(109,135,226,1)' && piece('B-3level', 'B21').ink.fill === 'rgba(138,159,232,1)', 'B-3level: lifts');
  must(pB.label.ink.fill === '#eee' && pB.label.ink.stroke === '#5070dd' && pB.label.ink.lineWidth === 2 && piece('B-3level', 'B2').label.ink.stroke === null, 'B-3level: label inks');
  must(d1('S-asc-D1') === 'C,A,A2,A1,B,B1,B2,B21', 'S-asc-D1: order');
  must(is(piece('S-asc-D1', 'A').shape.endAngle, 1.4054493450270125) && is(piece('S-asc-D1', 'A1').shape.endAngle, 1.4054493450270127) && is(piece('S-asc-D1', 'B').shape.startAngle, 1.4054493450270122), 'S-asc-D1: accumulator bits');
  must(d1('S-asc') === 'v,w,x,y,y3,y2,y1,z' || d1('S-asc').indexOf('y3,y2,y1') >= 0, 'S-asc: reversed ties ' + d1('S-asc'));
  const lB21 = piece('R-levels', 'B21');
  must(is(lB21.label.x, 594.9668363283799) && is(lB21.label.y, 120.52038351917864) && lB21.label.align === 'left' && lB21.shape.r0 === 200 && lB21.shape.r === 260, 'R-levels: B21 outside');
  const cB = piece('A-ccw', 'B');
  must(is(cB.shape.endAngle, -3.306939635357677) && is(cB.label.x, 394.46718385335373) && is(cB.label.y, 233.22883896855313) && cB.label.align === 'left', 'A-ccw: B');
  const fd = piece('X-fulldisc', 'Only');
  must(fd.label.x === 300 && fd.label.y === 240 && is(fd.label.rotation, 4.71238898038469), 'X-fulldisc: centred, rotated 3 PI / 2');
  must(piece('X-fulldisc', 'k').label.y === 420, 'X-fulldisc: child at 6 o\'clock');
  must(S0('V-string').rows[1].valueCompleted === '053' && S0('V-string').rows[1].value === 53, 'V-string: concatenation');
  must(S0('X-allzero').pieces.length === 0, 'X-allzero: nothing drawn');
  must(byId['X-two-series'].series[1].rows.find(r => r.name === 'a').fill === '#5070dd' && byId['X-two-series'].series[1].rows.find(r => r.name === 'c').fill === '#505372', 'X-two-series: shared palette');
  must(piece('F-flip-270', 'Solo').label.rotation !== piece('F-flip-90', 'Solo').label.rotation, 'F-flip: distinct');
  must(S0('L-align-middle').pieces.every(p => Number.isNaN(p.label.x)), 'L-align-middle: NaN anchors');
  must(piece('I-radius-pct', 'B2').shape.cornerRadius[0] === 30 && piece('I-radius-pct', 'B').shape.cornerRadius[0] === 15, 'I-radius-pct: percent of r');
  must(byId['G-drink'].paintRuns.some(r => r.owner === 'component' && r.type === 'title'), 'G-drink: title elements');
  must(byId['G-visualMap'].series[0].rows.every(r => r.fill !== 'red'), 'G-visualMap: the visualMap colour wins');
  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      const ds = chartDiffs(c.series, side[c.id], gd.mut);
      let any = false;
      ds.forEach((d, k) => {
        if (d.length) {
          any = true;
          if (gd.named.includes(c.id)) differs.push({ case: c.id + '/' + k, fields: d.slice(0, 3) });
        }
      });
      if (any) changed.push(c.id);
    }
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(x => changed.includes(x)), differs };
  });
}

// ============================================================================
// Output
// ============================================================================
let specials = 0;
function sanitize(v) {
  if (typeof v === 'number') {
    if (Number.isNaN(v)) return null;
    if (v === Infinity) { specials++; return 'Infinity'; }
    if (v === -Infinity) { specials++; return '-Infinity'; }
    if (Object.is(v, -0)) { specials++; return '-0'; }
    return v;
  }
  if (v === undefined) return undefined;
  if (v === null || typeof v !== 'object') return v;
  if (isArray(v)) return v.map(x => { const s = sanitize(x); return s === undefined ? null : s; });
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
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner)).join(',\n') + '\n' + ind + '}';
}

// the series record in the documented key order
function ordered(c) {
  c.series = c.series.map(sr => ({ seriesIndex: sr.seriesIndex, type: sr.type, name: sr.name, option: sr.option, geometry: sr.geometry, dimensions: sr.dimensions,
    rows: sr.rows.map(r => ({ index: r.index, name: r.name, valueWritten: r.valueWritten, valueCompleted: r.valueCompleted, values: r.values, value: r.value, depth: r.depth,
      height: r.height, parent: r.parent, children: r.children, childrenWritten: r.childrenWritten, layout: r.layout, drawn: r.drawn, notDrawn: r.notDrawn, piece: r.piece,
      fill: r.fill, colour: r.colour, visualMapFill: r.visualMapFill })),
    pieces: sr.pieces.map(p => Object.assign({}, p, { label: (({ text, ignore, hiddenBy, minAngle, x, y, rotation, transform, align, verticalAlign, position, rotate, distance, font, padding, style,
      textConfig, inkDefault, ink, tspans, background, z, z2, zlevel, silent, paint }) => ({ text, ignore, hiddenBy, minAngle, x, y, rotation, transform, align, verticalAlign, position, rotate,
      distance, font, padding, style, textConfig, inkDefault, ink, tspans, background, z, z2, zlevel, silent, paint }))(p.label) })) }));
  return c;
}

function generate() {
  const side = {};
  const cases = CASES.map(d => {
    try {
      return recordCase(d, side);
    } catch (e) {
      if (e instanceof OracleError) e.message = d.id + ': ' + e.message;
      throw e;
    }
  });
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version + ' (V8 ' + process.versions.v8 + ')',
    W, H, seed: SEED, tz: 'UTC',
    api: {
      update: "echarts.init(null, null, {renderer: 'svg', ssr: true, width: 800, height: 600}); setOption (animation false, forced when the option does not say so); zr.storage.getDisplayList(true) (transforms, updateInnerText, TSpan layout); no animation frame is ever stepped",
      model: "getData(): data.tree, tree.getNodeByDataIndex(i) {name, depth, height, parentNode, children (SORTED in place by the layout), getValue(), piece}, data.dimensions, data.get(dim, i), getRawDataItem(i) (the item AFTER completeTreeValue), getItemLayout(i), getItemVisual(i, 'style').fill, sm.getViewRoot()",
      view: 'chart.getViewOfSeriesModel(sm).group.children(): the SunburstPiece sectors in add order (shape, style, z / z2, path via getBoundingRect), piece.getTextContent() (the label ZRText: x, y, rotation, ignore, style, transform, TSpan children), piece.textConfig, piece._innerTextDefaultStyle',
      paint: 'zr.storage.getDisplayList(true); an element is owned by the first view group found climbing el.parent, then el.__hostTarget (a label Text -> its piece); its group is the class the reader gave it (sector / label / labelBg)',
      production: 'every case must record identically through dist/echarts.min.js',
    },
    notes: [
      "Rows: SeriesData row i = the i-th node of a PRE-ORDER walk of {name: series.name, children: series.data} in the WRITTEN order -- row 0 is the VIRTUAL root (depth 0, name = the series option name or '', never drawn on the first render). ALL roots are laid out and drawn (unlike the tree series). completeTreeValue runs first, post-order: a node without a value (null, missing, NaN, or a non-numeric string: global isNaN) takes the sum of its children's COMPLETED values (a leaf -> 0), a negative value becomes 0 BEFORE its parent sums it, an explicit parent value is KEPT (no rescale: V-gap / V-spill), an array's [0] is replaced; the sum is JS '+', so string values concatenate ('5' + '3' under 0 -> '053', stored as 53: V-string). The store parses the completed value: a scalar fills every dim, an array fills dim k with element k.",
      "Sort (the layout stage, before the colour visual; in place, so it drives the layout order, the draw order AND the palette order): 'asc' by value with ties REVERSED (higher dataIndex first); any other non-null value (the default 'desc', 'foo') by value descending with ties in dataIndex order; a PRESENT sort: null (or undefined) means no sort at all -- only an ABSENT key takes the default 'desc' (merge semantics). A comparator function is not representable in JSON (S-function-dropped).",
      "Layout: size = min(W, H); cx = P(center[0], W), cy = P(center[1], H) (a scalar center is used for both); r0 = P(radius[0], size / 2), r = P(radius[1], size / 2) (a scalar radius is [0, radius]); P = parsePositionOption (keywords, 'x%' -> parseFloat / 100 * base, other strings parseFloat, null NaN). startAngle = (-deg) * (PI / 180), minAngle = deg * (PI / 180); unitRadian = PI / (sum || validDataCount) * 2 with sum = the virtual root's value; rings = root height - 1; rPerLevel = (r - r0) / (rings || 1); angle = (sum === 0 && stillShowZeroSum) ? unitRadian : value * unitRadian, raised to minAngle (nothing shrinks); endAngle = startAngle + dir * angle; children start at the PARENT's startAngle with the GLOBAL unitRadian, each next child at parentStart + (the running sum of the returned endAngle - startAngle); ring d (0 = innermost): r0 + rPerLevel * d .. r0 + rPerLevel * (d + 1); levels[depth] (depth 1 = the first ring) .radius [r0, r] wins over the deprecated .r0 / .r, each given end parsed against size / 2, the other end kept.",
      "Colour (sunburstVisual, after the sort, over EVERY node in sorted pre-order incl. zero-valued ones): the first itemStyle.color on item -> levels[depth] -> series wins; otherwise the palette colour of the depth-1 ancestor, keyed by its name (or its dataIndex + '' when the name is ''), taken lazily from ONE scope shared by every sunburst series of the chart (a cached key returns its colour, a new key takes palette[cursor] and advances the cursor) -- the palette is the series' own color list, else the global color; a node deeper than 1 is lift(colour, (depth - 1) / (treeHeight - 1) * 0.5) with treeHeight the virtual root's height (lift: each channel ((255 - c) * level + c) | 0, printed 'rgba(r,g,b,a)'). A child does NOT inherit an explicit parent colour. The virtual root is '#86878c'. A visualMap overwrites the fill afterwards (G-visualMap).",
      "Pieces: pre-order over the sorted tree from the view root (the virtual root itself skipped); a node whose value is 0 is skipped unless renderLabelForZeroData. Each piece is a Sector (z2 2, series z 2) with shape = the layout + cornerRadius (itemStyle.borderRadius on the chain: null -> 0; a scalar -> [c, c, c, c]; each entry through zrender parsePercent against Math.abs(r || 0 - r0 || 0) = r (JS precedence)), style = the visual style (getItemStyle keys: fill, stroke 'white', lineWidth 1, opacity 1, lineDash = borderType 'solid', shadow*) with lineJoin 'bevel'. The path is zrender roundSector: arcs through PathProxy.arc -> normalizeArcAngles (modPI2 rounds the start angle to 1e-8 of PI).",
      "Labels (every piece has a Text, z2 4; all labels paint after all sectors): text = the string formatter ({a} series name, {b} name, {c} the COMPLETED raw value) || the name; empty -> no text. ignore = !(show && !(|endAngle - startAngle| < label.minAngle / 180 * PI)) (unset minAngle: NaN, never hides). mid = (start + end) / 2; flip = n > PI * 0.5 && !(|n - PI * 0.5| < 1e-4) && n < PI * 1.5 with n = normalizeRadian(tangential ? PI / 2 - mid : mid). position 'outside': r = layout.r + distance, align flip ? right : left; else align center / falsy: r = (r0 === 0 && |angle - 2 PI| < 1e-4) ? 0 : (r + r0) / 2; left: r0 + distance (flip -> 'right'); right: r - distance (flip -> 'left'); another align: r undefined -> NaN anchor. x = r * cos(mid) + cx, y = r * sin(mid) + cy. rotation = normalizeRadian(radial: normalizeRadian(-mid) + (flip ? PI : 0); tangential: normalizeRadian(PI / 2 - mid) + (flip ? PI : 0); a number: deg * PI / 180 (no flip); else 0). verticalAlign = label.verticalAlign || 'middle'. offset and labelLine are ignored.",
      "Label colours: textConfig {inside: position !== 'outside', outsideFill: label.color === 'inherit' ? the sector fill : null}; the label's own fill only for a concrete label.color (attached text: no global textStyle colour). Inside default fill from the sector fill's lum (> 0.5 '#333', > 0.2 '#eee', else '#ccc'), default stroke = the sector fill when (lum(textFill) < 0.4) === isDarkMode; outside default fill = outsideFill || (dark ? '#ccc' : '#333'), stroke = the zr background blended opaque toward white (dark: black), 'rgba(...)'. The TSpans draw the own fill else the default; the default stroke only when neither fill nor stroke is set, at lineWidth (own || 2).",
      'Not recorded: drill-down (sunburstRootToNode, the roll-up disc), emphasis / blur / focus / select states, hover, tooltip, click, animations. Text widths (TSpan x for align, background boxes) come from zrender\'s node measureText estimate, not a real font.',
    ],
    cases,
  };
  return { out, side };
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

let g1;
let nSpecial = 0;
let json1;
let json2;
let sweepChecks = 0;
try {
  g1 = generate();
  if (process.env.ORACLE_DUMP) fs.writeFileSync(process.env.ORACLE_DUMP, fmt(sanitize(g1.out), '') + '\n');
  g1.out.guards = check(g1);
  g1.out.cases = g1.out.cases.map(ordered);
  sweepChecks = sweep();
  specials = 0;
  const s1 = sanitize(g1.out);
  nSpecial = specials;
  json1 = fmt(s1, '') + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(s1), 'the written JSON does not parse back to the record');
  const g2 = generate();
  g2.out.guards = check(g2);
  g2.out.cases = g2.out.cases.map(ordered);
  json2 = fmt(sanitize(g2.out), '') + '\n';
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message + (process.env.ORACLE_DEBUG ? '\n' + e.stack : '') : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
const out = g1.out;
const bad = out.guards.filter(gd => !gd.ok);
out.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ' (' + gd.mutation + '): named '
  + gd.named.join(' / ') + '; changes ' + gd.changed.length + ': ' + gd.changed.join(', ')));
const deterministic = json1 === json2;
const nSeries = out.cases.reduce((a, c) => a + c.series.length, 0);
console.log(out.cases.length + ' cases (' + nSeries + ' sunburst series); sweep ' + sweepChecks + ' random charts agree; ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; ' + nSpecial + ' -0/Infinity values; ' + logged.length + ' console messages from upstream'
  + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (bad.length || !deterministic) {
  bad.forEach(gd => console.log('  ' + gd.id + ' named ' + gd.named.join(',') + ' changed ' + gd.changed.join(',')));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
