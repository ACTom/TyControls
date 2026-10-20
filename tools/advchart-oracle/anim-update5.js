/*
Upstream's own answers for round-2 batch R2-I7 (spec section 229f): the
update transitions the port did not animate, so their timing functions were
never asked and they jumped.

  markPoint  MarkPointView.renderSeries' SymbolDraw.updateData diffs mpData
             by getId -- the item's name, else its coordinate on the
             series' name dimension -- so a max that moves to another
             category is a symbol removed (Symbol.fadeOut: the label at
             once, the path to opacity 0 and scale 0, leave timing 200 ms
             cubicOut) and a symbol added (it pops in: enter timing, its
             row); a symbol whose id stays slides to its new place.
  pictorial  PictorialBarView.render's update of a kept bar (updateBar):
             the bundle updateProps its place; a repeated column's kept
             paths updateProps x / y / scale / rotation, the ones past the
             new count shrink to nothing and go, the new ones grow from
             nothing at their place; a single glyph updateProps all five;
             a symbolClip's clip path updateProps its shape -- each on the
             item's model at update timing, a delay function handed
             {index, count} for a repeated path and {} for the rest.
  tmLabel    LabelManager's pass after a treemap's merge: every label not
             ignored updateProps its layout (x / y / rotation, the host's
             frame) from the old one to the new at update timing and the
             host's row, while the treemap's own _doAnimation moves the
             host.

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off, with the clock of animation.js (the global
Date replaced BEFORE the dist loads; setTimeout a queue that never runs),
Math.random the port's xorshift32 and zrender's width table measuring text.

  node tools/advchart-oracle/anim-update5.js

writes tests/fixtures/advchart-anim-update5.json (ORACLE_OUT overrides).
Ends with process.exit().

-----------------------------------------------------------------------------
Numbers are the 16 lowercase hex digits of the IEEE double (big-endian; NaN
7ff8000000000000); strings, booleans and counts are plain JSON.

Top level: source, version, seed, measure {firstCode, ratio[] (hex)}, clock
{T0}, notes[], cases[], guards[].

A case: id, group, note, W, H, option, probes[], events[] (as
anim-update4.js: sample / frame / merge at t ms after T0). A sample's rec,
by probe:
  mp     per series s with markPoints: 'mp<s>/<i>' for mpData's item i
         {id, x, y (the Symbol group's place), sx, sy, op (its path's scale
         and opacity), n (clips on the group and the path)}; 'mp<s>/gone'
         [{id, x, y, sx, sy, op}] the symbols still in the group that
         mpData no longer holds (fading), by id.
  pict   per pictorialBar series s and data index i: 'pb<s>/<i>' {x, y
         (the bundle's place), n (its clips), clip: null | {sh [x, y,
         width, height], n}, paths [{ai (__pictorialAnimationIndex, null
         for a single glyph), x, y, sx, sy, rot, n}] in the bundle's order}.
  tml    per treemap s and raw index i whose content rect carries a label:
         'tl<s>/<i>' {x, y, rot (the text's own layout in its host's
         frame), op, n (its clips), gx, gy (its global place)}.

An option's function is written {$fn: name} (the test registers the same
name with the control's timing registry): 'pidx*30' (idx, params) =>
params && params.index != null ? params.index * 30 : 0.

Guards (any failure: nothing is written, exit 1): named discriminating facts
and the whole fixture generated twice, byte-identical.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

// ---------- the controlled clock (must precede loading the dist) ----------
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

// ---------- the random numbers: the port's xorshift32 ----------
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

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-anim-update5.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const hx = v => hex(typeof v === 'number' ? v : NaN);
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};
const arr = a => Array.from(a, x => hx(x));
const FNS = { 'pidx*30': (idx, params) => (params && params.index != null ? params.index * 30 : 0) };
function materialize(v) {
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    if (typeof v.$fn === 'string') {
      must(FNS[v.$fn], 'unknown $fn ' + v.$fn);
      return FNS[v.$fn];
    }
    const o = {};
    for (const k of Object.keys(v)) o[k] = materialize(v[k]);
    return o;
  }
  return v;
}
const nClip = el => (el && el.animators ? el.animators.filter(a => a.getClip()).length : 0);
const NULMARK = '\u2400';
const idText = s => String(s).split('\u0000').join(NULMARK);

// ---------- zrender's width table ----------
const FIRST_CODE = 32;
const LAST_CODE = 126;
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = Function('"use strict"; return (' + line.slice(line.indexOf('=') + 1).trim().replace(/;$/, '') + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, 'the width table is not 95 characters');
  return s;
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);

// ---------- the chart ----------
(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk(W, H) {
  rngState = SEED;
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
const zr = chart => chart.getZr();
function refresh(chart) { zr(chart).storage.getDisplayList(true); }

// ---------------------------------------------------------------------------
// the probes
// ---------------------------------------------------------------------------
function symRec(el) {
  const p = el.childAt(0);
  return { x: hx(el.x), y: hx(el.y), sx: hx(p.scaleX), sy: hx(p.scaleY),
    op: hx(p.style.opacity == null ? 1 : p.style.opacity), n: nClip(el) + nClip(p) };
}
// the series' mpData: its SymbolDraw's (keyed by the series' id)
function mpDataOf(chart, sm) {
  const view = markPointView(chart);
  const draw = view && view.markerGroupMap.get(sm.id);
  return draw ? draw._data : null;
}
function markPointView(chart) {
  return chart._componentsViews.find(v => v && v.type === 'markPoint');
}
const PROBES = {
  mp(chart, rec) {
    const view = markPointView(chart);
    if (!view) return;
    chart.getModel().eachSeries(sm => {
      const draw = view.markerGroupMap.get(sm.id);
      const data = mpDataOf(chart, sm);
      if (!draw || !data) return;
      const live = new Set();
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        live.add(el);
        const o = symRec(el);
        o.id = idText(data.getId(i));
        rec['mp' + sm.seriesIndex + '/' + i] = o;
      });
      const gone = [];
      draw.group.eachChild(el => {
        if (live.has(el) || !el.childAt) return;
        const o = symRec(el);
        o.id = idText(el.__r2i7Id);
        gone.push(o);
      });
      gone.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
      rec['mp' + sm.seriesIndex + '/gone'] = gone;
    });
  },
  pict(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'pictorialBar') return;
      const data = sm.getData();
      data.each(i => {
        const bar = data.getItemGraphicEl(i);
        if (!bar) return;
        const b = bar.__pictorialBundle;
        const cp = bar.__pictorialClipPath;
        const paths = [];
        b.eachChild(p => {
          paths.push({ ai: p.__pictorialAnimationIndex == null ? null : p.__pictorialAnimationIndex,
            x: hx(p.x), y: hx(p.y), sx: hx(p.scaleX), sy: hx(p.scaleY), rot: hx(p.rotation), n: nClip(p) });
        });
        rec['pb' + sm.seriesIndex + '/' + i] = { x: hx(b.x), y: hx(b.y), n: nClip(b),
          clip: cp ? { sh: arr([cp.shape.x, cp.shape.y, cp.shape.width, cp.shape.height]), n: nClip(cp) } : null,
          paths };
      });
    });
  },
  tml(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'treemap') return;
      const st = chart.getViewOfSeriesModel(sm)._storage;
      const n = sm.getData().count();
      for (let i = 0; i < n; i++) {
        const c = st.content[i];
        const t = c && c.getTextContent();
        if (!t || t.ignore || t.invisible || !t.style.text) continue;
        t.updateTransform();
        const m = t.getComputedTransform() || [1, 0, 0, 1, t.x, t.y];
        rec['tl' + sm.seriesIndex + '/' + i] = { x: hx(t.x), y: hx(t.y), rot: hx(t.rotation),
          op: hx(t.style.opacity == null ? 1 : t.style.opacity), n: nClip(t), gx: hx(m[4]), gy: hx(m[5]) };
      }
    });
  },
};

// the markPoint symbols by the id they were made for (a gone one keeps it)
function noteIds(chart) {
  const view = markPointView(chart);
  if (!view) return;
  chart.getModel().eachSeries(sm => {
    const data = mpDataOf(chart, sm);
    if (!data) return;
    data.each(i => {
      const el = data.getItemGraphicEl(i);
      if (el) el.__r2i7Id = data.getId(i);
    });
  });
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
function add(group, id, note, option, probes, events, more) {
  CASES.push(Object.assign({ group, id, note, W: 400, H: 300, option, probes, events }, more));
}
const T1 = 3000;
const after = (ts, from) => ts.map(t => ({ t: from + t, do: 'sample' }));

// ---- markPoint ----
const CAT = ['A', 'B', 'C', 'D', 'E'];
const LIN = { animationDurationUpdate: 1000, animationEasingUpdate: 'linear' };
add('markPoint', 'mp-move', "the max moves from D to C and the min from C to B: mpData's ids are the category coordinates ('3' -> '2', '2' -> '1'), so both old symbols fade (200 ms cubicOut) and two new ones pop in (enter timing: 600 ms linear); the custom point by name stays and slides (update timing, 1000 ms linear)",
  { animation: true, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' },
    series: [Object.assign({ type: 'line', data: [3, 5, 2, 6, 4], animationDuration: 600, animationEasing: 'linear',
      markPoint: { data: [{ type: 'max' }, { type: 'min' }, { name: 'here', coord: ['B', 5] }] } }, LIN)] },
  ['mp'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [4, 2, 6, 3, 5], markPoint: { data: [{ type: 'max' }, { type: 'min' },
      { name: 'here', coord: ['E', 3] }] } }] } },
    ...after([0, 1, 16, 100, 150, 199, 200, 201, 300, 599, 600, 601, 999, 1000, 1001], T1)]);
add('markPoint', 'mp-stay', "the max stays on D with a new value: its id is the same -- it slides (update timing) and nothing fades",
  { animation: true, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value', max: 10 },
    series: [Object.assign({ type: 'line', data: [3, 5, 2, 6, 4], markPoint: { data: [{ type: 'max' }] } }, LIN)] },
  ['mp'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [3, 5, 2, 8, 4] }] } },
    ...after([0, 1, 100, 500, 999, 1000, 1001], T1)]);

// ---- pictorial ----
const PCAT = ['a', 'b', 'c'];
const PB = (series, extra) => Object.assign({ animation: true, xAxis: { type: 'category', data: PCAT },
  yAxis: { type: 'value', max: 100 }, series }, extra || {});
const PS = (o) => Object.assign({ type: 'pictorialBar', symbol: 'rect', symbolSize: [20, 8], symbolMargin: 2,
  animationDurationUpdate: 600, animationEasingUpdate: 'linear', animationDelayUpdate: { $fn: 'pidx*30' } }, o);
add('pictorial', 'pb-repeat', "repeated columns: a merge raises a and lowers c -- the bundles move, the kept paths slide (each its {index, count} delay: 30 ms a step), a's new ones grow from nothing at their place, c's extra ones shrink and go",
  PB([PS({ data: [{ value: 40, symbolRepeat: true }, { value: 60, symbolRepeat: true }, { value: 70, symbolRepeat: true }] })]),
  ['pict'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ value: 60, symbolRepeat: true }, { value: 60, symbolRepeat: true },
      { value: 40, symbolRepeat: true }] }] } },
    ...after([0, 1, 16, 100, 200, 300, 599, 600, 601, 700, 900, 901, 1000], T1)]);
add('pictorial', 'pb-single', "single glyphs sized to their value (symbolSize ['100%', 20]): a merge changes the values -- the main path updateProps x / y / scale / rotation, the bundle its place; {} for the delay function (0)",
  PB([PS({ symbolSize: ['100%', 20], symbolRotate: 30, data: [30, 60, 90] })]),
  ['pict'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [60, 30, 80], symbolRotate: 0 }] } },
    ...after([0, 1, 100, 300, 599, 600, 601], T1)]);
add('pictorial', 'pb-move', "single glyphs at the end of their bars (symbolPosition end): a merge changes the values -- the main path's place in the bundle slides with the new length",
  PB([PS({ symbolPosition: 'end', symbolSize: [20, 20], data: [30, 60, 90] })]),
  ['pict'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [60, 30, 80] }] } },
    ...after([0, 1, 100, 300, 599, 600, 601], T1)]);
add('pictorial', 'pb-clip', "symbolClip: the clip path updateProps its shape (the new length along the value axis)",
  PB([PS({ symbolRepeat: 'fixed', symbolClip: true, symbolBoundingData: 100, data: [30, 60, 90] })]),
  ['pict'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [70, 20, 50] }] } },
    ...after([0, 1, 100, 300, 599, 600, 601], T1)]);

// ---- the treemap's labels ----
const TM = [{ name: 'a', children: [{ name: 'a1', value: 6 }, { name: 'a2', value: 4 }] },
  { name: 'b', children: [{ name: 'b1', value: 3 }, { name: 'b2', value: 3 }] }, { name: 'c', value: 4 }];
add('tmLabel', 'tml-merge', "a merge that changes values: every label not ignored moves from its old layout to its new one in its host's frame (LabelManager: update timing 1000 ms linear, the host's row) while the host's rect moves on the treemap's own (animationDurationUpdate, animationEasing quinticInOut)",
  { animation: true, series: [{ type: 'treemap', breadcrumb: { show: false }, width: 300, height: 200, left: 50, top: 50,
    animationDurationUpdate: 1000, animationEasingUpdate: 'linear', data: TM }] },
  ['tml'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'a', children: [{ name: 'a1', value: 2 }, { name: 'a2', value: 8 }] },
      { name: 'b', children: [{ name: 'b1', value: 5 }, { name: 'b2', value: 1 }] }, { name: 'c', value: 6 }] }] } },
    ...after([0, 1, 16, 100, 500, 999, 1000, 1001], T1)]);

add('tmLabel', 'tml-struct', "a merge that adds a3 under a and d at the top and takes b2 away: the new nodes' labels have no old layout -- LabelManager fades them in (enter timing: 600 ms linear, their rows); the kept ones ride their hosts",
  { animation: true, series: [{ type: 'treemap', breadcrumb: { show: false }, width: 300, height: 200, left: 50, top: 50,
    animationDuration: 600, animationEasing: 'linear', animationDurationUpdate: 1000, animationEasingUpdate: 'linear', data: TM }] },
  ['tml'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'a', children: [{ name: 'a1', value: 6 }, { name: 'a2', value: 4 }, { name: 'a3', value: 2 }] },
      { name: 'b', children: [{ name: 'b1', value: 3 }] }, { name: 'c', value: 4 }, { name: 'd', value: 3 }] }] } },
    ...after([0, 1, 16, 100, 300, 599, 600, 601, 999, 1000, 1001], T1)]);

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function readRec(chart, probes) {
  const rec = {};
  probes.forEach(p => PROBES[p](chart, rec));
  return rec;
}
function runCase(c) {
  const chart = mk(c.W, c.H);
  try {
    const out = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: clone(c.option),
      probes: c.probes, events: [] };
    quiet(() => chart.setOption(materialize(clone(c.option))));
    noteIds(chart);
    c.events.forEach(ev => {
      NOW = T0 + ev.t;
      const o = clone(ev);
      if (ev.do === 'sample') {
        zr(chart).animation.update();
        refresh(chart);
        o.rec = readRec(chart, c.probes);
      }
      else if (ev.do === 'frame') zr(chart).animation.update();
      else if (ev.do === 'merge') quiet(() => chart.setOption(materialize(clone(ev.option))));
      else must(false, 'an event it does not know: ' + ev.do);
      noteIds(chart);
      out.events.push(o);
    });
    return out;
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// named guards
// ---------------------------------------------------------------------------
function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => out.cases.find(q => q.id === id);
  const rec = (id, t, key) => {
    const smp = cs(id).events.filter(q => q.do === 'sample' && q.t === t).pop();
    must(smp, id + ': no sample at ' + t);
    return smp.rec[key];
  };
  const n = v => num(v);
  // markPoint
  guard('mp-move: the ids are the category coordinates', rec('mp-move', T1 - 1, 'mp0/0').id === '3'
    && rec('mp-move', T1, 'mp0/0').id === '2');
  guard('mp-move: the old max fades', (() => {
    const gone = rec('mp-move', T1 + 100, 'mp0/gone');
    return gone.length === 1 && gone[0].id === '3' && n(gone[0].op) > 0 && n(gone[0].op) < 1;
  })());
  guard('mp-move: the gone ones are gone after 200 ms', rec('mp-move', T1 + 201, 'mp0/gone').length === 0);
  guard('mp-move: the new max takes the old min symbol (both id 2) and the new min pops in',
    rec('mp-move', T1, 'mp0/0').n > 0 && n(rec('mp-move', T1, 'mp0/1').sx) === 0 && rec('mp-move', T1 + 100, 'mp0/1').n > 0);
  guard('mp-move: the named point slides', rec('mp-move', T1 + 100, 'mp0/2').n > 0
    && n(rec('mp-move', T1 + 100, 'mp0/2').x) !== n(rec('mp-move', T1 + 1001, 'mp0/2').x));
  guard('mp-stay: nothing fades', rec('mp-stay', T1 + 100, 'mp0/gone').length === 0 && rec('mp-stay', T1 + 100, 'mp0/0').n > 0);
  // pictorial
  guard('pb-repeat: the new paths of a grow', (() => {
    const p = rec('pb-repeat', T1 + 300, 'pb0/0').paths;
    return p.length === 9 && p[8].n === 1 && n(p[8].sx) > 0;
  })());
  guard('pb-repeat: c has more paths than its new count while they shrink', (() => {
    const a = rec('pb-repeat', T1 + 100, 'pb0/2').paths.length;
    const b = rec('pb-repeat', T1 + 1000, 'pb0/2').paths.length;
    return a > b;
  })());
  guard('pb-repeat: a path waits its index * 30 ms', (() => {
    const p = rec('pb-repeat', T1 + 200, 'pb0/0').paths;
    return n(p[6].sx) > 0 && n(p[8].sx) === 0;
  })());
  guard('pb-single: the main path rotates', n(rec('pb-single', T1 + 300, 'pb0/0').paths[0].rot) !== n(rec('pb-single', T1 - 1, 'pb0/0').paths[0].rot));
  guard('pb-clip: the clip path tweens', rec('pb-clip', T1 + 100, 'pb0/0').clip.n === 1);
  // the treemap's labels
  guard('tml-merge: the labels ride their hosts (their own layout stays)', (() => {
    const a = rec('tml-merge', T1 + 500, 'tl0/2');
    const b = rec('tml-merge', T1 - 1, 'tl0/2');
    return a.n === 0 && a.x === b.x && n(a.gx) !== n(b.gx);
  })());
  guard('tml-struct: the label of a new node fades in', (() => {
    const r = cs('tml-struct').events.find(q => q.do === 'sample' && q.t === T1 + 100).rec;
    return Object.keys(r).some(k => r[k].n > 0 && n(r[k].op) < 1);
  })());
  return g;
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    clock: { T0 },
    notes: [
      'every chart: chart._ssr false, env.node off, 400 x 300; the first setOption at T0.',
      'events in order at T0 + t; a sample is zr.animation.update(), a refresh of the display list, and a read of what the case\'s probes name.',
      'an id holds NULs: each written U+2400.',
    ],
    cases: CASES.map(runCase),
  };
  out.guards = guards(out);
  return out;
}
let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = process.env.ORACLE_ONCE ? json1 : JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (process.env.ORACLE_DUMP) fs.writeFileSync(process.env.ORACLE_DUMP, json1);
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
const deterministic = json1 === json2;
const nul = json1.indexOf('\\u0000') >= 0;
let parses = true;
try { JSON.parse(json1); } catch (e) { parses = false; }
let nSamples = 0;
out1.cases.forEach(q => q.events.forEach(e => { if (e.do === 'sample') nSamples++; }));
console.log(out1.cases.length + ' cases; ' + nSamples + ' samples; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : '')
  + '; ' + warnings + ' warnings');
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
