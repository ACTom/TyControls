// Upstream's own answers for round-5 batch R5-D (2026-10-27): what the
// toolbox draws and shows beyond its icons' colours (ToolboxView.ts
// createIconPaths):
//   * an icon's style is iconStyle's getItemStyle() -- borderType becomes
//     lineDash, borderDashOffset lineDashOffset, borderCap lineCap,
//     borderJoin lineJoin, borderMiterLimit miterLimit -- and its emphasis
//     state's is emphasis.iconStyle's, over it
//   * the title under the pointer is a ZRText with emphasis.iconStyle's
//     textBorderRadius, textPadding and font (textFontStyle / Weight / Size /
//     Family) and, set on mouseover, textFill and textBackgroundColor: the
//     box (padding around the text) is drawn behind it, the text inside
//   * every icon carries a component tooltip (setTooltipConfig: the icon's
//     name as its content, formatterParams {componentType, toolboxIndex,
//     name, title, $vars [name, title]}); TooltipView shows it through the
//     cascade [that, toolbox.tooltip, {formatter: content}] over the global
//     model, and the toolbox's default tooltip says show false -- so by
//     default a hover on an icon shows nothing new but dispatches its
//     showTip all the same (the box another target showed stays)
//
// The harness is axis-emphasis.js' (node, SVG, a fake clock and timers,
// chart._ssr false, env.node off, the tooltip view running, the box
// answering 80 x 40).
//
//   node tools/advchart-oracle/toolbox-extra.js
//
// writes tests/fixtures/advchart-toolbox-extra.json (ORACLE_OUT overrides).
//
// Per step: op ('move' | 'leave' | 'idle'), at, events [[chart, type,
// payload]] (showtip, hidetip), state: {icons [{key, states, style
// {lineWidth, lineDash, lineDashOffset, lineCap, lineJoin, miterLimit}}],
// title {text, shown, font, fill, backgroundColor, borderRadius, padding,
// box [x, y, w, h] (the background rect, global; null none), textX, textY
// (the first text span's global position), align, verticalAlign} | null
// (no icon's title shows), tip {which, text, box [x, y]} | null}.
'use strict';
const fs = require('fs');
const path = require('path');

// ---------- the fake clock and timers (installed before the build loads) ----------
const RealDate = Date;
const CLOCK0 = 1700000000000;
let NOW = CLOCK0;
class FakeDate extends RealDate {
  constructor(...a) {
    if (a.length) super(...a);
    else super(NOW);
  }
  static now() { return NOW; }
}
global.Date = FakeDate;
let TIMERS = [];
let timerSeq = 0;
global.setTimeout = function (fn, ms) {
  const id = ++timerSeq;
  TIMERS.push({ id, due: NOW + (+ms || 0), fn });
  return id;
};
global.clearTimeout = function (id) {
  TIMERS = TIMERS.filter(t => t.id !== id);
};
function advanceClock(to) {
  for (;;) {
    let best = null;
    for (const t of TIMERS) if (t.due <= to && (!best || t.due < best.due || (t.due === best.due && t.id < best.id))) best = t;
    if (!best) break;
    TIMERS = TIMERS.filter(t => t !== best);
    if (best.due > NOW) NOW = best.due;
    best.fn();
  }
  NOW = to;
}

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-toolbox-extra.json');

const W = 600;
const H = 400;
const SIZE = [80, 40];
const STEP_DT = 10;

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

// ---------- records ----------
const clone = v => JSON.parse(JSON.stringify(v));
const NULMARK = '\u2400';
function plain(v, depth) {
  if (typeof v === 'string') return v.split('\u0000').join(NULMARK);
  if (typeof v === 'number') {
    if (Number.isNaN(v)) return 'NaN';
    if (!Number.isFinite(v)) return v > 0 ? 'Infinity' : '-Infinity';
    return v;
  }
  if (v === null || typeof v !== 'object') return typeof v === 'function' ? undefined : v;
  must(depth < 40, 'too deep');
  if (Array.isArray(v)) return v.map(x => { const s = plain(x, depth + 1); return s === undefined ? null : s; });
  const o = {};
  for (const k of Object.keys(v)) {
    if (v[k] === undefined) continue;
    if (/^__ec_inner_\d+$/.test(k)) continue;
    const s = k === 'from' && typeof v[k] === 'string' ? '<view uid>' : plain(v[k], depth + 1);
    if (s !== undefined) o[k] = s;
  }
  return o;
}
const jsonOf = ev => (ev === undefined ? null : plain(JSON.parse(JSON.stringify(ev)), 0));

