// Upstream's own answers for EXPORT AND LOADING, batch B11: what getDataURL
// hides and resolves (echarts.ts getDataURL / renderToCanvas, zrender
// canvas/Painter.ts getRenderedCanvas and canvas/Layer.ts clear), and what
// the default loading effect draws and how its spinner turns
// (src/loading/default.ts, showLoading / hideLoading).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true), with
// the CONTROLLED CLOCK of animation.js (the global Date replaced before the
// dist loads; zr.animation.update() stepped by hand) and env.node = false.
//
//   node tools/advchart-oracle/export-loading.js
//
// writes tests/fixtures/advchart-export-loading.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// EXPORT. The SSR painter is the SVG one, and getDataURL takes the SVG branch
// for it. Each export case therefore swaps in a stand-in canvas painter for
// the one call: `type` / getType() answer 'canvas' (renderToCanvas checks
// painter.type in the dev build, getDataURL getType()), and
// getRenderedCanvas(opts) records what echarts.ts handed it -- the background
// (`opts.backgroundColor || model.get('backgroundColor')`) and the pixel
// ratio (`opts.pixelRatio || getDevicePixelRatio()`, which is 1 here: no
// painter dpr, no window) -- and snapshots every view AT THAT MOMENT, while
// the excluded ones have group.ignore set. Its toDataURL records the mime type
// ('image/' + (type || 'png')). Then, transcribed from zrender:
//   final   `opts.backgroundColor || this._backgroundColor` (Painter.ts
//           getRenderedCanvas; the painter's _backgroundColor is what
//           zr.setBackgroundColor(model bg || 'transparent') gave it)
//   paints  Layer.ts doClear: `clearColor && clearColor !== 'transparent'`
//           (a string that is no colour leaves the context's fillStyle at
//           its default, opaque black; 'none' is such a string)
//   image   the Layer's canvas: width = painter width * dpr, height likewise,
//           as a canvas' unsigned long attribute takes them (truncated)
//
// Per export case
//   id, note, W, H, theme (init theme or null), option, opts (as passed, or
//   null for none)
//   views[]    every component view and every chart view, in the instance's
//              own order (_componentsViews, then _chartsViews): kind
//              ('component' | 'series'), mainType, index (componentIndex),
//              type (view type), count (displayables in its group, ignored
//              ones and their subtrees skipped), ignored (group.ignore during
//              the export)
//   present    the sorted main types with a view that drew (count > 0) and
//              was not ignored -- 'series' for any chart view
//   excluded   the sorted main types whose views were ignored
//   restored   every group.ignore back to false afterwards
//   error      the message when getDataURL threw (null otherwise)
//   stuck      main types left ignored after a throw
//   bg         {chosen, zr, final, paints}: chosen as echarts.ts handed it
//              (json, null for undefined), zr the painter's own
//   pixelRatio, imageW, imageH, mime
//
// LOADING. showLoading(name, cfg) at NOW = T0; the effect group is read off
// chart._loadingFX after zr.storage.getDisplayList(true) has run the update.
// Per loading case
//   id, note, W, H, call ({name, cfg} as passed: name may be an object),
//   before (a default showLoading() came first), resize ({width, height}
//   after the show, or null)
//   shown      a loading group is in place (false: an unknown name)
//   z, zlevel  of the mask, the label rect and the arc
//   mask       {x, y, width, height, fill}
//   rect       the label rect: {x, y, width, height}
//   arc        {cx, cy, r, startAngle, endAngle, clockwise, stroke,
//              lineWidth, lineCap} or null without a spinner
//   text       {text, x, y (its transform's translation), align,
//              verticalAlign, font, fill, rect (getBoundingRect: x y w h)}
//   numbers are hex (16 hex digits of the double, big-endian) with a Text
//   twin
//
// TIMELINES. The spinner is two looping animators on the arc's shape
// (`animateShape(true).when(1000, {endAngle: 3pi/2}).start('circularInOut')`,
// and the same on startAngle with delay(300)). Their clips take their start
// at the FIRST step after the show (Clip.step), which is the first frame:
// here an update at NOW = T0 right after showLoading. Each timeline lists
// the clock offsets of its steps (`steps`, ms after T0), and at each step the
// arc's startAngle / endAngle (hex) and the clip count; a hide and a show
// can sit between steps (`events`).
//
// guards[]  the transcriptions (the layout formula, Clip.step with the loop's
//           remainder, circularInOut) are checked against every record, and
//           each named mutation of them must change the named records.
// ---------------------------------------------------------------------------

const fs = require('fs');
const path = require('path');

// ---------- the controlled clock (must precede loading the dist) ----------
const RealDate = Date;
const T_BASE = 1700000000000;
let NOW = T_BASE;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-export-loading.json');

echarts.env.node = false;

const W = 400;
const H = 300;

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
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const num = v => ({ hex: hex(v), text: text(v) });
const json = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
const isObj = v => v !== null && typeof v === 'object' && !Array.isArray(v);

