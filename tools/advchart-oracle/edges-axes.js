/*
Upstream's own answers for fix batch R5-G (spec section 244): THE AXES'
EDGES AND THE RESIDUALS OF THE ROUND.

  grid      GridView.render: when gridModel.get('show') is truthy, one
            silent Rect over coordinateSystem.getRect() at z2 -1, its style
            defaults({fill: backgroundColor}, getItemStyle()); nothing when
            it is falsy. Recorded per grid: present, the rect, the style as
            the canvas reads it (fill, stroke, lineWidth, lineDash,
            lineDashOffset, lineCap, opacity, the four shadow keys), z, z2,
            zlevel, and whether it is drawn before every element of the
            axes' views (display-list order).
  alone     a chart of no series: the toolbox's group position and icon
            count, and how many displayables the visualMap and timeline
            views hold.
  radar     the radar's pens' ends: each indicator axis' line (AxisBuilder:
            extend({lineCap: 'round'}, axisLine.lineStyle)), the ticks
            (axisTick.lineStyle), the split lines (mergePath with the
            splitLine.lineStyle): lineCap, lineJoin, miterLimit.
  gradient  a gradient written as an axis piece's colour: for each stroked
            element of the x / y axis views whose stroke is a gradient -- the
            axis line, each tick, the merged split lines -- its
            getBoundingRect() (the stroke-grown rect zrender's brush hands
            getCanvasGradient), the line's own end points, and the gradient
            as the canvas makes it: (x, y, x2, y2) times the rect plus its
            corner (a gradient that is not global), with its stops.

Each case is a chart rendered once, animation off, 600 x 400.

  node tools/advchart-oracle/edges-axes.js

writes tests/fixtures/advchart-edges-axes.json (ORACLE_OUT overrides). Two
generations byte-identical; ends with process.exit().
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const T0 = 1700000000000;
let NOW = T0;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-edges-axes.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}

(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

const W = 600, H = 400;
function mk() {
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function list(chart) { return chart.getZr().storage.getDisplayList(true); }
function eachDisp(g, fn) {
  if (!g) return;
  if (g.isGroup) { g.eachChild(c => eachDisp(c, fn)); return; }
  fn(g);
  // a Displayable's text content and guide line are separate elements
}
function rectRec(r) { return [hex(r.x), hex(r.y), hex(r.width), hex(r.height)]; }
function colourRec(c) {
  if (c == null) return null;
  if (typeof c === 'string') return c;
  must(c.colorStops, 'a colour object without stops');
  return { type: c.type, x: c.x, y: c.y, x2: c.x2, y2: c.y2, r: c.r, global: !!c.global,
    stops: c.colorStops.map(s => [s.offset, s.color]) };
}
function dashRec(d) {
  if (d == null) return null;
  if (typeof d === 'string' || typeof d === 'number') return d;
  return d.slice();
}
const nz = v => (typeof v === 'number' && !Number.isNaN(v) ? v : 0);

const CAT = { type: 'category', data: ['a', 'b', 'c', 'd'] };
const VAL = { type: 'value' };
const BAR = { type: 'bar', data: [5, 3, 8, 2] };

// ---- grid backgrounds ----
const GRID_CASES = [
  { id: 'grid-default', note: 'show: true and nothing else: no fill, the neutral30 border 1 px',
    option: { grid: { show: true }, xAxis: CAT, yAxis: VAL, series: [BAR] } },
  { id: 'grid-styled', note: 'every item-style key a grid reads',
    option: { grid: { show: true, left: 70, right: 40, top: 50, bottom: 60, backgroundColor: 'rgba(0,128,255,0.2)',
      borderColor: '#f00', borderWidth: 3, borderType: 'dashed', borderDashOffset: 2, borderCap: 'round',
      opacity: 0.5, shadowBlur: 10, shadowColor: 'rgba(0,0,0,0.5)', shadowOffsetX: 3, shadowOffsetY: 4 },
      xAxis: CAT, yAxis: VAL, series: [BAR] } },
  { id: 'grid-gradient', note: "a gradient background; borderColor 'none' strokes nothing; `color` is not the fill",
    option: { grid: { show: true, color: '#0f0', backgroundColor: { type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
      colorStops: [{ offset: 0, color: '#fff' }, { offset: 1, color: '#ccc' }] }, borderColor: 'none' },
      xAxis: CAT, yAxis: VAL, series: [BAR] } },
  { id: 'grid-hidden', note: 'show false (the default) with a background: no rect',
    option: { grid: { backgroundColor: '#eee', borderColor: '#000' }, xAxis: CAT, yAxis: VAL, series: [BAR] } },
  { id: 'grid-two', note: 'two grids, the second shown, a truthy number for show and borderWidth 0',
    option: { grid: [{ left: '7%', right: '55%' }, { show: 1, left: '55%', right: '7%', borderWidth: 0, backgroundColor: '#fafafa' }],
      xAxis: [Object.assign({ gridIndex: 0 }, CAT), Object.assign({ gridIndex: 1 }, CAT)],
      yAxis: [Object.assign({ gridIndex: 0 }, VAL), Object.assign({ gridIndex: 1 }, VAL)],
      series: [BAR, Object.assign({ xAxisIndex: 1, yAxisIndex: 1 }, BAR)] } },
  { id: 'grid-dotted', note: 'a dotted border 2 px wide, a numeric dash array is verbatim on the next',
    option: { grid: { show: true, borderType: 'dotted', borderWidth: 2, borderColor: '#333' }, xAxis: CAT, yAxis: VAL, series: [BAR] } },
  { id: 'grid-dasharray', note: 'borderType as an array',
    option: { grid: { show: true, borderType: [6, 3], borderWidth: 1.5, borderColor: '#336' }, xAxis: CAT, yAxis: VAL, series: [BAR] } },
];

function runGrid(c) {
  const chart = mk();
  chart.setOption(Object.assign({ animation: false }, c.option));
  const dl = list(chart);
  const ec = chart.getModel();
  const axisEls = new Set();
  ['xAxis', 'yAxis'].forEach(t => ec.eachComponent(t, m => eachDisp(chart.getViewOfComponentModel(m).group, el => axisEls.add(el))));
  let firstAxis = Infinity;
  dl.forEach((el, k) => { if (axisEls.has(el)) firstAxis = Math.min(firstAxis, k); });
  const grids = [];
  ec.eachComponent('grid', gm => {
    const view = chart.getViewOfComponentModel(gm);
    const kids = [];
    eachDisp(view.group, el => kids.push(el));
    must(kids.length <= 1, c.id + ': a grid view of ' + kids.length + ' elements');
    if (!kids.length) { grids.push({ present: false }); return; }
    const el = kids[0];
    const st = el.style;
    const sh = el.shape;
    const k = dl.indexOf(el);
    grids.push({ present: true, rect: rectRec(sh), gridRect: rectRec(gm.coordinateSystem.getRect()),
      fill: colourRec(st.fill), stroke: colourRec(st.stroke), lineWidth: st.lineWidth == null ? null : hex(st.lineWidth),
      lineDash: dashRec(st.lineDash), lineDashOffset: st.lineDashOffset == null ? null : hex(st.lineDashOffset),
      lineCap: st.lineCap == null ? null : st.lineCap, opacity: st.opacity == null ? null : hex(st.opacity),
      shadowBlur: hex(nz(st.shadowBlur)), shadowOffsetX: hex(nz(st.shadowOffsetX)), shadowOffsetY: hex(nz(st.shadowOffsetY)),
      shadowColor: st.shadowColor == null ? null : String(st.shadowColor),
      z: el.z, z2: el.z2, zlevel: el.zlevel, silent: !!el.silent, underAxes: k >= 0 && k < firstAxis });
  });
  chart.dispose();
  return { id: c.id, note: c.note, option: c.option, grids };
}

// ---- charts of no series ----
const ALONE_CASES = [
  { id: 'alone-toolbox', note: 'a toolbox and nothing else',
    option: { toolbox: { feature: { saveAsImage: {}, restore: {}, dataView: {} } } } },
  { id: 'alone-toolbox-timeline', note: 'a toolbox and a timeline, no series',
    option: { toolbox: { left: 10, feature: { saveAsImage: {} } }, timeline: { data: ['a', 'b', 'c'] } } },
  { id: 'alone-visualmap', note: 'a continuous visualMap and nothing else',
    option: { visualMap: { min: 0, max: 100, calculable: true } } },
];
function runAlone(c) {
  const chart = mk();
  chart.setOption(Object.assign({ animation: false }, c.option));
  const ec = chart.getModel();
  const rec = { id: c.id, note: c.note, option: c.option };
  const tb = ec.getComponent('toolbox', 0);
  if (tb) {
    const view = chart.getViewOfComponentModel(tb);
    let icons = 0;
    // the icons: every displayable but the background rect
    eachDisp(view.group, el => { if (el.type !== 'rect') icons++; });
    rec.toolbox = { x: hex(view.group.x), y: hex(view.group.y), icons };
  }
  ['visualMap', 'timeline'].forEach(t => {
    const m = ec.getComponent(t, 0);
    if (!m) return;
    let n = 0;
    eachDisp(chart.getViewOfComponentModel(m).group, () => n++);
    rec[t] = n;
  });
  chart.dispose();
  return rec;
}

// ---- the radar's pen ends ----
const IND = [{ name: 'A', max: 10 }, { name: 'B', max: 10 }, { name: 'C', max: 10 }, { name: 'D', max: 10 }, { name: 'E', max: 10 }];
const RADAR_CASES = [
  { id: 'radar-default', note: "the axis lines' round cap; the split lines' none",
    option: { radar: { indicator: IND }, series: [{ type: 'radar', data: [{ value: [3, 5, 7, 4, 6] }] }] } },
  { id: 'radar-ends', note: "a square axis-line cap, round split lines with a bevel join and miterLimit 3, ticks shown with a round cap",
    option: { radar: { indicator: IND, axisLine: { lineStyle: { cap: 'square', width: 3 } },
      splitLine: { lineStyle: { cap: 'round', join: 'bevel', miterLimit: 3, width: 2 } },
      axisTick: { show: true, length: 8, lineStyle: { cap: 'round', width: 3 } } },
      series: [{ type: 'radar', data: [{ value: [3, 5, 7, 4, 6] }] }] } },
  { id: 'radar-circle-join', note: 'a circle radar: the rings take the join too (miter)',
    option: { radar: { shape: 'circle', indicator: IND, splitLine: { lineStyle: { join: 'round', cap: 'butt' } } },
      series: [{ type: 'radar', data: [{ value: [3, 5, 7, 4, 6] }] }] } },
];
function runRadar(c) {
  const chart = mk();
  chart.setOption(Object.assign({ animation: false }, c.option));
  const rm = chart.getModel().getComponent('radar', 0);
  const view = chart.getViewOfComponentModel(rm);
  const out = { id: c.id, note: c.note, option: c.option, axisLines: [], ticks: [], splitLines: [] };
  const ends = st => ({ cap: st.lineCap == null ? null : st.lineCap, join: st.lineJoin == null ? null : st.lineJoin,
    miter: st.miterLimit == null ? null : st.miterLimit });
  view.group.eachChild(ch => {
    if (ch.isGroup) {
      eachDisp(ch, el => {
        if (el.anid === 'line') out.axisLines.push(ends(el.style));
        else if (typeof el.anid === 'string' && el.anid.indexOf('ticks') === 0) out.ticks.push(ends(el.style));
      });
    } else if (ch.style && ch.style.fill === 'none' && ch.style.stroke && ch.style.stroke !== 'none') {
      out.splitLines.push(ends(ch.style));
    }
  });
  chart.dispose();
  return out;
}

// ---- the radar's scale labels: the end rules, hideOverlap, the ticks with them ----
// (node measures text with zrender's estimate; the port's replay measures with
// the same estimate -- tests/fixtures/advchart-text-style.json's ratios)
const RL_IND = [{ name: 'A', max: 100 }, { name: 'B', max: 100 }, { name: 'C', max: 100 }, { name: 'D', max: 100 }];
const RL = (radar, extra) => ({ radar: Object.assign({ indicator: RL_IND, radius: 50, center: ['50%', '50%'],
  axisLabel: Object.assign({ show: true }, extra || {}), axisTick: { show: true } }, radar || {}),
  series: [{ type: 'radar', symbol: 'none', data: [{ value: [50, 60, 70, 80] }] }] });
const RADAR_LABEL_CASES = [
  { id: 'rl-crowded', note: 'rings 10 px apart: the min label crowds its neighbour and gives way, its tick with it', option: RL() },
  { id: 'rl-keepmin', note: 'showMinLabel true: the neighbour gives way instead', option: RL(null, { showMinLabel: true }) },
  { id: 'rl-hidemax', note: 'showMaxLabel false: the max label hidden whatever its room', option: RL({ radius: 150 }, { showMaxLabel: false }) },
  { id: 'rl-roomy', note: 'rings 30 px apart: every label and tick shows', option: RL({ radius: 150 }) },
  { id: 'rl-overlap', note: 'hideOverlap: every label that crowds one kept is hidden', option: RL({ radius: 70, splitNumber: 10 }, { hideOverlap: true }) },
];
function runRadarLabels(c) {
  const chart = mk();
  chart.setOption(Object.assign({ animation: false }, c.option));
  const rm = chart.getModel().getComponent('radar', 0);
  const view = chart.getViewOfComponentModel(rm);
  const axes = [];
  view.group.eachChild(ch => {
    if (!ch.isGroup) return;
    const rec = { labels: [], ticks: [] };
    eachDisp(ch, el => {
      if (el.type === 'text' && typeof el.anid === 'string' && el.anid.indexOf('label') === 0) rec.labels.push({ text: el.style.text, ignore: !!el.ignore });
      else if (typeof el.anid === 'string' && el.anid.indexOf('ticks') === 0) rec.ticks.push(!!el.ignore);
    });
    if (rec.labels.length) axes.push(rec);
  });
  chart.dispose();
  return { id: c.id, note: c.note, option: c.option, axes };
}

// ---- a river's boundaryGap through a resize: themeRiverLayout writes the
// parsePercent results back into the model's own array ----
const RIVER_OPT = { singleAxis: { type: 'time', top: 40, bottom: 40 },
  series: [{ type: 'themeRiver', data: [['2020/01/01', 10, 'A'], ['2020/01/02', 20, 'A'], ['2020/01/03', 15, 'A'],
    ['2020/01/01', 5, 'B'], ['2020/01/02', 8, 'B'], ['2020/01/03', 12, 'B']] }] };
function runRiver() {
  const chart = mk();
  chart.setOption(Object.assign({ animation: false }, RIVER_OPT));
  const steps = [];
  const rec = (what) => {
    const sm = chart.getModel().getSeriesByIndex(0);
    const li = sm.getData().getLayout('layoutInfo');
    steps.push({ what, gap: li.boundaryGap.map(hex), rect: rectRec(li.rect) });
  };
  rec('first');
  chart.resize({ width: W, height: 300 });
  rec('resized');
  chart.setOption({ legend: {} });
  rec('merged, no boundaryGap');
  chart.setOption({ series: [{ boundaryGap: ['10%', '20%'] }] });
  rec('merged, a boundaryGap');
  chart.resize({ width: W, height: H });
  rec('resized back');
  chart.dispose();
  return { option: RIVER_OPT, steps };
}

// ---- a log axis takes a pointer over its MAPPING extent: Log.contain is
// powStub.contain, scaleMapper's contain over getScaleExtentForMappingUnsafe
// -- the half bar containShape added on a log base axis included ----
const LOGPTR_OPT = { grid: { left: 60, right: 60, top: 40, bottom: 60 }, tooltip: { trigger: 'axis' },
  xAxis: { type: 'log' }, yAxis: { type: 'value' },
  series: [{ type: 'bar', barWidth: 30, data: [[1, 5], [10, 3], [100, 7]] }] };
function runLogPointer() {
  const chart = mk();
  chart.setOption(Object.assign({ animation: false }, LOGPTR_OPT));
  const ax = chart.getModel().getComponent('xAxis', 0).axis;
  const grid = chart.getModel().getComponent('grid', 0).coordinateSystem.getRect();
  const eff = ax.scale.getExtent();
  const map = ax.scale.getExtentUnsafe ? ax.scale.getExtentUnsafe(1, null) : null;
  const px = grid.x + 3;
  const v = ax.coordToData(ax.toLocalCoord(px));
  const out = { option: LOGPTR_OPT, px: hex(px), value: hex(v), effective: eff.map(hex), contain: !!ax.scale.contain(v),
    inEffective: v >= eff[0] && v <= eff[1] };
  chart.dispose();
  return out;
}

// ---- alignTicks with what spec 82 left undone: dataZoom on the aligned
// axis, an inverse one, containShape (bars on a value base axis), an axis
// that writes breaks (falls back: niced on its own) ----
const ALIGN_BASE = (extra) => Object.assign({ animation: false, grid: { left: 60, right: 60, top: 40, bottom: 60 },
  xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e'] },
  yAxis: [{ type: 'value' }, { type: 'value', alignTicks: true }],
  series: [{ type: 'line', data: [12, 37, 51, 8, 29] }, { type: 'line', yAxisIndex: 1, data: [0.3, 2.9, 1.7, 4.4, 2.2] }] }, extra || {});
const ALIGN_CASES = [
  { id: 'align-plain', option: ALIGN_BASE() },
  { id: 'align-zoom', note: 'a dataZoom window on the aligned axis: both its ends count as fixed',
    option: ALIGN_BASE({ dataZoom: [{ type: 'inside', yAxisIndex: 1, startValue: 1, endValue: 4, filterMode: 'none' }] }) },
  { id: 'align-zoom-ref', note: 'a dataZoom window on the reference axis',
    option: ALIGN_BASE({ dataZoom: [{ type: 'inside', yAxisIndex: 0, start: 10, end: 80, filterMode: 'none' }] }) },
  { id: 'align-inverse', note: 'the aligned axis inverse',
    option: ALIGN_BASE({ yAxis: [{ type: 'value' }, { type: 'value', alignTicks: true, inverse: true }] }) },
  { id: 'align-inverse-ref', note: 'the reference inverse',
    option: ALIGN_BASE({ yAxis: [{ type: 'value', inverse: true }, { type: 'value', alignTicks: true }] }) },
  { id: 'align-shape', note: 'bars on value x axes: containShape on the aligned one',
    option: { animation: false, grid: { left: 60, right: 60, top: 40, bottom: 60 },
      xAxis: [{ type: 'value' }, { type: 'value', alignTicks: true }], yAxis: { type: 'value' },
      series: [{ type: 'bar', data: [[1, 3], [4, 6], [9, 2]] }, { type: 'bar', xAxisIndex: 1, data: [[0.5, 2], [2.5, 5]] }] } },
  { id: 'align-breaks', note: 'the aligned axis writes breaks: niced on its own',
    option: ALIGN_BASE({ yAxis: [{ type: 'value' }, { type: 'value', alignTicks: true, breaks: [{ start: 2, end: 3 }] }] }) },
];
function runAlign(c) {
  const chart = mk();
  chart.setOption(c.option);
  const axes = [];
  ['xAxis', 'yAxis'].forEach(t => chart.getModel().eachComponent(t, m => {
    const ax = m.axis;
    if (ax.type === 'category') return;
    const ext = ax.scale.getExtent();
    axes.push({ dim: t, index: m.componentIndex, extent: ext.map(hex), interval: hex(ax.scale.getConfig ? ax.scale.getConfig().interval : ax.scale.getInterval()),
      ticks: ax.scale.getTicks().map(q => hex(q.value)), inverse: !!ax.inverse });
  }));
  chart.dispose();
  return { id: c.id, note: c.note || '', option: c.option, axes };
}

// ---- zlevel across what the port draws apart from its list: a title (z 6,
// zlevel 0) and a series of zlevel 1 that the title's box overlaps; the
// loading mask (zlevel 0, z 10000) under a series of zlevel 1 ----
const ZL_OPT = { title: { text: 'TITLE TEXT', left: 40, top: 40, backgroundColor: '#ff0000', padding: 20, textStyle: { fontSize: 20 } },
  xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
  series: [{ type: 'scatter', zlevel: 1, symbolSize: 40, itemStyle: { color: '#0000ff', opacity: 1 }, data: [[1, 9]] }] };
function runZLevel() {
  const chart = mk();
  chart.setOption(Object.assign({ animation: false }, ZL_OPT));
  const tm = chart.getModel().getComponent('title', 0);
  const titleEls = [];
  eachDisp(chart.getViewOfComponentModel(tm).group, el => titleEls.push({ zlevel: el.zlevel, z: el.z }));
  const sm = chart.getModel().getSeriesByIndex(0);
  const sym = sm.getData().getItemGraphicEl(0);
  const symLayout = sm.getData().getItemLayout(0);
  chart.showLoading({ text: '' });
  const mask = [];
  const fx = chart._loadingFX;
  eachDisp(fx, el => mask.push({ zlevel: el.zlevel, z: el.z, type: el.type }));
  chart.dispose();
  return { option: ZL_OPT, title: titleEls, symbol: { zlevel: sym.childAt(0).zlevel, z: sym.childAt(0).z, x: hex(symLayout[0]), y: hex(symLayout[1]) }, loading: mask };
}

// ---- a title's box: install.ts' Rect, fill backgroundColor, stroke
// borderColor (tokens.color.primary by default), lineWidth borderWidth ----
function runTitleBox() {
  const opts = [{ text: 'Box', left: 40, top: 40, padding: 10, backgroundColor: '#ff0000', borderColor: '#0000ff', borderWidth: 3 },
    { text: 'Box', left: 40, top: 40, padding: 10, borderWidth: 2 }];
  return opts.map(o => {
    const chart = mk();
    chart.setOption({ animation: false, title: o });
    const tm = chart.getModel().getComponent('title', 0);
    let rect = null;
    eachDisp(chart.getViewOfComponentModel(tm).group, el => { if (el.type === 'rect') rect = el; });
    const st = rect.style;
    const out = { option: { title: o }, rect: rectRec(rect.shape), fill: colourRec(st.fill), stroke: colourRec(st.stroke),
      lineWidth: hex(st.lineWidth) };
    chart.dispose();
    return out;
  });
}

// ---- gradients on the axis pieces ----
const H_GRAD = { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] };
const V_GRAD = { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#00c000' }, { offset: 1, color: '#c000c0' }] };
const GRAD_CASES = [
  { id: 'grad-axisline', note: 'a horizontal ramp on the x axis line (6 px), a vertical one on the shown y axis line (6 px)',
    option: { grid: { left: 60, right: 60, top: 40, bottom: 60 },
      xAxis: Object.assign({ axisLine: { lineStyle: { color: H_GRAD, width: 6 } }, axisTick: { show: false } }, CAT),
      yAxis: Object.assign({ axisLine: { show: true, lineStyle: { color: V_GRAD, width: 6 } }, splitLine: { show: false } }, VAL),
      series: [BAR] } },
  { id: 'grad-ticks', note: "the x axis' ticks 12 px long, 6 wide, a vertical ramp over each tick's own box; the axis line plain",
    option: { grid: { left: 60, right: 60, top: 40, bottom: 60 },
      xAxis: Object.assign({ axisLine: { lineStyle: { color: '#333' } }, axisTick: { show: true, length: 12, lineStyle: { color: V_GRAD, width: 6 } } }, CAT),
      yAxis: Object.assign({ splitLine: { show: false } }, VAL), series: [BAR] } },
  { id: 'grad-ticks-h', note: "the x axis' ticks 12 px long, 6 wide, a HORIZONTAL ramp: each tick's own 6 px box, not the five together",
    option: { grid: { left: 60, right: 60, top: 40, bottom: 60 },
      xAxis: Object.assign({ axisLine: { lineStyle: { color: '#333' } }, axisTick: { show: true, length: 12, lineStyle: { color: H_GRAD, width: 6 } } }, CAT),
      yAxis: Object.assign({ splitLine: { show: false } }, VAL), series: [BAR] } },
  { id: 'grad-split-v', note: "the y axis' split lines 4 px wide under a VERTICAL ramp: each line's own 5 px box, not the plot's height (the x axis' line and ticks hidden)",
    option: { grid: { left: 60, right: 60, top: 40, bottom: 60 },
      xAxis: Object.assign({ axisLine: { show: false }, axisTick: { show: false } }, CAT),
      yAxis: Object.assign({ splitLine: { lineStyle: { color: V_GRAD, width: 4 } } }, VAL), series: [BAR] } },
  { id: 'grad-split', note: "the y axis' split lines 4 px wide under one horizontal ramp, a Line each (the x axis' line and ticks hidden: the bottom one is in the open)",
    option: { grid: { left: 60, right: 60, top: 40, bottom: 60 },
      xAxis: Object.assign({ axisLine: { show: false }, axisTick: { show: false } }, CAT),
      yAxis: Object.assign({ splitLine: { lineStyle: { color: H_GRAD, width: 4 } } }, VAL), series: [BAR] } },
];
function runGrad(c) {
  const chart = mk();
  chart.setOption(Object.assign({ animation: false }, c.option));
  const ec = chart.getModel();
  const out = { id: c.id, note: c.note, option: c.option, strokes: [] };
  ['xAxis', 'yAxis'].forEach(t => ec.eachComponent(t, m => eachDisp(chart.getViewOfComponentModel(m).group, el => {
    const s = el.style && el.style.stroke;
    if (!s || typeof s !== 'object' || !s.colorStops) return;
    must(!el.transform || (el.transform[0] === 1 && el.transform[1] === 0 && el.transform[2] === 0 && el.transform[3] === 1
      && el.transform[4] === 0 && el.transform[5] === 0), c.id + ': a transformed gradient stroke');
    const r = el.getBoundingRect();
    const g = s;
    const gx = g.global ? g.x : g.x * r.width + r.x;
    const gy = g.global ? g.y : g.y * r.height + r.y;
    const gx2 = g.global ? g.x2 : g.x2 * r.width + r.x;
    const gy2 = g.global ? g.y2 : g.y2 * r.height + r.y;
    const sh = el.shape;
    const role = el.anid === 'line' ? 'line' : (typeof el.anid === 'string' && el.anid.indexOf('ticks') === 0 ? 'tick' : 'split');
    out.strokes.push({ axis: t, role, lineWidth: hex(el.style.lineWidth), rect: rectRec(r),
      ends: sh && sh.x1 != null ? [hex(sh.x1), hex(sh.y1), hex(sh.x2), hex(sh.y2)] : null,
      gradient: [hex(gx), hex(gy), hex(gx2), hex(gy2)], stops: g.colorStops.map(q => [q.offset, q.color]) });
  })));
  chart.dispose();
  return out;
}

// ---- blend modes: what reaches the canvas ----
const BLEND_MODES = ['hue', 'saturation', 'color', 'luminosity', 'source-atop', 'destination-over', 'xor', 'copy', 'destination-out', 'source-in'];
function runBlend() {
  return BLEND_MODES.map(mode => {
    const chart = mk();
    chart.setOption({ animation: false, xAxis: CAT, yAxis: VAL, series: [Object.assign({ blendMode: mode }, BAR)] });
    const blends = [];
    chart.getModel().eachSeries(sm => sm.getData().each(i => {
      const el = sm.getData().getItemGraphicEl(i);
      if (el) blends.push(el.style.blend == null ? null : el.style.blend);
    }));
    chart.dispose();
    return { mode, blends };
  });
}

function generate() {
  return {
    generator: 'tools/advchart-oracle/edges-axes.js', echarts: echarts.version, width: W, height: H,
    grid: GRID_CASES.map(runGrid),
    alone: ALONE_CASES.map(runAlone),
    radar: RADAR_CASES.map(runRadar),
    gradient: GRAD_CASES.map(runGrad),
    blend: runBlend(),
    radarLabels: RADAR_LABEL_CASES.map(runRadarLabels),
    river: runRiver(),
    logPointer: runLogPointer(),
    align: ALIGN_CASES.map(runAlign),
    zlevel: runZLevel(),
    titleBox: runTitleBox(),
  };
}

let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1);
  json2 = JSON.stringify(generate());
} catch (e) {
  console.log('ORACLE ERROR', e && e.stack || e);
  process.exit(1);
}

const gc = id => out1.grid.find(c => c.id === id);
const al = id => out1.alone.find(c => c.id === id);
const rc = id => out1.radar.find(c => c.id === id);
const gr = id => out1.gradient.find(c => c.id === id);
const guards = [
  { name: 'grid-default: one rect, a transparent fill (tokens.color.transparent), #b7b9be 1 px, z2 -1, silent, under the axes',
    ok: gc('grid-default').grids.length === 1 && gc('grid-default').grids[0].present && gc('grid-default').grids[0].fill === 'rgba(0,0,0,0)'
      && gc('grid-default').grids[0].stroke === '#b7b9be' && num(gc('grid-default').grids[0].lineWidth) === 1
      && gc('grid-default').grids[0].z2 === -1 && gc('grid-default').grids[0].silent && gc('grid-default').grids[0].underAxes },
  { name: 'grid-default: the rect is the grid rect',
    ok: JSON.stringify(gc('grid-default').grids[0].rect) === JSON.stringify(gc('grid-default').grids[0].gridRect) },
  { name: 'grid-styled: every key reached the style',
    ok: (g => g.fill === 'rgba(0,128,255,0.2)' && g.stroke === '#f00' && num(g.lineWidth) === 3 && g.lineDash === 'dashed'
      && num(g.lineDashOffset) === 2 && g.lineCap === 'round' && num(g.opacity) === 0.5 && num(g.shadowBlur) === 10
      && num(g.shadowOffsetX) === 3 && num(g.shadowOffsetY) === 4 && g.shadowColor === 'rgba(0,0,0,0.5)')(gc('grid-styled').grids[0]) },
  { name: "grid-gradient: the gradient is the fill (not `color`), the stroke 'none'",
    ok: typeof gc('grid-gradient').grids[0].fill === 'object' && gc('grid-gradient').grids[0].stroke === 'none' },
  { name: 'grid-hidden: no rect', ok: gc('grid-hidden').grids.length === 1 && !gc('grid-hidden').grids[0].present },
  { name: 'grid-two: the first hidden, the second shown, width 0',
    ok: !gc('grid-two').grids[0].present && gc('grid-two').grids[1].present && num(gc('grid-two').grids[1].lineWidth) === 0 },
  { name: 'grid-dotted / dasharray: the words and the array as written',
    ok: gc('grid-dotted').grids[0].lineDash === 'dotted' && JSON.stringify(gc('grid-dasharray').grids[0].lineDash) === '[6,3]' },
  { name: 'alone-toolbox: three icons', ok: al('alone-toolbox').toolbox && al('alone-toolbox').toolbox.icons === 3 },
  { name: 'alone-toolbox-timeline: a timeline drawn', ok: al('alone-toolbox-timeline').timeline > 0 && al('alone-toolbox-timeline').toolbox.icons === 1 },
  { name: 'alone-visualmap: a visualMap drawn', ok: al('alone-visualmap').visualMap > 0 },
  { name: "radar-default: five round axis lines, the split lines butt (getLineStyle's none, the path's default)",
    ok: rc('radar-default').axisLines.length === 5 && rc('radar-default').axisLines.every(e => e.cap === 'round')
      && rc('radar-default').splitLines.length > 0 && rc('radar-default').splitLines.every(e => e.cap === 'butt' && e.join == null && e.miter === 10) },
  { name: 'radar-ends: square lines, round ticks, round / bevel / 3 split lines',
    ok: rc('radar-ends').axisLines.every(e => e.cap === 'square') && rc('radar-ends').ticks.length > 0
      && rc('radar-ends').ticks.every(e => e.cap === 'round')
      && rc('radar-ends').splitLines.every(e => e.cap === 'round' && e.join === 'bevel' && e.miter === 3) },
  { name: 'radar-circle-join: the rings take the join', ok: rc('radar-circle-join').splitLines.every(e => e.join === 'round' && e.cap === 'butt') },
  { name: 'grad-axisline: two lines, each its own ramp',
    ok: gr('grad-axisline').strokes.filter(s => s.role === 'line').length === 2 },
  { name: "grad-axisline: the box is the stroke-grown rect (max(6, 5) = 6)",
    ok: (s => num(s.rect[3]) === 6)(gr('grad-axisline').strokes.find(s => s.axis === 'xAxis')) },
  { name: "grad-ticks: a box per tick, five ticks", ok: gr('grad-ticks').strokes.filter(s => s.role === 'tick').length === 5
    && new Set(gr('grad-ticks').strokes.map(s => s.gradient[0])).size === 5 },
  { name: "grad-split: a Line per split line (CartesianAxisView does not merge them), each its own box",
    ok: gr('grad-split').strokes.filter(s => s.role === 'split').length === 5 && gr('grad-split').strokes.every(s => num(s.rect[3]) === 5) },
  { name: 'blend: every mode written reaches every bar as style.blend', ok: out1.blend.every(c => c.blends.length === 4 && c.blends.every(x => x === c.mode)) },
  { name: 'rl-crowded: on the two upright spokes the min label (0) crowds 20 and gives way, its tick too; every max (100) crowds 80',
    ok: (c => c.axes.length === 4 && [0, 2].every(k => c.axes[k].labels[0].ignore && c.axes[k].ticks[0])
      && [1, 3].every(k => !c.axes[k].labels[0].ignore && !c.axes[k].ticks[0])
      && c.axes.every(x => x.labels[5].ignore && x.ticks[5] && x.labels.slice(1, 5).every(l => !l.ignore)))(out1.radarLabels.find(c => c.id === 'rl-crowded')) },
  { name: 'rl-keepmin: on the upright spokes the neighbour (20) gives way instead',
    ok: (c => [0, 2].every(k => !c.axes[k].labels[0].ignore && c.axes[k].labels[1].ignore && c.axes[k].ticks[1] && !c.axes[k].ticks[0]))(out1.radarLabels.find(c => c.id === 'rl-keepmin')) },
  { name: 'rl-hidemax: the max hidden, its tick too', ok: (c => c.axes.every(x => x.labels[x.labels.length - 1].ignore && x.ticks[x.ticks.length - 1]
      && !x.labels[0].ignore))(out1.radarLabels.find(c => c.id === 'rl-hidemax')) },
  { name: 'rl-roomy: nothing hidden', ok: out1.radarLabels.find(c => c.id === 'rl-roomy').axes.every(x => x.labels.every(l => !l.ignore) && x.ticks.every(q => !q)) },
  { name: 'rl-overlap: some hidden in the middle', ok: out1.radarLabels.find(c => c.id === 'rl-overlap').axes.some(x => x.labels.slice(2, -2).some(l => l.ignore)) },
  { name: "river: the first layout's gaps survive a resize and a merge without boundaryGap; a merge with one resolves it at that size",
    ok: (r => num(r.steps[0].gap[0]) === num(r.steps[1].gap[0]) && num(r.steps[1].gap[0]) === num(r.steps[2].gap[0])
      && num(r.steps[0].rect[3]) !== num(r.steps[1].rect[3])
      && num(r.steps[3].gap[1]) === num(r.steps[3].rect[3]) * 0.2 && num(r.steps[4].gap[1]) === num(r.steps[3].gap[1]))(out1.river) },
  { name: 'logPointer: a value outside the effective extent the log axis contains (its mapping extent)',
    ok: out1.logPointer.contain && !out1.logPointer.inEffective },
  { name: 'zlevel: the title at zlevel 0, the symbol at 1, the loading mask at 0 z 10000',
    ok: out1.zlevel.title.length > 0 && out1.zlevel.title.every(e => e.zlevel === 0) && out1.zlevel.symbol.zlevel === 1
      && out1.zlevel.loading.some(e => e.type === 'rect' && e.zlevel === 0 && e.z === 10000) },
  { name: "titleBox: the author's fill and border; the default border the primary token",
    ok: out1.titleBox[0].fill === '#ff0000' && out1.titleBox[0].stroke === '#0000ff' && num(out1.titleBox[0].lineWidth) === 3
      && typeof out1.titleBox[1].stroke === 'string' && num(out1.titleBox[1].lineWidth) === 2 },
];
out1.guards = guards.map(g => ({ name: g.name, ok: !!g.ok }));
out1.grid.forEach(c => console.log(c.id + ': ' + JSON.stringify(c.grids.map(g => g.present ? [g.fill, g.stroke, g.lineWidth && num(g.lineWidth), g.lineDash] : null))));
out1.alone.forEach(c => console.log(c.id + ': ' + JSON.stringify([c.toolbox, c.visualMap, c.timeline])));
out1.radar.forEach(c => console.log(c.id + ': ' + JSON.stringify([c.axisLines[0], c.ticks[0], c.splitLines[0], c.splitLines.length])));
out1.radarLabels.forEach(c => console.log(c.id + ': ' + JSON.stringify(c.axes.map(x => [x.labels.map(l => (l.ignore ? '-' : '') + l.text).join(' '), x.ticks.map(q => q ? 1 : 0).join('')]))));
console.log('river: ' + JSON.stringify(out1.river.steps.map(s => [s.what, s.gap.map(num), num(s.rect[3])])));
console.log('logPointer: ' + JSON.stringify([num(out1.logPointer.px), num(out1.logPointer.value), out1.logPointer.effective.map(num), out1.logPointer.contain]));
out1.align.forEach(c => console.log(c.id + ': ' + JSON.stringify(c.axes.map(x => [x.dim + x.index, x.extent.map(num), num(x.interval), x.ticks.length]))));
console.log('zlevel: ' + JSON.stringify([out1.zlevel.title, out1.zlevel.symbol.zlevel, out1.zlevel.loading]));
console.log('titleBox: ' + JSON.stringify(out1.titleBox.map(b => [b.rect.map(num), b.fill, b.stroke, num(b.lineWidth)])));
out1.gradient.forEach(c => console.log(c.id + ': ' + JSON.stringify(c.strokes.map(s => [s.axis, s.role, s.rect.map(num), s.gradient.map(num)]))));
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name));
const final = JSON.stringify(out1, null, 1) + '\n';
if (bad.length || json1 !== json2 || final.includes('\\u0000')) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, final);
console.log('wrote', OUT);
process.exit(0);
