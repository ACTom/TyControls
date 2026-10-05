// Upstream's own answers for where a cartesian grid's plot rect ends up once its
// axis labels (and names) are made to fit: grid.outerBounds / outerBoundsMode /
// outerBoundsContain / outerBoundsClamp*, and the legacy grid.containLabel.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode. Node has no canvas, so zrender
// measures every string with its built-in width table (zrender
// core/platform.ts:76-92): px is the number before 'px' in the font, else 12;
// each UTF-16 unit of char code 32..126 counts ratio*px, any other unit px,
// summed left to right; a line is px high. The fixture carries that table and a
// set of measured strings, so the port can measure exactly as upstream did here.
//
//   ratios    the 95 ratios of char codes 32..126, decoded from the width-table
//             string in the dist being run (and checked against the zrender
//             source when D:/Projects/zrender, or ZRENDER_SRC, is there), each
//             one also read back from a 1px Text so the table is the one in use.
//             fontSize is the size a font string without 'px' measures at.
//   measure   Text.getBoundingRect() width and height for strings x px; the
//             generator's own reading of the rule above must give the same
//             Doubles or the run fails.
//   cases     one record per grid. A chart is run twice: as given (the final
//             rect, the axes' pixel extents) and again with every grid's
//             outerBoundsMode 'none' and containLabel false, which lays the axes
//             out on the raw rect without moving it -- the estimate.
//
// Per case:
//   W, H      the canvas. grid: which grid of the option the record is about.
//   option    as run (animation false). Only JSON: no formatter functions.
//   mode      'legacy' when grid.containLabel is truthy (outerBounds* ignored);
//             else outerBoundsMode: 'same', 'auto' for null/'auto', 'none' for
//             'none' and anything else (Grid.ts:217-258, 998-1020).
//   contain   outerBoundsContain parsed: 'axisLabel', or 'all' for anything
//             else (Grid.ts:1023-1035). Only auto and same use it.
//   outer     auto: getLayoutRect(the model's merged outerBounds, the canvas),
//             run through the build's own helper; same: the raw rect. Null for
//             none and legacy. clamp: outerBoundsClampWidth/Height ('25%' when
//             absent) against the RAW rect's size (Grid.ts:1037-1045); null for
//             none and legacy.
//   raw       the grid rect before any shrink: the estimate run's getRect().
//   estimate  every axis of the grid in the grid's own order (x axes, then y),
//             from the estimate run's AxisBuilder shared record: labels are
//             labelInfoList (what survived thinning; the label's rect is its
//             global box), sorted by tick. text is label.style.text; tick is
//             getTickValueOutermost(scale, tick) of the label's own tick (the
//             raw ordinal on a category axis); p is the proportion Grid.ts:884-887
//             divides by: scale.normalize(tick), and 1 - that on a y axis (not
//             band-adjusted, not flipped by inverse). nameRect / nameP: the name's
//             rect and its proportion (0.5 for 'middle'/'center', NaN otherwise);
//             a name counts only when contain is 'all'. A hidden axis has no
//             labels and no name. A legacy case records the estimate too; there
//             it does not enter the rect.
//   legacy    (legacy only) the axes as legacyContainLabel.ts:41-120 walks them:
//             every tick's label text stepping ceil(n/40) past 40 ticks, the
//             label rotate, margin and px, inside / show / blank.
//   margin    [t,r,b,l] (auto and same only): the overflow per side, from a
//             transcription of Grid.ts:864-924 fed the estimate. Upstream keeps
//             it local; the transcription reproduces rect bit for bit (below).
//   rect      the final grid rect: coordinateSystem.getRect().
//   axes      dim, index and getGlobalExtent() of every axis, from the final run.
//   tol       4 ulp(max(W, H)) / the smallest proportion the shrink divided by
//             (1 when it divided by none): the absolute tolerance for a rect
//             or label box the port builds from its own label geometry. Shrink
//             arithmetic fed these very rects is expected to be exact.
//
// Self-checks. auto and same: a transcription of Grid.ts:864-924 and
// graphic.ts:608-672 (expandOrShrinkRect) fed estimate, outer and clamp must give
// rect exactly (Object.is on x, y, width, height). legacy: a transcription of
// legacyContainLabel.ts fed the legacy axes, measuring with the ratios above,
// must give rect exactly. none: rect must be raw. A case that fails is recorded
// all the same, deferred, with the reason.
//
// A case marked deferred depends on something the port does not do yet (label
// font size, truncate and break, the grid box merge); its upstream answer is
// recorded so a later batch only has to take the
// flag off. A documentary case pins a port test's fixture: the rect is compared,
// the label set need not match.
//
// Doubles are written as the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase) with a readable twin beside them (rectText beside rect, ...),
// because the Pascal JSON reader misparses integer literals above 2^63.
//
//   node tools/advchart-oracle/grid-bounds.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
// The development build asserts its own invariants and throws where the
// production build carries on; a case that trips one is run through the
// production build instead, which is what a page actually ships, and says so.
const PROD = require(DIST.replace(/echarts\.js$/, 'echarts.min.js'));
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-grid-bounds.json');

// This generator's own assertions: never retried through the production build.
class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const RECT = ['x', 'y', 'width', 'height'];
const hexRect = r => (r ? { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) } : null);
const textRect = r => (r ? { x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) } : null);
const plainRect = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
const finiteRect = r => r && RECT.every(k => typeof r[k] === 'number' && Number.isFinite(r[k]));
const sameRect = (a, b) => RECT.every(k => Object.is(a[k], b[k]));

// The distance to the next Double up, for a positive finite x.
function ulp(x) {
  bits.setFloat64(0, x);
  const hi = bits.getUint32(0);
  const lo = bits.getUint32(4);
  if (lo === 0xffffffff) {
    bits.setUint32(0, hi + 1);
    bits.setUint32(4, 0);
  } else {
    bits.setUint32(4, lo + 1);
  }
  return bits.getFloat64(0) - x;
}