// ============================================================================
// Export
// ============================================================================
const GRAD = { type: 'linear', x: 0, y: 0, x2: 1, y2: 0,
  colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] };

const OPT_FULL = {
  animation: false,
  title: { text: 'Sales', left: 'center' },
  legend: { top: 30 },
  tooltip: { trigger: 'axis' },
  grid: { top: 70, bottom: 80 },
  xAxis: { type: 'category', data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'] },
  yAxis: { type: 'value' },
  dataZoom: [{ type: 'slider', bottom: 10 }, { type: 'inside' }],
  visualMap: { type: 'continuous', min: 0, max: 300, dimension: 1, seriesIndex: 1, right: 0, top: 'middle' },
  series: [
    { name: 'A', type: 'bar', data: [120, 200, 150, 80, 70],
      markPoint: { data: [{ type: 'max' }] }, markLine: { data: [{ type: 'average' }] } },
    { name: 'B', type: 'line', data: [220, 182, 191, 234, 290],
      markArea: { data: [[{ xAxis: 'Tue' }, { xAxis: 'Wed' }]] } },
  ],
};
const OPT_RADAR = {
  animation: false,
  title: { text: 'Radar' },
  legend: { bottom: 5 },
  radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }] },
  series: [{ name: 'R', type: 'radar', data: [{ name: 'R', value: [3, 6, 9] }] }],
};
const OPT_CAL = {
  animation: false,
  visualMap: { type: 'piecewise', min: 0, max: 10, orient: 'horizontal', left: 'center', bottom: 5 },
  calendar: { range: '2024-01', cellSize: [20, 20], top: 60 },
  series: [{ type: 'heatmap', coordinateSystem: 'calendar',
    data: [['2024-01-02', 3], ['2024-01-09', 7], ['2024-01-20', 9]] }],
};
const OPT_PLAIN = {
  animation: false,
  xAxis: { type: 'category', data: ['a', 'b', 'c'] },
  yAxis: { type: 'value' },
  series: [{ type: 'bar', data: [3, 5, 2] }],
};
const OPT_AXES = {
  animation: false,
  xAxis: { type: 'category', data: ['a', 'b', 'c'] },
  yAxis: { type: 'value', min: 0, max: 10 },
  series: [],
};
const withBg = (opt, bg) => Object.assign({}, opt, { backgroundColor: bg });