function newChart() {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
(function enableTooltips() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();
function frame(chart) {
  chart._onframe();
  chart.renderToSVGString();
}
function rawEvent(type, x, y) {
  return {
    type, zrX: x, zrY: y, which: 1, shiftKey: false, ctrlKey: false, altKey: false, cancelBubble: false,
    preventDefault() {}, stopPropagation() {},
  };
}

// ---------- the tooltip view, watched ----------
function tooltipView(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  return m ? chart.getViewOfComponentModel(m) : null;
}
function watchTooltip(chart) {
  const view = tooltipView(chart);
  const w = { which: null, view };
  if (!view) return w;
  const content = view._tooltipContent;
  must(content, 'no tooltip content');
  content.getSize = () => SIZE.slice();
  const show = view._showTooltipContent;
  view._showTooltipContent = function (tooltipModel, html, params) {
    if (Array.isArray(params)) {
      w.which = 'axis:' + params.map(p => p.seriesIndex + '/' + p.dataIndex + '@' + p.axisDim + p.axisIndex).join(',');
    } else if (params && params.componentType === 'series') {
      w.which = 'item:' + params.seriesIndex + ':' + params.dataIndex;
    } else w.which = 'other';
    return show.apply(this, arguments);
  };
  return w;
}
const visible = c => !!(c && c.el && !c.el.ignore && !c.el.invisible);

function statesOf(el) {
  if (!el) return null;
  const p = typeof el.getSymbolPath === 'function' ? el.getSymbolPath() : el;
  return (p && p.currentStates) || [];
}
function stateOf(chart, w) {
  const series = [];
  chart.getModel().eachSeries(function (sm) {
    const data = sm.getData();
    const view = chart.getViewOfSeriesModel(sm);
    const rec = { e: [], b: [], t: [] };
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      const st = statesOf(el);
      if (!st) continue;
      const raw = data.getRawIndex(i);
      if (st.indexOf('emphasis') >= 0) rec.e.push(raw);
      if (st.indexOf('blur') >= 0) rec.b.push(raw);
      if (el.__temp) rec.t.push(raw);
    }
    rec.poly = view && view._polyline ? (view._polyline.currentStates || []).join(',') : null;
    series.push(rec);
  });
  let tip = null;
  if (w.view) tip = visible(w.view._tooltipContent) ? w.which : null;
  return { series, tip };
}

// ---------- an integer point over an item (tooltip-actions.js) ----------
function ecData(el) {
  const k = Object.keys(el).find(n => /^__ec_inner_\d+$/.test(n) && el[n] && 'dataIndex' in el[n]);
  return k ? el[k] : null;
}
function dispatcherOf(el) {
  for (let e = el; e; e = e.__hostTarget || e.parent) {
    const d = ecData(e);
    if (d && d.dataIndex != null) return d;
  }
  return null;
}
function globalRect(el) {
  const r = el.getBoundingRect().clone();
  if (el.transform) r.applyTransform(el.transform);
  return r;
}
function pointOn(chart, seriesIndex, dataIndex, where) {
  const els = chart.getZr().storage.getDisplayList(true);
  const h = chart.getZr().handler;
  for (const el of els) {
    const d = dispatcherOf(el);
    if (!d || d.seriesIndex !== seriesIndex || d.dataIndex !== dataIndex || d.dataType) continue;
    const r = globalRect(el);
    const cx = Math.round(r.x + r.width / 2);
    const cy = Math.round(r.y + r.height / 2);
    const R = Math.ceil(Math.max(r.width, r.height) / 2) + 1;
    for (let rad = 0; rad <= R; rad++) {
      for (let dx = -rad; dx <= rad; dx++) {
        for (let dy = -rad; dy <= rad; dy++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== rad) continue;
          const hv = h.findHover(cx + dx, cy + dy);
          const hd = hv && hv.target ? dispatcherOf(hv.target) : null;
          if (hd && hd.seriesIndex === seriesIndex && hd.dataIndex === dataIndex && !hd.dataType) return [cx + dx, cy + dy];
        }
      }
    }
  }
  throw new OracleError(where + ': no point over ' + seriesIndex + '/' + dataIndex);
}

