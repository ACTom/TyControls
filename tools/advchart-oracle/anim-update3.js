/*
Upstream's own answers for the fix phase, batch F3d: the update transitions
F3a and F3b left out.

  graph     GraphView.render on a kept view: the main group's transform
            (applyViewCoordSysTransToElement with the series' model, not on
            the first render) at update timing with no row; the node
            Symbols (SymbolDraw.updateData: a kept one's path scale at the
            row, its group x / y with no row, setSymbolScale(nodeScale) at
            once; an added one pops in; a removed one fades and shrinks); the
            edges (LineDraw.updateData: a kept Line's shape x1, y1, x2, y2,
            cpx1, cpy1 and percent at the row, its end symbols and label
            placed from the line every frame by Line.beforeUpdate; an added
            one draws out; a removed one goes at once).
  tree      TreeView.render after treeExpandAndCollapse (update: 'update')
            and after a setOption: the view group's transform; updateNode's
            group from the source's old place (__oldX / __oldY) to the
            layout; drawEdge's curve or TreePath from where it is (a new one
            from the source's old place); removeNode's group to the source's
            place + 1 and its fade (update timing), removeNodeEdge's edge to
            the source's place and to no opacity.
  radial    a radial tree's labels: placed by the host's rect every frame
            (zrender's updateInnerText with the text config's rotation and
            'center' origin), so they come out of and go into the node with
            its path's scale.
  stateGrad a series state whose colour is a gradient (an emphasis or a
            select itemStyle.color with colorStops): the state's fill tweens
            through zrender's gradient track.

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off, with the clock of animation.js (the global
Date replaced BEFORE the dist loads; setTimeout a queue that never runs),
Math.random the port's xorshift32 and zrender's width table measuring text.

  node tools/advchart-oracle/anim-update3.js

writes tests/fixtures/advchart-anim-update3.json (ORACLE_OUT overrides).
Ends with process.exit().

-----------------------------------------------------------------------------
Numbers are the 16 lowercase hex digits of the IEEE double (big-endian; NaN
7ff8000000000000); strings, booleans and counts are plain JSON.

Top level: source, version, seed, measure {firstCode, ratio[] (hex)}, clock
{T0}, notes[], cases[], guards[].

A case: id, group, note, W, H, option, probes[], events[] (ring: a circular
layout -- the ring's cos / sin are not correctly rounded in either runtime,
compared to 1e-9; placeFrom: from this t on the places -- node x / y, edge
shapes, what is drawn -- are not compared, only the scales, the opacities,
the percents and whether things move: a force layout laid out again after a
legend filter is not the port's yet). The first
setOption is at T0. An event, in order, at t ms after T0:
  {t, do: 'sample', rec}       zr.animation.update(), then what the probes
                               read
  {t, do: 'frame'}             zr.animation.update(), nothing recorded
  {t, do: 'merge', option}     setOption(option)        (its flush steps)
  {t, do: 'notMerge', option}  setOption(option, true)
  {t, do: 'action', action}    dispatchAction(action)
  {t, do: 'hover', series, dataIndex, dataType}   the element's onmouseover
                               (the states' handler, as a pointer would)
  {t, do: 'out', ...}          its onmouseout
A sample's rec, by probe:
  graph  per graph series s:
         'g<s>/view' {x, y, scaleX, scaleY, n} the main group (a view only);
         'g<s>/node<i>' per data index i: {raw, x, y, gs (the group's
         scale: setSymbolScale), sx, sy (the path's scale), op (the path's
         opacity), n (clips on the group and the path), wx, wy, ws (the
         path's global transform: its place and scale on the canvas)};
         'g<s>/ghost<i>' a removed node still fading, by its OLD data index
         (its ECData): {x, y, sx, sy, op, n};
         'g<s>/edge<i>' per edge data index: {x1, y1, x2, y2, cpx1, cpy1,
         percent, n} the line's shape; 'g<s>/edge<i>/from', '/to' {x, y,
         scale, rotation} the end symbols; 'g<s>/edge<i>/label' {x, y,
         rotation, scale, op} the label's.
  tree   per tree series s:
         'tr<s>/view' {x, y, scaleX, scaleY, n} the view group (this.group);
         'tr<s>/node<i>' per data index whose element lives (data's or a
         ghost's): {ghost, x, y, sx, sy, op, gop (the group's opacity), n};
         'tr<s>/edge<i>' the node's __edge while it is in the main group:
         a curve's {x1, y1, cpx1, cpy1, cpx2, cpy2, x2, y2, op, n}, a
         TreePath's {parentPoint[], childPoints[], op, n};
         'tr<s>/label<i>' the node's text: {x, y, rotation, op} as the text's
         own transform after the frame's updateInnerText.
  state  per series s and data index i the item's path (a bar's rect):
         'st<s>/<i>' {fill (a colour string or a gradient object with hex
         numbers), n}.

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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-anim-update3.json');

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
// a function in an option, written {$fn: name} in the fixture (the test
// registers the same name with the control's timing registry)
const FNS = { 'idx*30': idx => idx * 30 };
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
// a frame: every element's beforeUpdate / updateInnerText runs, as the
// painter's refresh does
function refresh(chart) { zr(chart).storage.getDisplayList(true); }

// getECData = makeInner() (util/innerStore.ts): an own property '__ec_inner_<n>'
function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'dataIndex' in el[k]) return el[k];
  }
  return null;
}

// a fill or a stroke: a string as it is, a gradient with its numbers in hex
function paint(v) {
  if (v == null) return null;
  if (typeof v === 'string') return v;
  if (v.colorStops) {
    const o = { type: v.type, global: !!v.global,
      stops: v.colorStops.map(s => ({ offset: hx(s.offset), color: s.color })) };
    for (const k of ['x', 'y', 'x2', 'y2', 'r']) if (typeof v[k] === 'number') o[k] = hx(v[k]);
    return o;
  }
  return String(v);
}

// ---------------------------------------------------------------------------
// the probes
// ---------------------------------------------------------------------------
// the global transform's translation and scale (after the frame's update):
// wx, wy, ws
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
        for (const nm of ['fromSymbol', 'toSymbol']) {
          const sym = g.childOfName(nm);
          if (sym) {
            rec[key + '/edge' + i + '/' + (nm === 'fromSymbol' ? 'from' : 'to')] = glob({ x: hx(sym.x), y: hx(sym.y),
              scale: hx(sym.scaleX), rotation: hx(sym.rotation) }, sym);
          }
        }
        const label = g.getTextContent();
        if (label && !label.ignore) {
          rec[key + '/edge' + i + '/label'] = glob({ x: hx(label.x), y: hx(label.y), rotation: hx(label.rotation),
            scale: hx(label.scaleX), op: hx(label.style.opacity) }, label);
        }
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
        const t = p.getTextContent();
        if (t && !t.ignore && t.style.text) {
          const m = t.transform || [1, 0, 0, 1, 0, 0];
          rec[nk.replace('/node', '/label').replace('/ghost', '/glabel')] = { m: arr(m), sx: hx(t.style.x || 0), sy: hx(t.style.y || 0),
            align: t.style.align || null, vAlign: t.style.verticalAlign || null, op: hx(t.style.opacity),
            text: t.style.text };
        }
      });
    });
  },
  pictorial(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'pictorialBar') return;
      const data = sm.getData();
      data.each(i => {
        const bar = data.getItemGraphicEl(i);
        if (!bar || !bar.__pictorialBundle) return;
        const key = 'pict' + sm.seriesIndex + ':' + i;
        let k = 0;
        bar.__pictorialBundle.eachChild(p => {
          const m = p.transform || [1, 0, 0, 1, p.x, p.y];
          rec[key + '/' + k] = { x: hx(p.x), y: hx(p.y), scaleX: hx(p.scaleX), scaleY: hx(p.scaleY),
            rotation: hx(p.rotation), gx: hx(m[4]), gy: hx(m[5]), n: nClip(p) };
          k++;
        });
        rec[key + '/count'] = k;
      });
    });
  },
  state(chart, rec) {
    chart.getModel().eachSeries(sm => {
      const data = sm.getData();
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        if (!el || !el.style) return;
        rec['st' + sm.seriesIndex + '/' + i] = { fill: paint(el.style.fill), n: nClip(el) };
      });
    });
  },
};

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

// ---- graph ----
const GN = [{ name: 'a', x: 10, y: 10, category: 0 }, { name: 'b', x: 100, y: 50, category: 1 },
  { name: 'c', x: 50, y: 100, category: 0 }, { name: 'd', x: 150, y: 120, category: 1 }, { name: 'e', x: 80, y: 160, category: 0 }];
const GL = [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }, { source: 'c', target: 'd' },
  { source: 'd', target: 'e' }, { source: 'e', target: 'a' }];
const GCATS = [{ name: 'A' }, { name: 'B' }];

add('graph', 'graph-legend', "layout none on a view with two categories, arrows and edge labels: the legend switches category B off -- its nodes fade and shrink, their edges go at once, the view's rect changes so the main group tweens (update timing, no row) while the kept nodes stay at their place in the group and their scale is set at once; switched on again later",
  { animation: true, legend: { data: ['A', 'B'] },
    series: [Object.assign({ type: 'graph', layout: 'none', categories: GCATS, symbolSize: 20, edgeSymbol: ['none', 'arrow'],
      edgeLabel: { show: true, formatter: 'e' }, data: GN, links: GL }, LIN)] },
  ['graph'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'legendToggleSelect', name: 'B' } }, ...after(S_LIN, T1),
    { t: T1 + 2000, do: 'action', action: { type: 'legendToggleSelect', name: 'B' } }, ...after(S_LIN, T1 + 2000)]);

add('graph', 'graph-move', "layout none: a merge moves two nodes and adds one with an edge; the kept nodes slide (no row), the kept edges' shapes tween at their rows, the new node pops in, the new edge draws out; curved edges (curveness 0.3) with a from-arrow and labels (insideEndTop: beforeUpdate turns them with the tangent); 300 ms cubicInOut, the default update timing",
  { animation: true,
    series: [{ type: 'graph', layout: 'none', symbolSize: [24, 16], edgeSymbol: ['circle', 'arrow'], edgeSymbolSize: 8,
      edgeLabel: { show: true, formatter: 'L', position: 'insideEndTop' },
      lineStyle: { curveness: 0.3 }, data: GN.map(n => ({ name: n.name, x: n.x, y: n.y })), links: GL }] },
  ['graph'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'a', x: 10, y: 10 }, { name: 'b', x: 140, y: 30 },
      { name: 'c', x: 50, y: 100 }, { name: 'd', x: 120, y: 150 }, { name: 'e', x: 80, y: 160 }, { name: 'f', x: 180, y: 80 }],
      links: GL.concat([{ source: 'f', target: 'b' }]) }] } }, ...after(S_UPD, T1)]);

add('graph', 'graph-edge-delay', "layout none with animationDelayUpdate (idx) => idx * 30 (linear, 1000 ms): a merge moves two nodes; each kept Line's shape waits by its own edge index (LineDraw.updateData's updateProps at the row), each kept node's path scale by its node index, the groups and the view with no row",
  { animation: true,
    series: [Object.assign({ type: 'graph', layout: 'none', symbolSize: 16, edgeSymbol: ['none', 'arrow'],
      data: GN.map(n => ({ name: n.name, x: n.x, y: n.y })), links: GL }, LIN, { animationDelayUpdate: { $fn: 'idx*30' } })] },
  ['graph'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'a', x: 10, y: 10 }, { name: 'b', x: 140, y: 30 },
      { name: 'c', x: 50, y: 100 }, { name: 'd', x: 120, y: 150 }, { name: 'e', x: 80, y: 160 }] }] } },
    ...after([0, 1, 16, 31, 61, 91, 100, 121, 250, 500, 1000, 1031, 1061, 1091, 1121, 1200], T1)]);

add('graph', 'graph-circular', "layout circular, legend off for category B: the circular layout is solved again for the nodes left, so every kept node moves (its group x / y in the main group) and the main group tweens; rotateLabel off",
  { animation: true, legend: { data: ['A', 'B'] },
    series: [Object.assign({ type: 'graph', layout: 'circular', categories: GCATS, symbolSize: 16, label: { show: true },
      data: GN.map(n => ({ name: n.name, category: n.category })), links: GL }, LIN)] },
  ['graph'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'legendToggleSelect', name: 'B' } }, ...after(S_LIN, T1)], { ring: true });

add('graph', 'graph-enter-update', "an update while the enter still runs (at 150 of the enter's 1000 ms): a kept edge's percent goes on from where it is to 1 at update timing, its ends move; the nodes' pop-in goes on",
  { animation: true,
    series: [Object.assign({ type: 'graph', layout: 'none', symbolSize: 20, edgeSymbol: ['none', 'arrow'],
      animationDuration: 1000, animationEasing: 'linear',
      data: GN.map(n => ({ name: n.name, x: n.x, y: n.y })), links: GL }, LIN)] },
  ['graph'],
  [{ t: 0, do: 'sample' }, { t: 150, do: 'sample' },
    { t: 150, do: 'merge', option: { series: [{ data: [{ name: 'a', x: 30, y: 10 }, { name: 'b', x: 100, y: 50 },
      { name: 'c', x: 50, y: 100 }, { name: 'd', x: 150, y: 120 }, { name: 'e', x: 80, y: 190 }] }] } },
    ...after([0, 1, 50, 200, 500, 849, 850, 851, 1000, 1149, 1150, 1151, 1500], 150)]);

add('graph', 'graph-force', "a force layout without layoutAnimation (layoutAnimation true turns the series' animation off altogether, GraphSeriesModel.isAnimationEnabled): its iteration runs synchronously in the render and updateLayout stops the node groups' and the lines' tweens -- the paths pop in and scale, nothing slides or draws out; the legend switches category B off (the nodes' x / y written: the iteration starts from them, no random numbers)",
  { animation: true, legend: { data: ['A', 'B'] },
    series: [{ type: 'graph', layout: 'force', force: { layoutAnimation: false, repulsion: 80 }, categories: GCATS, symbolSize: 16,
      edgeSymbol: ['none', 'arrow'], data: GN, links: GL }] },
  ['graph'],
  [{ t: 0, do: 'sample' }, { t: 100, do: 'sample' }, { t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'legendToggleSelect', name: 'B' } }, ...after(S_UPD, T1)], { placeFrom: T1 });

add('graph', 'graph-force-anim', "a force layout with layoutAnimation (the default): GraphSeriesModel.isAnimationEnabled is false, the series does not animate at all -- the paths are at their scale at once, no line draws out, a legend toggle tweens nothing (the iteration runs on a timer that never fires here: the places are not compared)",
  { animation: true, legend: { data: ['A', 'B'] },
    series: [{ type: 'graph', layout: 'force', force: { repulsion: 80 }, categories: GCATS, symbolSize: 16,
      edgeSymbol: ['none', 'arrow'], data: GN, links: GL }] },
  ['graph'],
  [{ t: 0, do: 'sample' }, { t: 100, do: 'sample' }, { t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'legendToggleSelect', name: 'B' } }, ...after([0, 1, 100, 300], T1)], { placeFrom: 0 });

add('graph', 'graph-cartesian', "a graph on cartesian2d: no view, the nodes' groups slide in pixels, the edges tween in pixels; a value changes",
  { animation: true, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
    series: [Object.assign({ type: 'graph', coordinateSystem: 'cartesian2d', symbolSize: 14, edgeSymbol: ['none', 'arrow'],
      data: [[1, 1], [5, 8], [9, 3]], links: [{ source: 0, target: 1 }, { source: 1, target: 2 }] }, LIN)] },
  ['graph'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [[2, 2], [5, 8], [7, 6]] }] } }, ...after(S_LIN, T1)]);

// ---- tree ----
const TREE = [{ name: 'root', children: [
  { name: 'a', children: [{ name: 'a1' }, { name: 'a2', children: [{ name: 'a21' }] }] },
  { name: 'b', children: [{ name: 'b1' }, { name: 'b2' }] },
  { name: 'c' }] }];
const S_TREE = [0, 1, 16, 100, 250, 499, 500, 501, 750, 999, 1000, 1001, 1500];
// A REMOVAL'S END STARVES THE FRAME: zrender's Animation.update saves the
// next clip before it steps one, and a removal's done (group.remove) takes
// that next clip off the list -- the loop ends there, and every clip after
// it waits for a later frame (as many frames as there are removals ending
// at once). Upstream's kept nodes stand still for those frames; the port
// steps every clip. So after a collapse the samples stop short of the
// removal's end, a few frames run unrecorded, and the next sample is when
// everything has caught up.
const S_TREE_RM = [0, 1, 16, 100, 250, 499, 500, 501, 750, 999];
const afterRm = from => [...after(S_TREE_RM, from),
  ...[1000, 1016, 1032, 1048, 1064, 1080, 1096, 1112, 1128, 1144].map(t => ({ t: from + t, do: 'frame' })),
  ...after([1500], from)];
const TLIN = { animationDurationUpdate: 1000, animationEasingUpdate: 'linear', expandAndCollapse: true };

add('tree', 'tree-collapse', "orthogonal LR, curve edges, 1000 ms linear: collapsing 'a' (data index 2) -- its children go to a's place + 1 and fade (removeNode, the update timing), their edges shrink into a's place and fade, the kept nodes slide (the layout changed), the view group tweens to the new rect; then expanding it again -- the children grow out of a's OLD place (sourceOldLayout: __oldX / __oldY)",
  { animation: true, series: [Object.assign({ type: 'tree', data: TREE, initialTreeDepth: -1 }, TLIN)] },
  ['tree'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 2 } }, ...afterRm(T1),
    { t: T1 + 2000, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 2 } }, ...after(S_TREE, T1 + 2000)]);

add('tree', 'tree-polyline', "orient TB, polyline edges: collapsing 'b' removes its TreePath (to the source's place, no opacity) and its children; expanding it builds a TreePath from one child point on b",
  { animation: true, series: [Object.assign({ type: 'tree', orient: 'TB', edgeShape: 'polyline', data: TREE, initialTreeDepth: -1 }, TLIN)] },
  ['tree'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 6 } }, ...afterRm(T1),
    { t: T1 + 2000, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 6 } }, ...after(S_TREE, T1 + 2000)]);

add('tree', 'tree-midway', "collapse 'a' and expand it again 300 ms in, before the removal ends: the removed elements are not given back -- new ones are made from the source's old place while the old ones still fade",
  { animation: true, series: [Object.assign({ type: 'tree', data: TREE, initialTreeDepth: -1 }, TLIN)] },
  ['tree'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 2 } }, ...after([0, 1, 300], T1),
    { t: T1 + 300, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 2 } },
    ...after([300, 301, 500, 999], T1)]);

add('tree', 'tree-zoom', "a tree zoomed by its option (zoom 1.6): the view group is not the identity, and collapsing 'a' (its a21 the deepest node) changes the nodes' bounding rect -- the view group tweens (update timing, no row) under the nodes' own slides, and the compensation scale is set at once",
  { animation: true, series: [Object.assign({ type: 'tree', data: TREE, initialTreeDepth: -1, zoom: 1.6, roam: true }, TLIN)] },
  ['tree'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 2 } }, ...afterRm(T1)]);

add('tree', 'tree-default-timing', "the default update timing (300 ms cubicInOut) and the initial depth: expanding a collapsed 'a2' (data index 4) whose child was never drawn",
  { animation: true, series: [{ type: 'tree', data: TREE, initialTreeDepth: 2, expandAndCollapse: true }] },
  ['tree'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 4 } }, ...after(S_UPD, T1)]);

// ---- radial ----
add('radial', 'radial-enter', "a radial tree's first render: every label comes out of its node with the path's scale (the text config's rect is the path's, scaled), turned about its centre",
  { animation: true, series: [{ type: 'tree', layout: 'radial', data: TREE, initialTreeDepth: -1, symbolSize: 12,
    animationDuration: 1000, animationEasing: 'linear' }] },
  ['tree'],
  [...[0, 1, 16, 100, 250, 500, 750, 999, 1000, 1001].map(t => ({ t, do: 'sample' }))]);

add('radial', 'radial-toggle', "a radial tree, collapsing 'b' (data index 6) and expanding it again: the removed labels fade with the node, the new ones come out of b's old place",
  { animation: true, series: [Object.assign({ type: 'tree', layout: 'radial', data: TREE, initialTreeDepth: -1, symbolSize: 12 }, TLIN)] },
  ['tree'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 6 } }, ...afterRm(T1),
    { t: T1 + 2000, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 6 } }, ...after(S_TREE, T1 + 2000)]);

add('radial', 'radial-midway', "a radial tree, collapsing 'b' (data index 6) and expanding it again 300 ms in, while b still slides: the new curves start at b's raw place of its previous render (__radialOldRawX), not at where its group is now",
  { animation: true, series: [Object.assign({ type: 'tree', layout: 'radial', data: TREE, initialTreeDepth: -1, symbolSize: 12 }, TLIN)] },
  ['tree'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 6 } }, ...after([0, 1, 300], T1),
    { t: T1 + 300, do: 'action', action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 6 } },
    ...after([300, 301, 500, 999], T1)]);

add('radial', 'radial-delay', "a radial tree entering with animationDelay (idx) => idx * 30: a later node's path waits at no scale while its group already slides and its label already fades in -- the label's rect is the path's (nought), with no stroke margin (lineScale nought)",
  { animation: true, series: [{ type: 'tree', layout: 'radial', data: TREE, initialTreeDepth: -1, symbolSize: 12,
    animationDuration: 1000, animationEasing: 'linear', animationDelay: { $fn: 'idx*30' } }] },
  ['tree'],
  [...[0, 1, 16, 100, 200, 250, 500, 999, 1000, 1300].map(t => ({ t, do: 'sample' }))]);

// ---- a data item's array symbolSize ----
add('pictorial', 'pict-item-size', "a data item's array symbolSize -- [20, '100%'] (the percent of the bar's length, symbolRepeat off), ['50%', 12] repeated (the percent of the category's width), [16] (one number, the second NaN), and a row's array symbolOffset [5, '-50%'] -- read from the item's own visual (visual/symbol.ts getShallow), not the series'",
  { animation: false, xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: { type: 'value', max: 100 },
    series: [{ type: 'pictorialBar', symbol: 'rect', symbolSize: [30, 10],
      data: [{ value: 40, symbolSize: [20, '100%'] }, { value: 60, symbolSize: ['50%', 12], symbolRepeat: true },
        { value: 30, symbolSize: [16], symbolRepeat: true }, { value: 50, symbolOffset: [5, '-50%'] }] }] },
  ['pictorial'],
  [{ t: 0, do: 'sample' }]);

add('pictorial', 'pict-item-size-h', "the same on a horizontal bar (the category axis on y): the value dimension is x; a series' one-number array [18] (the second NaN: no glyph); a row's one-number symbolOffset [10] (both ways)",
  { animation: false, yAxis: { type: 'category', data: ['a', 'b'] }, xAxis: { type: 'value', max: 100 },
    series: [{ type: 'pictorialBar', symbol: 'circle', symbolRepeat: true,
      data: [{ value: 70, symbolSize: ['40%', '30%'] }, { value: 45, symbolSize: [12, 24], symbolRepeat: false }] },
      { type: 'pictorialBar', symbol: 'rect', symbolSize: [18], data: [30, 60] },
      { type: 'pictorialBar', symbol: 'rect', symbolSize: ['60%', 8], symbolOffset: [0, '50%'], data: [{ value: 20, symbolOffset: [10] }, 40] }] },
  ['pictorial'],
  [{ t: 0, do: 'sample' }]);

// ---- state gradients ----
const G1 = { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] };
const G2 = { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: '#00ff00' }, { offset: 0.5, color: 'rgba(0,0,0,0.5)' }, { offset: 1, color: '#ffff00' }] };
const G3 = { type: 'linear', x: 0, y: 0, x2: 1, y2: 1, colorStops: [{ offset: 0, color: '#336699' }, { offset: 1, color: 'rgba(100,150,50,0.8)' }] };
const S_ST = [0, 1, 16, 50, 150, 299, 300, 301];
add('stateGrad', 'state-gradient', "a bar whose emphasis colour is a gradient over a plain colour (discrete: at once), another whose own colour is a gradient and whose emphasis is another gradient (two stops to three), a series whose colour is a gradient with no emphasis colour (createEmphasisDefaultState's liftColor lifts every stop): highlighted and downplayed, the state's fill tweens through zrender's gradient track (300 ms cubicOut, the state animation)",
  { animation: true, xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [3, { value: 5, itemStyle: { color: G1 }, emphasis: { itemStyle: { color: G2 } } }, 4],
      emphasis: { itemStyle: { color: G1 } } },
      { type: 'bar', itemStyle: { color: G3 }, data: [2, 2, 2] }] },
  ['state'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'highlight', seriesIndex: 0, dataIndex: 0 } }, ...after(S_ST.concat([600]), T1),
    { t: T1 + 700, do: 'action', action: { type: 'downplay', seriesIndex: 0, dataIndex: 0 } }, ...after(S_ST, T1 + 700),
    { t: T1 + 1100, do: 'action', action: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } }, ...after(S_ST, T1 + 1100),
    { t: T1 + 1500, do: 'action', action: { type: 'downplay', seriesIndex: 0, dataIndex: 1 } }, ...after([0, 1, 100, 299, 300, 301], T1 + 1500),
    { t: T1 + 1900, do: 'action', action: { type: 'highlight', seriesIndex: 0, dataIndex: 2 } }, ...after([0, 1, 100], T1 + 1900),
    { t: T1 + 2000, do: 'action', action: { type: 'downplay', seriesIndex: 0, dataIndex: 2 } }, ...after([0, 1, 100, 299, 300, 301], T1 + 2000),
    { t: T1 + 2400, do: 'action', action: { type: 'highlight', seriesIndex: 1, dataIndex: 1 } }, ...after([0, 1, 50, 150, 299, 300, 301], T1 + 2400),
    { t: T1 + 2800, do: 'action', action: { type: 'downplay', seriesIndex: 1, dataIndex: 1 } }, ...after([0, 1, 50, 150, 299, 300, 301], T1 + 2800)]);

add('stateGrad', 'select-gradient', "a bar's own colour a radial gradient, its select colour another (the centre and the radius move, two stops each): selected by the action, unselected 400 ms later, selected again 100 ms after that while the unselect's tween still runs; a plain bar beside it selects at once (a colour against a gradient is discrete)",
  { animation: true, xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' },
    series: [{ type: 'bar', selectedMode: 'multiple', data: [3, 5, 4],
      itemStyle: { color: { type: 'radial', x: 0.5, y: 0.5, r: 0.5, colorStops: [{ offset: 0, color: '#ffffff' }, { offset: 1, color: '#3366cc' }] } },
      select: { itemStyle: { color: { type: 'radial', x: 0.3, y: 0.2, r: 0.9, colorStops: [{ offset: 0.2, color: 'rgba(255,255,255,0.5)' }, { offset: 1, color: '#f00' }] } } } },
      { type: 'bar', selectedMode: 'single', data: [2, 2, 2], select: { itemStyle: { color: G1 } } }] },
  ['state'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'select', seriesIndex: 0, dataIndex: 2 } },
    { t: T1, do: 'action', action: { type: 'select', seriesIndex: 1, dataIndex: 0 } }, ...after(S_ST, T1),
    { t: T1 + 400, do: 'action', action: { type: 'unselect', seriesIndex: 0, dataIndex: 2 } }, ...after([0, 1, 50, 100], T1 + 400),
    { t: T1 + 500, do: 'action', action: { type: 'select', seriesIndex: 0, dataIndex: 2 } }, ...after(S_ST, T1 + 500)]);

add('stateGrad', 'state-gradient-lift', "a series whose colour is a gradient with no emphasis colour, its channels ones whose lift (x 1.1) has a fraction of a half or more (5, 15, 25, 45, 75, 105): lift's '| 0' truncates them, it does not round",
  { animation: true, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [2, 3],
      itemStyle: { color: { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#050f19' }, { offset: 1, color: 'rgb(45,75,105)' }] } } }] },
  ['state'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'action', action: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } }, ...after([0, 1, 50, 150, 299, 300, 301], T1)]);

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function readRec(chart, probes) {
  const rec = {};
  probes.forEach(p => PROBES[p](chart, rec));
  return rec;
}
function itemEl(chart, ev) {
  const sm = chart.getModel().getSeriesByIndex(ev.series);
  const data = ev.dataType === 'edge' ? sm.getEdgeData() : sm.getData();
  const el = data.getItemGraphicEl(ev.dataIndex);
  must(el, 'no element at ' + JSON.stringify(ev));
  return el;
}
// the states' hover handler where a pointer would land (echarts' own
// mouseover / mouseout handlers on the zr instance)
function pointer(chart, ev, type) {
  const el = itemEl(chart, ev);
  const target = el.isGroup ? el.childAt(0) : el;
  zr(chart).handler.dispatchToElement({ target, topTarget: target }, type, { type, target, topTarget: target });
}
function runCase(c) {
  const chart = mk(c.W, c.H);
  try {
    const out = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, ring: !!c.ring,
      placeFrom: c.placeFrom == null ? null : c.placeFrom, option: clone(c.option),
      probes: c.probes, events: [] };
    // a copy: echarts stores its inner records on the objects it is given
    quiet(() => chart.setOption(materialize(clone(c.option))));
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
      else if (ev.do === 'notMerge') quiet(() => chart.setOption(materialize(clone(ev.option)), true));
      else if (ev.do === 'action') quiet(() => chart.dispatchAction(clone(ev.action)));
      else if (ev.do === 'hover') quiet(() => pointer(chart, ev, 'mouseover'));
      else if (ev.do === 'out') quiet(() => pointer(chart, ev, 'mouseout'));
      else must(false, 'an event it does not know: ' + ev.do);
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
  // the record at the LAST sample at t ms after T0 (numbers decoded)
  const rec = (id, t, key) => {
    const smp = cs(id).events.filter(q => q.do === 'sample' && q.t === t).pop();
    must(smp, id + ': no sample at ' + t);
    return smp.rec[key];
  };
  const n = v => num(v);
  // graph
  guard('graph-move: the main group tweens', rec('graph-move', T1 + 100, 'g0/view').n === 1
    && n(rec('graph-move', T1 + 100, 'g0/view').x) !== n(rec('graph-move', T1 - 1, 'g0/view').x));
  guard('graph-move: a kept edge tweens its shape', rec('graph-move', T1 + 100, 'g0/edge0').n === 1
    && n(rec('graph-move', T1 + 100, 'g0/edge0').x2) !== n(rec('graph-move', T1 - 1, 'g0/edge0').x2));
  guard('graph-move: a new edge draws out', n(rec('graph-move', T1, 'g0/edge5').percent) === 0);
  guard('graph-edge-delay: a later edge waits by its row', n(rec('graph-edge-delay', T1 + 16, 'g0/edge0').x2)
    !== n(rec('graph-edge-delay', T1 - 1, 'g0/edge0').x2)
    && n(rec('graph-edge-delay', T1 + 16, 'g0/edge3').x1) === n(rec('graph-edge-delay', T1 - 1, 'g0/edge3').x1));
  guard('graph-legend: a filtered node fades as a ghost', rec('graph-legend', T1 + 100, 'g0/ghost1')
    && n(rec('graph-legend', T1 + 100, 'g0/ghost1').op) > 0 && !rec('graph-legend', T1 + 200, 'g0/ghost1'));
  guard('graph-enter-update: useStyle strands the opacity tween',
    n(rec('graph-enter-update', 0, 'g0/node0').op) === 0 && n(rec('graph-enter-update', 151, 'g0/node0').op) === 1
    && n(rec('graph-enter-update', 151, 'g0/node0').sx) < 6);
  guard('graph-force: no line draws out', n(rec('graph-force', 0, 'g0/edge0').percent) === 1
    && rec('graph-force', 0, 'g0/edge0').n === 0);
  guard('graph-force: the paths still pop in', n(rec('graph-force', 0, 'g0/node0').sx) === 0
    && rec('graph-force', 100, 'g0/node0').n > 0);
  guard('graph-force: a toggle slides nothing', rec('graph-force', T1 + 100, 'g0/node0').n === 0);
  guard('graph-force-anim: no path pops in', n(rec('graph-force-anim', 0, 'g0/node0').sx) > 0
    && rec('graph-force-anim', 0, 'g0/node0').n === 0 && n(rec('graph-force-anim', 0, 'g0/edge0').percent) === 1);
  // tree
  guard('tree-collapse: a removed node goes to the source + 1', Math.abs(n(rec('tree-collapse', T1 + 999, 'tr0/ghost3').x)
    - (n(rec('tree-collapse', T1 + 1500, 'tr0/node2').x) + 1)) < 0.1);
  guard("tree-collapse: an expanded child starts at its parent's old place",
    n(rec('tree-collapse', T1 + 2000, 'tr0/node3').x) === n(rec('tree-collapse', T1 + 1500, 'tr0/node2').x));
  guard('tree-polyline: the TreePath shrinks to one child point', rec('tree-polyline', T1 + 500, 'tr0/edge6').n > 0
    && n(rec('tree-polyline', T1 + 500, 'tr0/edge6').op) < 1);
  guard('tree-midway: a ghost and a new node share a row', !!rec('tree-midway', T1 + 500, 'tr0/ghost3')
    && !!rec('tree-midway', T1 + 500, 'tr0/node3'));
  // radial
  guard("radial-midway: a new curve starts at the source's previous raw place, not its group now",
    n(rec('radial-midway', T1 + 300, 'tr0/edge7').x1) !== n(rec('radial-midway', T1 + 300, 'tr0/node6').x));
  guard('radial-enter: a label sits at its distance from a node of no scale', (() => {
    const l = rec('radial-enter', 0, 'tr0/label3');
    const nd = rec('radial-enter', 0, 'tr0/node3');
    const dx = n(l.m[4]) - n(nd.wx);
    const dy = n(l.m[5]) - n(nd.wy);
    return Math.abs(Math.sqrt(dx * dx + dy * dy) - 5) < 1e-9;
  })());
  guard('radial-enter: the stroke margin comes with any scale', (() => {
    const l = rec('radial-enter', 1, 'tr0/label3');
    const nd = rec('radial-enter', 1, 'tr0/node3');
    const dx = n(l.m[4]) - n(nd.wx);
    const dy = n(l.m[5]) - n(nd.wy);
    return Math.sqrt(dx * dx + dy * dy) > 5.9;
  })());
  // pictorial
  guard("pict-item-size: a row's [20, '100%'] reaches the glyph", n(rec('pict-item-size', 0, 'pict0:0/0').scaleX) === 20 / 400);
  guard('pict-item-size: a one-number array draws nothing repeated', rec('pict-item-size', 0, 'pict0:2/count') === 0);
  // states
  guard('state-gradient: gradient to gradient tweens', (() => {
    const f = rec('state-gradient', T1 + 1250, 'st0/1').fill;
    return f && f.stops && f.stops.length === 3 && n(f.x2) > 0 && n(f.x2) < 1;
  })());
  guard('state-gradient: a colour to a gradient is at once', (() => {
    const f = rec('state-gradient', T1, 'st0/0').fill;
    return f && f.type === 'linear';
  })());
  guard('state-gradient: liftColor lifts every stop', rec('state-gradient', T1 + 2700, 'st1/1').fill.stops[0].color
    !== rec('state-gradient', T1 + 2400, 'st1/1').fill.stops[0].color);
  guard('select-gradient: a radial gradient tweens its radius', (() => {
    const f = rec('select-gradient', T1 + 150, 'st0/2').fill;
    return f && f.type === 'radial' && n(f.r) > 0.5 && n(f.r) < 0.9;
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