const EXPORT_CASES = [
  { id: 'full-none', option: OPT_FULL, opts: null, note: 'no opts: nothing hidden, the model has no backgroundColor' },
  { id: 'full-empty-list', option: OPT_FULL, opts: { excludeComponents: [] } },
  { id: 'full-title', option: OPT_FULL, opts: { excludeComponents: ['title'] } },
  { id: 'full-legend', option: OPT_FULL, opts: { excludeComponents: ['legend'] } },
  { id: 'full-xaxis', option: OPT_FULL, opts: { excludeComponents: ['xAxis'] } },
  { id: 'full-axes', option: OPT_FULL, opts: { excludeComponents: ['yAxis', 'xAxis'] } },
  { id: 'full-datazoom', option: OPT_FULL, opts: { excludeComponents: ['dataZoom'] }, note: 'both dataZoom models; only the slider draws' },
  { id: 'full-visualmap', option: OPT_FULL, opts: { excludeComponents: ['visualMap'] } },
  { id: 'full-markpoint', option: OPT_FULL, opts: { excludeComponents: ['markPoint'] } },
  { id: 'full-markline-area', option: OPT_FULL, opts: { excludeComponents: ['markLine', 'markArea'] } },
  { id: 'full-nondrawing', option: OPT_FULL, opts: { excludeComponents: ['tooltip', 'axisPointer', 'grid'] },
    note: 'views whose groups hold nothing: the picture does not change' },
  { id: 'full-everything', option: OPT_FULL,
    opts: { excludeComponents: ['legend', 'title', 'dataZoom', 'visualMap', 'markPoint', 'markLine', 'markArea', 'xAxis', 'yAxis'] } },
  { id: 'full-absent', option: OPT_FULL, opts: { excludeComponents: ['toolbox', 'foo', 'radar'] }, note: 'types with no model hide nothing' },
  { id: 'full-string', option: OPT_FULL, opts: { excludeComponents: 'legend' },
    note: 'a string is iterated as array-like: one-letter main types, none of which exist' },
  { id: 'full-twice', option: OPT_FULL, opts: { excludeComponents: ['legend', 'legend'] } },
  { id: 'full-series', option: OPT_FULL, opts: { excludeComponents: ['series'] },
    note: 'a series view is not in _componentsMap: view.group throws' },
  { id: 'full-legend-series', option: OPT_FULL, opts: { excludeComponents: ['legend', 'series'] },
    note: 'the throw leaves the legend ignored for good' },
  { id: 'radar-none', option: OPT_RADAR, opts: null },
  { id: 'radar-radar', option: OPT_RADAR, opts: { excludeComponents: ['radar'] } },
  { id: 'cal-none', option: OPT_CAL, opts: null },
  { id: 'cal-calendar', option: OPT_CAL, opts: { excludeComponents: ['calendar', 'visualMap'] } },
  { id: 'axes-none', option: OPT_AXES, opts: null },
  { id: 'axes-both', option: OPT_AXES, opts: { excludeComponents: ['xAxis', 'yAxis'] } },
  // the background
  { id: 'bg-unset', option: OPT_PLAIN, opts: {}, note: 'neither: the painter clears to transparent' },
  { id: 'bg-opts-hex', option: OPT_PLAIN, opts: { backgroundColor: '#123456' } },
  { id: 'bg-opts-rgba', option: OPT_PLAIN, opts: { backgroundColor: 'rgba(255,0,0,0.5)' } },
  { id: 'bg-opts-transparent', option: OPT_PLAIN, opts: { backgroundColor: 'transparent' } },
  { id: 'bg-opts-none', option: OPT_PLAIN, opts: { backgroundColor: 'none' }, note: 'no colour: fillStyle keeps its default black' },
  { id: 'bg-opts-zero-alpha', option: OPT_PLAIN, opts: { backgroundColor: 'rgba(0,0,0,0)' } },
  { id: 'bg-opts-empty', option: withBg(OPT_PLAIN, '#abcdef'), opts: { backgroundColor: '' }, note: "'' is falsy: the option's" },
  { id: 'bg-opts-bad', option: OPT_PLAIN, opts: { backgroundColor: 'notacolor' } },
  { id: 'bg-opts-gradient', option: OPT_PLAIN, opts: { backgroundColor: GRAD } },
  { id: 'bg-option', option: withBg(OPT_PLAIN, '#abcdef'), opts: {} },
  { id: 'bg-opts-over-option', option: withBg(OPT_PLAIN, '#abcdef'), opts: { backgroundColor: '#000000' } },
  { id: 'bg-option-transparent', option: withBg(OPT_PLAIN, 'transparent'), opts: {} },
  { id: 'bg-option-gradient', option: withBg(OPT_PLAIN, GRAD), opts: null },
  { id: 'bg-theme-dark', option: OPT_PLAIN, opts: {}, theme: 'dark', note: 'the dark theme writes the model backgroundColor' },
  // the pixel ratio and the type
  { id: 'pr-2', option: OPT_PLAIN, opts: { pixelRatio: 2 } },
  { id: 'pr-1.5', option: OPT_PLAIN, opts: { pixelRatio: 1.5 } },
  { id: 'pr-0', option: OPT_PLAIN, opts: { pixelRatio: 0 }, note: '0 is falsy: the device ratio' },
  { id: 'pr-0.5', option: OPT_PLAIN, opts: { pixelRatio: 0.5 } },
  { id: 'pr-odd', option: OPT_PLAIN, opts: { pixelRatio: 1.3 }, W: 333, H: 217 },
  { id: 'type-jpeg', option: OPT_PLAIN, opts: { type: 'jpeg', backgroundColor: 'transparent' } },
  { id: 'type-svg', option: OPT_PLAIN, opts: { type: 'svg' }, note: 'in the canvas renderer: toDataURL("image/svg"), which a browser answers with PNG' },
  { id: 'type-png', option: OPT_PLAIN, opts: { type: 'png', pixelRatio: 3 } },
];

function groupCount(g) {
  let n = 0;
  (function walk(e) {
    if (e.ignore) return;
    if (e.isGroup) { e.eachChild(walk); return; }
    n++;
  })(g);
  return n;
}

function viewsOf(chart) {
  const out = [];
  for (const v of chart._componentsViews) {
    const m = v.__model;
    out.push({ kind: 'component', mainType: m ? m.mainType : null, index: m ? m.componentIndex : null,
      type: v.type, count: groupCount(v.group), ignored: !!v.group.ignore });
  }
  for (const v of chart._chartsViews) {
    const m = v.__model;
    out.push({ kind: 'series', mainType: 'series', index: m ? m.componentIndex : null,
      type: v.type, count: groupCount(v.group), ignored: !!v.group.ignore });
  }
  return out;
}
const uniqSorted = a => Array.from(new Set(a)).sort();