// =====================================================================
// the cases
// =====================================================================
const cats = ['a', 'b', 'c', 'd'];
const BARS = { animation: false, xAxis: { type: 'category', data: cats }, yAxis: { min: 0, max: 10 },
  series: [{ type: 'bar', name: 'B', data: [3, 9, 6, 8] }] };
const CASES = [
  {
    id: 'icon-line', note: 'iconStyle with a dashed border, its offset, a round cap, a bevel join and a miter limit; '
      + 'emphasis.iconStyle a list of a dash',
    option: Object.assign({ toolbox: { feature: { saveAsImage: {}, restore: {} },
      iconStyle: { borderWidth: 2, borderType: 'dashed', borderDashOffset: 1, borderCap: 'round', borderJoin: 'bevel', borderMiterLimit: 3 },
      emphasis: { iconStyle: { borderType: [2, 3] } } } }, BARS),
    steps: [
      { op: 'idle', ms: 0 },
      { op: 'move', at: 'icon:saveAsImage' },
      { op: 'move', at: [5, 300] },
    ],
  },
  {
    id: 'title-box', note: 'the title in a box: a background, a radius, a padding, white text in a bold italic serif of 14',
    option: Object.assign({ toolbox: { left: 'center', feature: { saveAsImage: {}, restore: {} },
      emphasis: { iconStyle: { textBackgroundColor: '#333333', textBorderRadius: 4, textPadding: [2, 6], textFill: '#ffffff',
        textFontFamily: 'serif', textFontWeight: 'bold', textFontStyle: 'italic', textFontSize: 14 } } } }, BARS),
    steps: [
      { op: 'move', at: 'icon:restore' },
      { op: 'move', at: [5, 300] },
    ],
  },
  {
    id: 'tooltip', note: 'toolbox.tooltip show: the icon\'s component tooltip -- its name by default, a template over name and '
      + 'title, the position bottom by default',
    option: Object.assign({ tooltip: {}, toolbox: { left: 'center', feature: { saveAsImage: {}, restore: {} }, tooltip: { show: true } } }, BARS),
    steps: [
      { op: 'move', at: 'icon:saveAsImage' },
      { op: 'move', at: [5, 300] },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'tooltip-fmt', note: 'toolbox.tooltip with a template ({a} is the name, {b} the title) and a position',
    option: Object.assign({ tooltip: {}, toolbox: { left: 'center', feature: { saveAsImage: {}, restore: {} },
      tooltip: { show: true, formatter: '{b} ({a})', position: 'left' } } }, BARS),
    steps: [
      { op: 'move', at: 'icon:restore' },
      { op: 'leave' },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'tooltip-off', note: 'the toolbox\'s own tooltip off (its default): a hover on an icon dispatches showTip and leaves the box '
      + 'the bar showed as it was',
    option: Object.assign({ tooltip: { trigger: 'item' }, toolbox: { left: 'center', feature: { saveAsImage: {} } } }, BARS),
    steps: [
      { op: 'move', at: [240, 200] },
      { op: 'move', at: 'icon:saveAsImage' },
      { op: 'idle', ms: 200 },
      { op: 'move', at: [5, 300] },
      { op: 'idle', ms: 200 },
    ],
  },
];

// =====================================================================
const TYPES = ['showtip', 'hidetip'];
const val = v => (v === undefined ? null : v);
function toolboxView(chart) {
  const m = chart.getModel().getComponent('toolbox', 0);
  return m ? chart.getViewOfComponentModel(m) : null;
}
function iconPaths(chart) {
  const out = [];
  const m = chart.getModel().getComponent('toolbox', 0);
  m.eachFeature ? null : null;
  const v = toolboxView(chart);
  v.group.eachChild(function (el) {
    if (el.__title !== undefined) out.push(el);
  });
  return out;
}
function iconKey(el) {
  return String(el.__title);
}
function globalRect(el) {
  const r = el.getBoundingRect().clone();
  el.updateTransform();
  if (el.transform) r.applyTransform(el.transform);
  return r;
}
function iconPoint(chart, title) {
  const map = { saveAsImage: 'Save as Image', restore: 'Restore' };
  for (const el of iconPaths(chart)) {
    if (iconKey(el) !== map[title]) continue;
    const r = globalRect(el);
    return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)];
  }
  throw new OracleError('no icon ' + title);
}
function stateOf3(chart, w) {
  const icons = iconPaths(chart).map(el => {
    const s = el.style;
    return { key: iconKey(el), states: (el.currentStates || []).slice(), style: {
      lineWidth: val(s.lineWidth), lineDash: val(s.lineDash), lineDashOffset: val(s.lineDashOffset),
      lineCap: val(s.lineCap), lineJoin: val(s.lineJoin), miterLimit: val(s.miterLimit) } };
  });
  let title = null;
  for (const el of iconPaths(chart)) {
    const t = el.getTextContent();
    if (!t || t.ignore || t.invisible) continue;
    t.updateTransform();
    const kids = t.childrenRef();
    let box = null;
    let tx = null;
    let ty = null;
    for (const k of kids) {
      k.updateTransform && k.updateTransform();
      if (k.type === 'rect' && !box) {
        const r = k.getBoundingRect().clone();
        const m = t.transform;
        if (m) r.applyTransform(m);
        box = [r.x, r.y, r.width, r.height];
      }
      if (k.type === 'tspan' && tx === null) {
        const p = [k.style.x, k.style.y];
        const m = t.transform;
        tx = m ? m[0] * p[0] + m[2] * p[1] + m[4] : p[0];
        ty = m ? m[1] * p[0] + m[3] * p[1] + m[5] : p[1];
      }
    }
    const s = t.style;
    title = { key: iconKey(el), text: val(s.text), font: val(s.font), fill: val(s.fill), backgroundColor: val(s.backgroundColor),
      borderRadius: val(s.borderRadius), padding: val(s.padding), box, textX: tx, textY: ty,
      tspanAlign: kids.filter(k => k.type === 'tspan').map(k => [k.style.textAlign, k.style.textBaseline])[0] || null };
  }
  let tip = null;
  if (w.view) {
    const c = w.view._tooltipContent;
    // the default markup (its style names are random per tooltip) is 'default'
    if (visible(c)) {
      tip = { which: w.which, text: c.el ? String(c.el.style.text) : null, box: w.box ? w.box.slice() : null };
      if (tip.text && /\{__EC_aUTo_\d+\|/.test(tip.text)) tip.text = 'default';
    }
  }
  return { icons, title, tip };
}
function watchTooltip2(chart) {
  const w = watchTooltip(chart);
  if (!w.view) return w;
  const content = w.view._tooltipContent;
  const mv = content.moveTo;
  content.moveTo = function (x, y) {
    w.box = [x, y];
    return mv.apply(this, arguments);
  };
  const show = w.view._showTooltipContent;
  w.view._showTooltipContent = function (tooltipModel, html, params) {
    // a show that returns at once changes nothing
    const before = w.which;
    const r = show.apply(this, arguments);
    if (!tooltipModel.get('showContent') || !tooltipModel.get('show')) w.which = before;
    else if (params && params.componentType === 'toolbox') w.which = 'toolbox:' + params.name;
    return r;
  };
  return w;
}
function runCase(def) {
  NOW = CLOCK0;
  TIMERS = [];
  const ch = newChart();
  const log = [];
  let w;
  try {
    ch.setOption(clone(def.option));
    frame(ch);
    w = watchTooltip2(ch);
    for (const t of TYPES) ch.on(t, e => log.push([0, t, jsonOf(e)]));
    const hd = ch.getZr().handler;
    const steps = [];
    for (const st of def.steps) {
      log.length = 0;
      const rec = { op: st.op };
      let at = st.at;
      if (typeof at === 'string') at = iconPoint(ch, at.slice(5));
      if (at) rec.at = at;
      if (st.op === 'move' || st.op === 'leave') advanceClock(NOW + STEP_DT);
      if (st.op === 'move') hd.mousemove(rawEvent('mousemove', at[0], at[1]));
      else if (st.op === 'leave') hd.mouseout(rawEvent('mouseout', W + 50, H / 2));
      else if (st.op === 'idle') {
        rec.ms = st.ms;
        advanceClock(NOW + st.ms);
      } else throw new OracleError('op ' + st.op);
      frame(ch);
      rec.events = log.slice();
      rec.state = stateOf3(ch, w);
      steps.push(rec);
    }
    return { id: def.id, note: def.note, option: plain(def.option, 0), steps };
  } finally {
    ch.dispose();
  }
}

function generate() {
  return CASES.map(runCase);
}

function anchors(cases) {
  const guards = [];
  const guard = (id, ok, what) => guards.push({ id, ok: !!ok, what });
  const cs = id => cases.find(c => c.id === id);
  const il = cs('icon-line');
  const i0 = il.steps[0].state.icons[0];
  guard('icon-dash', i0.style.lineDash === 'dashed' && i0.style.lineDashOffset === 1 && i0.style.lineCap === 'round'
    && i0.style.lineJoin === 'bevel' && i0.style.miterLimit === 3, 'getItemStyle maps the border keys');
  const i1 = il.steps[1].state.icons[0];
  guard('icon-emph', Array.isArray(i1.style.lineDash) && i1.states.indexOf('emphasis') >= 0, 'the emphasis dash');
  const tb = cs('title-box');
  const t0 = tb.steps[0].state.title;
  guard('title-box', t0 && t0.backgroundColor === '#333333' && t0.box && t0.borderRadius === 4, 'a box behind the title');
  const tp = cs('tooltip');
  guard('tip-name', tp.steps[0].state.tip && tp.steps[0].state.tip.text === 'saveAsImage' && tp.steps[0].state.tip.which === 'toolbox:saveAsImage', 'the name by default');
  const tf = cs('tooltip-fmt');
  guard('tip-fmt', tf.steps[0].state.tip && tf.steps[0].state.tip.text === 'Restore (restore)', 'the template');
  const to = cs('tooltip-off');
  guard('tip-off', to.steps[1].events.some(e => e[1] === 'showtip') && to.steps[2].state.tip && to.steps[2].state.tip.which.indexOf('item:') === 0
    && to.steps[2].state.tip.box[0] === to.steps[0].state.tip.box[0],
    'showTip dispatched, the box stays');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'Pointer steps: zrender Handler mousemove / mousedown + mouseup + click / mouseout from outside the canvas; each '
    + STEP_DT + ' ms after the last; a frame of every chart after every step.',
  'TooltipRichContent.getSize answers ' + SIZE.join(' x ') + '.',
];

let g1;
let json1;
let json2;
let guards;
try {
  g1 = generate();
  guards = anchors(g1);
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version,
    W, H, seed: SEED, clock: { start: CLOCK0, stepDt: STEP_DT },
    notes: NOTES, cases: g1, guards,
  };
  json1 = JSON.stringify(plain(out, 0), null, 1) + '\n';
  const nul = json1.indexOf('\\u0000');
  must(nul < 0, 'the fixture holds a \\u0000: ' + json1.slice(Math.max(0, nul - 300), nul + 40));
  JSON.parse(json1);
  if (!process.env.ORACLE_ONCE) {
    const g2 = generate();
    json2 = JSON.stringify(plain(Object.assign({}, out, { cases: g2, guards: anchors(g2) }), 0), null, 1) + '\n';
  } else json2 = json1;
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
if (process.env.ORACLE_DUMP) fs.writeFileSync(process.env.ORACLE_DUMP, json1);
const bad = guards.filter(gd => !gd.ok);
guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ': ' + gd.what));
const deterministic = json1 === json2;
console.log(g1.length + ' cases, ' + g1.reduce((n, c) => n + c.steps.length, 0) + ' steps; '
  + (guards.length - bad.length) + '/' + guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; '
  + logged.length + ' console messages' + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
