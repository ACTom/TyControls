/*
Upstream's own answers for the fix phase, round 2, batch R2-C: the update
transitions still missing after F3d.

  sunburst  SunburstView.render on a render that is not a drill (a merge):
            the DataDiffer over the view root's nodes by getId -- a kept
            piece updateProps its whole shape (update timing, no row), a new
            one grows r from r0 (enter timing, the row), a gone one is
            removed at once; LabelManager moves a kept label from its old x /
            y / rotation (update timing, the row) and fades a new one in.
  treemap   TreemapView.render with no payload (a merge): _doRender's
            hierarchical DataDiffer by getId between the old tree and the
            new one, and _doAnimation -- the kept elements from their old
            place and shape, the new ones out of their parent's old corner,
            the deleted ones shrinking to their parent's centre and fading;
            animationDurationUpdate and animationEasing, no delay.
  roam      an animated merge that writes a view's centre / zoom: the
            graph's main group, the tree's view group and the geo's
            transform group updateProps to the new view transform (update
            timing, no row) -- applyViewCoordSysTransToElement with the
            model, MapDraw's isFirstDraw false.
  force     a force graph after a legend filter (and a merge): the layout
            starts from preservedPoints by node id, not afresh.
  step      a line whose `step` changed: LineView.render's init branch --
            a new polyline, the clip grown again, every symbol popping in
            again on its delay.
  treeData  a tree's merge that changes its data: TreeView.render's diff
            by getId (old order: update / remove, then add), removeNode /
            removeNodeEdge walking the OLD tree's parent chain and reading
            the old data's layout.

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off, with the clock of animation.js (the global
Date replaced BEFORE the dist loads; setTimeout a queue that never runs),
Math.random the port's xorshift32 and zrender's width table measuring text.

  node tools/advchart-oracle/anim-update4.js

writes tests/fixtures/advchart-anim-update4.json (ORACLE_OUT overrides).
Ends with process.exit().

-----------------------------------------------------------------------------
Numbers are the 16 lowercase hex digits of the IEEE double (big-endian; NaN
7ff8000000000000); strings, booleans and counts are plain JSON.

Top level: source, version, seed, measure {firstCode, ratio[] (hex)}, clock
{T0}, maps [{name, text}], notes[], cases[], guards[], themeCheck {clips}.

A case: id, group, note, W, H, option, probes[], events[]. The first
setOption is at T0. An event, in order, at t ms after T0:
  {t, do: 'sample', rec}       zr.animation.update(), then what the probes
                               read
  {t, do: 'frame'}             zr.animation.update(), nothing recorded
  {t, do: 'merge', option}     setOption(option)
  {t, do: 'action', action}    dispatchAction(action)
A sample's rec, by probe:
  graph  as anim-update3's: 'g<s>/view' {x, y, scaleX, scaleY, n};
         'g<s>/node<i>' {raw, x, y, gs, sx, sy, op, n, wx, wy, ws};
         'g<s>/ghost<i>'; 'g<s>/edge<i>' {x1, y1, x2, y2, cpx1, cpy1,
         percent, n}.
  tree   as anim-update3's: 'tr<s>/view', 'tr<s>/node<i>' {ghost, x, y, sx,
         sy, op, gop, n, wx, wy, ws}, 'tr<s>/ghost<i>' (by the OLD data
         index), 'tr<s>/edge<i>' / 'tr<s>/gedge<i>' a curve's {x1, y1,
         cpx1, cpy1, cpx2, cpy2, x2, y2, op, n} or a TreePath's
         {parentPoint[], childPoints[], op, n}.
  sun    per sunburst s and data index i of the piece drawn for it:
         'sb<s>/<i>' {sh [cx, cy, r0, r, startAngle, endAngle], n (clips on
         the piece)}; 'sb<s>/<i>/label' {x, y, rot, op, n} its text.
  tm     per treemap s and raw index i in the storage: 'tm<s>/<i>' {g [x, y]
         the node group, gn (its clips), bg, ct: null or {sh [x, y, w, h],
         t [x, y] (the global translation after the frame), op, n}};
         'tm<s>/del' [{kind ('nodeGroup' | 'background' | 'content'), di
         (the OLD raw index), g [x, y] | sh [x, y, w, h] and t, op}]
         the deleted elements still in the container; 'tm<s>/state'.
  geo    per geo component g: 'geo<g>/group' {x, y, scaleX, scaleY, n} the
         MapDraw's transform group; per map series s drawing its own map:
         'map<s>/group' the same.
  line   per line series s: 'ln<s>/clip' {x, y, width, height, n} the
         line group's clip rect; 'ln<s>/sym<i>' {sx, sy, n} the symbol's
         group scale; 'ln<s>/poly' {n, len} the polyline's clips and its
         points' length.

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
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-anim-update4.json');

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
const nClip = el => (el && el.animators ? el.animators.filter(a => a.getClip()).length : 0);

// ---------- zrender's width table ----------
const FIRST_CODE = 32;
const LAST_CODE = 126;
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

// ---------- the map ----------
function sq(x0, y0, x1, y1) { return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]; }
const MAPS = [{ name: 'r2c', text: JSON.stringify({ type: 'FeatureCollection', features: [
  { type: 'Feature', properties: { name: 'A' }, geometry: { type: 'Polygon', coordinates: [sq(0, 0, 10, 10)] } },
  { type: 'Feature', properties: { name: 'B' }, geometry: { type: 'Polygon', coordinates: [sq(10, 0, 20, 10)] } },
  { type: 'Feature', properties: { name: 'C' }, geometry: { type: 'Polygon', coordinates: [sq(0, 10, 20, 16)] } }] }) }];
function registerMaps() {
  for (const m of MAPS) echarts.registerMap(m.name, m.text);
}

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

function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'dataIndex' in el[k]) return el[k];
  }
  return null;
}

// ---------------------------------------------------------------------------
// the probes
// ---------------------------------------------------------------------------
const glob = (o, el) => {
  const m = el.transform || [1, 0, 0, 1, el.x, el.y];
  o.wx = hx(m[4]);
  o.wy = hx(m[5]);
  o.ws = hx(m[0]);
  return o;
};
function symbolRec(el) {
  const p = el.childAt(0);
  return glob({ x: hx(el.x), y: hx(el.y), gs: hx(el.scaleX), sx: hx(p.scaleX), sy: hx(p.scaleY),
    op: hx(p.style.opacity), n: nClip(el) + nClip(p) }, p);
}
function rectOf(el) {
  if (!el) return null;
  const m = el.transform || [1, 0, 0, 1, 0, 0];
  return { sh: arr([el.shape.x, el.shape.y, el.shape.width, el.shape.height]), t: arr([m[4], m[5]]),
    op: hx(el.style.opacity == null ? 1 : el.style.opacity), n: nClip(el) };
}
const PROBES = {
  graph(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'graph') return;
      const v = chart.getViewOfSeriesModel(sm);
      const key = 'g' + sm.seriesIndex;
      const mg = v._mainGroup;
      if (sm.coordinateSystem && sm.coordinateSystem.type === 'view') {
        rec[key + '/view'] = { x: hx(mg.x), y: hx(mg.y), scaleX: hx(mg.scaleX), scaleY: hx(mg.scaleY), n: nClip(mg) };
      }
      const data = sm.getData();
      const live = new Set();
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        live.add(el);
        const o = symbolRec(el);
        o.raw = data.getRawIndex(i);
        rec[key + '/node' + i] = o;
      });
      v._symbolDraw.group.eachChild(el => {
        if (live.has(el) || !el.childAt) return;
        const ec = ecDataOf(el.childAt(0)) || ecDataOf(el);
        must(ec, 'a ghost without its data index');
        rec[key + '/ghost' + ec.dataIndex] = symbolRec(el);
      });
      const edata = sm.getEdgeData();
      edata.each(i => {
        const g = edata.getItemGraphicEl(i);
        if (!g) return;
        const line = g.childOfName('line');
        const s = line.shape;
        rec[key + '/edge' + i] = { x1: hx(s.x1), y1: hx(s.y1), x2: hx(s.x2), y2: hx(s.y2), cpx1: hx(s.cpx1),
          cpy1: hx(s.cpy1), percent: hx(s.percent), n: nClip(line) };
      });
    });
  },
  tree(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'tree') return;
      const v = chart.getViewOfSeriesModel(sm);
      const key = 'tr' + sm.seriesIndex;
      const g = v.group;
      rec[key + '/view'] = { x: hx(g.x), y: hx(g.y), scaleX: hx(g.scaleX), scaleY: hx(g.scaleY), n: nClip(g) };
      const data = sm.getData();
      const live = new Set();
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        if (el) live.add(el);
      });
      v._mainGroup.eachChild(el => {
        if (!el.getSymbolPath) return;
        const p = el.getSymbolPath();
        const ec = ecDataOf(p) || ecDataOf(el);
        must(ec, 'a tree symbol without its data index');
        const i = ec.dataIndex;
        const o = symbolRec(el);
        const ghost = !live.has(el);
        let nk = key + (ghost ? '/ghost' : '/node') + i;
        if (ghost) {
          let k = 2;
          while (rec[nk]) nk = key + '/ghost' + i + '_' + k++;
        }
        must(!rec[nk], 'two live tree symbols of one data index');
        rec[nk] = o;
        const e = el.__edge;
        if (e && e.parent === v._mainGroup) {
          const s = e.shape;
          const eo = { op: hx(e.style.opacity), n: nClip(e) };
          if (s.parentPoint) {
            eo.parentPoint = arr(s.parentPoint);
            eo.childPoints = arr([].concat(...s.childPoints));
          }
          else {
            for (const k of ['x1', 'y1', 'cpx1', 'cpy1', 'cpx2', 'cpy2', 'x2', 'y2']) eo[k] = hx(s[k]);
          }
          rec[nk.replace('/node', '/edge').replace('/ghost', '/gedge')] = eo;
        }
      });
    });
  },
  sun(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'sunburst') return;
      const v = chart.getViewOfSeriesModel(sm);
      for (const el of v.group.children()) {
        if (el === v.virtualPiece) continue;
        const ec = ecDataOf(el);
        must(ec, 'a sunburst piece without its data index');
        const key = 'sb' + sm.seriesIndex + '/' + ec.dataIndex;
        must(!rec[key], 'two pieces of one data index');
        const s = el.shape;
        rec[key] = { sh: arr([s.cx, s.cy, s.r0, s.r, s.startAngle, s.endAngle]), n: nClip(el) };
        const t = el.getTextContent();
        if (t && !t.ignore && t.style.text) {
          rec[key + '/label'] = { x: hx(t.x), y: hx(t.y), rot: hx(t.rotation),
            op: hx(t.style.opacity == null ? 1 : t.style.opacity), n: nClip(t) };
        }
      }
    });
  },
  tm(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'treemap') return;
      const v = chart.getViewOfSeriesModel(sm);
      const st = v._storage;
      const key = 'tm' + sm.seriesIndex;
      const known = new Set();
      const n = sm.getData().count();
      for (let i = 0; i < n; i++) {
        const g = st.nodeGroup[i];
        if (!g) continue;
        known.add(g);
        if (st.background[i]) known.add(st.background[i]);
        if (st.content[i]) known.add(st.content[i]);
        rec[key + '/' + i] = { g: arr([g.x, g.y]), gn: nClip(g), bg: rectOf(st.background[i]), ct: rectOf(st.content[i]) };
      }
      const del = [];
      const cg = v._containerGroup;
      if (cg) {
        cg.traverse(el => {
          if (known.has(el) || el === cg) return;
          if (el.type !== 'rect' && !(el.isGroup && el.parent && el.parent !== cg.parent)) return;
          const who = DELETED.get(el);
          if (!who) return;
          const o = { kind: who.kind, di: who.di, op: hx(el.style ? (el.style.opacity == null ? 1 : el.style.opacity) : 1) };
          if (el.isGroup) o.g = arr([el.x, el.y]);
          else {
            o.sh = arr([el.shape.x, el.shape.y, el.shape.width, el.shape.height]);
            const m = el.transform || [1, 0, 0, 1, 0, 0];
            o.t = arr([m[4], m[5]]);
          }
          del.push(o);
        });
      }
      del.sort((a, b) => (a.kind < b.kind ? -1 : a.kind > b.kind ? 1 : a.di - b.di));
      rec[key + '/del'] = del;
      rec[key + '/state'] = v._state;
    });
  },
  geo(chart, rec) {
    let g = 0;
    chart.getModel().eachComponent('geo', gm => {
      const view = chart.getViewOfComponentModel(gm);
      const md = view && view._mapDraw;
      if (md) {
        const tg = md._transformGroup;
        rec['geo' + g + '/group'] = { x: hx(tg.x), y: hx(tg.y), scaleX: hx(tg.scaleX), scaleY: hx(tg.scaleY), n: nClip(tg) };
      }
      g++;
    });
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'map') return;
      const md = chart.getViewOfSeriesModel(sm)._mapDraw;
      if (!md) return;
      const tg = md._transformGroup;
      rec['map' + sm.seriesIndex + '/group'] = { x: hx(tg.x), y: hx(tg.y), scaleX: hx(tg.scaleX), scaleY: hx(tg.scaleY), n: nClip(tg) };
    });
  },
  line(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'line') return;
      const v = chart.getViewOfSeriesModel(sm);
      const key = 'ln' + sm.seriesIndex;
      const cp = v._lineGroup.getClipPath();
      if (cp) rec[key + '/clip'] = { x: hx(cp.shape.x), y: hx(cp.shape.y), width: hx(cp.shape.width), height: hx(cp.shape.height), n: nClip(cp) };
      const data = sm.getData();
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        rec[key + '/sym' + i] = { sx: hx(el.scaleX), sy: hx(el.scaleY), n: nClip(el) };
      });
      if (v._polyline) rec[key + '/poly'] = { n: nClip(v._polyline), len: v._polyline.shape.points.length };
    });
  },
};

// the treemap's elements by the node they were stored for, as a render
// stores them: a deleted one is known by the storage it left
const DELETED = new Map();
function noteStorage(chart) {
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'treemap') return;
    const st = chart.getViewOfSeriesModel(sm)._storage;
    if (!st) return;
    for (const kind of ['nodeGroup', 'background', 'content']) {
      st[kind].forEach((el, i) => { if (el) DELETED.set(el, { kind, di: i }); });
    }
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
const S_UPD = [0, 1, 16, 50, 100, 150, 200, 299, 300, 301, 500, 1000];
const LIN = { animationDurationUpdate: 1000, animationEasingUpdate: 'linear' };
const S_LIN = [0, 1, 16, 100, 199, 200, 201, 250, 500, 999, 1000, 1001, 1500];

// ---- sunburst ----
const SB = [{ name: 'a', children: [{ name: 'a1', value: 3 }, { name: 'a2', value: 2 }] },
  { name: 'b', children: [{ name: 'b1', value: 4 }] }, { name: 'c', value: 2 }];
add('sunburst', 'sb-merge', "a merge that changes the values, takes a2 away and adds a3 and d: the kept pieces' shapes tween (update timing, no row), a new piece grows r from r0 (enter timing, its row), a2 goes at once; a kept label moves from its old x / y / rotation, a new one fades in",
  { animation: true, series: [Object.assign({ type: 'sunburst', radius: [20, '80%'], label: { show: true }, data: SB,
    animationDuration: 600, animationEasing: 'linear' }, LIN)] },
  ['sun'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'a', children: [{ name: 'a1', value: 5 }, { name: 'a3', value: 1 }] },
      { name: 'b', children: [{ name: 'b1', value: 2 }] }, { name: 'c', value: 3 }, { name: 'd', value: 2 }] }] } },
    ...after(S_LIN, T1)]);
add('sunburst', 'sb-default', "the sunburst's own update timing (500 ms, cubicInOut): a merge that only changes values; the labels turned radially",
  { animation: true, series: [{ type: 'sunburst', label: { rotate: 'radial' }, data: SB }] },
  ['sun'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'a', children: [{ name: 'a1', value: 1 }, { name: 'a2', value: 6 }] },
      { name: 'b', children: [{ name: 'b1', value: 1 }] }, { name: 'c', value: 2 }] }] } },
    ...after([0, 1, 16, 100, 250, 400, 499, 500, 501], T1)]);
add('sunburst', 'sb-midway', "a second merge 200 ms into the first: every kept piece tweens on from where it is",
  { animation: true, series: [Object.assign({ type: 'sunburst', data: SB }, LIN)] },
  ['sun'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'a', children: [{ name: 'a1', value: 6 }, { name: 'a2', value: 2 }] },
      { name: 'b', children: [{ name: 'b1', value: 4 }] }, { name: 'c', value: 2 }] }] } },
    ...after([0, 100, 200], T1),
    { t: T1 + 200, do: 'merge', option: { series: [{ data: [{ name: 'a', children: [{ name: 'a1', value: 1 }, { name: 'a2', value: 2 }] },
      { name: 'b', children: [{ name: 'b1', value: 4 }] }, { name: 'c', value: 6 }] }] } },
    ...after([200, 201, 500, 1199, 1200, 1201], T1)]);

// ---- treemap ----
const TM = [{ name: 'a', children: [{ name: 'a1', value: 6 }, { name: 'a2', value: 4 }] },
  { name: 'b', children: [{ name: 'b1', value: 3 }, { name: 'b2', value: 3 }] }, { name: 'c', value: 4 }];
const TMO = { type: 'treemap', breadcrumb: { show: false }, width: 300, height: 200, left: 50, top: 50 };
add('treemap', 'tm-merge', "a merge that only changes values (the same names: the hierarchical diff pairs every node): every kept group and rect tweens from its old place and shape (animationDurationUpdate 1000, linear, no delay)",
  { animation: true, series: [Object.assign({}, TMO, { data: TM, animationDurationUpdate: 1000, animationEasing: 'linear' })] },
  ['tm'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'a', children: [{ name: 'a1', value: 2 }, { name: 'a2', value: 8 }] },
      { name: 'b', children: [{ name: 'b1', value: 5 }, { name: 'b2', value: 1 }] }, { name: 'c', value: 6 }] }] } },
    ...after([0, 1, 16, 100, 500, 999, 1000, 1001], T1)]);
add('treemap', 'tm-struct', "a merge that takes b2 away and adds a3 under a and d at the top: the new elements come out of their parent's old corner and fade in, b2's shrink to b's centre and fade; the default timing (900 ms, quinticInOut)",
  { animation: true, series: [Object.assign({}, TMO, { data: TM })] },
  ['tm'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'a', children: [{ name: 'a1', value: 6 }, { name: 'a2', value: 4 }, { name: 'a3', value: 2 }] },
      { name: 'b', children: [{ name: 'b1', value: 3 }] }, { name: 'c', value: 4 }, { name: 'd', value: 3 }] }] } },
    ...after([0, 1, 16, 100, 450, 899, 900, 901], T1)]);
add('treemap', 'tm-renamed', "a merge that renames a1 and moves c into b: the diff is by name within each parent, so the renamed one is new and the old one deleted, c leaves the top and comes in under b",
  { animation: true, series: [Object.assign({}, TMO, { data: TM, animationDurationUpdate: 600, animationEasing: 'linear' })] },
  ['tm'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'a', children: [{ name: 'x1', value: 6 }, { name: 'a2', value: 4 }] },
      { name: 'b', children: [{ name: 'b1', value: 3 }, { name: 'b2', value: 3 }, { name: 'c', value: 4 }] }] }] } },
    ...after([0, 1, 100, 300, 599, 600, 601], T1)]);

// ---- roam ----
const GN = [{ name: 'a', x: 10, y: 10 }, { name: 'b', x: 100, y: 50 }, { name: 'c', x: 50, y: 100 }];
const GL = [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }];
add('roam', 'graph-roam', "a graph on a view: a merge writes zoom 2 and a centre -- the main group tweens to the new view transform (update timing, no row), the compensation scale is set at once, the nodes stay at their place in the group",
  { animation: true, series: [Object.assign({ type: 'graph', layout: 'none', roam: true, symbolSize: 16, data: GN, links: GL }, LIN)] },
  ['graph'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ zoom: 2, center: [60, 40] }] } }, ...after(S_LIN, T1)]);
const TREE = [{ name: 'root', children: [
  { name: 'a', children: [{ name: 'a1' }, { name: 'a2', children: [{ name: 'a21' }] }] },
  { name: 'b', children: [{ name: 'b1' }, { name: 'b2' }] },
  { name: 'c' }] }];
add('roam', 'tree-roam', "a tree: a merge writes zoom 1.5 -- the view group tweens (update timing, no row); every node keeps its place in the group",
  { animation: true, series: [Object.assign({ type: 'tree', data: TREE, initialTreeDepth: -1, roam: true }, LIN)] },
  ['tree'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ zoom: 1.5 }] } }, ...after(S_LIN, T1)]);
add('roam', 'geo-roam', "a geo component: a merge writes zoom 2 and a centre -- MapDraw's transform group tweens to the new roam transform (the geo's model: the global update timing, 300 ms cubicInOut)",
  { animation: true, geo: { map: 'r2c', roam: true } },
  ['geo'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { geo: { zoom: 2, center: [10, 8] } } }, ...after(S_UPD, T1)]);
add('roam', 'map-roam', "a map series drawing its own map: a merge writes zoom 1.5 and a centre -- its MapDraw's transform group tweens on the series' model (its own update timing: 800 ms linear)",
  { animation: true, series: [{ type: 'map', map: 'r2c', roam: true, animationDurationUpdate: 800, animationEasingUpdate: 'linear',
    data: [{ name: 'A', value: 1 }, { name: 'C', value: 3 }] }] },
  ['geo'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ zoom: 1.5, center: [5, 5] }] } }, ...after([0, 1, 100, 400, 799, 800, 801], T1)]);

// ---- force ----
const FN = [{ name: 'a', x: 10, y: 10, category: 0 }, { name: 'b', x: 100, y: 50, category: 1 },
  { name: 'c', x: 50, y: 100, category: 0 }, { name: 'd', x: 150, y: 120, category: 1 }, { name: 'e', x: 80, y: 160, category: 0 }];
const FL = [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }, { source: 'c', target: 'd' },
  { source: 'd', target: 'e' }, { source: 'e', target: 'a' }];
const FCATS = [{ name: 'A' }, { name: 'B' }];
add('force', 'force-legend', "a force layout without layoutAnimation: the legend switches category B off and on again -- each layout starts from preservedPoints by node id (a node switched off keeps its last place there), not from the option's x / y",
  { animation: true, legend: { data: ['A', 'B'] },
    series: [{ type: 'graph', layout: 'force', force: { layoutAnimation: false, repulsion: 80 }, categories: FCATS, symbolSize: 16,
      edgeSymbol: ['none', 'arrow'], data: FN, links: FL }] },
  ['graph'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'legendToggleSelect', name: 'B' } }, ...after([0, 1, 100, 300], T1),
    { t: T1 + 1000, do: 'action', action: { type: 'legendToggleSelect', name: 'B' } }, ...after([0, 1, 100, 300], T1 + 1000)]);
add('force', 'force-merge', "a force layout without layoutAnimation: a merge renames d to f and adds g -- the kept nodes start from their preserved points, the new ones (no preserved point) from the random box",
  { animation: true,
    series: [{ type: 'graph', layout: 'force', force: { layoutAnimation: false, repulsion: 80 }, symbolSize: 16,
      data: FN.map(n => ({ name: n.name, x: n.x, y: n.y })), links: FL }] },
  ['graph'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'a', x: 10, y: 10 }, { name: 'b', x: 100, y: 50 },
      { name: 'c', x: 50, y: 100 }, { name: 'f', x: 150, y: 120 }, { name: 'e', x: 80, y: 160 }, { name: 'g', x: 0, y: 0 }],
      links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }, { source: 'c', target: 'f' }, { source: 'f', target: 'g' }] }] } },
    ...after([0, 1, 100, 300], T1)]);

// ---- step ----
const LX = { type: 'category', data: ['a', 'b', 'c', 'd', 'e'] };
add('step', 'step-change', "a step line whose step changes from start to end: LineView's init branch -- a new polyline, the clip grows from nothing again (enter timing, 1000 ms linear), every symbol pops in again on its delay and its label fades",
  { animation: true, xAxis: LX, yAxis: { type: 'value' },
    series: [{ type: 'line', step: 'start', label: { show: true }, data: [3, 5, 2, 6, 4], animationDuration: 1000, animationEasing: 'linear' }] },
  ['line'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ step: 'end' }] } }, ...after([0, 1, 16, 100, 199, 200, 201, 250, 500, 999, 1000, 1001, 1300], T1)]);
add('step', 'step-on', "a plain line that becomes a step line (step 'middle') with a value changed: the same init branch, nothing tweens from the old points",
  { animation: true, xAxis: LX, yAxis: { type: 'value' },
    series: [{ type: 'line', data: [3, 5, 2, 6, 4], areaStyle: {} }] },
  ['line'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ step: 'middle', data: [3, 5, 2, 7, 4] }] } }, ...after([0, 1, 16, 100, 300, 500, 999, 1000, 1001, 1300], T1)]);
add('step', 'step-same', "a step line merged with the same step and a new value: the update branch (the stepped points tween), for contrast",
  { animation: true, xAxis: LX, yAxis: { type: 'value' },
    series: [{ type: 'line', step: 'end', data: [3, 5, 2, 6, 4] }] },
  ['line'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [3, 5, 2, 1, 4] }] } }, ...after([0, 1, 100, 300, 301], T1)]);

// ---- a tree's data merge ----
const S_TREE_RM = [0, 1, 16, 100, 250, 499, 500, 501, 750, 999];
const afterRm = from => [...after(S_TREE_RM, from),
  ...[1000, 1016, 1032, 1048, 1064, 1080, 1096, 1112, 1128, 1144].map(t => ({ t: from + t, do: 'frame' })),
  ...after([1500], from)];
const TLIN = { animationDurationUpdate: 1000, animationEasingUpdate: 'linear' };
add('treeData', 'tree-data', "orthogonal LR, curve edges: a merge takes a2 (and its child a21) away and adds b3 under b -- the rows shift, the diff pairs the nodes by name; a2 goes to a's OLD place + 1 and a21 to a2's old place + 1 (the old tree's parent chain, the old data's layout), their edges to the same; b3 grows out of b's old place",
  { animation: true, series: [Object.assign({ type: 'tree', data: TREE, initialTreeDepth: -1 }, TLIN)] },
  ['tree'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'root', children: [
      { name: 'a', children: [{ name: 'a1' }] },
      { name: 'b', children: [{ name: 'b1' }, { name: 'b2' }, { name: 'b3' }] },
      { name: 'c' }] }] }] } }, ...afterRm(T1)]);
add('treeData', 'tree-data-move', "orient TB, polyline edges: a merge takes a away (and a1, a2, a21 with it) and gives c two children -- the removed subtree shrinks into its OLD parents' old places; a's TreePath goes to the root's old place, a2's (an only child under it) to a's; c's children and its new TreePath come out of c's place",
  { animation: true, series: [Object.assign({ type: 'tree', orient: 'TB', edgeShape: 'polyline', data: TREE, initialTreeDepth: -1 }, TLIN)] },
  ['tree'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'root', children: [
      { name: 'b', children: [{ name: 'b1' }, { name: 'b2' }] },
      { name: 'c', children: [{ name: 'c1' }, { name: 'c2' }] }] }] }] } }, ...afterRm(T1)]);

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function readRec(chart, probes) {
  const rec = {};
  probes.forEach(p => PROBES[p](chart, rec));
  return rec;
}
function runCase(c) {
  registerMaps();
  DELETED.clear();
  const chart = mk(c.W, c.H);
  try {
    const out = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: clone(c.option),
      probes: c.probes, events: [] };
    quiet(() => chart.setOption(clone(c.option)));
    noteStorage(chart);
    c.events.forEach(ev => {
      NOW = T0 + ev.t;
      const o = clone(ev);
      if (ev.do === 'sample') {
        zr(chart).animation.update();
        refresh(chart);
        o.rec = readRec(chart, c.probes);
      }
      else if (ev.do === 'frame') zr(chart).animation.update();
      else if (ev.do === 'merge') quiet(() => chart.setOption(clone(ev.option)));
      else if (ev.do === 'action') quiet(() => chart.dispatchAction(clone(ev.action)));
      else must(false, 'an event it does not know: ' + ev.do);
      noteStorage(chart);
      out.events.push(o);
    });
    return out;
  } finally {
    chart.dispose();
  }
}

// upstream's setTheme carries the payload {type: 'setTheme'}: a treemap does
// not transition (only a payload of none, zoomToNode or rootToNode does)
function themeCheck() {
  const chart = mk(400, 300);
  try {
    quiet(() => chart.setOption({ animation: true, series: [Object.assign({}, TMO, { data: TM })] }));
    NOW = T0 + T1;
    zr(chart).animation.update();
    quiet(() => chart.setTheme('dark'));
    let clips = 0;
    const v = chart.getViewOfSeriesModel(chart.getModel().getSeriesByIndex(0));
    v._containerGroup.traverse(el => { if (el.type === 'rect' || el.isGroup) clips += nClip(el); });
    return { clips, state: v._state };
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
  // sunburst
  guard('sb-merge: a kept piece tweens its shape', rec('sb-merge', T1 + 100, 'sb0/2').n === 1
    && n(rec('sb-merge', T1 + 100, 'sb0/2').sh[5]) !== n(rec('sb-merge', T1 - 1, 'sb0/2').sh[5]));
  guard('sb-merge: a new piece grows from r0', (() => {
    const r = rec('sb-merge', T1, 'sb0/3');
    return r && n(r.sh[3]) === n(r.sh[2]);
  })());
  guard('sb-merge: a kept label moves', rec('sb-merge', T1 + 100, 'sb0/2/label').n >= 1);
  guard('sb-merge: a new label fades in', n(rec('sb-merge', T1, 'sb0/3/label').op) === 0);
  // treemap
  guard('tm-merge: a kept rect tweens', (() => {
    const r = rec('tm-merge', T1 + 100, 'tm0/2');
    return r && r.bg && r.bg.n === 1;
  })());
  guard('tm-struct: a deleted element shrinks', rec('tm-struct', T1 + 100, 'tm0/del').length > 0);
  guard('tm-struct: the wrap ends ready', rec('tm-struct', T1 + 901, 'tm0/state') === 'ready');
  guard("setTheme's payload: no treemap transition", out.themeCheck.clips === 0);
  // roam
  guard('graph-roam: the main group tweens', rec('graph-roam', T1 + 100, 'g0/view').n === 1);
  guard('tree-roam: the view group tweens', rec('tree-roam', T1 + 100, 'tr0/view').n === 1);
  guard('geo-roam: the transform group tweens', rec('geo-roam', T1 + 100, 'geo0/group').n === 1);
  guard('map-roam: the series transform group tweens', rec('map-roam', T1 + 100, 'map0/group').n === 1);
  // force
  guard('force-legend: the kept nodes do not restart from the option', (() => {
    const a = rec('force-legend', T1 - 1, 'g0/node0');
    const b = rec('force-legend', T1, 'g0/node0');
    return n(b.x) !== 10 && n(a.x) !== 10;
  })());
  // step
  guard('step-change: the clip grows again', rec('step-change', T1 + 100, 'ln0/clip').n === 1
    && n(rec('step-change', T1, 'ln0/clip').width) === 0);
  guard('step-same: the polyline tweens', rec('step-same', T1 + 100, 'ln0/poly').n === 1);
  // the tree's data
  guard('tree-data: a2 goes to a\'s old place + 1', (() => {
    const gh = rec('tree-data', T1 + 999, 'tr0/ghost4');
    const a = rec('tree-data', T1 - 1, 'tr0/node2');
    return gh && Math.abs(n(gh.x) - (n(a.x) + 1)) < 0.5 && Math.abs(n(gh.y) - (n(a.y) + 1)) < 0.5;
  })());
  return g;
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    clock: { T0 },
    maps: MAPS,
    notes: [
      'every chart: chart._ssr false, env.node off, 400 x 300; the first setOption at T0.',
      'events in order at T0 + t; a sample is zr.animation.update(), a refresh of the display list, and a read of what the case\'s probes name.',
    ],
    cases: CASES.map(runCase),
  };
  out.themeCheck = themeCheck();
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