function readExport(cs) {
  const w = cs.W || W;
  const h = cs.H || H;
  const chart = echarts.init(null, cs.theme || null, { renderer: 'svg', ssr: true, width: w, height: h });
  try {
    chart.setOption(JSON.parse(JSON.stringify(cs.option)));
    chart.getZr().storage.getDisplayList(true);
    const painter = chart.getZr().painter;
    let seen = null;
    let mime = null;
    painter.type = 'canvas';
    painter.getType = () => 'canvas';
    painter.getRenderedCanvas = o => {
      seen = { opts: o, views: viewsOf(chart) };
      return { toDataURL: t => { mime = t; return 'data:'; } };
    };
    let error = null;
    try {
      chart.getDataURL(cs.opts === null ? undefined : JSON.parse(JSON.stringify(cs.opts)));
    } catch (e) {
      error = e.message;
    }
    const after = viewsOf(chart);
    const zrBg = painter._backgroundColor;
    const rec = { id: cs.id, note: cs.note || null, W: w, H: h, theme: cs.theme || null, option: cs.option, opts: cs.opts,
      error, stuck: uniqSorted(after.filter(v => v.ignored).map(v => v.mainType)) };
    if (seen) {
      rec.views = seen.views;
      rec.present = uniqSorted(seen.views.filter(v => v.count > 0 && !v.ignored).map(v => v.mainType));
      rec.excluded = uniqSorted(seen.views.filter(v => v.ignored).map(v => v.mainType));
      rec.restored = after.every(v => !v.ignored);
      const chosen = seen.opts.backgroundColor;
      const final = chosen || zrBg;
      rec.bg = { chosen: json(chosen), zr: json(zrBg), final: json(final),
        paints: !!(final && final !== 'transparent') };
      rec.pixelRatio = seen.opts.pixelRatio;
      rec.imageW = Math.floor(w * seen.opts.pixelRatio);
      rec.imageH = Math.floor(h * seen.opts.pixelRatio);
      rec.mime = mime;
    } else {
      rec.views = viewsOf(chart);
      rec.present = null;
      rec.excluded = null;
      rec.restored = null;
      rec.bg = null;
      rec.pixelRatio = null;
      rec.imageW = null;
      rec.imageH = null;
      rec.mime = null;
    }
    return rec;
  } finally {
    chart.dispose();
  }
}

// the transcription of the background chain (echarts.ts + Painter.ts + Layer.ts)
function bgTranscribe(rec, mut) {
  const opts = rec.opts || {};
  const modelBg = rec.theme === 'dark' ? rec.bg.zr : (rec.option.backgroundColor);
  const chosen = mut.optionFirst ? (modelBg || opts.backgroundColor) : (opts.backgroundColor || modelBg);
  const zrBg = modelBg || 'transparent';
  const final = mut.noZrFallback ? chosen : (chosen || zrBg);
  const paints = mut.transparentPaints ? !!final : !!(final && final !== 'transparent');
  const pr = mut.prDefault2 ? (opts.pixelRatio || 2) : (opts.pixelRatio || 1);
  const iw = mut.roundSize ? Math.round(rec.W * pr) : Math.floor(rec.W * pr);
  return { chosen: json(chosen), final: json(final), paints, pr, iw };
}
function bgDiff(rec, mut) {
  if (!rec.bg) return [];
  const t = bgTranscribe(rec, mut);
  const d = [];
  if (JSON.stringify(t.chosen) !== JSON.stringify(rec.bg.chosen)) d.push('chosen');
  if (JSON.stringify(t.final) !== JSON.stringify(rec.bg.final)) d.push('final');
  if (t.paints !== rec.bg.paints) d.push('paints');
  if (t.pr !== rec.pixelRatio) d.push('pixelRatio');
  if (t.iw !== rec.imageW) d.push('imageW');
  return d;
}

// ============================================================================
// Loading
// ============================================================================
const LOADING_CASES = [
  { id: 'default', call: { cfg: undefined } },
  { id: 'text-empty', call: { cfg: { text: '' } }, note: 'no text: the spinner alone, 5 px left of centre' },
  { id: 'no-spinner', call: { cfg: { showSpinner: false } } },
  { id: 'no-spinner-no-text', call: { cfg: { showSpinner: false, text: '' } } },
  { id: 'custom', call: { cfg: { text: 'Please wait', fontSize: 20, fontWeight: 'bold', spinnerRadius: 16, lineWidth: 3,
    color: '#c23531', textColor: 'red', maskColor: 'rgba(0,0,0,0.5)' } } },
  { id: 'odd-size', call: { cfg: {} }, W: 333, H: 217 },
  { id: 'font-px-string', call: { cfg: { fontSize: '18px' } } },
  { id: 'font-num-string', call: { cfg: { fontSize: '14' } } },
  { id: 'text-number', call: { cfg: { text: 42 } } },
  { id: 'radius-zero', call: { cfg: { spinnerRadius: 0 } } },
  { id: 'radius-frac', call: { cfg: { spinnerRadius: 7.3, text: 'abc' } }, W: 401, H: 299 },
  { id: 'spinner-truthy', call: { cfg: { showSpinner: 1 } } },
  { id: 'spinner-falsy', call: { cfg: { showSpinner: 0 } } },
  { id: 'cjk', call: { cfg: { text: '加载中…' } } },
  { id: 'multiline', call: { cfg: { text: 'loading\nplease wait' } } },
  { id: 'null-keys', call: { cfg: { text: null, fontSize: null, showSpinner: null, spinnerRadius: null } },
    note: 'zrUtil.defaults fills a null key' },
  { id: 'mono', call: { cfg: { fontFamily: 'monospace' } } },
  { id: 'zlevel', call: { cfg: { zlevel: 2 } } },
  { id: 'name-object', call: { name: { text: 'x' } }, note: 'an object as the name is the cfg' },
  { id: 'name-default', call: { name: 'default', cfg: { text: 'y' } } },
  { id: 'name-unknown', call: { name: 'nope', cfg: { text: 'z' } }, before: true,
    note: 'hideLoading runs first: the default one shown before is gone and nothing replaces it' },
  { id: 'resize', call: { cfg: {} }, resize: { width: 520, height: 180 } },
  { id: 'small', call: { cfg: {} }, W: 60, H: 40, note: 'narrower than the text: cx goes negative' },
  { id: 'text-sum-order', call: { cfg: { spinnerRadius: 7.3 } }, W: 315, H: 200,
    note: 'rect.x + (distance + width) and (rect.x + distance) + width differ here' },
];

