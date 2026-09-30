/*
Upstream's own answers for the TREE series: the data model, the layout, every
node symbol, every edge and every label exactly as chart/tree/TreeSeries.ts
(getInitialData: the virtual root, pre-order data indices, the leaves-model
wrap, isExpand from initialTreeDepth / expandAndCollapse / collapsed),
data/Tree.ts (createTree, depth / height), chart/tree/treeLayout.ts +
layoutHelper.ts + traversalHelper.ts (the view rect, the Reingold-Tilford walk
copied from d3-hierarchy, the mapping into the rect, radialCoordinate),
chart/tree/treeVisual.ts (the per-node style), chart/tree/TreeView.ts (the
symbols, the Bezier / TreePath edges, the radial label side and rotation),
chart/helper/Symbol.ts + util/symbol.ts (createSymbol, the emptyCircle brush:
fill '#fff' or the colour when collapsed with children, stroke = the colour,
lineWidth 2), label/labelStyle.ts and zrender (Path.getBoundingRect with the
stroke, Element.updateInnerText, contain/text.ts calculateTextPosition, Text /
TSpan) build them.

Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) at 800 x 600
with Math.random replaced by the port's xorshift32 (seed 2463534242, reset
before each chart) and process.env.TZ = 'UTC' set inside this script before
anything touches Date (checked: a script that runs under another zone stops).
EVERY case is rendered with `animation: false`: an option that does not say so
(the gallery files) gets it set before setOption and the case records
animationForced true -- without it zrender's initial animation would leave
every new symbol and edge at its parent's old position, since nothing here
steps an animation frame. After setOption it runs zr.storage.getDisplayList(true)
(every element's update: transforms, updateInnerText, TSpan layout) and reads
the live models, views and the display list. Every chart is disposed in a
finally. Every case is recorded from the DEVELOPMENT build (dist/echarts.js)
and must record identically through the PRODUCTION build
(dist/echarts.min.js); a case marked `prod` is recorded from production and
must throw in development (radial + polyline: TreeView.ts drawEdge throws
'The polyline edgeShape can only be used in orthogonal layout' under __DEV__).

  node tools/advchart-oracle/tree.js

writes tests/fixtures/advchart-tree.json (ORACLE_OUT overrides;
ORACLE_DUMP=<file> also writes the record before the checks, for debugging).

-----------------------------------------------------------------------------
Numbers are plain JSON numbers written by JSON.stringify (shortest round-trip
form). Values JSON has no form for:
  null        NaN in a number field (e.g. `value` of a node without a value),
              or an undefined value inside an array
  "-0" / "Infinity" / "-Infinity"   those doubles, as strings (the writer counts
              them and prints the count; the radial root's x is often "-0")
  an absent key   upstream holds undefined
A colour is a css string exactly as upstream holds it (or null).

Top level
  source, W, H, seed, tz ('UTC'), api {...}, notes[], symbolPaths, cases[],
  guards[]
  symbolPaths  {symbolType: {bbox {x, y, width, height}, commands [{cmd,
    args}]}}: the PathProxy of every symbol type drawn anywhere in the fixture,
    built by createSymbol(type, -1, -1, 2, 2) (the unit box; the path's scale
    makes the real size), with its raw path bounding rect (no stroke) --
    checked identical for every element of that type (M L C Q A Z R: A = cx,
    cy, rx, ry, startAngle, sweep, 0, clockwise 1)
  cases[]  one per chart:
    id, note, gallery (file name or null), option (as fed, animation false
    included; null for a gallery case: load
    examples/advchart/gallery/<gallery>.json, set animation false when
    animationForced, and feed it VERBATIM otherwise), animationForced (bool),
    productionBuild (bool), devError (the development build's message, or null)
    ground     {background, isDark}
    textStyle  ecModel.option.textStyle (the global text style; fontFamily
               'Microsoft YaHei' on this Windows machine)
    paintRuns  the WHOLE display list in paint order, run-length encoded:
               [{owner, index, type, group, zlevel, z, z2, n}]. owner 'series'
               (index = series index, type 'tree', group 'edge' (a Bezier or
               TreePath edge) | 'symbol' (a node symbol path) | 'label' (a
               label's TSpan) | 'labelBg' (a label's background Rect) | 'mark'
               (anything else)), 'component' (a component's elements, e.g. the
               legend: group 'mark' / 'label'), 'other'
    series[]   one per series, series order: seriesIndex, type, name (the
               option name as a string, or null: upstream's default
               'series\u0000<i>' is NOT written -- a JSON \u0000 does not
               survive fpjson; it is what {a} prints for an unnamed series),
      layout ('orthogonal' | 'radial', the option), orientOption (as fed / the
      default 'LR'), orient (getOrient(): 'horizontal' -> 'LR', 'vertical' ->
      'TB'), edgeShape, edgeForkPosition, curveness (series lineStyle.curveness:
      the ONLY curveness read), expandAndCollapse, initialTreeDepth,
      layoutInfo {x, y, width, height} (getLayoutRect of the box params in the
      800 x 600 canvas), viewGroup {x, y, scaleX, scaleY} (the view's roam
      group: identity at the default zoom 1, checked), mainGroup {x, y} (the
      layout origin: layoutInfo.x / y, or the box centre for radial),
      dimensions (['value', 'value0', ...]: as many as the longest value array),
      rows[]  EVERY SeriesData row, data-index order = pre-order of the
        hierarchy; row 0 is the VIRTUAL root {name: series option name,
        children: data} (depth 0, never drawn); row 1 is data[0] (depth 1);
        rows of data[1..] exist but are never laid out:
        index, name (convertOptionIdName: '' for none, a number stringified),
        valueWritten (json of the item's `value` key; absent when the item has
        none), values [one per dimension] (the store: a scalar fills EVERY
        dim, an array fills dim k with element k, null / missing / a
        non-numeric string -> NaN), value (node.getValue(): dim 'value'),
        depth, height (leaf 1), isExpand, parent (the parent's data index, null
        for the virtual root), children [data indices], leaves (bool: the item
        model's parent is the leaves model -- !(children.length && isExpand):
        true leaves AND collapsed inner nodes), chain (the model chain labels /
        itemStyle / lineStyle / emphasis resolve through, first non-null wins:
        ['item', 'leaves', 'series'] or ['item', 'series']; symbol* keys are
        read from the item's OWN value or the series only), laidOut (a layout
        with non-NaN x / y exists), layout (null, or {x, y} local to the main
        group; radial also rawX (the angle-ish coordinate: 0..2PI from 12
        o'clock, clockwise) and rawY (the radius)), drawn (a symbol element
        exists),
        symbol  null, or
          group      {x, y, scaleX, scaleY, rotation}: the Symbol group (x / y =
                     layout)
          global     [x, y]: the group's global translation (= layout + the
                     main group offset: "after the view transform")
          type       the symbol visual (item's own symbol, else the series')
          pathType   shape.symbolType ('emptyCircle' -> 'circle')
          emptyBrush __isEmptyBrush
          size       [w, h] normalised symbolSize
          path       {x, y, scaleX, scaleY, rotation}: the path in the group
                     (scale = size / 2, x / y = symbolOffset, rotation =
                     symbolRotate in radians)
          transform  the path's GLOBAL m6
          style      the path's own style keys (null = own undefined)
          ink        {fill, stroke, lineWidth, opacity} as the path reads them
                     (prototype defaults included)
          z, z2 (100), zlevel, silent, paint (display-list index)
        label   null (no text content, or ignored: show false), or
          text, lines, textConfig {position, distance, offset, rotation,
          origin, inside, local}, layoutRect (the symbol path's bounding rect
          WITH its stroke -- width += lineWidth / lineScale, lineScale =
          size / 2 because strokeNoScale -- then the path's global transform;
          the rect calculateTextPosition works on), inner {x, y, rotation,
          originX, originY} (the innerTransformable: the anchor, checked =
          calculateTextPosition(position, distance, layoutRect) + offset; radial
          origin 'center' -> originX / Y = the rect centre - the anchor, so the
          rotation turns about the SYMBOL centre), transform (the label's
          final m6), align, verticalAlign (author, else the position's
          default), font, padding, style {fill, stroke, lineWidth, opacity,
          backgroundColor}, inkDefault {fill, stroke, align, verticalAlign},
          ink (what the TSpans draw), background (null, or the label box Rect
          {shape {x, y, width, height}, style, paint}), tspans [{text, x, y,
          textAlign, textBaseline}] (TEXT WIDTHS are zrender's node
          measureText estimate), z, z2 (102), zlevel, silent, paint
      edges[]  every edge element added to the view, in owner pre-order:
        owner (data index of the node whose symbol owns it), kind 'curve' (one
        BezierCurve per laid-out node under a real parent: from = the parent,
        to = [the node]) | 'polyline' (one TreePath per EXPANDED node with
        children: from = the node, to = all its children), lineStyleOf (the
        node whose itemModel lineStyle styles it: the owner -- the CHILD for a
        curve, the PARENT for a polyline), shape (curve: {x1, y1, cpx1, cpy1,
        cpx2, cpy2, x2, y2, percent}; polyline: {parentPoint, childPoints,
        orient, forkPosition}), commands (the built path, decoded: curve = M +
        C; polyline = M L (stem) M L L L (first twig, bar, last twig) + M L per
        middle child; a single child: M L), style (own keys), ink {stroke,
        lineWidth, opacity, lineDash} (lineDash = lineStyle.type as written:
        'dashed', 'solid' ... or null), z, z2 (0), zlevel, silent, paint
  guards[]  one per mutation of the transcription: id, mutation, named,
            changed, ok (named is a subset of changed), differs

-----------------------------------------------------------------------------
The transcription (checked against every recorded series, Object.is on every
field it produces) takes as INPUTS only: each series option as fed merged over
TreeSeriesModel.defaultOption (checked against upstream's own on the keys read),
the canvas size, the series index, and each symbol type's unit path bbox (from
symbolPaths). It reproduces: the rows (pre-order, name, values, depth, height,
isExpand, parent / children, the leaves wrap, the chain), getLayoutRect, the
Reingold-Tilford walk (firstWalk / apportion / executeShifts / moveSubtree /
secondWalk, the radial separation / depth), the extremes / delta / tx / kx /
ky mapping for LR / RL / TB / BT / radial (radialCoordinate), the symbol
(type, size, scale, offset, rotation, ink incl. the empty brush and the
collapsed fill, z / z2, global position), every edge (Bezier control points
incl. the radial raw-space ones with `|| 0`, the TreePath shape and the path
commands buildPath emits, ink, owner, z / z2) and every label (text incl. a
string formatter, textConfig position / distance / rotation, the stroke-grown
layoutRect through the composed transform, the anchor, origin, final m6, the
radial side / rotation rule, align / verticalAlign). Label colours, fonts,
TSpans and backgrounds are RECORDED, not transcribed.
Self-checks (any failure: nothing is written, exit 1): TZ is UTC; the
transcription reproduces every recorded series; an extra sweep of random trees
(not written) through upstream and the transcription agrees; upstream.md's
anchor numbers; within one tree series the paint order is all edges, then all
symbols, then all labels; the display list is sorted by (zlevel, z, z2); the
production build records every case identically; every guard is ok; two
generations in the process give identical bytes.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-tree.json');
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
const json = v => (v === undefined ? null : zrClone(v));
const PI = Math.PI;
const rect4 = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
const m6 = t => (t ? Array.from(t).slice(0, 6) : null);

// ============================================================================
// The transcription (with the guards' mutations as switches)
// ============================================================================

// TreeSeriesModel.defaultOption on the keys the transcription reads
const DEFAULTS = {
  z: 2, left: '12%', top: '12%', right: '12%', bottom: '12%', layout: 'orthogonal', edgeShape: 'curve', edgeForkPosition: '50%',
  zoom: 1, orient: 'LR', symbol: 'emptyCircle', symbolSize: 7, expandAndCollapse: true, initialTreeDepth: 2,
  lineStyle: { color: '#cfd2d7', width: 1.5, curveness: 0.5 }, itemStyle: { color: 'lightsteelblue', borderWidth: 1.5 }, label: { show: true },
};
// the series option upstream holds: the fed option merged over the defaults, the box keys through
// util/layout.ts mergeLayoutParam (2 fed params of left / right / width drop the third default)
function mergedOption(opt) {
  const S = zrMerge(zrClone(opt), DEFAULTS);
  for (const names of [['left', 'right', 'width'], ['top', 'bottom', 'height']]) {
    const hasValue = (o, k) => o[k] != null && o[k] !== 'auto';
    const newParams = {};
    const merged = {};
    let newCount = 0;
    let mergedCount = 0;
    names.forEach(k => { merged[k] = DEFAULTS[k]; });
    names.forEach(k => {
      if (hasOwn(opt, k)) newParams[k] = merged[k] = opt[k];
      if (hasValue(newParams, k)) newCount++;
      if (hasValue(merged, k)) mergedCount++;
    });
    let res;
    if (mergedCount === 2 || !newCount) res = merged;
    else if (newCount >= 2) res = newParams;
    else {
      res = newParams;
      for (const k of names) if (!hasOwn(newParams, k) && hasOwn(DEFAULTS, k)) { res[k] = DEFAULTS[k]; break; }
    }
    names.forEach(k => { S[k] = res[k]; });
  }
  return S;
}
const READ_KEYS = ['z', 'zlevel', 'left', 'top', 'right', 'bottom', 'width', 'height', 'layout', 'edgeShape', 'edgeForkPosition', 'orient', 'symbol', 'symbolSize',
  'symbolRotate', 'symbolOffset', 'expandAndCollapse', 'initialTreeDepth', 'lineStyle', 'itemStyle', 'label', 'leaves', 'zoom', 'center'];

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
// util/layout.ts getLayoutRect(positionInfo, containerRect), margin 0, no aspect
function getLayoutRect(p, c) {
  const cw = c.width;
  const ch = c.height;
  let left = parsePercent(p.left, cw);
  let top = parsePercent(p.top, ch);
  const right = parsePercent(p.right, cw);
  const bottom = parsePercent(p.bottom, ch);
  let width = parsePercent(p.width, cw);
  let height = parsePercent(p.height, ch);
  const vm = 0;
  const hm = 0;
  if (isNaN(width)) width = cw - right - hm - left;
  if (isNaN(height)) height = ch - bottom - vm - top;
  if (isNaN(left)) left = cw - right - width - hm;
  if (isNaN(top)) top = ch - bottom - height - vm;
  switch (p.left || p.right) {
    case 'center': left = cw / 2 - width / 2 - 0; break;
    case 'right': left = cw - width - hm; break;
  }
  switch (p.top || p.bottom) {
    case 'middle': case 'center': top = ch / 2 - height / 2 - 0; break;
    case 'bottom': top = ch - height - vm; break;
  }
  left = left || 0;
  top = top || 0;
  if (isNaN(width)) width = cw - hm - left - (right || 0);
  if (isNaN(height)) height = ch - vm - top - (bottom || 0);
  return { x: (c.x || 0) + left + 0, y: (c.y || 0) + top + 0, width, height };
}

// ---- zrender core/matrix.ts + Transformable (no skew / anchor anywhere here) ----
function mul(m1, m2) {
  return [m1[0] * m2[0] + m1[2] * m2[1], m1[1] * m2[0] + m1[3] * m2[1], m1[0] * m2[2] + m1[2] * m2[3], m1[1] * m2[2] + m1[3] * m2[3],
    m1[0] * m2[4] + m1[2] * m2[5] + m1[4], m1[1] * m2[4] + m1[3] * m2[5] + m1[5]];
}
function rotateM(a, rad) {
  const aa = a[0]; const ac = a[2]; const atx = a[4]; const ab = a[1]; const ad = a[3]; const aty = a[5];
  const st = Math.sin(rad);
  const ct = Math.cos(rad);
  return [aa * ct + ab * st, -aa * st + ab * ct, ac * ct + ad * st, -ac * st + ct * ad, ct * (atx - 0) + st * (aty - 0) + 0, ct * (aty - 0) - st * (atx - 0) + 0];
}
const notAroundZero = v => v > 5e-5 || v < -5e-5;
const T = t => Object.assign({ x: 0, y: 0, scaleX: 1, scaleY: 1, rotation: 0, originX: 0, originY: 0 }, t);
const needLocal = t => notAroundZero(t.rotation) || notAroundZero(t.x) || notAroundZero(t.y) || notAroundZero(t.scaleX - 1) || notAroundZero(t.scaleY - 1);
function localM(t) {
  const ox = t.originX || 0;
  const oy = t.originY || 0;
  const sx = t.scaleX;
  const sy = t.scaleY;
  let m = [];
  if (ox || oy) {
    const dx = ox + 0;
    const dy = oy + 0;
    m[4] = -dx * sx - 0 * dy * sy;
    m[5] = -dy * sy - 0 * dx * sx;
  } else m[4] = m[5] = 0;
  m[0] = sx;
  m[3] = sy;
  m[1] = 0 * sx;
  m[2] = 0 * sy;
  if (t.rotation || 0) m = rotateM(m, t.rotation);
  m[4] += ox + t.x;
  m[5] += oy + t.y;
  return m;
}
// Transformable.updateTransform: null when neither a local transform nor a parent's
function compose(parentM, t) {
  t = T(t);
  const need = needLocal(t);
  if (!need && !parentM) return null;
  let m = need ? localM(t) : [1, 0, 0, 1, 0, 0];
  if (parentM) m = need ? mul(parentM, m) : parentM.slice();
  return m;
}
// BoundingRect.applyTransform
function applyRect(r, m) {
  if (!m) return r;
  if (m[1] < 1e-5 && m[1] > -1e-5 && m[2] < 1e-5 && m[2] > -1e-5) {
    const o = { x: r.x * m[0] + m[4], y: r.y * m[3] + m[5], width: r.width * m[0], height: r.height * m[3] };
    if (o.width < 0) { o.x += o.width; o.width = -o.width; }
    if (o.height < 0) { o.y += o.height; o.height = -o.height; }
    return o;
  }
  const pt = (x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
  const lt = pt(r.x, r.y);
  const rt = pt(r.x + r.width, r.y);
  const rb = pt(r.x + r.width, r.y + r.height);
  const lb = pt(r.x, r.y + r.height);
  const x = Math.min(lt[0], rb[0], lb[0], rt[0]);
  const y = Math.min(lt[1], rb[1], lb[1], rt[1]);
  return { x, y, width: Math.max(lt[0], rb[0], lb[0], rt[0]) - x, height: Math.max(lt[1], rb[1], lb[1], rt[1]) - y };
}
// zr contain/text.ts calculateTextPosition (+ the default align / verticalAlign)
function zrParsePercent(value, maxValue) {
  if (typeof value === 'string') {
    if (value.lastIndexOf('%') >= 0) return parseFloat(value) / 100 * maxValue;
    return parseFloat(value);
  }
  return value;
}
function calculateTextPosition(position, distance, rect) {
  const textPosition = position || 'inside';
  distance = distance != null ? distance : 5;
  const height = rect.height;
  const width = rect.width;
  const halfHeight = height / 2;
  let x = rect.x;
  let y = rect.y;
  let align = 'left';
  let verticalAlign = 'top';
  if (textPosition instanceof Array) {
    x += zrParsePercent(textPosition[0], rect.width);
    y += zrParsePercent(textPosition[1], rect.height);
    align = null;
    verticalAlign = null;
  } else {
    switch (textPosition) {
      case 'left': x -= distance; y += halfHeight; align = 'right'; verticalAlign = 'middle'; break;
      case 'right': x += distance + width; y += halfHeight; verticalAlign = 'middle'; break;
      case 'top': x += width / 2; y -= distance; align = 'center'; verticalAlign = 'bottom'; break;
      case 'bottom': x += width / 2; y += height + distance; align = 'center'; break;
      case 'inside': x += width / 2; y += halfHeight; align = 'center'; verticalAlign = 'middle'; break;
      case 'insideLeft': x += distance; y += halfHeight; verticalAlign = 'middle'; break;
      case 'insideRight': x += width - distance; y += halfHeight; align = 'right'; verticalAlign = 'middle'; break;
      case 'insideTop': x += width / 2; y += distance; align = 'center'; break;
      case 'insideBottom': x += width / 2; y += height - distance; align = 'center'; verticalAlign = 'bottom'; break;
      case 'insideTopLeft': x += distance; y += distance; break;
      case 'insideTopRight': x += width - distance; y += distance; align = 'right'; break;
      case 'insideBottomLeft': x += distance; y += height - distance; verticalAlign = 'bottom'; break;
      case 'insideBottomRight': x += width - distance; y += height - distance; align = 'right'; verticalAlign = 'bottom'; break;
    }
  }
  return { x, y, align, verticalAlign };
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
const nameOf = n => (n == null ? '' : String(n)); // convertOptionIdName(name, '')
const storeFloat = v => (v == null || v === '' ? NaN : Number(v));
function formatTpl(tpl, params) {
  const vars = ['seriesName', 'name', 'value'];
  const alias = ['a', 'b', 'c'];
  for (let i = 0; i < vars.length; i++) tpl = tpl.replace('{' + alias[i] + '}', '{' + alias[i] + '0}');
  for (let k = 0; k < vars.length; k++) tpl = tpl.replace('{' + alias[k] + '0}', params[vars[k]]);
  return tpl;
}
function radialCoordinate(rad, r) {
  rad -= Math.PI / 2;
  return { x: r * Math.cos(rad), y: r * Math.sin(rad) };
}

// the whole tree series: inp {S (merged option), seriesIndex, bbox {pathType: rect}}
function transcribeTree(inp, mut) {
  const S = inp.S;
  const orientOpt = S.orient;
  const orient = mut.aliasUnmapped ? orientOpt : orientOpt === 'horizontal' ? 'LR' : orientOpt === 'vertical' ? 'TB' : orientOpt;
  const radial = S.layout === 'radial';
  const seriesName = S.name != null ? String(S.name) : 'series\u0000' + inp.seriesIndex;
  // ---- data model ----
  const nodes = [];
  let dimMax = 1;
  function mk(item, parent, depth) {
    const nd = { item, parent, depth, children: [], idx: nodes.length, name: nameOf(item.name) };
    const v = item.value;
    dimMax = Math.max(dimMax, isArray(v) ? v.length : 1);
    nodes.push(nd);
    (item.children || []).forEach(c => nd.children.push(mk(c, nd, depth + 1)));
    nd.height = 1 + nd.children.reduce((h, c) => Math.max(h, c.height), 0);
    return nd;
  }
  const vroot = mk({ name: S.name, children: S.data }, null, 0);
  let treeDepth = 0;
  nodes.forEach(n => { if (n.depth > treeDepth) treeDepth = n.depth; });
  const eac = S.expandAndCollapse;
  const expandTreeDepth = (eac && S.initialTreeDepth >= 0) ? S.initialTreeDepth : treeDepth;
  nodes.forEach(n => {
    const it = n.item;
    const useFlag = it && it.collapsed != null && !(mut.collapsedIgnoredWithoutEac && !eac);
    n.isExpand = useFlag ? !it.collapsed : mut.expandLessThan ? n.depth < expandTreeDepth : n.depth <= expandTreeDepth;
  });
  nodes.forEach(n => {
    n.leaves = mut.leavesTrueOnly ? n.children.length === 0 : !(n.children.length && n.isExpand);
    n.levels = n.leaves ? [n.item, S.leaves || {}, S] : [n.item, S];
    n.values = [];
    for (let k = 0; k < dimMax; k++) n.values.push(storeFloat(isArray(n.item.value) ? n.item.value[k] : n.item.value));
  });
  // ---- layout (treeLayout.ts / layoutHelper.ts) ----
  const layoutInfo = getLayoutRect({ left: S.left, top: S.top, right: S.right, bottom: S.bottom, width: S.width, height: S.height }, { x: 0, y: 0, width: W, height: H });
  const cousins = mut.sepCousinsOne ? 1 : 2;
  const sep = radial && !mut.radialNoDepth
    ? (a, b) => (a.parent === b.parent ? 1 : cousins) / a.depth
    : (a, b) => (a.parent === b.parent ? 1 : cousins);
  const vis = n => (n.isExpand ? n.children : []);
  const preorder = (r, cb) => { cb(r); vis(r).forEach(c => preorder(c, cb)); };
  const postorder = (r, cb) => { vis(r).forEach(c => postorder(c, cb)); cb(r); };
  const root = vroot.children[0];
  if (root) {
    const mkH = (n, i) => { n.h = { anc: n, defAnc: null, prelim: 0, mod: 0, change: 0, shift: 0, i, thread: null }; };
    mkH(vroot, 0);
    (function initRec(n) { if (n.isExpand) n.children.forEach((c, i) => { mkH(c, i); initRec(c); }); })(vroot);
    const nextLeft = n => ((n.children.length && n.isExpand) ? n.children[0] : n.h.thread);
    const nextRight = n => ((n.children.length && n.isExpand) ? n.children[n.children.length - 1] : n.h.thread);
    const nextAnc = (vil, v, anc) => (vil.h.anc.parent === v.parent ? vil.h.anc : anc);
    const moveSubtree = (wl, wr, shift) => {
      const change = shift / (wr.h.i - wl.h.i);
      wr.h.change -= change; wr.h.shift += shift; wr.h.mod += shift; wr.h.prelim += shift; wl.h.change += change;
    };
    const executeShifts = v => {
      let shift = 0;
      let change = 0;
      for (let k = v.children.length - 1; k >= 0; k--) {
        const c = v.children[k];
        c.h.prelim += shift; c.h.mod += shift; change += c.h.change; shift += c.h.shift + change;
      }
    };
    const apportion = (v, w, anc) => {
      if (!w) return anc;
      let vor = v; let vir = v; let vol = v.parent.children[0]; let vil = w;
      let sor = vor.h.mod; let sir = vir.h.mod; let sol = vol.h.mod; let sil = vil.h.mod;
      while ((vil = nextRight(vil), vir = nextLeft(vir), vil && vir)) {
        vor = nextRight(vor); vol = nextLeft(vol); vor.h.anc = v;
        const shift = vil.h.prelim + sil - vir.h.prelim - sir + sep(vil, vir);
        if (shift > 0 && !mut.noApportion) { moveSubtree(nextAnc(vil, v, anc), v, shift); sir += shift; sor += shift; }
        sil += vil.h.mod; sir += vir.h.mod; sor += vor.h.mod; sol += vol.h.mod;
      }
      if (vil && !nextRight(vor)) { vor.h.thread = vil; vor.h.mod += sil - sor; }
      if (vir && !nextLeft(vol)) { vol.h.thread = vir; vol.h.mod += sir - sol; anc = v; }
      return anc;
    };
    postorder(root, v => {
      const ch = vis(v);
      const sibs = v.parent.children;
      const w = v.h.i ? sibs[v.h.i - 1] : null;
      if (ch.length) {
        executeShifts(v);
        const mid = (ch[0].h.prelim + ch[ch.length - 1].h.prelim) / 2;
        if (w) { v.h.prelim = w.h.prelim + sep(v, w); v.h.mod = v.h.prelim - mid; } else v.h.prelim = mid;
      } else if (w) v.h.prelim = w.h.prelim + sep(v, w);
      v.parent.h.defAnc = apportion(v, w, v.parent.h.defAnc || sibs[0]);
    });
    vroot.h.mod = -root.h.prelim;
    preorder(root, v => { v.x = v.h.prelim + v.parent.h.mod; v.h.mod += v.parent.h.mod; });
    let left = root;
    let right = root;
    let bottom = root;
    preorder(root, v => { if (v.x < left.x) left = v; if (v.x > right.x) right = v; if (v.depth > bottom.depth) bottom = v; });
    const delta = left === right ? 1 : mut.deltaFromRight ? sep(right, left) / 2 : sep(left, right) / 2;
    const tx = delta - left.x;
    const span = mut.spanNoFallback ? bottom.depth - 1 : (bottom.depth - 1) || 1;
    if (radial) {
      const width = 2 * Math.PI;
      const height = Math.min(layoutInfo.height, layoutInfo.width) / 2;
      const kx = width / (right.x + delta + tx);
      const ky = height / span;
      preorder(root, v => {
        const cx = (v.x + tx) * kx;
        const cy = (v.depth - 1) * ky;
        const f = radialCoordinate(cx, cy);
        v.L = { x: f.x, y: f.y, rawX: cx, rawY: cy };
      });
    } else if (orient === 'LR' || orient === 'RL') {
      const ky = layoutInfo.height / (right.x + delta + tx);
      const kx = layoutInfo.width / span;
      preorder(root, v => { v.L = { x: orient === 'RL' && !mut.rlNoMirror ? layoutInfo.width - (v.depth - 1) * kx : (v.depth - 1) * kx, y: (v.x + tx) * ky }; });
    } else if (orient === 'TB' || orient === 'BT') {
      const kx = layoutInfo.width / (right.x + delta + tx);
      const ky = layoutInfo.height / span;
      preorder(root, v => { v.L = { x: (v.x + tx) * kx, y: orient === 'TB' ? (v.depth - 1) * ky : layoutInfo.height - (v.depth - 1) * ky }; });
    }
  }
  const laidOut = n => !!(n.L && !isNaN(n.L.x) && !isNaN(n.L.y));
  const mainGroup = radial ? { x: layoutInfo.x + layoutInfo.width / 2, y: layoutInfo.y + layoutInfo.height / 2 } : { x: layoutInfo.x, y: layoutInfo.y };
  const mainM = compose(null, mainGroup);
  const z = S.z || 0;
  const zlevel = S.zlevel || 0;
  // ---- symbols ----
  const rows = nodes.map(n => ({ index: n.idx, name: n.name, values: n.values, value: n.values[0], depth: n.depth, height: n.height, isExpand: n.isExpand,
    parent: n.parent ? n.parent.idx : null, children: n.children.map(c => c.idx), leaves: n.leaves, chain: n.leaves ? ['item', 'leaves', 'series'] : ['item', 'series'],
    laidOut: laidOut(n), layout: n.L ? Object.assign({}, n.L) : null, drawn: laidOut(n) }));
  const symbols = [];
  const labels = [];
  const drawnNodes = nodes.filter(laidOut);
  drawnNodes.forEach(n => {
    const it = n.item;
    const own = k => (mut.leavesSymbolUsed ? mget(n.leaves ? [it, S.leaves || {}] : [it], k) : it[k]);
    const type = retrieve2(own('symbol'), S.symbol);
    let sz = retrieve2(own('symbolSize'), S.symbolSize);
    sz = isArray(sz) ? [sz[0] || 0, sz[1] || 0] : [+sz || 0, +sz || 0];
    const rot = retrieve2(own('symbolRotate'), S.symbolRotate);
    const rotation = (rot || 0) * Math.PI / 180 || 0;
    let off = retrieve2(own('symbolOffset'), S.symbolOffset);
    if (off != null) {
      if (!isArray(off)) off = [off, off];
      off = [parsePercent(off[0], sz[0]) || 0, parsePercent(retrieve2(off[1], off[0]), sz[1]) || 0];
    }
    const empty = type.indexOf('empty') === 0;
    const pathType = empty ? type.substr(5, 1).toLowerCase() + type.substr(6) : type;
    const k = mut.sizeFull ? 1 : 2;
    const path = { x: off ? off[0] : 0, y: off ? off[1] : 0, scaleX: sz[0] / k, scaleY: sz[1] / k, rotation };
    // the style visual: series itemStyle extended by the node model's itemStyle (the chain holds both)
    const color = mget(n.levels, ['itemStyle', 'color']);
    const borderColor = mget(n.levels, ['itemStyle', 'borderColor']);
    const borderWidth = mget(n.levels, ['itemStyle', 'borderWidth']);
    const opacity = mget(n.levels, ['itemStyle', 'opacity']);
    const collapsedFill = mut.collapsedLeafFilled ? n.isExpand === false : n.isExpand === false && n.children.length !== 0;
    const inner = collapsedFill ? color : '#fff';
    let ink;
    if (empty) ink = { fill: inner || '#fff', stroke: color, lineWidth: mut.noTwoPx ? borderWidth : 2, opacity: opacity != null ? opacity : 1 };
    else ink = { fill: color, stroke: borderColor != null ? borderColor : null, lineWidth: borderWidth != null ? borderWidth : 1, opacity: opacity != null ? opacity : 1 };
    const groupM = compose(mainM, { x: n.L.x, y: n.L.y });
    const pathM = compose(groupM, path);
    symbols.push({ row: n.idx, global: groupM ? [groupM[4], groupM[5]] : [n.L.x, n.L.y], type, pathType, emptyBrush: empty, size: sz, path, transform: pathM, ink, z, z2: mut.z2Zero ? 0 : 100, zlevel });
    n.sym = { pathType, ink, pathM };
  });
  // ---- labels ----
  const realRoot = root;
  drawnNodes.forEach(n => {
    const show = mget(n.levels, ['label', 'show']);
    if (!show) return;
    const lv = n.levels.map(o => (o && typeof o === 'object' ? o.label : undefined));
    const fmt = mget(lv, 'formatter');
    let text = n.name;
    if (typeof fmt === 'string') text = formatTpl(fmt, { seriesName, name: n.name, value: n.item.value });
    let position = mget(lv, 'position');
    const rotate = mget(lv, 'rotate');
    let rotationCfg = rotate != null ? rotate * (Math.PI / 180) : undefined;
    const distance = retrieve2(mget(lv, 'distance'), 5);
    const offset = mget(lv, 'offset');
    let origin = null;
    let vAlignForced = null;
    if (radial) {
      const Tl = n.L;
      const R = realRoot.L;
      let rad;
      let isLeft;
      if (Tl.x === R.x && n.isExpand === true && realRoot.children.length) {
        const f = realRoot.children[0].L;
        const l = realRoot.children[realRoot.children.length - 1].L;
        const cx = (f.x + l.x) / 2;
        const cy = (f.y + l.y) / 2;
        rad = Math.atan2(cy - R.y, cx - R.x);
        if (rad < 0) rad = Math.PI * 2 + rad;
        isLeft = cx < R.x;
        if (isLeft) rad = rad - Math.PI;
      } else {
        rad = Math.atan2(Tl.y - R.y, Tl.x - R.x);
        if (rad < 0) rad = Math.PI * 2 + rad;
        if (n.children.length === 0 || (n.children.length !== 0 && n.isExpand === false) || mut.radialInnerAsLeaf) {
          isLeft = Tl.x < R.x;
          if (isLeft) rad = rad - Math.PI;
        } else {
          isLeft = Tl.x > R.x;
          if (!isLeft) rad = rad - Math.PI;
        }
      }
      position = position || (isLeft ? 'left' : 'right');
      rotationCfg = rotate == null || mut.radialRotateIgnored ? -rad : rotate * (Math.PI / 180);
      origin = mut.radialNoOrigin ? null : 'center';
      vAlignForced = 'middle';
    } else if (position == null) position = mut.labelDefaultRight ? 'right' : 'inside';
    // the layout rect: the path's bbox grown by the stroke (strokeNoScale: / lineScale), then its global transform
    const sy = n.sym;
    const bb = inp.bbox[sy.pathType];
    must(bb, 'no unit bbox for ' + sy.pathType);
    let r = { x: bb.x, y: bb.y, width: bb.width, height: bb.height };
    const hasStroke = !(sy.ink.stroke == null || sy.ink.stroke === 'none' || !(sy.ink.lineWidth > 0));
    if (hasStroke) {
      const M = sy.pathM;
      const lineScale = mut.lineScaleOne ? 1 : (M && Math.abs(M[0] - 1) > 1e-10 && Math.abs(M[3] - 1) > 1e-10 ? Math.sqrt(Math.abs(M[0] * M[3] - M[2] * M[1])) : 1);
      let w = sy.ink.lineWidth;
      if (!(sy.ink.fill != null && sy.ink.fill !== 'none')) w = Math.max(w, 4);
      if (lineScale > 1e-10) {
        r.width += w / lineScale; r.height += w / lineScale; r.x -= w / lineScale / 2; r.y -= w / lineScale / 2;
      }
    }
    r = applyRect(r, sy.pathM);
    const c = calculateTextPosition(position, distance, r);
    const inner = { x: c.x, y: c.y, rotation: 0, originX: 0, originY: 0 };
    let innerOrigin = false;
    if (origin && rotationCfg != null) {
      innerOrigin = true;
      inner.originX = -inner.x + r.width * 0.5 + r.x;
      inner.originY = -inner.y + r.height * 0.5 + r.y;
    }
    if (rotationCfg != null) inner.rotation = rotationCfg;
    if (offset) {
      inner.x += offset[0];
      inner.y += offset[1];
      if (!innerOrigin) { inner.originX = -offset[0]; inner.originY = -offset[1]; }
    }
    const tm = compose(null, inner);
    labels.push({ row: n.idx, text, position, distance, rotation: rotationCfg, layoutRect: r, inner, transform: tm,
      align: mget(lv, 'align') || c.align || 'left', verticalAlign: vAlignForced || mget(lv, 'verticalAlign') || c.verticalAlign || 'top', z, z2: 102 });
  });
  // ---- edges (TreeView drawEdge / getEdgeShape / TreePath.buildPath) ----
  const edges = [];
  const edgeShape = S.edgeShape;
  const curvature = mut.curvenessFromItem ? null : S.lineStyle.curveness;
  const inkOf = n => {
    const ls = p => mget(n.levels, ['lineStyle', p]);
    const op = ls('opacity');
    const ty = ls('type');
    return { stroke: ls('color'), lineWidth: ls('width'), opacity: op != null ? op : 1, lineDash: ty != null ? ty : null };
  };
  drawnNodes.forEach(n => {
    if (edgeShape === 'curve') {
      if (n.parent && n.parent !== vroot) {
        const s = n.parent.L;
        const t = n.L;
        const cv = mut.curvenessFromItem ? mget(n.levels, ['lineStyle', 'curveness']) : curvature;
        let sh;
        if (radial) {
          const z0 = mut.radialNoOrZero ? (v => v) : (v => v || 0);
          const p1 = radialCoordinate(s.rawX, s.rawY);
          const p2 = radialCoordinate(s.rawX, s.rawY + (t.rawY - s.rawY) * cv);
          const p3 = radialCoordinate(t.rawX, t.rawY + (s.rawY - t.rawY) * cv);
          const p4 = radialCoordinate(t.rawX, t.rawY);
          sh = { x1: z0(p1.x), y1: z0(p1.y), cpx1: z0(p2.x), cpy1: z0(p2.y), cpx2: z0(p3.x), cpy2: z0(p3.y), x2: z0(p4.x), y2: z0(p4.y) };
        } else if (orient === 'LR' || orient === 'RL') {
          sh = { x1: s.x, y1: s.y, cpx1: s.x + (t.x - s.x) * cv, cpy1: s.y, cpx2: t.x + (s.x - t.x) * cv, cpy2: t.y, x2: t.x, y2: t.y };
        } else {
          sh = { x1: s.x, y1: s.y, cpx1: s.x, cpy1: s.y + (t.y - s.y) * cv, cpx2: t.x, cpy2: t.y + (s.y - t.y) * cv, x2: t.x, y2: t.y };
        }
        sh.percent = 1;
        const styleNode = mut.edgeFromParent ? n.parent : n;
        edges.push({ owner: n.idx, kind: 'curve', from: n.parent.idx, to: [n.idx], lineStyleOf: styleNode.idx, shape: sh,
          commands: [{ cmd: 'M', args: [sh.x1, sh.y1] }, { cmd: 'C', args: [sh.cpx1, sh.cpy1, sh.cpx2, sh.cpy2, sh.x2, sh.y2] }], ink: inkOf(styleNode), z, z2: 0 });
      }
    } else if (edgeShape === 'polyline' && !radial) {
      if (n.children.length !== 0 && n.isExpand === true) {
        const pp = [n.L.x, n.L.y];
        const cps = n.children.map(c => [c.L.x, c.L.y]);
        const cmds = [];
        const len = cps.length;
        const first = cps[0];
        const last = cps[len - 1];
        if (len === 1) cmds.push({ cmd: 'M', args: [pp[0], pp[1]] }, { cmd: 'L', args: [first[0], first[1]] });
        else {
          const forkDim = (orient === 'TB' || orient === 'BT') ? 0 : 1;
          const otherDim = 1 - forkDim;
          const f = parsePercent(S.edgeForkPosition, 1);
          const tmp = [];
          tmp[forkDim] = pp[forkDim];
          tmp[otherDim] = mut.forkFromChildSide ? last[otherDim] + (pp[otherDim] - last[otherDim]) * f : pp[otherDim] + (last[otherDim] - pp[otherDim]) * f;
          cmds.push({ cmd: 'M', args: [pp[0], pp[1]] }, { cmd: 'L', args: [tmp[0], tmp[1]] }, { cmd: 'M', args: [first[0], first[1]] });
          tmp[forkDim] = first[forkDim];
          cmds.push({ cmd: 'L', args: [tmp[0], tmp[1]] });
          tmp[forkDim] = last[forkDim];
          cmds.push({ cmd: 'L', args: [tmp[0], tmp[1]] }, { cmd: 'L', args: [last[0], last[1]] });
          for (let i = 1; i < len - 1; i++) {
            const p = cps[i];
            cmds.push({ cmd: 'M', args: [p[0], p[1]] });
            tmp[forkDim] = p[forkDim];
            cmds.push({ cmd: 'L', args: [tmp[0], tmp[1]] });
          }
        }
        const styleNode = mut.polylineFromFirstChild ? n.children[0] : n;
        edges.push({ owner: n.idx, kind: 'polyline', from: n.idx, to: n.children.map(c => c.idx), lineStyleOf: styleNode.idx,
          shape: { parentPoint: pp, childPoints: cps, orient, forkPosition: S.edgeForkPosition }, commands: cmds, ink: inkOf(styleNode), z, z2: 0 });
      }
    }
  });
  return { layoutInfo, mainGroup, orient, dimensions: nodes.length ? dimMax : 0, rows, symbols, labels, edges };
}

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
  return Array.prototype.slice.call(el.path.data, 0, el.path.len());
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

function readLabel(host, displayIndex, classes) {
  const t = host.getTextContent();
  if (!t || t.ignore || t.invisible) return null;
  const s = t.style;
  must(!s.rich, 'a rich label');
  const kids = t.childrenRef();
  const spans = kids.filter(k => k.type === 'tspan');
  const boxes = kids.filter(k => k.type === 'rect');
  must(kids.length === spans.length + boxes.length && boxes.length <= 1, 'a label with unexpected children');
  spans.forEach(k => classes.set(k, 'label'));
  boxes.forEach(k => classes.set(k, 'labelBg'));
  classes.set(t, 'label');
  const txt = s.text == null ? null : String(s.text);
  let ink = null;
  if (spans.length) {
    const inks = spans.map(sp => ({ fill: sp.style.fill == null ? null : sp.style.fill, stroke: sp.style.stroke || null, lineWidth: sp.style.stroke ? sp.style.lineWidth : null, opacity: sp.style.opacity }));
    must(inks.every(k => JSON.stringify(k) === JSON.stringify(inks[0])), 'TSpans with different inks');
    ink = inks[0];
  }
  const tc = host.textConfig || {};
  must(tc.position != null, 'a tree label without a textConfig position');
  const BR = echarts.graphic.BoundingRect;
  const lr = tc.layoutRect ? BR.create(tc.layoutRect) : BR.create(host.getBoundingRect());
  if (!tc.local && host.transform) lr.applyTransform(host.transform);
  const layoutRect = rect4(lr);
  const it = t.innerTransformable;
  // the placement is calculateTextPosition on that rect (+ offset)
  const c = calculateTextPosition(tc.position, tc.distance, layoutRect);
  const off = tc.offset || [0, 0];
  must(Object.is(it.x, c.x + off[0]) && Object.is(it.y, c.y + off[1]), 'the label placement is not calculateTextPosition on the host rect');
  const ds = t._defaultStyle || {};
  const has = k => k in s;
  const p = spans.length ? displayIndex.get(spans[0]) : undefined;
  let background = null;
  if (boxes.length) {
    const b = boxes[0];
    const bp = displayIndex.get(b);
    background = { shape: rect4(b.shape), style: ownStyle(b.style), paint: bp === undefined ? null : bp };
  }
  return { text: txt, lines: spans.length,
    textConfig: { position: json(tc.position), distance: json(tc.distance), offset: json(tc.offset), rotation: json(tc.rotation), origin: json(tc.origin), inside: json(tc.inside), local: !!tc.local },
    layoutRect,
    inner: { x: it.x, y: it.y, rotation: it.rotation, originX: it.originX, originY: it.originY },
    transform: m6(t.transform),
    align: s.align || ds.align || 'left', verticalAlign: s.verticalAlign || ds.verticalAlign || 'top',
    font: s.font, padding: json(s.padding),
    style: { fill: has('fill') ? json(s.fill) : null, stroke: has('stroke') ? json(s.stroke) : null, lineWidth: has('lineWidth') ? json(s.lineWidth) : null,
      opacity: json(s.opacity), backgroundColor: json(s.backgroundColor) },
    inkDefault: { fill: json(ds.fill), stroke: json(ds.stroke), align: json(ds.align), verticalAlign: json(ds.verticalAlign) }, ink, background,
    tspans: spans.map(sp => ({ text: sp.style.text, x: sp.style.x, y: sp.style.y, textAlign: sp.style.textAlign, textBaseline: sp.style.textBaseline })),
    z: t.z, z2: t.z2, zlevel: t.zlevel, silent: !!t.silent, paint: p === undefined ? null : p };
}

function readSymbol(el, data, idx, displayIndex, classes, symbolPaths) {
  must(el.childCount() === 1, 'a symbol group with several children');
  const pe = el.childAt(0);
  classes.set(pe, 'symbol');
  const type = pe.shape.symbolType;
  must(pe.shape.x === -1 && pe.shape.y === -1 && pe.shape.width === 2 && pe.shape.height === 2, 'a symbol not built in the -1..1 box');
  const cmds = decode(pathOf(pe));
  const bbox = rect4(pe.path.getBoundingRect());
  const rec = JSON.stringify({ bbox, commands: cmds });
  if (symbolPaths[type] === undefined) symbolPaths[type] = rec;
  else must(symbolPaths[type] === rec, 'two ' + type + ' symbols with different paths');
  const size = data.getItemVisual(idx, 'symbolSize');
  const sz = isArray(size) ? [size[0] || 0, size[1] || 0] : [+size || 0, +size || 0];
  const p = displayIndex.get(pe);
  const gt = el.transform;
  return { group: { x: el.x, y: el.y, scaleX: el.scaleX, scaleY: el.scaleY, rotation: el.rotation }, global: gt ? [gt[4], gt[5]] : [el.x, el.y],
    type: el.getSymbolType(), pathType: type, emptyBrush: !!pe.__isEmptyBrush, size: sz,
    path: { x: pe.x, y: pe.y, scaleX: pe.scaleX, scaleY: pe.scaleY, rotation: pe.rotation }, transform: m6(pe.transform), style: ownStyle(pe.style),
    ink: { fill: json(pe.style.fill), stroke: json(pe.style.stroke), lineWidth: json(pe.style.lineWidth), opacity: json(pe.style.opacity) },
    z: pe.z, z2: pe.z2, zlevel: pe.zlevel, silent: !!pe.isSilent(), paint: p === undefined ? null : p,
    label: readLabel(pe, displayIndex, classes) };
}

function readTree(chart, sm, displayIndex, classes, symbolPaths) {
  const data = sm.getData();
  const tree = data.tree;
  const view = chart.getViewOfSeriesModel(sm);
  const g = view.group;
  const mg = view._mainGroup;
  must(!g.transform || g.transform.join() === '1,0,0,1,0,0', 'a transformed tree view group (roam zoom / center)');
  must(mg.parent === g && mg.scaleX === 1 && mg.scaleY === 1 && mg.rotation === 0, 'the main group is not a plain translate');
  const li = sm.layoutInfo;
  const rows = [];
  const edges = [];
  for (let i = 0; i < data.count(); i++) {
    const node = tree.getNodeByDataIndex(i);
    must(node && node.dataIndex === i, 'row ' + i + ': no node');
    const raw = data.getRawDataItem(i);
    const L = data.getItemLayout(i);
    const laidOut = !!(L && !isNaN(L.x) && !isNaN(L.y));
    const im = data.getItemModel(i);
    const leaves = im.parentModel !== sm;
    if (leaves) must(im.parentModel && im.parentModel.parentModel === sm, 'row ' + i + ': an item model parent that is neither the series nor the leaves model');
    const el = data.getItemGraphicEl(i);
    const row = { index: i, name: node.name, valueWritten: raw && hasOwn(raw, 'value') ? json(raw.value) : undefined,
      values: data.dimensions.map(d => data.get(d, i)), value: node.getValue(), depth: node.depth, height: node.height, isExpand: node.isExpand,
      parent: node.parentNode ? node.parentNode.dataIndex : null, children: node.children.map(c => c.dataIndex), leaves,
      chain: leaves ? ['item', 'leaves', 'series'] : ['item', 'series'], laidOut,
      layout: L ? (L.rawX !== undefined ? { x: L.x, y: L.y, rawX: L.rawX, rawY: L.rawY } : { x: L.x, y: L.y }) : null, drawn: !!el, symbol: null, label: null };
    if (el) {
      must(el.parent === mg, 'row ' + i + ': a symbol outside the main group');
      const sy = readSymbol(el, data, i, displayIndex, classes, symbolPaths);
      row.label = sy.label;
      delete sy.label;
      row.symbol = sy;
      const e = el.__edge;
      if (e && e.parent === mg) {
        classes.set(e, 'edge');
        const ep = displayIndex.get(e);
        const isCurve = e.type === 'bezier-curve';
        const sh = e.shape;
        const rec = { owner: i, kind: isCurve ? 'curve' : 'polyline', elType: e.type,
          from: isCurve ? node.parentNode.dataIndex : i, to: isCurve ? [i] : node.children.map(c => c.dataIndex), lineStyleOf: i,
          shape: isCurve ? { x1: sh.x1, y1: sh.y1, cpx1: sh.cpx1, cpy1: sh.cpy1, cpx2: sh.cpx2, cpy2: sh.cpy2, x2: sh.x2, y2: sh.y2, percent: sh.percent }
            : { parentPoint: sh.parentPoint.slice(), childPoints: sh.childPoints.map(q => q.slice()), orient: sh.orient, forkPosition: json(sh.forkPosition) },
          commands: decode(pathOf(e)), style: ownStyle(e.style),
          ink: { stroke: json(e.style.stroke), lineWidth: json(e.style.lineWidth), opacity: json(e.style.opacity), lineDash: json(e.style.lineDash) },
          z: e.z, z2: e.z2, zlevel: e.zlevel, silent: !!e.isSilent(), paint: ep === undefined ? null : ep };
        edges.push(rec);
      }
    }
    rows.push(row);
  }
  // nothing else in the main group
  mg.childrenRef().forEach(k => must(classes.has(k.childAt ? k.childAt(0) : k) || classes.has(k), 'an unread element in the tree main group'));
  return { name: sm.name, layout: sm.get('layout'), orientOption: sm.get('orient'), orient: sm.getOrient(), edgeShape: sm.get('edgeShape'), edgeForkPosition: json(sm.get('edgeForkPosition')),
    curveness: json(sm.get(['lineStyle', 'curveness'])), expandAndCollapse: json(sm.get('expandAndCollapse')), initialTreeDepth: json(sm.get('initialTreeDepth')),
    layoutInfo: rect4(li), viewGroup: { x: g.x, y: g.y, scaleX: g.scaleX, scaleY: g.scaleY }, mainGroup: { x: mg.x, y: mg.y },
    dimensions: data.dimensions.slice(), rows, edges };
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

const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));

function recordWith(E, def, optionText, side, symbolPaths) {
  const input = JSON.parse(optionText);
  return runChart(E, JSON.parse(optionText), chart => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const list = zr.storage.getDisplayList(true);
    const displayIndex = new Map();
    list.forEach((el, i) => displayIndex.set(el, i));
    const classes = new Map();
    const ground = { background: zr.getBackgroundColor(), isDark: !!zr.isDarkMode() };
    const textStyle = json(ec.option.textStyle);
    const series = seriesArray(input).map((opt, si) => {
      const sm = ec.getSeriesByIndex(si);
      must(sm && sm.subType === opt.type && opt.type === 'tree', 'series ' + si + ' is not a tree');
      must(!ec.isSeriesFiltered(sm), 'a filtered tree series');
      const S = mergedOption(opt);
      for (const k of READ_KEYS) {
        must(JSON.stringify(json(sm.option[k])) === JSON.stringify(json(S[k])), 'series ' + si + ': the option ' + k + ' is not the fed option over the defaults: ' + JSON.stringify(sm.option[k]) + ' vs ' + JSON.stringify(S[k]));
      }
      const rec = Object.assign({ seriesIndex: si, type: 'tree' }, readTree(chart, sm, displayIndex, classes, symbolPaths));
      // upstream's default name 'series\u0000<i>' is not written (fpjson drops \u0000): null instead
      if (opt.name == null) {
        must(rec.name === 'series\u0000' + si, 'series ' + si + ': default name ' + JSON.stringify(rec.name));
        rec.name = null;
      }
      side[def.id + '/' + si] = { S, seriesIndex: si };
      return rec;
    });
    must(series.length > 0, 'no tree series');
    const runs = paintRuns(chart, list, classes);
    return { ground, textStyle, paintRuns: runs, series };
  });
}

function recordCase(def, side, symbolPaths) {
  const opt = def.gallery ? gallery(def.gallery) : zrClone(def.option);
  const animationForced = opt.animation !== false;
  opt.animation = false;
  const optionText = JSON.stringify(opt);
  let productionBuild = false;
  let devError = null;
  let base;
  let local = {};
  try {
    base = recordWith(echarts, def, optionText, local, symbolPaths);
  } catch (e) {
    if (e instanceof OracleError) throw e;
    devError = String(e.message);
    local = {};
    base = recordWith(PROD, def, optionText, local, symbolPaths);
    productionBuild = true;
  }
  must(!!def.prod === productionBuild, productionBuild ? 'the development build threw (' + devError + ') although the case is not marked prod' : 'expected the development build to throw');
  if (!productionBuild) {
    const p = recordWith(PROD, def, optionText, {}, {});
    must(JSON.stringify(sanitize(p)) === JSON.stringify(sanitize(base)), 'the production build records differently');
  }
  Object.assign(side, local);
  return Object.assign({ id: def.id, note: def.note, gallery: def.gallery || null, option: def.gallery ? null : JSON.parse(optionText),
    animationForced, productionBuild, devError }, base);
}

// ============================================================================
// The cases
// ============================================================================
const T7 = () => ({ name: 'A', value: 1, children: [
  { name: 'B', value: 2, children: [{ name: 'D', value: 4 }, { name: 'E', value: 5 }] },
  { name: 'C', value: 3, children: [{ name: 'F', value: 6 }, { name: 'G', value: 7 }] }] });
const TA = () => ({ name: 'R', children: [
  { name: 'X', children: [{ name: 'x1' }, { name: 'x2' }, { name: 'x3' }] },
  { name: 'Y' },
  { name: 'Z', children: [{ name: 'z1', children: [{ name: 'z11' }, { name: 'z12' }] }, { name: 'z2' }] }] });
// a deeper lopsided tree (depth 5 below the root) for the expansion cases
const TD = () => ({ name: 'r', children: [
  { name: 'a', children: [{ name: 'a1', children: [{ name: 'a11', children: [{ name: 'a111' }, { name: 'a112' }] }, { name: 'a12' }] }, { name: 'a2' }] },
  { name: 'b' },
  { name: 'c', children: [{ name: 'c1' }, { name: 'c2', children: [{ name: 'c21' }] }] }] });
const chain = (n, k) => (k >= n ? { name: 'n' + k } : { name: 'n' + k, children: [chain(n, k + 1)] });
const fan = n => ({ name: 'hub', children: Array.from({ length: n }, (_, i) => ({ name: 'f' + (i + 1), value: i + 1 })) });
const leavesN = n => ({ name: 'o', children: Array.from({ length: n }, (_, i) => ({ name: 'q' + i })) });
// radial: 8 inner children with 0..2 leaves each -> labels in every quadrant, leaves and inner nodes on both sides
const R8 = () => ({ name: 'core', children: Array.from({ length: 8 }, (_, i) => ({ name: 'k' + i, children: Array.from({ length: i % 3 }, (__, j) => ({ name: 'k' + i + '_' + j })) })) });
const one = (series, extra) => Object.assign({ animation: false, series: [].concat(series).map(s => Object.assign({ type: 'tree' }, s)) }, extra || {});

const CASES = [
  // ---- orientation ----
  { id: 'O-LR', note: 'T7 (A{B{D,E},C{F,G}}) all defaults: LR, box 12% (96, 72, 608, 456), emptyCircle 7, inside labels (the name, centred on the node), curve edges curveness 0.5; D..G are depth 3 > initialTreeDepth 2 -> isExpand false but leaves (hollow)', option: one({ data: [T7()] }) },
  { id: 'O-RL', note: 'T7 orient RL: x = width - (depth - 1) * kx', option: one({ data: [T7()], orient: 'RL' }) },
  { id: 'O-TB', note: 'T7 orient TB', option: one({ data: [T7()], orient: 'TB' }) },
  { id: 'O-BT', note: 'T7 orient BT', option: one({ data: [T7()], orient: 'BT' }) },
  { id: 'O-horizontal', note: "T7 orient 'horizontal' = LR through getOrient() (the option keeps 'horizontal')", option: one({ data: [T7()], orient: 'horizontal' }) },
  { id: 'O-vertical', note: "T7 orient 'vertical' = TB through getOrient(); the curve control points follow TB", option: one({ data: [T7()], orient: 'vertical' }) },
  { id: 'O-radial', note: 'T7 layout radial: main group at the box centre (400, 300), r = min(456, 608) / 2 = 228, separation / depth, automatic label sides and rotation (origin center), raw-space Bezier edges', option: one({ data: [T7()], layout: 'radial' }) },
  // ---- shapes ----
  { id: 'H-TA', note: 'TA (R{X{x1,x2,x3},Y,Z{z1{z11,z12},z2}}) initialTreeDepth -1: apportion pushes Z right of X\'s subtree (moveSubtree / executeShifts)', option: one({ data: [TA()], initialTreeDepth: -1 }) },
  { id: 'H-TA-TB', note: 'TA TB, all expanded', option: one({ data: [TA()], initialTreeDepth: -1, orient: 'TB' }) },
  { id: 'H-TA-radial', note: 'TA radial, all expanded: the root x is -0 (0 * a negative cosine); leaves at depth 4 and 3 mixed (delta from the LEFT node\'s depth)', option: one({ data: [TA()], initialTreeDepth: -1, layout: 'radial' }) },
  { id: 'H-radial-lopsided', note: 'radial r{A{a1, a2}, B}: the leftmost node a1 (depth 3) and the rightmost B (depth 2) differ in depth, so delta = sep(left, right) / 2 = (2 / 3) / 2 uses the LEFT node depth (sep(right, left) would give 1 / 2)', option: one({ data: [{ name: 'r', children: [{ name: 'A', children: [{ name: 'a1' }, { name: 'a2' }] }, { name: 'B' }] }], layout: 'radial' }) },
  { id: 'H-TD', note: 'TD (depth 5 below the root, lopsided) all expanded, LR: threads and shifts across several levels', option: one({ data: [TD()], initialTreeDepth: -1 }) },
  { id: 'H-solo', note: "a single node: left === right -> delta 1, tx 1, (bottom.depth - 1) || 1 -> the node at (0, height / 2); label 'right'", option: one({ data: [{ name: 'solo', value: 9 }], label: { position: 'right' } }) },
  { id: 'H-solo-TB', note: 'a single node TB: (width / 2, 0)', option: one({ data: [{ name: 'solo' }], orient: 'TB' }) },
  { id: 'H-solo-radial', note: 'a single node radial: r 0 -> (0 * cos, 0 * sin); the label rule for a node that is the root but has no children', option: one({ data: [{ name: 'solo' }], layout: 'radial' }) },
  { id: 'H-one', note: 'root with one child: every x is 0 -> left === right -> delta 1; the child straight across', option: one({ data: [{ name: 'p', children: [{ name: 'c' }] }] }) },
  { id: 'H-one-radial', note: 'root with one child, radial: the child at rawX = PI (6 o\'clock), the root label from the (single) child centroid', option: one({ data: [{ name: 'p', children: [{ name: 'c' }] }], layout: 'radial' }) },
  { id: 'H-chain', note: 'a chain of 7 (n0 > n1 > ... > n6) all expanded: all on one line, kx = width / 6', option: one({ data: [chain(6, 0)], initialTreeDepth: -1 }) },
  { id: 'H-chain-radial', note: 'the chain radial: every node at rawX PI, radius (depth - 1) * ky', option: one({ data: [chain(6, 0)], initialTreeDepth: -1, layout: 'radial' }) },
  { id: 'H-fan20', note: 'root with 20 leaf children (values 1..20), labels right', option: one({ data: [fan(20)], label: { position: 'right' } }) },
  { id: 'H-fan20-TB', note: '20 children TB', option: one({ data: [fan(20)], orient: 'TB' }) },
  { id: 'H-fan20-radial', note: '20 children radial: rawX = (2i + 1) PI / 20, labels outward on both halves', option: one({ data: [fan(20)], layout: 'radial' }) },
  // ---- expansion ----
  { id: 'X-itd0', note: 'TD initialTreeDepth 0: only the root, collapsed with children -> FILLED (the colour); leaves wrap -> leaves.label applies to it', option: one({ data: [TD()], initialTreeDepth: 0, leaves: { label: { position: 'right' } } }) },
  { id: 'X-itd1', note: 'TD initialTreeDepth 1: the root open, its children collapsed (a, c filled; b hollow leaf)', option: one({ data: [TD()], initialTreeDepth: 1 }) },
  { id: 'X-itd2', note: 'TD initialTreeDepth 2 (the default, explicit)', option: one({ data: [TD()], initialTreeDepth: 2 }) },
  { id: 'X-itd3', note: 'TD initialTreeDepth 3', option: one({ data: [TD()], initialTreeDepth: 3 }) },
  { id: 'X-itdm1', note: 'TD initialTreeDepth -1: everything open', option: one({ data: [TD()], initialTreeDepth: -1 }) },
  { id: 'X-collapsed', note: "per-item collapsed at initialTreeDepth 1: B collapsed true with children (filled, no descendants laid out), C collapsed true on a LEAF (isExpand false, still hollow, leaves wrap anyway), D collapsed false below the depth (open; its child d1 at depth 3 > 1 collapsed with a child -> filled), d1's child d11 collapsed false but hidden, E children: [] (a leaf), leaves.label right / series label left",
    option: one({ data: [{ name: 'A', children: [
      { name: 'B', collapsed: true, children: [{ name: 'b1' }] },
      { name: 'C', collapsed: true },
      { name: 'D', collapsed: false, children: [{ name: 'd1', children: [{ name: 'd11', collapsed: false, children: [{ name: 'd111' }] }] }, { name: 'd2', collapsed: false }] },
      { name: 'E', children: [] }] }], initialTreeDepth: 1, label: { position: 'left' }, leaves: { label: { position: 'right' } } }) },
  { id: 'X-eac-false', note: 'expandAndCollapse false: initialTreeDepth 1 ignored (everything open) BUT the explicit collapsed: true on c is honoured', option: one({ data: [(() => { const t = TD(); t.children[2].collapsed = true; return t; })()], expandAndCollapse: false, initialTreeDepth: 1 }) },
  { id: 'X-multi-root', note: 'two roots in data: rows 8.. (Other, o1, o2) exist in SeriesData (pre-order after T7) but get no layout and are not drawn; only data[0] is laid out; the virtual root is named by the series name', option: one({ name: 'forest', data: [T7(), { name: 'Other', value: 10, children: [{ name: 'o1' }, { name: 'o2' }] }] }) },
  // ---- layout box ----
  { id: 'B-px', note: 'box left 50, top 40, right 100, bottom 60 (px): 650 x 500 at (50, 40)', option: one({ data: [TA()], initialTreeDepth: -1, left: 50, top: 40, right: 100, bottom: 60 }) },
  { id: 'B-pct', note: "box left '5%', top '10%', right '20%', bottom '15%'", option: one({ data: [TA()], initialTreeDepth: -1, left: '5%', top: '10%', right: '20%', bottom: '15%' }) },
  { id: 'B-wh', note: "box left 100, top 50, width 300, height '50%' (right / bottom stay 12% but are unused)", option: one({ data: [TA()], initialTreeDepth: -1, left: 100, top: 50, width: 300, height: '50%' }) },
  { id: 'B-center', note: "box left 'center', top 'middle', width 400, height 300 -> (200, 150)", option: one({ data: [T7()], left: 'center', top: 'middle', width: 400, height: 300 }) },
  { id: 'B-radial', note: 'radial in a non-square box (left 20, top 30, width 500, height 333): r = min / 2 = 166.5, centre (270, 196.5)', option: one({ data: [TA()], initialTreeDepth: -1, layout: 'radial', left: 20, top: 30, width: 500, height: 333 }) },
  // ---- symbols ----
  { id: 'Y-series', note: "series symbol 'rect', symbolSize [12, 8]: fill = the colour lightsteelblue, NO stroke (no borderColor), lineWidth 1.5 (borderWidth); labels right: the layout rect has no stroke growth", option: one({ data: [T7()], symbol: 'rect', symbolSize: [12, 8], label: { position: 'right' } }) },
  { id: 'Y-item', note: "item symbols: B 'triangle' size 14, C symbolSize [6, 10] + symbolRotate 45 (the label rect through a rotated transform: the 4-corner path), D 'emptyDiamond' + symbolOffset [3, '50%'], E symbolSize 0, F symbol 'roundRect' symbolRotate -30, G 'pin'; leaves.symbol 'rect' + leaves.symbolSize 20 are IGNORED (symbol keys read the item's own value only); labels bottom",
    option: one({ data: [{ name: 'A', children: [
      { name: 'B', symbol: 'triangle', symbolSize: 14, children: [{ name: 'D', symbol: 'emptyDiamond', symbolOffset: [3, '50%'] }, { name: 'E', symbolSize: 0 }] },
      { name: 'C', symbolSize: [6, 10], symbolRotate: 45, children: [{ name: 'F', symbol: 'roundRect', symbolRotate: -30 }, { name: 'G', symbol: 'pin' }] }] }],
    leaves: { symbol: 'rect', symbolSize: 20 }, label: { position: 'bottom' } }) },
  { id: 'Y-style-empty', note: "emptyCircle with itemStyle at three levels: series {color '#c23531', borderColor '#000', borderWidth 3, opacity 0.8}, leaves {color 'red', borderColor '#00f', opacity 0.5}, item C {color '#0a0', borderWidth 5}; the empty brush forces stroke = the colour and lineWidth 2 (borderColor / borderWidth have NO effect); collapsed inner nodes take the LEAVES style (initialTreeDepth 1: B / C collapsed, filled with their colour)",
    option: one({ data: [(() => { const t = T7(); t.children[1].itemStyle = { color: '#0a0', borderWidth: 5 }; return t; })()], initialTreeDepth: 1,
      itemStyle: { color: '#c23531', borderColor: '#000', borderWidth: 3, opacity: 0.8 }, leaves: { itemStyle: { color: 'red', borderColor: '#00f', opacity: 0.5 } }, label: { position: 'left' } }) },
  { id: 'Y-style-circle', note: "the same styles with symbol 'circle' (not empty): fill = color, stroke = borderColor, lineWidth = borderWidth, opacity; all open (leaves = true leaves)",
    option: one({ data: [(() => { const t = T7(); t.children[1].itemStyle = { color: '#0a0', borderWidth: 5 }; return t; })()], initialTreeDepth: -1, symbol: 'circle', symbolSize: 10,
      itemStyle: { color: '#c23531', borderColor: '#000', borderWidth: 3, opacity: 0.8 }, leaves: { itemStyle: { color: 'red', borderColor: '#00f', opacity: 0.5 } }, label: { position: 'left' } }) },
  // ---- edges ----
  { id: 'E-curve0', note: 'curveness 0: the control points collapse onto the ends (a straight Bezier)', option: one({ data: [TA()], initialTreeDepth: -1, lineStyle: { curveness: 0 } }) },
  { id: 'E-curve1', note: 'curveness 1, TB: cp1 = (s.x, t.y), cp2 = (t.x, s.y)', option: one({ data: [TA()], initialTreeDepth: -1, orient: 'TB', lineStyle: { curveness: 1 } }) },
  { id: 'E-curve-item', note: 'series curveness 0.3 RL; item lineStyle.curveness 0.9 on X and leaves.lineStyle.curveness 0 are IGNORED (drawEdge reads the SERIES curveness)',
    option: one({ data: [(() => { const t = TA(); t.children[0].lineStyle = { curveness: 0.9 }; return t; })()], initialTreeDepth: -1, orient: 'RL', lineStyle: { curveness: 0.3 }, leaves: { lineStyle: { curveness: 0 } } }) },
  { id: 'E-curve-style', note: "lineStyle at three levels: series {color '#999', width 3, opacity 0.6, type 'dashed'}, leaves {color '#0a0', width 1}, item X {color '#f00', type 'dotted'}, item z1 {width 5}; a curve takes the CHILD's (target's) lineStyle",
    option: one({ data: [(() => { const t = TA(); t.children[0].lineStyle = { color: '#f00', type: 'dotted' }; t.children[2].children[0].lineStyle = { width: 5 }; return t; })()], initialTreeDepth: -1,
      lineStyle: { color: '#999', width: 3, opacity: 0.6, type: 'dashed' }, leaves: { lineStyle: { color: '#0a0', width: 1 } } }) },
  { id: 'E-poly50', note: "edgeShape polyline LR, fork '50%': one TreePath per expanded node with children, owned by the PARENT (stem, bar, twigs)", option: one({ data: [TA()], initialTreeDepth: -1, edgeShape: 'polyline' }) },
  { id: 'E-poly20-TB', note: "polyline TB edgeForkPosition '20%' (the fork measured toward the LAST child)", option: one({ data: [TA()], initialTreeDepth: -1, edgeShape: 'polyline', orient: 'TB', edgeForkPosition: '20%' }) },
  { id: 'E-poly-num-BT', note: 'polyline BT edgeForkPosition 0.8 (a number: +0.8)', option: one({ data: [TA()], initialTreeDepth: -1, edgeShape: 'polyline', orient: 'BT', edgeForkPosition: 0.8 }) },
  { id: 'E-poly-RL', note: "polyline RL, edgeForkPosition 'center' (0.5 via parsePositionOption), 20 children (18 middle twigs)", option: one({ data: [fan(20)], edgeShape: 'polyline', orient: 'RL', edgeForkPosition: 'center' }) },
  { id: 'E-poly-collapsed', note: 'polyline with the default depth 2 on TD: collapsed nodes with children (a1, c2) draw NO polyline; a single child: one straight M L', option: one({ data: [TD()], edgeShape: 'polyline' }) },
  { id: 'E-poly-style', note: "polyline styles: series {color '#333', width 2}, item X {color '#f00', width 4} (X's own TreePath takes it: a polyline uses the PARENT's lineStyle), leaf x1 {color '#00f'} (no effect: leaves own no polyline), leaves {type 'dashed'}",
    option: one({ data: [(() => { const t = TA(); t.children[0].lineStyle = { color: '#f00', width: 4 }; t.children[0].children[0].lineStyle = { color: '#00f' }; return t; })()], initialTreeDepth: -1, edgeShape: 'polyline',
      lineStyle: { color: '#333', width: 2 }, leaves: { lineStyle: { type: 'dashed' } } }) },
  { id: 'E-poly-radial', prod: true, note: 'polyline with layout radial: the DEVELOPMENT build throws in drawEdge; recorded from the production build, which draws the symbols and labels and NO edges', option: one({ data: [T7()], layout: 'radial', edgeShape: 'polyline' }) },
  // ---- labels ----
  { id: 'L-left', note: "series label position 'left' (align right, middle)", option: one({ data: [T7()], label: { position: 'left' } }) },
  { id: 'L-top', note: "series label position 'top' (center, bottom), TB", option: one({ data: [T7()], orient: 'TB', label: { position: 'top' } }) },
  { id: 'L-bottom', note: "series label position 'bottom' (center, top), distance 2, BT", option: one({ data: [T7()], orient: 'BT', label: { position: 'bottom', distance: 2 } }) },
  { id: 'L-gallery-style', note: "the gallery idiom: label {position 'left', verticalAlign 'middle', align 'right', fontSize 9}, leaves.label {position 'right', verticalAlign 'middle', align 'left'} (fontSize 9 reaches the leaves through the chain)",
    option: one({ data: [TA()], label: { position: 'left', verticalAlign: 'middle', align: 'right', fontSize: 9 }, leaves: { label: { position: 'right', verticalAlign: 'middle', align: 'left' } } }) },
  { id: 'L-rotate', note: "label rotate 30 (about the anchor: no origin), distance 10, offset [4, -6] (origin = -offset), fontSize 16, color '#00f' (no auto stroke), position 'right'; leaves.label rotate -90 + align 'right'",
    option: one({ data: [T7()], label: { position: 'right', rotate: 30, distance: 10, offset: [4, -6], fontSize: 16, color: '#00f' }, leaves: { label: { rotate: -90, align: 'right' } } }) },
  { id: 'L-show', note: 'series label show false, leaves.label show true: only the leaves (D, E, G: depth-3 isExpand-false leaves) carry text; the item label show false on the leaf F wins over leaves.label.show true (F: no label)',
    option: one({ data: [(() => { const t = T7(); t.children[1].children[0].label = { show: false }; return t; })()], label: { show: false }, leaves: { label: { show: true, position: 'right' } } }) },
  { id: 'L-formatter', note: "formatter '{b}: {c} ({a})' with values: numeric 1, array [1, 2, 3] ('1,2,3'), string '7', null ('null'), none ('undefined'), 0; series named 'S'", option: one({ name: 'S', data: [{ name: 'A', value: [1, 2, 3], children: [{ name: 'B', value: '7', children: [{ name: 'D' }, { name: 'E', value: null }] }, { name: 'C', value: 0, children: [{ name: 'F', value: [4] }, { name: 'G', value: 'x' }, { name: 12 }] }] }],
    initialTreeDepth: -1, label: { formatter: '{b}: {c} ({a})', position: 'right' } }) },
  { id: 'L-bg', note: "label backgroundColor '#fff' + padding [2, 3] + borderColor '#999' borderWidth 1 (the label box Rect), position left; leaves.label position right inherits the box", option: one({ data: [T7()], label: { position: 'left', backgroundColor: '#fff', padding: [2, 3], borderColor: '#999', borderWidth: 1 }, leaves: { label: { position: 'right' } } }) },
  { id: 'L-inherit', note: "label color 'inherit' (the symbol colour), position 'right'; item B itemStyle color '#f80'", option: one({ data: [(() => { const t = T7(); t.children[0].itemStyle = { color: '#f80' }; return t; })()], label: { position: 'right', color: 'inherit' } }) },
  { id: 'L-radial-quadrants', note: 'radial R8 (8 inner nodes with 0..2 leaves each): leaves outward, expanded inner nodes toward the centre, collapsed-free; nodes in all four quadrants', option: one({ data: [R8()], layout: 'radial', initialTreeDepth: -1 }) },
  { id: 'L-radial-axes2', note: 'radial root with 2 leaf children: rawX exactly PI / 2 and 3 PI / 2 (on the horizontal axis: 3 o\'clock and 9 o\'clock); the root label from the near-zero centroid (atan2 of float noise)', option: one({ data: [leavesN(2)], layout: 'radial' }) },
  { id: 'L-radial-axes4', note: 'radial root with 4 leaf children: PI / 4 + k PI / 2 (the diagonals); and a 3-child root (below) for rawX near PI', option: one({ data: [leavesN(4)], layout: 'radial' }) },
  { id: 'L-radial-3', note: 'radial root with 3 leaf children: the middle child at rawX = 0.75 * (2 PI / 1.5) ~ PI (6 o\'clock, x a tiny +/- number)', option: one({ data: [leavesN(3)], layout: 'radial' }) },
  { id: 'L-radial-rotate', note: 'radial with label.rotate 30 (overrides -rad: every label 30 deg about the symbol centre) and symbolSize 10', option: one({ data: [T7()], layout: 'radial', symbolSize: 10, label: { rotate: 30 } }) },
  { id: 'L-radial-position', note: "radial with label.position 'top' (overrides the automatic side; the rotation is still -rad, verticalAlign forced 'middle') and leaves.label.position 'inside'", option: one({ data: [T7()], layout: 'radial', label: { position: 'top' }, leaves: { label: { position: 'inside' } } }) },
  { id: 'L-radial-collapsed', note: 'radial TD at the default depth 2: collapsed nodes with children (a1, c2) take the LEAF side rule (outward) and the leaves model', option: one({ data: [TD()], layout: 'radial' }) },
  // ---- values ----
  { id: 'V-values', note: "values: numeric, missing, array (dims value / value0 / value1: a scalar fills every dim), a numeric string '12', a non-numeric string (NaN), null, 0; labels default (the name)", option: one({ data: [{ name: 'A', value: 5, children: [{ name: 'B', value: [1, 2, 3] }, { name: 'C' }, { name: 'D', value: '12' }, { name: 'E', value: 'abc' }, { name: 'F', value: null }, { name: 'G', value: 0 }, { name: 'H', value: [7] }] }] }) },
];
for (const [name, note] of [
  ['tree-basic', "tree-basic.json verbatim: flare (252 nodes), LR, box 7% / 1% / 20% / 1%, label left / right idiom with fontSize 9, 5 root children collapsed: true, initialTreeDepth 2 default"],
  ['tree-orient-right-left', 'tree-orient-right-left.json verbatim: flare RL, label right / leaves left'],
  ['tree-legend', 'tree-legend.json verbatim: two tree series (tree1, tree2) in their own boxes + a legend (component elements in the paint order)'],
  ['tree-vertical', "tree-vertical.json verbatim: flare orient 'vertical' (= TB), labels top / bottom with rotate -90"],
  ['tree-orient-bottom-top', 'tree-orient-bottom-top.json verbatim: flare BT, labels bottom / top with rotate 90'],
  ['tree-polyline', "tree-polyline.json verbatim: polyline, edgeForkPosition '63%', initialTreeDepth 3, lineStyle width 2, label backgroundColor '#fff'"],
  ['tree-radial', 'tree-radial.json verbatim: flare radial, initialTreeDepth 3, box top 18% / bottom 14%, automatic label sides and rotation'],
]) CASES.push({ id: 'G-' + name, gallery: name, note: note + ' (examples/advchart/gallery; animation forced false)' });

// ============================================================================
// The guards
// ============================================================================
const GUARDS = [
  { id: 'sep-cousins-one', mutation: 'the separation of non-siblings 1 instead of 2', mut: { sepCousinsOne: true }, named: ['O-LR', 'H-TA', 'O-radial', 'G-tree-basic'] },
  { id: 'radial-no-depth', mutation: 'the radial separation not divided by the depth', mut: { radialNoDepth: true }, named: ['O-radial', 'H-TA-radial', 'G-tree-radial'] },
  { id: 'delta-from-right', mutation: "delta = sep(right, left) / 2 (the RIGHT node's depth in radial)", mut: { deltaFromRight: true }, named: ['H-radial-lopsided'] },
  { id: 'no-apportion', mutation: 'apportion never shifts a subtree', mut: { noApportion: true }, named: ['H-TA', 'H-TD', 'O-LR'] },
  { id: 'span-no-fallback', mutation: '(bottom.depth - 1) without the || 1 (a single visible level divides by 0)', mut: { spanNoFallback: true }, named: ['H-solo', 'X-itd0'] },
  { id: 'rl-no-mirror', mutation: 'RL laid out as LR', mut: { rlNoMirror: true }, named: ['O-RL', 'G-tree-orient-right-left'] },
  { id: 'alias-unmapped', mutation: "'horizontal' / 'vertical' not mapped to LR / TB", mut: { aliasUnmapped: true }, named: ['O-horizontal', 'O-vertical', 'G-tree-vertical'] },
  { id: 'expand-less-than', mutation: 'isExpand = depth < initialTreeDepth instead of <=', mut: { expandLessThan: true }, named: ['O-LR', 'X-itd1', 'X-itd3'] },
  { id: 'collapsed-ignored-no-eac', mutation: 'explicit collapsed flags ignored when expandAndCollapse is false', mut: { collapsedIgnoredWithoutEac: true }, named: ['X-eac-false'] },
  { id: 'leaves-true-only', mutation: 'the leaves model only for true leaves (not for collapsed inner nodes)', mut: { leavesTrueOnly: true }, named: ['X-itd0', 'X-collapsed', 'Y-style-empty', 'G-tree-basic'] },
  { id: 'leaves-symbol-used', mutation: 'symbol / symbolSize resolved through the leaves model', mut: { leavesSymbolUsed: true }, named: ['Y-item'] },
  { id: 'collapsed-leaf-filled', mutation: 'the collapsed fill for every isExpand false node (also leaves)', mut: { collapsedLeafFilled: true }, named: ['O-LR', 'X-collapsed'] },
  { id: 'no-two-px', mutation: 'the empty brush keeps itemStyle.borderWidth instead of the hard-coded 2', mut: { noTwoPx: true }, named: ['O-LR', 'Y-style-empty'] },
  { id: 'size-full', mutation: 'the path scale = symbolSize instead of symbolSize / 2', mut: { sizeFull: true }, named: ['O-LR', 'Y-series'] },
  { id: 'z2-zero', mutation: 'the symbol z2 0 instead of 100', mut: { z2Zero: true }, named: ['O-LR'] },
  { id: 'edge-from-parent', mutation: "a curve edge styled by the PARENT's lineStyle instead of the child's", mut: { edgeFromParent: true }, named: ['E-curve-style'] },
  { id: 'polyline-from-first-child', mutation: "a polyline styled by its first child's lineStyle instead of the parent's", mut: { polylineFromFirstChild: true }, named: ['E-poly-style'] },
  { id: 'curveness-from-item', mutation: 'curveness read through the node model (item / leaves) instead of the series', mut: { curvenessFromItem: true }, named: ['E-curve-item'] },
  { id: 'fork-from-child-side', mutation: 'the polyline fork position measured from the children back toward the parent (last + (parent - last) * f)', mut: { forkFromChildSide: true }, named: ['E-poly20-TB', 'E-poly-num-BT', 'G-tree-polyline'] },
  { id: 'radial-no-or-zero', mutation: 'the radial edge coordinates without `|| 0` (-0 kept)', mut: { radialNoOrZero: true }, named: ['H-TA-radial'] },
  { id: 'radial-inner-as-leaf', mutation: 'expanded inner nodes take the leaf side rule (outward)', mut: { radialInnerAsLeaf: true }, named: ['O-radial', 'L-radial-quadrants', 'G-tree-radial'] },
  { id: 'radial-rotate-ignored', mutation: 'label.rotate ignored in radial (always -rad)', mut: { radialRotateIgnored: true }, named: ['L-radial-rotate'] },
  { id: 'radial-no-origin', mutation: "the radial label rotated about its anchor (no origin 'center')", mut: { radialNoOrigin: true }, named: ['O-radial', 'G-tree-radial'] },
  { id: 'label-default-right', mutation: "the orthogonal default label position 'right' instead of 'inside'", mut: { labelDefaultRight: true }, named: ['O-LR', 'E-poly50'] },
  { id: 'line-scale-one', mutation: 'the stroke growth of the label rect not divided by the line scale', mut: { lineScaleOne: true }, named: ['L-left', 'G-tree-basic'] },
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
  const symbols = [];
  const labels = [];
  sr.rows.forEach(r => {
    if (r.symbol) {
      const s = r.symbol;
      symbols.push({ row: r.index, global: s.global, type: s.type, pathType: s.pathType, emptyBrush: s.emptyBrush, size: s.size, path: s.path, transform: s.transform, ink: s.ink, z: s.z, z2: s.z2, zlevel: s.zlevel });
    }
    if (r.label) {
      const l = r.label;
      labels.push({ row: r.index, text: l.text, position: l.textConfig.position, distance: l.textConfig.distance, rotation: l.textConfig.rotation === null ? undefined : l.textConfig.rotation,
        layoutRect: l.layoutRect, inner: l.inner, transform: l.transform, align: l.align, verticalAlign: l.verticalAlign, z: l.z, z2: l.z2 });
    }
  });
  return { layoutInfo: sr.layoutInfo, mainGroup: sr.mainGroup, orient: sr.orient, dimensions: sr.dimensions.length,
    rows: sr.rows.map(r => ({ index: r.index, name: r.name, values: r.values, value: r.value, depth: r.depth, height: r.height, isExpand: r.isExpand, parent: r.parent,
      children: r.children, leaves: r.leaves, chain: r.chain, laidOut: r.laidOut, layout: r.layout, drawn: r.drawn })),
    symbols, labels,
    edges: sr.edges.map(e => ({ owner: e.owner, kind: e.kind, from: e.from, to: e.to, lineStyleOf: e.lineStyleOf, shape: e.shape, commands: e.commands, ink: e.ink, z: e.z, z2: e.z2 })) };
}
function transcribedView(t) {
  return Object.assign({}, t, { symbols: t.symbols.map(s => Object.assign({}, s, { transform: s.transform ? s.transform.slice() : null })) });
}
function runTranscription(inp, mut, strict) {
  try {
    return transcribeTree(zrClone(inp), mut);
  } catch (e) {
    if (strict) throw e;
    return { threw: String(e.message) };
  }
}
function seriesDiffs(sr, inp, mut) {
  const t = runTranscription(inp, mut, !Object.keys(mut).length);
  if (t.threw) return [{ field: 'threw', upstream: null, mutated: t.threw }];
  return diffFlat(flat(upstreamView(sr), 's', {}), flat(transcribedView(t), 's', {}));
}
function bboxTable(symbolPaths) {
  const r = {};
  for (const k of Object.keys(symbolPaths)) r[k] = JSON.parse(symbolPaths[k]).bbox;
  return r;
}

// the random sweep: random trees x option variants through upstream and the transcription (not written)
function sweep(symbolPaths) {
  let s = 2463534242;
  const rnd = () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
  let counter = 0;
  const gen = depth => {
    const n = { name: 'n' + (counter++) };
    if (depth < 5) {
      const k = Math.floor(rnd() * (depth === 0 ? 6 : 4));
      if (k > 0) { n.children = []; for (let i = 0; i < k; i++) n.children.push(gen(depth + 1)); }
    }
    if (rnd() < 0.08) n.collapsed = rnd() < 0.5;
    return n;
  };
  const variants = [{ orient: 'LR' }, { orient: 'RL', initialTreeDepth: -1 }, { orient: 'TB', edgeShape: 'polyline', edgeForkPosition: '30%' }, { orient: 'BT', initialTreeDepth: 3 },
    { layout: 'radial' }, { layout: 'radial', initialTreeDepth: -1, width: 500, height: 333 }, { orient: 'LR', edgeShape: 'polyline', expandAndCollapse: false, label: { position: 'left' }, leaves: { label: { position: 'right' } } }];
  let checks = 0;
  for (let t = 0; t < 30; t++) {
    const data = [gen(0)];
    for (const v of variants) {
      const opt = Object.assign({ type: 'tree', data: zrClone(data) }, zrClone(v));
      runChart(echarts, { animation: false, series: [opt] }, chart => {
        const list = chart.getZr().storage.getDisplayList(true);
        const di = new Map();
        list.forEach((el, i) => di.set(el, i));
        const sp = {};
        const sm = chart.getModel().getSeriesByIndex(0);
        const sr = readTree(chart, sm, di, new Map(), sp);
        for (const k of Object.keys(sp)) if (symbolPaths[k] === undefined) symbolPaths[k] = sp[k];
        const d = seriesDiffs(sr, { S: mergedOption(opt), seriesIndex: 0, bbox: bboxTable(symbolPaths) }, {});
        must(!d.length, 'sweep tree ' + t + ' ' + JSON.stringify(v) + ': the transcription differs at ' + d.slice(0, 4).map(x => JSON.stringify(x)).join('; '));
        checks++;
      });
    }
  }
  return checks;
}

function check(g) {
  const { out, side, symbolPathsText } = g;
  const bbox = bboxTable(symbolPathsText);
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    for (const sr of c.series) {
      const sd = side[c.id + '/' + sr.seriesIndex];
      const d = seriesDiffs(sr, { S: sd.S, seriesIndex: sd.seriesIndex, bbox }, {});
      must(!d.length, c.id + '/' + sr.seriesIndex + ': the transcription differs at ' + d.slice(0, +(process.env.ORACLE_NDIFF || 4)).map(x => JSON.stringify(x)).join('; '));
      // paint order inside one series: edges, then symbols, then labels
      const sp = sr.rows.filter(r => r.symbol).map(r => r.symbol.paint);
      const ep = sr.edges.map(e => e.paint);
      const lp = sr.rows.filter(r => r.label).map(r => r.label.paint);
      const asc = a => a.every((x, i) => i === 0 || x > a[i - 1]);
      must(asc(sp) && asc(ep) && asc(lp) && (!ep.length || !sp.length || Math.max(...ep) < Math.min(...sp)) && (!lp.length || !sp.length || Math.max(...sp) < Math.min(...lp)),
        c.id + '/' + sr.seriesIndex + ': the paint order is not edges < symbols < labels in pre-order');
    }
  }
  // anchors from upstream.md section 6
  const S0 = id => byId[id].series[0];
  const at = (id, i) => S0(id).rows[i];
  const lay = (id, i) => at(id, i).layout;
  const eqL = (id, i, x, y) => Object.is(lay(id, i).x, x) && Object.is(lay(id, i).y, y);
  must(JSON.stringify(S0('O-LR').layoutInfo) === JSON.stringify({ x: 96, y: 72, width: 608, height: 456 }), 'O-LR: layoutInfo');
  must(eqL('O-LR', 1, 0, 228) && eqL('O-LR', 2, 304, 114) && eqL('O-LR', 3, 608, 76) && eqL('O-LR', 7, 608, 380), 'O-LR: T7 positions');
  must(eqL('O-RL', 1, 608, 228) && eqL('O-RL', 3, 0, 76), 'O-RL: T7 positions');
  must(eqL('O-TB', 3, 101.33333333333333, 456) && eqL('O-TB', 7, 506.66666666666663, 456) && eqL('O-BT', 1, 304, 456), 'O-TB / O-BT: T7 positions');
  const e0 = S0('O-LR').edges.find(e => e.owner === 2).shape;
  must(e0.x1 === 0 && e0.y1 === 228 && e0.cpx1 === 152 && e0.cpy1 === 228 && e0.cpx2 === 152 && e0.cpy2 === 114 && e0.x2 === 304 && e0.y2 === 114, 'O-LR: edge A->B');
  must(Object.is(lay('O-radial', 3).x, 197.45379206285202) && Object.is(lay('O-radial', 3).y, -113.99999999999996) && Object.is(lay('O-radial', 5).rawX, 4.71238898038469), 'O-radial: D / C');
  must(JSON.stringify(at('O-radial', 3).label.transform) === JSON.stringify([0.8660254037844388, -0.49999999999999967, 0.49999999999999967, 0.8660254037844388, 605.6810333988042, 181.25000000000006]), 'O-radial: D label matrix');
  must(JSON.stringify(at('O-radial', 6).label.transform) === JSON.stringify([0.8660254037844389, -0.49999999999999944, 0.49999999999999944, 0.8660254037844389, 194.31896660119577, 418.7499999999999]), 'O-radial: F label matrix');
  must(at('O-radial', 1).label.textConfig.rotation === -1.5707963267948966 && at('O-radial', 1).label.textConfig.position === 'right', 'O-radial: root label');
  must(Object.is(lay('H-TA', 1).y, 244.28571428571428) && Object.is(lay('H-TA', 9).y, 293.1428571428571) && Object.is(lay('H-TA', 11).y, 390.85714285714283), 'H-TA: positions');
  must(Object.is(lay('H-TA-radial', 1).x, -0) && Object.is(lay('H-TA-radial', 2).x, 74.09452132581859), 'H-TA-radial: -0 root, X');
  const ta = S0('H-TA-radial').edges.find(e => e.owner === 2).shape;
  must(Object.is(ta.x1, 0) && ta.cpx1 === -8.455795490339963 && ta.cpy1 === 37.047260662909295, 'H-TA-radial: edge R->X (|| 0 on the start)');
  must(eqL('H-solo', 1, 0, 228), 'H-solo: (0, 228)');
  must(at('O-LR', 1).symbol.ink.lineWidth === 2 && at('O-LR', 1).symbol.ink.fill === '#fff' && at('O-LR', 1).symbol.ink.stroke === 'lightsteelblue' && at('O-LR', 1).symbol.z2 === 100, 'O-LR: the empty brush');
  must(at('X-itd0', 1).symbol.ink.fill === 'lightsteelblue' && at('X-itd0', 1).leaves, 'X-itd0: the collapsed root filled and leaf-wrapped');
  must(at('X-collapsed', 4).isExpand === false && at('X-collapsed', 4).symbol.ink.fill === '#fff', 'X-collapsed: collapsed leaf C hollow');
  must(S0('X-multi-root').rows.slice(8).every(r => !r.laidOut && !r.drawn) && S0('X-multi-root').rows[0].name === 'forest', 'X-multi-root: extra roots not laid out');
  const poly = S0('E-poly50').edges[0];
  must(poly.kind === 'polyline' && poly.owner === 1 && poly.commands.length === 8, 'E-poly50: the root TreePath (3 children: stem, first twig, bar, last twig, 1 middle)');
  must(byId['E-poly-radial'].productionBuild && S0('E-poly-radial').edges.length === 0, 'E-poly-radial: production, no edges');
  must(at('L-formatter', 1).label.text === 'A: 1,2,3 (S)' && at('L-formatter', 3).label.text === 'D: undefined (S)' && at('L-formatter', 4).label.text === 'E: null (S)', 'L-formatter: texts');
  must(at('L-left', 1).label.inner.x === 86.5 && at('L-left', 1).label.inner.y === 300, 'L-left: A anchor (86.5, 300)');
  must(['symbolPaths'].length && ['circle', 'rect', 'triangle', 'diamond', 'roundRect', 'pin'].every(k => symbolPathsText[k]), 'symbol paths');
  must(byId['G-tree-legend'].paintRuns.some(r => r.owner === 'component' && r.type === 'legend'), 'G-tree-legend: legend elements');
  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let any = false;
      for (const sr of c.series) {
        const sd = side[c.id + '/' + sr.seriesIndex];
        const d = seriesDiffs(sr, { S: sd.S, seriesIndex: sd.seriesIndex, bbox }, gd.mut);
        if (d.length) {
          any = true;
          if (gd.named.includes(c.id)) differs.push({ case: c.id + '/' + sr.seriesIndex, fields: d.slice(0, 3) });
        }
      }
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

function generate() {
  const side = {};
  const symbolPathsText = {};
  const cases = CASES.map(d => {
    try {
      return recordCase(d, side, symbolPathsText);
    } catch (e) {
      if (e instanceof OracleError) e.message = d.id + ': ' + e.message;
      throw e;
    }
  });
  const symbolPaths = {};
  for (const k of Object.keys(symbolPathsText).sort()) symbolPaths[k] = JSON.parse(symbolPathsText[k]);
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version + ' (V8 ' + process.versions.v8 + ')',
    W, H, seed: SEED, tz: 'UTC',
    api: {
      update: "echarts.init(null, null, {renderer: 'svg', ssr: true, width: 800, height: 600}); setOption (animation false, forced when the option does not say so); zr.storage.getDisplayList(true) (transforms, updateInnerText, TSpan layout); no animation frame is ever stepped",
      model: "getData(): the tree = data.tree, tree.getNodeByDataIndex(i) {name, depth, height, isExpand, parentNode, children, getValue()}, data.get(dim, i), getRawDataItem(i), getItemLayout(i) {x, y[, rawX, rawY]}, getItemModel(i).parentModel (the series model, or the leaves model whose parent is the series), sm.layoutInfo, sm.getOrient()",
      view: "chart.getViewOfSeriesModel(sm): .group (roam), ._mainGroup; data.getItemGraphicEl(i) = the Symbol group (child 0 = the symbol path: shape.symbolType, x / y / scale / rotation, transform, style, z / z2 / zlevel, getTextContent(), textConfig), .__edge (the BezierCurve / TreePath, recorded when its parent is the main group)",
      paint: 'zr.storage.getDisplayList(true); an element is owned by the first view group found climbing el.parent, then el.__hostTarget (a label Text -> its host); its group is the class the reader gave it (edge / symbol / label / labelBg)',
      production: 'every case must record identically through dist/echarts.min.js; a prod case is recorded from it',
    },
    notes: [
      'Rows: SeriesData row i = the i-th node of a PRE-ORDER walk of {name: series.name, children: series.data} -- row 0 is that VIRTUAL root (depth 0, never drawn), row 1 is data[0] (depth 1). Only data[0] is laid out; data[1..] are rows without a layout (X-multi-root). height: a leaf 1, else 1 + max child height. Values: dims value, value0, ... (as many as the longest value array); a scalar value fills EVERY dim (V-values B / D), an array fills dim k with element k and NaN beyond; null, a missing value and a non-numeric string are NaN.',
      'isExpand: expandTreeDepth = (expandAndCollapse && initialTreeDepth >= 0) ? initialTreeDepth : the max depth; node.isExpand = item.collapsed != null ? !item.collapsed : depth <= expandTreeDepth (depth counted with the real root at 1: the default 2 opens the root and its children; grandchildren are visible but closed). An explicit collapsed flag wins even with expandAndCollapse false. A node is laid out when every ancestor from the real root down is expanded.',
      "The leaves model: every node that is NOT (children.length && isExpand) -- true leaves AND collapsed inner nodes AND collapsed-flagged leaves -- resolves label / itemStyle / lineStyle / emphasis through item -> leaves -> series; an expanded inner node through item -> series. symbol / symbolSize / symbolRotate / symbolOffset are the item's OWN value else the series' (leaves.symbol* ignored: Y-item). Edge curveness is the SERIES lineStyle.curveness only (E-curve-item).",
      'Layout: d3-hierarchy Reingold-Tilford on the visible nodes: separation 1 for siblings, 2 otherwise (radial: divided by the FIRST argument\'s depth); extremes left / right / bottom in pre-order with strict < / >; delta = left === right ? 1 : sep(left, right) / 2; tx = delta - left.x; LR / RL: ky = height / (right.x + delta + tx), kx = width / ((bottom.depth - 1) || 1), y = (x + tx) * ky, x = (depth - 1) * kx (RL: width - that); TB / BT the transpose; radial: kx = 2 PI / (right.x + delta + tx), ky = (min(w, h) / 2) / ((bottom.depth - 1) || 1), rawX = (x + tx) * kx, rawY = (depth - 1) * ky, (x, y) = rawY * (cos, sin)(rawX - PI / 2). Coordinates are local to the main group (layoutInfo.x / y, or the box centre for radial); the view group is identity at zoom 1.',
      "Symbol: a Symbol group at the layout holding one path from createSymbol(type, -1, -1, 2, 2), scale = size / 2, z2 100, strokeNoScale. The style visual is series itemStyle extended by the node model's itemStyle (the leaves chain applies). emptyXxx: stroke = the colour, lineWidth 2 (hard-coded: borderWidth / borderColor have no effect), fill '#fff', or the COLOUR when the node is collapsed and has children (a collapsed-flagged leaf stays hollow). Other symbols: fill = the colour, stroke = borderColor only when set, lineWidth = borderWidth (default 1.5).",
      "Edges: z2 0, paint below every symbol. curve: one BezierCurve per laid-out node under a real parent, parent -> node, the NODE's lineStyle; LR / RL cp1 = (s.x + (t.x - s.x) c, s.y), cp2 = (t.x + (s.x - t.x) c, t.y); TB / BT the transpose; radial: the four points radialCoordinate(rawX, rawY) of (s), (s.rawX, s.rawY + (t.rawY - s.rawY) c), (t.rawX, t.rawY + (s.rawY - t.rawY) c), (t), each `|| 0` (-0 -> 0). polyline (orthogonal only; radial throws in development and draws nothing in production): one TreePath per expanded node with children, the PARENT's lineStyle; fork = parent + (LAST child - parent) * parsePercent(edgeForkPosition, 1) on the depth axis; commands M parent L fork, M first L (first, fork) L (last, fork) L last, then M child L (child, fork) per middle child; a single child: M parent L child. lineDash = lineStyle.type as written ('solid' included), default stroke '#cfd2d7' width 1.5.",
      "Labels: the node NAME (useNameLabel), or a string formatter via formatTpl ({a} series name, {b} name, {c} the RAW value: an array joins with ',', a missing value prints 'undefined', null prints 'null'). textConfig position = label.position || 'inside' (orthogonal: no tree-specific logic for any orient), distance ?? 5, rotation = rotate * (PI / 180) when set (about the anchor). The anchor is calculateTextPosition on the symbol path's bounding rect GROWN by its stroke (lineWidth / lineScale, lineScale = sqrt|det| = size / 2 unless a scale is ~1) through the path's global transform: for emptyCircle 7 a 9 x 9 box. Radial: side = leaf / collapsed -> outward (left when x < root x), expanded inner -> toward the centre, the root -> from the centroid of its first and last child; rotation = label.rotate != null ? rotate * PI / 180 : -rad; origin 'center' (the rotation turns about the symbol centre); verticalAlign forced 'middle'; label.position still overrides the side. z2 102: all labels paint after all symbols.",
      "Colours of labels are recorded, not transcribed: inside -> the symbol path's getInsideTextFill ('#333' on a light fill), no stroke; outside -> '#333' with an auto stroke of the background colour width 2 unless label.color is set. Text widths (TSpan x for align, the background Rect) come from zrender's node measureText estimate, not a real font.",
      'Not recorded: emphasis / blur / focus states, hover scale, tooltip, click expand / collapse, roam (zoom / center; every case is at the identity), animations.',
    ],
    symbolPaths,
    cases,
  };
  return { out, side, symbolPathsText };
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
  sweepChecks = sweep(Object.assign({}, g1.symbolPathsText));
  specials = 0;
  const s1 = sanitize(g1.out);
  nSpecial = specials;
  json1 = fmt(s1, '') + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(s1), 'the written JSON does not parse back to the record');
  const g2 = generate();
  g2.out.guards = check(g2);
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
console.log(out.cases.length + ' cases (' + nSeries + ' tree series); sweep ' + sweepChecks + ' random charts agree; ' + (out.guards.length - bad.length) + '/' + out.guards.length
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