// ---------- the width table ----------

const FIRST_CODE = 32;
const LAST_CODE = 126;
const DEFAULT_FONT_SIZE = 12;

function decodeTable(literal, where) {
  // the literal is JavaScript source (a quoted string in the dist, a template
  // literal in the TypeScript source): evaluate it as written
  const s = Function('"use strict"; return (' + literal + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1,
    where + ': the width table is not ' + (LAST_CODE - FIRST_CODE + 1) + ' characters');
  return s;
}
const mapStr = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = decodeTable(line.slice(line.indexOf('=') + 1).trim().replace(/;$/, ''), DIST);
  if (fs.existsSync(ZRENDER_SRC)) {
    const m = /const defaultWidthMapStr = (`[^`]*`)/.exec(fs.readFileSync(ZRENDER_SRC, 'utf8'));
    must(m, ZRENDER_SRC + ': no defaultWidthMapStr');
    must(decodeTable(m[1], ZRENDER_SRC) === s, 'the dist and the zrender source disagree on the width table');
  } else {
    console.log('no zrender source at ' + ZRENDER_SRC + ': the width table is read from the dist only');
  }
  return s;
})();
// platform.ts getTextWidthMap: (charCode - OFFSET) / SCALE
const RATIO = Array.from(mapStr, ch => (ch.charCodeAt(0) - 20) / 100);

function measureText(t, font) {
  return new echarts.graphic.Text({ style: { text: t, font } }).getBoundingRect();
}
// Each ratio is what a 1px font measures its character at, and a font with no
// 'px' measures at DEFAULT_FONT_SIZE: the table decoded is the table in use.
RATIO.forEach((r, i) => {
  const ch = String.fromCharCode(FIRST_CODE + i);
  const w = measureText(ch, '1px sans-serif').width;
  must(Object.is(w, r), 'char code ' + (FIRST_CODE + i) + ': the table says ' + r + ', a 1px Text measures ' + w);
});
must(Object.is(measureText('0', 'sans-serif').width, RATIO['0'.charCodeAt(0) - FIRST_CODE] * DEFAULT_FONT_SIZE),
  'a font with no px does not measure at ' + DEFAULT_FONT_SIZE);

// The rule the port implements: per UTF-16 unit, left to right; the widest line;
// px per line.
function lineWidth(line, px) {
  let w = 0;
  for (let i = 0; i < line.length; i++) {
    const c = line.charCodeAt(i);
    const r = c >= FIRST_CODE && c <= LAST_CODE ? RATIO[c - FIRST_CODE] : null;
    w += r == null ? px : r * px;
  }
  return w;
}
function textBox(t, px) {
  const lines = String(t).split('\n');
  return { x: 0, y: 0, width: Math.max(...lines.map(l => lineWidth(l, px))), height: px * lines.length };
}

const MEASURED = ['0123456789', '1,000', '1,000,000,000', '20,000,000,000', '-40', '1.5', 'Mon', 'Wednesday',
  'Category 10', '\u56fd', '\u00e9', '\ud83d\ude00', 'Ab\tc', 'ab\nlonger line', 'Mon\nl2\nl3'];
const measure = [];
for (const px of [9, 12, 14, 16]) {
  for (const t of MEASURED) {
    const r = measureText(t, px + 'px sans-serif');
    const f = textBox(t, px);
    must(Object.is(r.width, f.width) && Object.is(r.height, f.height),
      JSON.stringify(t) + ' at ' + px + 'px: Text measures ' + r.width + ' x ' + r.height
      + ', the rule gives ' + f.width + ' x ' + f.height);
    measure.push({ text: t, px, width: hex(r.width), widthText: text(r.width), height: hex(r.height), heightText: text(r.height) });
  }
}

// ---------- transcriptions ----------

// Grid.ts:864-924 (after the estimate pass) and util/graphic.ts:608-672.
const XY = ['x', 'y'];
const WH = ['width', 'height'];
const XY_TO_MARGIN_IDX = [[3, 1], [0, 2]];

function expandRectOnOneDimension(rect, delta, xy, wh, ltIdx, rbIdx, minSize) {
  const deltaSum = delta[rbIdx] + delta[ltIdx];
  const oldSize = rect[wh];
  rect[wh] += deltaSum;
  minSize = Math.max(0, Math.min(minSize, oldSize));
  if (rect[wh] < minSize) {
    rect[wh] = minSize;
    rect[xy] += (
      delta[ltIdx] >= 0 ? -delta[ltIdx]
        : delta[rbIdx] >= 0 ? oldSize + delta[rbIdx]
          : Math.abs(deltaSum) > 1e-8 ? (oldSize - minSize) * delta[ltIdx] / deltaSum
            : 0
    );
  } else {
    rect[xy] -= delta[ltIdx];
  }
}
function expandOrShrinkRect(rect, delta, shrinkOrExpand, noNegative, minSize) {
  const d = delta.slice();
  if (noNegative) for (let i = 0; i < 4; i++) d[i] = Math.max(0, d[i]);
  if (shrinkOrExpand) for (let i = 0; i < 4; i++) d[i] = -d[i];
  expandRectOnOneDimension(rect, d, 'x', 'width', 3, 1, (minSize && minSize[0]) || 0);
  expandRectOnOneDimension(rect, d, 'y', 'height', 0, 2, (minSize && minSize[1]) || 0);
  return rect;
}

// estimate: [{dim, labels: [{rect, p}], name: {rect, p} | null}] in numbers.
function solveOuterBounds(raw, outer, contain, clamp, estimate) {
  const margin = [0, 0, 0, 0];
  let minP = Infinity;
  function applyProportion(overflow, proportion) {
    if (overflow > 0 && !Number.isNaN(proportion) && proportion > 1e-4) {
      overflow /= proportion;
      minP = Math.min(minP, proportion);
    }
    return overflow;
  }
  function fill(itemRect, xyIdx, proportion) {
    let overflow1 = outer[XY[xyIdx]] - itemRect[XY[xyIdx]];
    let overflow2 = (itemRect[WH[xyIdx]] + itemRect[XY[xyIdx]]) - (outer[WH[xyIdx]] + outer[XY[xyIdx]]);
    overflow1 = applyProportion(overflow1, 1 - proportion);
    overflow2 = applyProportion(overflow2, proportion);
    const minIdx = XY_TO_MARGIN_IDX[xyIdx][0];
    const maxIdx = XY_TO_MARGIN_IDX[xyIdx][1];
    margin[minIdx] = Math.max(margin[minIdx], overflow1);
    margin[maxIdx] = Math.max(margin[maxIdx], overflow2);
  }
  [0, 1].forEach(xyIdx => estimate.filter(a => a.dim === XY[xyIdx]).forEach(a => {
    a.labels.forEach(l => {
      fill(l.rect, xyIdx, l.p);
      fill(l.rect, 1 - xyIdx, NaN);
    });
    if (contain === 'all' && a.name) {
      fill(a.name.rect, xyIdx, a.name.p);
      fill(a.name.rect, 1 - xyIdx, NaN);
    }
  }));
  fill(raw, 0, NaN);
  fill(raw, 1, NaN);
  const rect = expandOrShrinkRect(plainRect(raw), margin, true, true, clamp);
  return { margin, rect, minP: minP === Infinity ? 1 : minP };
}

// legacyContainLabel.ts:41-120, measuring with the table above.
function unionRect(a, b) {
  // zrender BoundingRect.union, for finite rects
  const x = Math.min(b.x, a.x);
  const y = Math.min(b.y, a.y);
  a.width = Math.max(b.x + b.width, a.x + a.width) - x;
  a.height = Math.max(b.y + b.height, a.y + a.height) - y;
  a.x = x;
  a.y = y;
}
function legacyContainLabel(raw, legacyAxes) {
  const rect = plainRect(raw);
  legacyAxes.forEach(a => {
    if (a.inside) return;
    let union = null;
    if (a.labelShow && !a.blank) {
      const rad = a.rotate * Math.PI / 180;
      a.labels.forEach(t => {
        const box = textBox(t, a.px);
        const single = {
          x: box.x,
          y: box.y,
          width: box.width * Math.abs(Math.cos(rad)) + Math.abs(box.height * Math.sin(rad)),
          height: box.width * Math.abs(Math.sin(rad)) + Math.abs(box.height * Math.cos(rad)),
        };
        if (union) unionRect(union, single);
        else union = single;
      });
    }
    if (union) {
      const dim = a.horizontal ? 'height' : 'width';
      rect[dim] -= union[dim] + a.margin;
      if (a.position === 'top') rect.y += union.height + a.margin;
      else if (a.position === 'left') rect.x += union.width + a.margin;
    }
  });
  return rect;
}

// ---------- running upstream ----------

const clone = o => JSON.parse(JSON.stringify(o));
// A function, undefined or non-finite number would not survive JSON: the option
// written would not be the option run.
function assertJson(v, where) {
  if (typeof v === 'function' || v === undefined) throw new OracleError(where + ': not JSON');
  if (typeof v === 'number') must(Number.isFinite(v), where + ': a non-finite number');
  if (v && typeof v === 'object') Object.keys(v).forEach(k => assertJson(v[k], where + '.' + k));
}

function render(lib, option, W, H) {
  const chart = lib.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart.setOption(clone(option));
  chart.renderToSVGString();
  return chart;
}

// getLabelInner(label) is a makeInner store: an '__ec_inner_<n>' key holding
// {labelInfo, layoutRotation}.
function labelInfoOf(label, where) {
  const found = Object.keys(label).filter(k => k.indexOf('__ec_inner_') === 0
    && label[k] && typeof label[k] === 'object' && label[k].labelInfo);
  must(found.length === 1, where + ': ' + found.length + ' inner stores with a labelInfo on the label');
  const info = label[found[0]].labelInfo;
  must(info.tick && typeof info.tick.value === 'number', where + ': the labelInfo has no numeric tick');
  return info;
}

function estimateOf(grid, where, defaultFont) {
  return grid.coordinateSystem.getAxes().map(axis => {
    const dim = axis.dim;
    const index = axis.model.componentIndex;
    const aw = where + ' ' + dim + index;
    must(dim === 'x' || dim === 'y', aw + ': dim ' + dim);
    const out = { dim, index, position: axis.position, labels: [], name: null };
    if (!axis.model.getShallow('show')) {
      must(!axis.axisBuilder, aw + ': a hidden axis has a builder');
      return out;
    }
    const b = axis.axisBuilder;
    must(b && b._shared && typeof b._shared.ensureRecord === 'function', aw + ': no axisBuilder._shared.ensureRecord');
    const rec = b._shared.ensureRecord(axis.model);
    must(rec && typeof rec === 'object', aw + ': no shared record');
    const list = rec.labelInfoList;
    must(list === undefined || Array.isArray(list), aw + ': labelInfoList is not an array');
    const ordinal = axis.scale.type === 'ordinal';
    (list || []).forEach((li, k) => {
      const lw = aw + ' label ' + k;
      must(li && li.label && li.label.style && typeof li.label.style.text === 'string', lw + ': no label text');
      must(finiteRect(li.rect), lw + ': no finite rect');
      if (defaultFont) {
        must(/(^|\s)12px(\s|$)/.test(String(li.label.style.font)), lw + ': font ' + li.label.style.font + ' is not the default 12px');
      }
      const info = labelInfoOf(li.label, lw);
      // getTickValueOutermost
      const tick = ordinal ? axis.scale.getRawOrdinalNumber(info.tick.value) : info.tick.value;
      must(li.label.anid === 'label_' + tick, lw + ': anid ' + li.label.anid + ' is not label_' + tick);
      let p = axis.scale.normalize(tick);
      p = dim === 'y' ? 1 - p : p;
      must(typeof p === 'number' && !Number.isNaN(p), lw + ': proportion ' + p);
      out.labels.push({ text: li.label.style.text, tick, p, rect: plainRect(li.rect) });
    });
    out.labels.sort((a, c) => a.tick - c.tick);
    const nl = rec.nameLayout;
    if (nl) {
      must(finiteRect(nl.rect), aw + ': the name has no finite rect');
      const loc = rec.nameLocation;
      out.name = { rect: plainRect(nl.rect), p: loc === 'middle' || loc === 'center' ? 0.5 : NaN };
    }
    return out;
  });
}

// What legacyContainLabel.ts reads, per axis in the grid's own order.
function legacyAxesOf(grid, where) {
  return grid.coordinateSystem.getAxes().map(axis => {
    const aw = where + ' ' + axis.dim + axis.model.componentIndex;
    const labelModel = axis.getLabelModel();
    const scale = axis.scale;
    const out = {
      dim: axis.dim,
      index: axis.model.componentIndex,
      position: axis.position,
      horizontal: axis.isHorizontal(),
      inside: !!axis.model.get(['axisLabel', 'inside']),
      labelShow: !!axis.model.get(['axisLabel', 'show']),
      blank: scale.isBlank(),
      rotate: labelModel.get('rotate') || 0,
      margin: axis.model.get(['axisLabel', 'margin']),
      px: labelModel.get('fontSize'),
      step: 1,
      labels: [],
    };
    must(typeof out.margin === 'number' && typeof out.rotate === 'number', aw + ': margin or rotate is not a number');
    must(out.px === DEFAULT_FONT_SIZE, aw + ': label font size ' + out.px);
    if (!out.labelShow || out.blank) return out;
    must(axis.type !== 'time', aw + ': a time axis');
    // makeLabelFormatter(axis), without a formatter or with a string one
    const formatter = labelModel.get('formatter');
    must(formatter == null || typeof formatter === 'string', aw + ': a formatter that is not a string');
    const format = tick => {
      const label = scale.getLabel(tick);
      return formatter == null ? label : formatter.replace('{value}', label != null ? label : '');
    };
    const ordinal = scale.type === 'ordinal';
    const ticks = ordinal ? null : scale.getTicks();
    const count = ordinal ? scale.count() : ticks.length;
    const extent0 = scale.getExtent()[0];
    if (count > 40) out.step = Math.ceil(count / 40);
    for (let i = 0; i < count; i += out.step) {
      const t = format(ticks ? ticks[i] : { value: extent0 + i });
      must(typeof t === 'string', aw + ': label ' + i + ' is not a string');
      out.labels.push(t);
    }
    return out;
  });
}

const OUTER_BOUNDS_DEFAULT = { left: 0, right: 0, top: 0, bottom: 0 };
// number.ts parsePositionSizeOption
function parsePositionSizeOption(option, percentBase) {
  if (typeof option === 'string') {
    if (/%$/.test(option.trim())) return parseFloat(option) / 100 * percentBase + 0;
    return parseFloat(option);
  }
  return option == null ? NaN : +option;
}

function run(c, lib) {
  const where = c.name;
  const option = clone(c.option);
  option.animation = false;

  // the estimate: every grid laid out on its raw rect and left there
  const flat = clone(option);
  const none = g => Object.assign({}, g || {}, { outerBoundsMode: 'none', containLabel: false });
  flat.grid = Array.isArray(option.grid) ? option.grid.map(none) : none(option.grid);
  const est = render(lib, flat, c.W, c.H);
  let raw;
  let estimate;
  try {
    const g = est.getModel().getComponent('grid', c.grid);
    must(g && g.coordinateSystem, where + ': no grid ' + c.grid + ' in the estimate run');
    raw = plainRect(g.coordinateSystem.getRect());
    must(finiteRect(raw), where + ': the raw rect is not finite');
    estimate = estimateOf(g, where, !c.deferred);
  } finally {
    est.dispose();
  }

  const chart = render(lib, option, c.W, c.H);
  try {
    const gm = chart.getModel().getComponent('grid', c.grid);
    must(gm && gm.coordinateSystem, where + ': no grid ' + c.grid);
    const cs = gm.coordinateSystem;
    const container = { x: 0, y: 0, width: c.W, height: c.H };
    // the rect the final run started from is the estimate run's rect
    must(sameRect(plainRect(lib.helper.getLayoutRect(gm.getBoxLayoutParams(), container)), raw),
      where + ': the final run starts from another raw rect');

    let mode;
    if (gm.get('containLabel')) mode = 'legacy';
    else {
      const m = gm.get('outerBoundsMode', true);
      mode = m === 'same' ? 'same' : m == null || m === 'auto' ? 'auto' : 'none';
    }
    const oc = gm.get('outerBoundsContain', true);
    const contain = oc === 'axisLabel' ? 'axisLabel' : 'all';
    let outer = null;
    let clamp = null;
    if (mode === 'same') outer = plainRect(raw);
    if (mode === 'auto') {
      outer = plainRect(lib.helper.getLayoutRect(gm.get('outerBounds', true) || OUTER_BOUNDS_DEFAULT, container));
    }
    if (mode === 'same' || mode === 'auto') {
      const cw = gm.get('outerBoundsClampWidth', true);
      const ch = gm.get('outerBoundsClampHeight', true);
      clamp = [
        parsePositionSizeOption(cw != null ? cw : '25%', raw.width),
        parsePositionSizeOption(ch != null ? ch : '25%', raw.height),
      ];
    }

    const rect = plainRect(cs.getRect());
    must(finiteRect(rect), where + ': the final rect is not finite');
    const axes = cs.getAxes().map(axis => {
      const e = axis.getGlobalExtent();
      return { dim: axis.dim, index: axis.model.componentIndex, globalExtent: e.map(hex), globalExtentText: e.map(text) };
    });
    const legacy = mode === 'legacy' ? legacyAxesOf(gm, where) : null;
    return { option, mode, contain, outer, clamp, raw, estimate, legacy, rect, axes };
  } finally {
    chart.dispose();
  }
}

function runEither(c) {
  try {
    return run(c, echarts);
  } catch (e) {
    if (e instanceof OracleError) throw e;
    console.log(c.name + ': the development build threw (' + e.message + ')');
    return Object.assign(run(c, PROD), { productionBuild: true });
  }
}

// ---------- cases ----------

const cases = [];
const add = (name, option, extra) => {
  assertJson(option, name);
  cases.push(Object.assign({ name, option, W: 600, H: 400, grid: 0 }, extra || {}));
};
const deferred = why => ({ deferred: why });

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const VALS = [120, 200, 150, 80, 70, 110, 130];
const BIG9 = VALS.map(v => v * 1e7); // up to 2,000,000,000
const BIG10 = VALS.map(v => v * 1e8); // up to 20,000,000,000
const LONG = DAYS.map(d => 'A very long category label ' + d);
const X68 = '{value} ' + 'X'.repeat(68);
function bar(grid, x, y, data) {
  const o = {};
  if (grid) o.grid = grid;
  o.xAxis = Object.assign({ type: 'category', data: DAYS }, x || {});
  o.yAxis = Object.assign({ type: 'value' }, y || {});
  o.series = [{ type: 'bar', data: data || VALS }];
  return o;
}
const scatter = grid => ({ grid, xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: [{ type: 'scatter', data: [[1, 2], [3, 4]] }] });

// auto: outer = the canvas unless outerBounds says otherwise
add('A default bar', bar());
add('C 7-line x labels overflow the bottom', bar(null, { data: DAYS.map(d => d + '\nl2\nl3\nl4\nl5\nl6\nl7') }));
add('D y labels 2,000,000,000 fit', bar(null, null, null, BIG9));
add('D2 y labels 20,000,000,000 overflow left', bar(null, null, null, BIG10));
add('D4 y labels 2,000,000,000,000 overflow left', bar(null, null, null, VALS.map(v => v * 1e10)));
add('H outerBounds 10 on each side, big9', bar({ outerBounds: { left: 10, right: 10, top: 10, bottom: 10 } }, null, null, BIG9));
add('H2 outerBounds {left:100} only, big9', bar({ outerBounds: { left: 100 } }, null, null, BIG9));
add('X outerBounds {left:10,width:300}: the raw rect itself overflows', bar({ outerBounds: { left: 10, width: 300 } }));
add('M5 outerBounds {left:10,width:300}, big10', bar({ outerBounds: { left: 10, width: 300 } }, null, null, BIG10));
// interval 0 written out: upstream shows all seven turned labels here anyway,
// and the case then does not hang on the category auto interval (the
// thinning batch), which the port answers differently for turned labels
add('J x labels rotate 45, long categories', bar(null, { data: LONG, axisLabel: { rotate: 45, interval: 0 } }));
add('J2 x labels rotate 90, long categories', bar(null, { data: LONG, axisLabel: { rotate: 90 } }));
add('J5 x labels rotate -45, long categories', bar(null, { data: LONG, axisLabel: { rotate: -45, interval: 0 } }));
add('K y left + y right + y right offset 60: max per side', {
  xAxis: { type: 'category', data: DAYS },
  yAxis: [{ type: 'value' }, { type: 'value', position: 'right', offset: 0 }, { type: 'value', position: 'right', offset: 60 }],
  series: [{ type: 'bar', data: BIG9 }, { type: 'line', yAxisIndex: 1, data: VALS },
    { type: 'line', yAxisIndex: 2, data: VALS.map(v => v * 1000) }],
});
add('K2 two left y axes, the second offset 70: max per side, not the sum', {
  xAxis: { type: 'category', data: DAYS },
  yAxis: [{ type: 'value' }, { type: 'value', position: 'left', offset: 70 }],
  series: [{ type: 'bar', data: VALS }, { type: 'line', yAxisIndex: 1, data: BIG9 }],
});
add('Z x axis offset 30', bar(null, { offset: 30 }));
add('P x axis on top + inverse y, big9', bar(null, { position: 'top' }, { inverse: true }, BIG9));
add('PM1 port multiaxis fixture: y offset 40, 400x300', {
  xAxis: { type: 'value' }, yAxis: { type: 'value', offset: 40 }, series: [{ type: 'scatter', data: [[1, 2]] }],
}, { W: 400, H: 300 });
add('L grid 0/0/0/0', bar({ left: 0, top: 0, right: 0, bottom: 0 }));
add('M grid px left 20 top 20, 300x200', bar({ left: 20, top: 20, width: 300, height: 200 }));
// The audit's W2 put one 20-line label at 150 with a formatter function; JSON
// has none, so every label is 20 lines, the end labels are hidden, and the
// bottom is high enough that only 150 (normalize .75) overflows: top 47.5 / .75.
// Both ends are hidden outright: left to themselves (or forced on), upstream
// drops an end label or its neighbour for overlapping (fixMinMaxLabelShow);
// interior labels overlap and all stay, since a value axis is never thinned
// by index (label-thinning.js records the label sets).
add('W2 interior y label p=.75 overflows the top: 20-line labels, end labels hidden', {
  grid: { top: 10, bottom: 140 },
  xAxis: { type: 'category', data: DAYS },
  yAxis: { type: 'value', min: 0, max: 200, interval: 50,
    axisLabel: { formatter: '{value}' + '\nx'.repeat(19), showMinLabel: false, showMaxLabel: false } },
  series: [{ type: 'bar', data: VALS }],
});
add('Z12 value x labels overflow right, grid right 0', {
  grid: { right: 0 },
  xAxis: { type: 'value', min: 0, max: 1e9 }, yAxis: { type: 'category', data: DAYS },
  series: [{ type: 'bar', data: VALS.map(v => v * 1e6) }],
});
// The audit's discriminating inverse case, JSON-only: every label is long, the
// end labels are hidden, so 80 (normalize .8, near the LEFT end when inverse)
// and 20 overflow. Unflipped p divides by .2 on both sides, flipped by .8.
add('inverse value x: p is not flipped (discriminating), long labels, end labels hidden', {
  grid: { left: 0, right: 0 },
  xAxis: { type: 'value', inverse: true, min: 0, max: 100, interval: 20,
    axisLabel: { formatter: '{value} eighty-eighty-eighty-eighty-eighty-eighty-eighty', showMinLabel: false, showMaxLabel: false } },
  yAxis: { type: 'category', data: DAYS, axisLabel: { show: false } },
  series: [{ type: 'bar', data: VALS.map(v => v / 3) }],
});
add('AD interval 0 long categories, grid left/right 0: band labels under-shrink',
  bar({ left: 0, right: 0 }, { data: LONG, axisLabel: { interval: 0 } }));
add('n=1 category, a long label, grid left/right 0',
  bar({ left: 0, right: 0 }, { data: ['A single very long category label that overflows both sides of the plot area'] }, null, [1]));
// interval 1 is what the category auto interval picks here; written out so the
// case does not hang on the auto interval (the thinning batch). The bars widen
// the unbanded category extent by half a band (containShape: mapping
// [-0.5, 6.5] from the raw rect's 600 px), so normalize(0) is 0.5/7.
add('boundaryGap false category, long labels, interval 1, grid left/right 0',
  bar({ left: 0, right: 0 }, { boundaryGap: false, data: DAYS.map(d => d + ' long label text'), axisLabel: { interval: 1 } }));
add('log y, grid left 0', {
  grid: { left: 0 }, xAxis: { type: 'category', data: DAYS }, yAxis: { type: 'log' },
  series: [{ type: 'bar', data: [1, 10, 100, 1e3, 1e4, 1e5, 1e6] }],
});
add('inside y labels, big10, grid left 0', bar({ left: 0 }, null, { axisLabel: { inside: true } }, BIG10));
add('Q hidden y axis, big10', bar(null, null, { show: false }, BIG10));
add('Q2 y labels hidden, big10', bar(null, null, { axisLabel: { show: false } }, BIG10));
add('Y1 x ticks 40 + arrow, x labels off, grid 60/0/0/20: ticks and arrows never count',
  bar({ left: 60, right: 0, top: 0, bottom: 20 },
    { axisTick: { length: 40, show: true }, axisLabel: { show: false }, axisLine: { symbol: ['none', 'arrow'] } }));
add('scatter value/value, grid bottom 20: labels end at the edge', scatter({ bottom: 20 }));
add('scatter value/value, grid bottom 19: shrink 1, the tick is not in the gap', scatter({ bottom: 19 }));
add('textMargin 0 on y, grid left 0', bar({ left: 0 }, null, { axisLabel: { textMargin: 0 } }));
add('textMargin [0,10] on y, grid left 0', bar({ left: 0 }, null, { axisLabel: { textMargin: [0, 10] } }));
add('S2 default bar, 300x200', bar(), { W: 300, H: 200 });
add('S3 default bar, 800x600', bar(), { W: 800, H: 600 });
const N = {
  grid: [{ left: 0, right: '55%', top: 0, bottom: 0 }, { left: '55%', right: 0, top: 0, bottom: 0 }],
  xAxis: [{ type: 'category', data: DAYS, gridIndex: 0 }, { type: 'category', data: DAYS, gridIndex: 1 }],
  yAxis: [{ type: 'value', gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
  series: [{ type: 'bar', data: BIG9, xAxisIndex: 0, yAxisIndex: 0 }, { type: 'bar', data: VALS, xAxisIndex: 1, yAxisIndex: 1 }],
};
add('N two grids: grid 0', N);
add('N two grids: grid 1', N, { grid: 1 });

// same: outer = the raw rect
add('G outerBoundsMode same, big9', bar({ outerBoundsMode: 'same' }, null, null, BIG9));
add('G2 outerBoundsMode same, default data', bar({ outerBoundsMode: 'same' }));

// mode edges
add('F outerBoundsMode none, big10', bar({ outerBoundsMode: 'none' }, null, null, BIG10));
add('Z10 outerBoundsMode "foo" is none, big10', bar({ outerBoundsMode: 'foo' }, null, null, BIG10));
add('outerBoundsMode null is auto, big10', bar({ outerBoundsMode: null }, null, null, BIG10));
add('outerBoundsContain "bogus" is all, big10', bar({ outerBoundsContain: 'bogus' }, null, null, BIG10));

// clamp: a percent of the RAW rect
add('O clamp one-sided: the far-edge rule', bar(null, null, { axisLabel: { formatter: X68 } }));
add('O3 clamp two-sided', {
  xAxis: { type: 'category', data: DAYS },
  yAxis: [{ type: 'value', axisLabel: { formatter: '{value} ' + 'X'.repeat(40) } },
    { type: 'value', position: 'right', axisLabel: { formatter: '{value} ' + 'X'.repeat(20) } }],
  series: [{ type: 'bar', data: VALS }, { type: 'line', yAxisIndex: 1, data: VALS }],
});
add('M6 outerBoundsClampWidth 0', bar({ outerBoundsClampWidth: 0 }, null, { axisLabel: { formatter: X68 } }));
add('M7 outerBoundsClampWidth "50%"', bar({ outerBoundsClampWidth: '50%' }, null, { axisLabel: { formatter: X68 } }));
add('M8 outerBoundsClampWidth 100 (px)', bar({ outerBoundsClampWidth: 100 }, null, { axisLabel: { formatter: X68 } }));

// legacy containLabel
add('E containLabel, default data', bar({ containLabel: true }));
add('E2 containLabel, big9', bar({ containLabel: true }, null, null, BIG9));
add('D3 containLabel, big10', bar({ containLabel: true }, null, null, BIG10));
add('L2 containLabel, grid 0/0/0/0', bar({ left: 0, top: 0, right: 0, bottom: 0, containLabel: true }));
add('V containLabel, y show:false, big9: the hidden axis still counts', bar({ containLabel: true }, null, { show: false }, BIG9));
add('CL1 containLabel ignores the offset (y offset 60)', bar({ containLabel: true }, null, { offset: 60 }));
add('CL5 containLabel ignores outerBoundsMode same and outerBounds',
  bar({ containLabel: true, outerBoundsMode: 'same', outerBounds: { left: 200 } }));
add('CL9 containLabel ignores names',
  bar({ containLabel: true }, { name: 'Day of the week' }, { name: 'Revenue', nameLocation: 'middle', nameGap: 60 }));
add('containLabel 1-line x labels, data 1..7 (the 3-line baseline)', bar({ containLabel: true }, null, null, [1, 2, 3, 4, 5, 6, 7]));
add('containLabel 3-line x labels, data 1..7: every line counts',
  bar({ containLabel: true }, { data: DAYS.map(d => d + '\nx\ny') }, null, [1, 2, 3, 4, 5, 6, 7]));
const cats45 = wide => ({ grid: { containLabel: true },
  xAxis: { type: 'category', data: Array.from({ length: 45 }, (_, i) => (i === wide ? 'W'.repeat(20) : 'c' + i)), axisLabel: { rotate: 90 } },
  yAxis: { type: 'value' }, series: [{ type: 'bar', data: Array.from({ length: 45 }, () => 1) }] });
add('containLabel 45 categories rotate 90, the widest at 1: step 2 skips it', cats45(1));
add('containLabel 45 categories rotate 90, the widest at 2: step 2 counts it', cats45(2));
add('CL2 containLabel x labels rotate 45, long categories', bar({ containLabel: true }, { data: LONG, axisLabel: { rotate: 45 } }));
add('CL3 containLabel x axis on top', bar({ containLabel: true }, { position: 'top' }));
add('CL4 containLabel y axis on the right', bar({ containLabel: true }, null, { position: 'right' }));

// documentary: the port tests' own fixtures, none of which shrinks
const documentary = note => ({ documentary: true, note });
add('PM2 documentary: port furniture fixture, y ticks 20, 400x300', {
  xAxis: { type: 'category', data: ['A', 'B'] }, yAxis: { type: 'value', axisTick: { show: true, length: 20 } },
  series: [{ type: 'bar', data: [1, 2] }],
}, Object.assign({ W: 400, H: 300 }, documentary('the furniture tests draw at 400x300; nothing shrinks')));
add('PM3 documentary: port fixture, x labels rotate 90 Wednesday/Thursday, 400x300', {
  xAxis: { type: 'category', data: ['Wednesday', 'Thursday'], axisLabel: { rotate: 90 } }, yAxis: { type: 'value' },
  series: [{ type: 'bar', data: [1, 2] }],
}, Object.assign({ W: 400, H: 300 }, documentary('nothing shrinks')));
add('PM4 documentary: port axislabel fixture, 30 categories, 900x520', {
  xAxis: { type: 'category', data: Array.from({ length: 30 }, (_, i) => 'Category ' + (i + 1)) }, yAxis: { type: 'value' },
  series: [{ type: 'bar', data: Array.from({ length: 30 }, (_, i) => 10 + ((i + 1) * 37) % 50) }],
}, Object.assign({ W: 900, H: 520 }, documentary(
  'nothing shrinks; upstream labels every fourth category (the category auto interval picks 3); the last '
  + 'category\'s label is built off the interval and dropped for that, not for overlapping')));

// axis names (how each name is laid out: axis-names.js)
const NAMED_X = { name: 'Day of the week', nameLocation: 'end' };
const NAMED_Y = { name: 'Revenue in dollars (USD)', nameLocation: 'middle', nameGap: 60 };
add('I names, outerBoundsContain all', bar({ outerBoundsContain: 'all' }, NAMED_X, NAMED_Y));
add('I2 names, outerBoundsContain axisLabel', bar({ outerBoundsContain: 'axisLabel' }, NAMED_X, NAMED_Y));
add('I3 y name middle, big9', bar(null, null, NAMED_Y, BIG9));
add('Z4 y name at the end overflows the top, grid top 10', bar({ top: 10 }, null, { name: 'Revenue (USD)' }));
add('Z6 outerBoundsMode same + names: the name margin level differs per pass',
  bar({ outerBoundsMode: 'same' }, NAMED_X, NAMED_Y));

// label thinning (label-thinning.js records the label sets per pass)
add('AC hideOverlap, interval 0 long categories, grid left/right 0',
  bar({ left: 0, right: 0 }, { data: LONG, axisLabel: { interval: 0, hideOverlap: true } }));
add('B long categories, horizontal: category auto interval', bar(null, { data: LONG }));

// deferred
add('AA label margin 20 + fontSize 14, grid left/bottom 0',
  bar({ left: 0, bottom: 0 }, { axisLabel: { margin: 20, fontSize: 14 } }, { axisLabel: { margin: 20, fontSize: 14 } }),
  deferred('axisLabel.fontSize: the label font is the theme\'s'));
add('truncate: y labels width 40 overflow truncate, big10, grid left 0',
  bar({ left: 0 }, null, { axisLabel: { width: 40, overflow: 'truncate' } }, BIG10),
  deferred('axisLabel.width with overflow truncate is not in the estimate yet'));
add('break: x labels width 60 overflow break, interval 0, long categories',
  bar(null, { data: LONG, axisLabel: { interval: 0, width: 60, overflow: 'break' } }),
  deferred('axisLabel.width with overflow break is not in the estimate yet'));
const BOX = 'the grid box merge and its keywords (left:\'right\', top:\'bottom\', centre without a size) are phase A, a batch of its own';
[
  { width: 300 },
  { right: 20, width: 300 },
  { right: 20 },
  { bottom: 10, height: 100 },
  { height: 100 },
  { left: 'center', width: '50%' },
  { left: 'right', width: 200 },
  { top: 'bottom', height: 100 },
  { left: 'center' },
  { left: 10, right: 10, width: 100 },
].forEach(g => add('box-merge ' + JSON.stringify(g), {
  grid: Object.assign({ outerBoundsMode: 'none' }, g),
  xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: [1, 2] }],
}, deferred(BOX)));

// ---------- run, check and write ----------

{
  const names = new Set();
  for (const c of cases) {
    if (names.has(c.name)) throw new Error('two cases named ' + c.name);
    names.add(c.name);
  }
}

const tally = { shrink: [0, 0], legacy: [0, 0], none: [0, 0] };
const failed = [];
const ulpMax = c => ulp(Math.max(c.W, c.H));

function recordOf(c) {
  const r = runEither(c);
  const rec = { name: c.name, W: c.W, H: c.H, grid: c.grid, option: r.option, mode: r.mode, contain: r.contain };
  rec.outer = hexRect(r.outer);
  rec.outerText = textRect(r.outer);
  rec.clamp = r.clamp ? r.clamp.map(hex) : null;
  rec.clampText = r.clamp ? r.clamp.map(text) : null;
  rec.raw = hexRect(r.raw);
  rec.rawText = textRect(r.raw);
  rec.estimate = r.estimate.map(a => ({
    dim: a.dim,
    index: a.index,
    position: a.position,
    labels: a.labels.map(l => ({ text: l.text, tick: hex(l.tick), tickText: text(l.tick), p: hex(l.p), pText: text(l.p),
      rect: hexRect(l.rect), rectText: textRect(l.rect) })),
    nameRect: a.name ? hexRect(a.name.rect) : null,
    nameRectText: a.name ? textRect(a.name.rect) : null,
    nameP: a.name ? hex(a.name.p) : null,
    namePText: a.name ? text(a.name.p) : null,
  }));
  if (r.legacy) rec.legacy = r.legacy;

  // the self-checks
  let check;
  let minP = 1;
  let margin = null;
  if (r.mode === 'auto' || r.mode === 'same') {
    const s = solveOuterBounds(r.raw, r.outer, r.contain, r.clamp, r.estimate);
    margin = s.margin;
    minP = s.minP;
    check = { kind: 'shrink', ok: sameRect(s.rect, r.rect), got: s.rect };
  } else if (r.mode === 'legacy') {
    const got = legacyContainLabel(r.raw, r.legacy);
    check = { kind: 'legacy', ok: sameRect(got, r.rect), got };
  } else {
    check = { kind: 'none', ok: sameRect(r.raw, r.rect), got: r.raw };
  }
  tally[check.kind][check.ok ? 0 : 1]++;
  rec.margin = margin ? margin.map(hex) : null;
  rec.marginText = margin ? margin.map(text) : null;
  rec.rect = hexRect(r.rect);
  rec.rectText = textRect(r.rect);
  rec.axes = r.axes;
  const tol = 4 * ulpMax(c) / minP;
  rec.tol = hex(tol);
  rec.tolText = text(tol);
  const miss = check.ok ? null : 'the ' + check.kind + ' transcription gives ' + JSON.stringify(textRect(check.got))
    + ', upstream ' + JSON.stringify(textRect(r.rect));
  if (miss) failed.push(c.name + (c.deferred ? ' (deferred anyway)' : '') + ': ' + miss);
  if (c.deferred || miss) {
    rec.deferred = true;
    rec.why = c.deferred ? c.deferred + (miss ? '; and ' + miss : '') : miss;
  }
  if (c.documentary) {
    rec.documentary = true;
    rec.note = c.note;
  }
  if (r.productionBuild) rec.productionBuild = true;
  return rec;
}

const out = {
  source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version,
  ratios: {
    firstCode: FIRST_CODE,
    lastCode: LAST_CODE,
    fontSize: DEFAULT_FONT_SIZE,
    ratio: RATIO.map(hex),
    ratioText: RATIO.map(text),
  },
  measure,
  cases: cases.map(recordOf),
};

// A number JSON.stringify would write as an integer literal past 2^63 goes
// out in exponent form instead: marked in the replacer, unquoted afterwards.
const BIG = 9223372036854775808;
const json = JSON.stringify(out, (k, v) => (typeof v === 'number' && Number.isFinite(v)
  && Math.abs(v) >= BIG && Math.abs(v) < 1e21 ? '@@num:' + v.toExponential() + '@@' : v), 1)
  .replace(/"@@num:([^"@]+)@@"/g, '$1');

const prod = out.cases.filter(c => c.productionBuild).map(c => c.name);
if (prod.length) console.log('through the production build:', prod.join(', '));
failed.forEach(f => console.log('self-check failed: ' + f));
console.log('self-checks: shrink ' + tally.shrink[0] + '/' + (tally.shrink[0] + tally.shrink[1])
  + ', legacy ' + tally.legacy[0] + '/' + (tally.legacy[0] + tally.legacy[1])
  + ', none ' + tally.none[0] + '/' + (tally.none[0] + tally.none[1]));
fs.writeFileSync(OUT, json + '\n');
const d = out.cases.filter(c => c.deferred).length;
console.log('wrote', OUT, (out.cases.length - d) + ' cases + ' + d + ' deferred, '
  + measure.length + ' measured strings');
process.exit(0);