function shapeRec(o, keys) {
  const r = {};
  for (const k of keys) r[k] = typeof o[k] === 'number' ? num(o[k]) : o[k];
  return r;
}

function readLoading(cs) {
  const w = cs.W || W;
  const h = cs.H || H;
  NOW = T_BASE;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: w, height: h });
  chart._ssr = false;
  try {
    chart.setOption({ animation: false, series: [] });
    if (cs.before) chart.showLoading();
    const c = cs.call;
    // a copy each: zrUtil.defaults writes the defaults into the cfg it is
    // handed, and the record keeps the call as written
    const copy = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
    if (c.name !== undefined) chart.showLoading(copy(c.name), copy(c.cfg));
    else chart.showLoading(copy(c.cfg));
    if (cs.resize) chart.resize(cs.resize);
    const zr = chart.getZr();
    zr.storage.getDisplayList(true);
    const fx = chart._loadingFX;
    const rec = { id: cs.id, note: cs.note || null, W: w, H: h, call: c, before: !!cs.before, resize: cs.resize || null, shown: !!fx };
    if (!fx) return rec;
    must(fx.childCount() === 2 || fx.childCount() === 3, cs.id + ': children');
    const mask = fx.childAt(0);
    const rect = fx.childAt(1);
    const arc = fx.childCount() === 3 ? fx.childAt(2) : null;
    const t = rect.getTextContent();
    const tr = t.transform || [1, 0, 0, 1, 0, 0];
    must(tr[0] === 1 && tr[1] === 0 && tr[2] === 0 && tr[3] === 1, cs.id + ': the text is only moved');
    const br = t.getBoundingRect();
    rec.z = { mask: mask.z, rect: rect.z, arc: arc ? arc.z : null, text: t.z };
    rec.zlevel = { mask: mask.zlevel, rect: rect.zlevel, arc: arc ? arc.zlevel : null, text: t.zlevel };
    rec.mask = Object.assign(shapeRec(mask.shape, ['x', 'y', 'width', 'height']), { fill: json(mask.style.fill) });
    rec.rect = shapeRec(rect.shape, ['x', 'y', 'width', 'height']);
    rec.rectFill = json(rect.style.fill);
    rec.arc = arc ? Object.assign(shapeRec(arc.shape, ['cx', 'cy', 'r', 'startAngle', 'endAngle']), {
      clockwise: arc.shape.clockwise, stroke: json(arc.style.stroke), lineWidth: json(arc.style.lineWidth),
      lineCap: json(arc.style.lineCap) }) : null;
    const spans = (t.childrenRef ? t.childrenRef() : t._children) || [];
    must(spans.every(sp => sp.type === 'tspan'), cs.id + ': the text is tspans');
    const sp0 = spans.length ? spans[0].style : {};
    rec.text = { text: json(t.style.text), x: num(tr[4]), y: num(tr[5]), align: json(sp0.textAlign),
      verticalAlign: json(sp0.textBaseline), font: json(sp0.font), fill: json(t.style.fill),
      spans: spans.map(sp => ({ text: sp.style.text, x: num(sp.style.x), y: num(sp.style.y) })),
      fontSize: json(t.style.fontSize), fontWeight: json(t.style.fontWeight), fontFamily: json(t.style.fontFamily),
      rect: [num(br.x), num(br.y), num(br.width), num(br.height)] };
    // the facts the transcription is fed
    rec._facts = { w: chart.getWidth(), h: chart.getHeight(), tw: br.width, cfg: c };
    return rec;
  } finally {
    chart.dispose();
  }
}

// the transcription of default.ts: the cfg after zrUtil.defaults, and resize()
function loadingCfg(c) {
  let cfg = c.name !== undefined && isObj(c.name) ? c.name : c.cfg;
  cfg = Object.assign({}, cfg || {});
  const def = { text: 'loading', fontSize: 12, showSpinner: true, spinnerRadius: 10, lineWidth: 5, zlevel: 0 };
  for (const k of Object.keys(def)) if (cfg[k] == null) cfg[k] = def[k];
  return cfg;
}
function layoutTranscribe(rec, mut) {
  const f = rec._facts;
  const o = loadingCfg(f.cfg);
  const tw = f.tw;
  const r = o.showSpinner ? o.spinnerRadius : 0;
  const gap = mut.noGap ? 0 : 10;
  const cx = (f.w - r * 2 - (o.showSpinner && tw ? gap : 0) - tw) / 2
    - (o.showSpinner && tw ? 0 : (mut.noFive ? 0 : 5) + tw / 2)
    + (o.showSpinner ? 0 : tw / 2)
    + (tw ? 0 : r);
  const cy = mut.cyRound ? Math.round(f.h / 2) : f.h / 2;
  const rect = { x: cx - r, y: cy - r, width: r * 2, height: r * 2 };
  const dist = mut.distance5 ? 5 : 10;
  // calculateTextPosition, 'right': x += distance + width, y += height / 2
  let tx = rect.x;
  let ty = rect.y;
  if (mut.textAtCentre) { tx = cx; } else if (mut.sumOrder) { tx = tx + dist + rect.width; } else { tx += dist + rect.width; }
  ty += rect.height / 2;
  return { cx, cy, rect, tx, ty };
}
function layoutDiff(rec, mut) {
  if (!rec.shown) return [];
  const t = layoutTranscribe(rec, mut);
  const d = [];
  if (hex(t.rect.x) !== rec.rect.x.hex || hex(t.rect.y) !== rec.rect.y.hex
    || hex(t.rect.width) !== rec.rect.width.hex || hex(t.rect.height) !== rec.rect.height.hex) d.push('rect');
  if (rec.arc && (hex(t.cx) !== rec.arc.cx.hex || hex(t.cy) !== rec.arc.cy.hex)) d.push('arc');
  if (hex(t.tx) !== rec.text.x.hex || hex(t.ty) !== rec.text.y.hex) d.push('text');
  if (rec.mask.width.hex !== hex(rec._facts.w) || rec.mask.height.hex !== hex(rec._facts.h)) d.push('mask');
  return d;
}

// ---------- timelines ----------
const SPARSE = [0, 1, 16, 50, 100, 250, 299, 300, 301, 500, 750, 999, 1000, 1001, 1100, 1299, 1300, 1301, 1500,
  1999, 2000, 2001, 2299, 2300, 2500, 3333, 3500, 5000, 7777, 7900, 10007];
function framesTo(end, step) {
  const a = [];
  for (let t = 0; t <= end; t += step) a.push(t);
  return a;
}
const TIMELINES = [
  { id: 'sparse', steps: SPARSE, note: 'sparse steps: a loop restarts from its remainder at the step that ends it' },
  { id: 'frames16', steps: framesTo(3200, 16), note: 'a step every 16 ms' },
  { id: 'frames-odd', steps: framesTo(4000, 37), note: 'a step every 37 ms' },
  { id: 'rehide', steps: [0, 100, 400, 1200, 2500, 4000, 4016, 4100, 4300, 4400, 5000, 5300, 6000],
    events: [{ before: 2500, op: 'hide' }, { before: 4000, op: 'show' }],
    note: 'hidden before 2500, shown again before 4000: a fresh arc whose clips start at the 4000 step' },
  { id: 'late-first', steps: [40, 60, 340, 1040, 1340], note: 'the first frame comes 40 ms after the show' },
];

function readTimeline(tl) {
  NOW = T_BASE;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption({ animation: false, series: [] });
    chart.showLoading();
    const zr = chart.getZr();
    const out = [];
    const events = (tl.events || []).slice();
    for (const s of tl.steps) {
      while (events.length && events[0].before <= s) {
        const ev = events.shift();
        NOW = T_BASE + ev.before;
        if (ev.op === 'hide') chart.hideLoading();
        else chart.showLoading();
      }
      NOW = T_BASE + s;
      zr.animation.update();
      const fx = chart._loadingFX;
      let clips = 0;
      for (let c = zr.animation._head; c; c = c.next) clips++;
      if (!fx) {
        out.push({ t: s, shown: false, clips });
        continue;
      }
      const arc = fx.childAt(2);
      out.push({ t: s, shown: true, clips, start: hex(arc.shape.startAngle), end: hex(arc.shape.endAngle),
        startText: text(arc.shape.startAngle), endText: text(arc.shape.endAngle) });
    }
    return { id: tl.id, note: tl.note, steps: tl.steps, events: tl.events || [], samples: out };
  } finally {
    chart.dispose();
  }
}

// the transcription: Clip.step (loop, remainder, delay at the first step),
// circularInOut, the tracks' (to - from) * w + from
function circularInOut(k) {
  if ((k *= 2) < 1) return -0.5 * (Math.sqrt(1 - k * k) - 1);
  return 0.5 * (Math.sqrt(1 - (k -= 2) * k) + 1);
}
function makeClip(delay, mut) {
  return { delay: mut.noDelay ? 0 : delay, inited: false, start: 0 };
}
function clipStep(c, g, mut) {
  if (!c.inited) { c.start = g + c.delay; c.inited = true; }
  const life = 1000;
  const elapsed = g - c.start;
  let p = elapsed / life;
  if (p < 0) p = 0;
  p = Math.min(p, 1);
  const e = mut.linear ? p : circularInOut(p);
  if (p === 1) c.start = mut.noRemainder ? g : g - elapsed % life;
  return e;
}
function timelineTranscribe(tl, mut) {
  const PI = Math.PI;
  const s0 = -PI / 2;
  const e0 = -PI / 2 + 0.1;
  const to = PI * 3 / 2;
  let clips = null;
  const out = [];
  const events = (tl.events || []).slice();
  let shown = true;
  const fresh = () => ({ end: makeClip(0, mut), start: makeClip(300, mut), s: s0, e: e0 });
  clips = fresh();
  for (const t of tl.steps) {
    while (events.length && events[0].before <= t) {
      const ev = events.shift();
      if (ev.op === 'hide') shown = false;
      else { shown = true; clips = fresh(); }
    }
    if (!shown) { out.push({ t, shown: false }); continue; }
    const we = clipStep(clips.end, t, mut);
    clips.e = (to - e0) * we + e0;
    const ws = clipStep(clips.start, t, mut);
    clips.s = (to - s0) * ws + s0;
    out.push({ t, shown: true, start: hex(clips.s), end: hex(clips.e) });
  }
  return out;
}
function timelineDiff(rec, tl, mut) {
  const t = timelineTranscribe(tl, mut);
  const d = [];
  for (let i = 0; i < t.length; i++) {
    const a = t[i];
    const b = rec.samples[i];
    if (a.shown !== b.shown) { d.push(a.t + ': shown'); continue; }
    if (!a.shown) continue;
    if (a.start !== b.start || a.end !== b.end) d.push(a.t + ': angles');
  }
  return d;
}

// ============================================================================
// Generation, checks and guards
// ============================================================================
function strip(o) {
  if (Array.isArray(o)) return o.map(strip);
  if (isObj(o)) {
    const r = {};
    for (const k of Object.keys(o)) if (!k.startsWith('_')) r[k] = strip(o[k]);
    return r;
  }
  return o;
}

const GUARDS = [
  { id: 'option-first', mutation: 'the option\'s backgroundColor wins over the opts\'', mut: { optionFirst: true }, named: ['bg-opts-over-option'] },
  { id: 'no-zr-fallback', mutation: 'no fallback to the painter\'s own background', mut: { noZrFallback: true }, named: ['bg-unset'] },
  { id: 'transparent-paints', mutation: '\'transparent\' is painted like a colour', mut: { transparentPaints: true }, named: ['bg-unset', 'bg-opts-transparent'] },
  { id: 'pr-default-2', mutation: 'the default pixel ratio is 2', mut: { prDefault2: true }, named: ['bg-unset', 'pr-0'] },
  { id: 'round-size', mutation: 'the image size is rounded, not truncated', mut: { roundSize: true }, named: ['pr-odd'] },
  { id: 'no-gap', mutation: 'no 10 px between the spinner and the text', mut: { noGap: true }, named: ['default', 'custom'] },
  { id: 'no-five', mutation: 'no 5 px shift without a text or a spinner', mut: { noFive: true }, named: ['text-empty', 'no-spinner'] },
  { id: 'cy-round', mutation: 'the centre height is rounded', mut: { cyRound: true }, named: ['odd-size'] },
  { id: 'distance-5', mutation: 'the text sits 5 px off the label rect', mut: { distance5: true }, named: ['default', 'no-spinner'] },
  { id: 'text-sum-order', mutation: 'the text anchor adds the distance first', mut: { sumOrder: true }, named: ['text-sum-order'] },
  { id: 'text-at-centre', mutation: 'the text starts at the spinner centre', mut: { textAtCentre: true }, named: ['default'] },
  { id: 'no-delay', mutation: 'the startAngle loop is not delayed', mut: { noDelay: true }, named: ['sparse', 'frames16'] },
  { id: 'no-remainder', mutation: 'a loop restarts at the step that ends it', mut: { noRemainder: true }, named: ['sparse', 'frames-odd'] },
  { id: 'linear', mutation: 'the easing is linear', mut: { linear: true }, named: ['sparse', 'frames16', 'rehide', 'late-first'] },
];

function build() {
  const exports = EXPORT_CASES.map(readExport);
  const loading = LOADING_CASES.map(readLoading);
  const timelines = TIMELINES.map(readTimeline);
  // the transcriptions reproduce every record
  for (const r of exports) must(!bgDiff(r, {}).length, r.id + ': the background transcription: ' + bgDiff(r, {}).join(', '));
  for (const r of loading) must(!layoutDiff(r, {}).length, r.id + ': the layout transcription: ' + layoutDiff(r, {}).join(', '));
  for (let i = 0; i < timelines.length; i++) {
    const d = timelineDiff(timelines[i], TIMELINES[i], {});
    must(!d.length, timelines[i].id + ': the timeline transcription: ' + d.slice(0, 5).join(', '));
  }
  // anchors
  const ex = id => exports.find(r => r.id === id);
  const ld = id => loading.find(r => r.id === id);
  must(ex('full-none').present.join() === 'dataZoom,legend,markArea,markLine,markPoint,series,title,visualMap,xAxis,yAxis',
    'full-none present: ' + ex('full-none').present.join());
  must(ex('full-legend').excluded.join() === 'legend' && !ex('full-legend').present.includes('legend'), 'the legend hidden');
  must(ex('full-legend').restored, 'restored');
  must(ex('full-series').error !== null, 'series throws');
  must(ex('full-legend-series').stuck.join() === 'legend', 'the legend stuck');
  must(ex('full-nondrawing').present.join() === ex('full-none').present.join(), 'the non-drawing views change nothing');
  must(ex('full-string').excluded.length === 0, 'a string hides nothing');
  must(ex('bg-unset').bg.final === 'transparent' && !ex('bg-unset').bg.paints, 'unset is transparent');
  must(ex('bg-opts-none').bg.paints, "'none' paints (black)");
  must(ex('bg-theme-dark').bg.chosen !== null, 'the dark theme bg');
  must(ex('pr-2').imageW === 800 && ex('pr-odd').imageW === 432, 'image sizes');
  must(ex('type-jpeg').mime === 'image/jpeg' && ex('full-none').mime === 'image/png', 'mime');
  must(ld('default').text.text === 'loading' && ld('default').text.align === 'left'
    && ld('default').text.verticalAlign === 'middle', 'the default text');
  must(ld('default').z.mask === 10000 && ld('default').z.arc === 10001, 'z');
  must(ld('no-spinner').arc === null && ld('spinner-falsy').arc === null && ld('spinner-truthy').arc !== null, 'showSpinner');
  must(!ld('name-unknown').shown, 'an unknown name shows nothing');
  must(ld('text-number').text.text === 42, 'a number text stays a number');
  must(ld('resize').mask.width.text === '520', 'resize');
  const guards = GUARDS.map(gd => {
    const changed = [];
    for (const r of exports) if (bgDiff(r, gd.mut).length) changed.push(r.id);
    for (const r of loading) if (layoutDiff(r, gd.mut).length) changed.push(r.id);
    for (let i = 0; i < timelines.length; i++) if (timelineDiff(timelines[i], TIMELINES[i], gd.mut).length) changed.push(timelines[i].id);
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(n => changed.includes(n)) };
  });
  return {
    source: 'ECharts 6.1 dist (' + path.basename(DIST) + '), SVG SSR with a stand-in canvas painter for getDataURL; a controlled clock for the spinner',
    W, H,
    clock: { T0: T_BASE, note: 'showLoading at T0; the first zr.animation.update() of a timeline is its first step' },
    envNodeFlipped: true,
    api: {
      getDataURL: 'each excludeComponents type: every model of it, its view (_componentsMap[__viewId]) group.ignore = true unless already; renderToCanvas; then ignore = false on the ones it set',
      renderToCanvas: 'backgroundColor: opts.backgroundColor || model.get(\'backgroundColor\'); pixelRatio: opts.pixelRatio || getDevicePixelRatio()',
      getRenderedCanvas: 'a new Layer at pixelRatio (canvas width = painter width * dpr), cleared with opts.backgroundColor || the painter\'s own (model bg || \'transparent\')',
      layerClear: 'clearRect; then, when clearColor && clearColor !== \'transparent\', fillRect with it (a gradient against {0, 0, w, h} in canvas pixels; a string that is no colour leaves fillStyle at #000000)',
      loading: 'zrUtil.defaults(cfg, {text: \'loading\', textColor: tokens.color.primary, fontSize: 12, fontWeight: \'normal\', fontStyle: \'normal\', fontFamily: \'sans-serif\', maskColor: \'rgba(255,255,255,0.8)\', showSpinner: true, color: tokens.color.theme[0], spinnerRadius: 10, lineWidth: 5, zlevel: 0}); mask z 10000, label rect and arc z 10001; the text is the label rect\'s textContent at position right, distance 10',
      resize: 'r = showSpinner ? spinnerRadius : 0; cx = (W - 2r - (showSpinner && tw ? 10 : 0) - tw) / 2 - (showSpinner && tw ? 0 : 5 + tw / 2) + (showSpinner ? 0 : tw / 2) + (tw ? 0 : r); cy = H / 2; label rect (cx - r, cy - r, 2r, 2r); mask (0, 0, W, H)',
      spinner: 'arc startAngle -PI/2, endAngle -PI/2 + 0.1, lineCap round; animateShape(true).when(1000, {endAngle: PI*3/2}).start(\'circularInOut\'); animateShape(true).when(1000, {startAngle: PI*3/2}).delay(300).start(\'circularInOut\')',
    },
    notes: [
      'excludeComponents never reaches the axis pointer, a richText tooltip or the loading effect: they are added to zr directly, not to a view group.',
      'An html tooltip is a DOM node and never in a canvas export.',
      'showLoading(name) with an unknown name has already hidden the loading shown before.',
    ],
    exports: strip(exports),
    loading: strip(loading),
    timelines,
    guards,
  };
}

// the compact writer of palette-fill.js
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
console.log(g1.exports.length + ' export cases, ' + g1.loading.length + ' loading cases, ' + g1.timelines.length
  + ' timelines; ' + (g1.guards.length - bad.length) + '/' + g1.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
