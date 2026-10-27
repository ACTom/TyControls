/*
Upstream's own answers for spec section 243b (R5-I): the animation edges the
port did not follow.

  candle  CandlestickView._renderNormal: a simple box (candleWidth <= 1.3,
          one stroke from the highest to the lowest point) enters as a full
          box does -- initProps of shape.points out of transInit (every
          point's value coordinate on the open price's), enter timing at the
          row; a candle the data diff ADDS in a later render enters the same
          way; a kept one updateProps its points (update timing, its row).
  funnel  FunnelPiece.updateData: a kept piece updateProps its opacity AND
          its four points (update timing, its row); _updateLabel
          updateProps the label text's style x / y the same way.

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off, with the clock of animation.js (the global
Date replaced BEFORE the dist loads; setTimeout a queue that never runs),
Math.random the port's xorshift32.

  node tools/advchart-oracle/anim-edges.js

writes tests/fixtures/advchart-anim-edges.json (ORACLE_OUT overrides).
Ends with process.exit().

Numbers are the 16 lowercase hex digits of the IEEE double (big-endian; NaN
7ff8000000000000). A case: id, group, note, W, H, option, probes[], rows
(the rows a probe reads, where it does not read them all), events[]
(sample / merge / mergeq (a merge the port's replay paints nothing after:
the next setOption comes before any frame) / set (notMerge) / act
(dispatchAction) at t ms after T0).
A sample's rec, by probe:
  candle  'cd<s>/<i>' {pts (the eight points, flat), simple, n (clips)}
  funnel  'fn<s>/<i>' {pts (the four points, flat), op, n}; 'fl<s>/<i>'
          {x, y (the text's anchor on the canvas), op, n} for a label shown
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-anim-edges.json');

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
// [R2-I8] where an element's origin lands on the canvas
function gpos(el) {
  const m = el.getComputedTransform();
  return m ? [m[4], m[5]] : [0, 0];
}
// [r2v] the path's box on the canvas: its own box through its computed
// transform (for a rect symbol the box of the turned, scaled rect)
function gbox(el) {
  const r = el.getBoundingRect().clone();
  const m = el.getComputedTransform();
  if (m) r.applyTransform(m);
  return [r.x, r.y, r.width, r.height];
}
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
const flat = pts => {
  const out = [];
  if (!pts) return out;
  for (let i = 0; i < pts.length; i++) {
    const p = pts[i];
    if (p != null && typeof p === 'object') { out.push(p[0], p[1]); }
    else out.push(p);
  }
  return out;
};
const opOf = el => hx(el.style && el.style.opacity != null ? el.style.opacity : 1);
const rowsOf = (c, data) => {
  if (c.rows) return c.rows.filter(i => i < data.count());
  const r = [];
  data.each(i => r.push(i));
  return r;
};
// where a text's anchor (style.x / style.y) lands on the canvas
function textAt(t) {
  t.updateTransform();
  const m = t.getComputedTransform();
  const x = t.style.x || 0;
  const y = t.style.y || 0;
  if (!m) return [x, y];
  return [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
}
const PROBES = {
  // a candlestick's boxes: the eight points and whether it is a simple box
  candle(chart, rec, c) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'candlestick') return;
      const data = sm.getData();
      rowsOf(c, data).forEach(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        rec['cd' + sm.seriesIndex + '/' + i] = { pts: arr(flat(el.shape.points)), simple: !!el.__simpleBox, n: nClip(el) };
      });
    });
  },
  // a bar series' rects (cartesian): the shape, whether ignored
  bar(chart, rec, c) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'bar') return;
      const data = sm.getData();
      rowsOf(c, data).forEach(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        const sh = el.shape;
        rec['br' + sm.seriesIndex + '/' + i] = { sh: arr([sh.x, sh.y, sh.width, sh.height]), ig: !!el.ignore, n: nClip(el) };
      });
    });
  },
  // a series' markLines (its LineDraw's lineData, by data index): the
  // line's shape and percent, its id; and its markPoints (SymbolDraw):
  // the group's place, the path's scale
  mark(chart, rec) {
    const mlv = chart._componentsViews.find(v => v && v.type === 'markLine');
    const mpv = chart._componentsViews.find(v => v && v.type === 'markPoint');
    chart.getModel().eachSeries(sm => {
      const ld = mlv && mlv.markerGroupMap.get(sm.id);
      const data = ld && ld._lineData;
      if (data) {
        data.each(i => {
          const el = data.getItemGraphicEl(i);
          if (!el || !el.parent) return;
          const line = el.childOfName('line');
          const sh = line.shape;
          rec['ml' + sm.seriesIndex + '/' + i] = { id: idText(data.getId(i)), sh: arr([sh.x1, sh.y1, sh.x2, sh.y2]),
            pc: hx(sh.percent == null ? 1 : sh.percent), n: nClip(line) };
        });
      }
      const sd = mpv && mpv.markerGroupMap.get(sm.id);
      const pd = sd && sd._data;
      if (pd) {
        pd.each(i => {
          const el = pd.getItemGraphicEl(i);
          if (!el || !el.parent) return;
          const pth = el.childAt(0);
          rec['mk' + sm.seriesIndex + '/' + i] = { x: hx(el.x), y: hx(el.y), sx: hx(pth.scaleX), n: nClip(el) + nClip(pth) };
        });
      }
    });
  },
  // a bar view's elements its data no longer holds (fading out), by the
  // view's series index: each one's opacity and clips, in group order
  ghost(chart, rec) {
    chart._chartsViews.forEach(v => {
      if (!v || v.type !== 'bar' || !v.__model) return;
      const data = v._data;
      const live = new Set();
      if (data) data.each(i => { const el = data.getItemGraphicEl(i); if (el) live.add(el); });
      const gone = [];
      v.group.eachChild(el => {
        if (live.has(el) || (el.type !== 'rect' && el.type !== 'sector' && el.type !== 'sausage')) return;
        gone.push({ op: opOf(el), n: nClip(el) });
      });
      rec['gh' + v.__model.seriesIndex + '/all'] = gone;
    });
  },
  // a bar series on a polar: each sector's shape, its cornerRadius as the
  // shape holds it, its label's textConfig rotation
  pol(chart, rec, c) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'bar' || sm.coordinateSystem.type !== 'polar') return;
      const data = sm.getData();
      rowsOf(c, data).forEach(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        const sh = el.shape;
        const cr = sh.cornerRadius;
        const tc = el.textConfig;
        rec['po' + sm.seriesIndex + '/' + i] = { type: el.type, sh: arr([sh.cx, sh.cy, sh.r0, sh.r, sh.startAngle, sh.endAngle]),
          cr: cr == null ? null : arr(Array.isArray(cr) ? cr : [cr]),
          rot: tc && tc.rotation != null ? hx(tc.rotation) : null, n: nClip(el) };
      });
    });
  },
  // a pie's label lines: the commands a canvas frame draws of each --
  // PathProxy.rebuildPath at its strokePercent over the path built afresh
  // (a plain array: doubles) -- with its smooth and its strokePercent
  pguide(chart, rec, c) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'pie') return;
      const data = sm.getData();
      rowsOf(c, data).forEach(i => {
        const el = data.getItemGraphicEl(i);
        const g = el && el.getTextGuideLine();
        if (!g || g.ignore || g.invisible) return;
        if (!g.path) g.createPathProxy();
        const PP = g.path.constructor;
        const pp = new PP(false);
        pp.beginPath();
        g.buildPath(pp, g.shape, false);
        const cmds = [];
        const ctx = {
          moveTo: (x, y) => cmds.push('M', hx(x), hx(y)),
          lineTo: (x, y) => cmds.push('L', hx(x), hx(y)),
          bezierCurveTo: (a, b, c2, d, e, f) => cmds.push('C', hx(a), hx(b), hx(c2), hx(d), hx(e), hx(f)),
          quadraticCurveTo: (a, b, c2, d) => cmds.push('Q', hx(a), hx(b), hx(c2), hx(d)),
          closePath: () => cmds.push('Z'),
        };
        const pc = g.style.strokePercent == null ? 1 : g.style.strokePercent;
        pp.rebuildPath(ctx, pc);
        rec['pg' + sm.seriesIndex + '/' + i] = { pc: hx(pc), smooth: hx(+g.shape.smooth || 0), cmds,
          stroke: String(g.style.stroke), lw: hx(g.style.lineWidth == null ? 1 : g.style.lineWidth), n: nClip(g) };
      });
    });
  },
  // a continuous visualMap's handle labels: their opacity (a blur's fade)
  vmlab(chart, rec) {
    const v = chart._componentsViews.find(q => q && q.type === 'visualMap.continuous');
    const ls = v && v._shapes && v._shapes.handleLabels;
    if (!ls) return;
    ls.forEach((lb, h) => {
      rec['vl0/' + h] = { op: opOf(lb), blur: lb.hoverState === 1, n: nClip(lb) };
    });
  },
  // [R5-I] what is drawn on top at the case's points (c.pts): the display
  // list from the end, the first element that contains the point -- a
  // ripple (an EffectSymbol's second child's path) 'ripple', else its fill;
  // rip: whether some ripple contains the point
  zord(chart, rec, c) {
    const list = zr(chart).storage.getDisplayList(true);
    const isRipple = el => {
      const g = el.parent, es = g && g.parent;
      return !!(es && es.childCount && es.childCount() === 2 && es.childAt(1) === g);
    };
    c.pts.forEach((p, k) => {
      let top = null, rip = false;
      for (let i = list.length - 1; i >= 0; i--) {
        const el = list[i];
        if (el.ignore || el.invisible || typeof el.contain !== 'function') continue;
        if (!el.contain(p[0], p[1])) continue;
        if (isRipple(el)) {
          rip = true;
          if (top === null) top = 'ripple';
          continue;
        }
        if (top === null) top = String(el.style && el.style.fill);
      }
      rec['zo0/' + k] = { top, rip };
    });
  },
  // [R5-I] an effectScatter's symbol path (the EffectSymbol's Symbol's
  // path): its scale -- half the size drawn -- and the group's place
  esym(chart, rec, c) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'effectScatter') return;
      const data = sm.getData();
      rowsOf(c, data).forEach(i => {
        const g = data.getItemGraphicEl(i);
        if (!g) return;
        const sym = g.childAt(0);
        const path = sym && sym.childAt(0);
        if (!path) return;
        rec['es' + sm.seriesIndex + '/' + i] = { sx: hex(path.scaleX), sy: hex(path.scaleY), x: hex(g.x), y: hex(g.y),
          st: (path.currentStates || []).join(','), n: nClip(path) };
      });
    });
  },
  // [R5-I] a line's end label as drawn: the text's place and its rich
  // block's pieces -- each TSpan's words, place (in the text's frame) and
  // alignment -- as this frame laid them out
  elab(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'line') return;
      const v = chart.getViewOfSeriesModel(sm);
      const pl = v && v._polyline;
      const t = pl && pl.getTextContent();
      if (!t || t.ignore || t.invisible) return;
      const pieces = (t.childrenRef ? t.childrenRef() : []).filter(c => c.type === 'tspan')
        .map(c => ({ text: String(c.style.text), x: hex(c.style.x), y: hex(c.style.y), align: String(c.style.textAlign || 'left') }));
      rec['el' + sm.seriesIndex + '/0'] = { x: hex(t.x), y: hex(t.y), text: String(t.style.text), pieces };
    });
  },
  // a bar series' rects: the fill they are drawn with now (a state's tween)
  bfill(chart, rec, c) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'bar') return;
      const data = sm.getData();
      rowsOf(c, data).forEach(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        rec['bf' + sm.seriesIndex + '/' + i] = { fill: String(el.style.fill), n: nClip(el) };
      });
    });
  },
  // a heatmap's tooltip (and label) dimensions, as the raw columns they read
  // (encode.defaultedTooltip / defaultedLabel)
  htip(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'heatmap') return;
      const data = sm.getData();
      const col = d => data.getDimensionInfo(d).storeDimIndex;
      rec['ht' + sm.seriesIndex + '/all'] = { tip: data.mapDimensionsAll('defaultedTooltip').map(col),
        label: data.mapDimensionsAll('defaultedLabel').map(col), value: col(data.mapDimension('value')) };
    });
  },
  // a radar's symbols: each symbol group's place, its label's anchor on the
  // canvas and its label line's points
  rsym(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'radar') return;
      const data = sm.getData();
      data.each(i => {
        const g = data.getItemGraphicEl(i);
        if (!g) return;
        const syms = g.childAt(2);
        if (!syms) return;
        syms.eachChild((sy, k) => {
          const path = sy;
          const t = path && path.getTextContent && path.getTextContent();
          const gl = path && path.getTextGuideLine && path.getTextGuideLine();
          const o = { x: hx(sy.x), y: hx(sy.y), n: nClip(sy) };
          if (t && !t.ignore) { const a = textAt(t); o.lx = hx(a[0]); o.ly = hx(a[1]); }
          if (gl && !gl.ignore) { o.g = arr(flat(gl.shape.points)); o.gp = hx(gl.style.strokePercent == null ? 1 : gl.style.strokePercent); o.gn = nClip(gl); }
          rec['rs' + sm.seriesIndex + '/' + i + '.' + k] = o;
        });
      });
    });
  },
  // a themeRiver's layer labels: the clip their polygon's clip path puts
  // on them (a textContent takes its host's clip paths),
  // in the canvas' frame, null for none
  rvlab(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'themeRiver') return;
      const view = chart.getViewOfSeriesModel(sm);
      const ls = view._layersSeries || [];
      (view._layers || []).forEach((g, k) => {
        if (!g) return;
        const poly = g.childAt(0);
        const t = poly && poly.getTextContent();
        if (!t || t.ignore || !t.style.text) return;
        const cp = poly.getClipPath();
        let clip = null;
        if (cp) {
          const m = poly.getComputedTransform();
          const sh = cp.shape;
          const dy = m ? m[5] : 0;
          clip = arr([sh.x, sh.y + dy, sh.width, sh.height]);
        }
        rec['rl' + sm.seriesIndex + '/' + ls[k].name] = { clip, n: cp ? nClip(cp) : 0 };
      });
    });
  },
  // a pictorial bar's glyphs: each path's box on the canvas (its scale and
  // turn applied) and its scale
  pglyph(chart, rec, c) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'pictorialBar') return;
      const data = sm.getData();
      rowsOf(c, data).forEach(i => {
        const bar = data.getItemGraphicEl(i);
        if (!bar) return;
        const out = [];
        bar.__pictorialBundle.eachChild(p => {
          if (p === bar.__pictorialBarRect) return;
          out.push({ gb: arr(gbox(p)), sx: hx(p.scaleX), n: nClip(p) });
        });
        rec['gl' + sm.seriesIndex + '/' + i] = out;
      });
    });
  },
  // a funnel's pieces and their labels
  funnel(chart, rec, c) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'funnel') return;
      const data = sm.getData();
      rowsOf(c, data).forEach(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        rec['fn' + sm.seriesIndex + '/' + i] = { pts: arr(flat(el.shape.points)), op: opOf(el), n: nClip(el) };
        const t = el.getTextContent();
        if (t && !t.ignore && !t.invisible && t.style && t.style.text) {
          const g = textAt(t);
          rec['fl' + sm.seriesIndex + '/' + i] = { x: hx(g[0]), y: hx(g[1]), op: opOf(t), n: nClip(t) };
        }
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
const LIN = { animationDuration: 1000, animationEasing: 'linear', animationDurationUpdate: 1000, animationEasingUpdate: 'linear' };
const FNS6 = { 'idx*100': idx => idx * 100 };
Object.assign(FNS, FNS6);
const ENTER = [0, 1, 16, 100, 500, 999, 1000, 1001];

// ---- candlestick ----
const KDATA = n => {
  const out = [];
  let v = 50;
  for (let i = 0; i < n; i++) {
    const o = v;
    const c = v + ((i * 37) % 11) - 5;
    out.push([o, c, Math.min(o, c) - 3 - (i % 4), Math.max(o, c) + 2 + (i % 3)]);
    v = c;
  }
  return out;
};
const CD = (n, extra) => Object.assign({ animation: true, xAxis: { type: 'category', data: Array.from({ length: n }, (_, i) => 'c' + i) },
  yAxis: { type: 'value', scale: true }, series: [Object.assign({ type: 'candlestick', data: KDATA(n) }, LIN)] }, extra || {});
add('candle', 'cd-simple-enter', "300 candles on 400 px: candleWidth <= 1.3, every box simple -- each still enters, its points out of the open price's (enter timing, its row)",
  CD(300), ['candle'], after(ENTER, 0), { rows: [0, 1, 150, 299] });
add('candle', 'cd-simple-delay', "the same with animationDelay idx * 100: each simple box waits its turn",
  CD(300, { series: [Object.assign({ type: 'candlestick', data: KDATA(300), animationDelay: { $fn: 'idx*100' } }, LIN)] }), ['candle'],
  after([0, 50, 150, 1099, 1100, 1101, 1200, 1300], 0), { rows: [0, 1, 2] });
add('candle', 'cd-add', "a merge adds two candles: the kept ones updateProps their points (update timing, their row), the new ones enter out of transInit (enter timing, their row)",
  CD(4), ['candle'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { xAxis: { data: ['c0', 'c1', 'c2', 'c3', 'c4', 'c5'] }, series: [{ data: KDATA(6) }] } },
    ...after(ENTER, T1)]);
add('candle', 'cd-add-delay', "the same with animationDelay idx * 100 and animationDelayUpdate idx * 100",
  CD(4, { series: [Object.assign({ type: 'candlestick', data: KDATA(4), animationDelay: { $fn: 'idx*100' }, animationDelayUpdate: { $fn: 'idx*100' } }, LIN)] }),
  ['candle'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { xAxis: { data: ['c0', 'c1', 'c2', 'c3', 'c4', 'c5'] }, series: [{ data: KDATA(6) }] } },
    ...after([0, 1, 300, 450, 500, 550, 1300, 1450, 1500, 1501], T1)]);
add('candle', 'cd-simple-update', "simple boxes in a merge that changes the values: each updateProps its points",
  CD(300), ['candle'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: KDATA(300).map(r => [r[0] + 4, r[1] + 4, r[2] + 4, r[3] + 4]) }] } },
    ...after([0, 1, 500, 1001], T1)], { rows: [0, 150, 299] });

// ---- bar: a bar clipped past the plot ----
const BR = (data, extra) => Object.assign({ animation: true, animationDuration: 600, animationEasing: 'linear',
  animationDurationUpdate: 1000, animationEasingUpdate: 'linear',
  xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', min: 20, max: 100 },
  series: [{ type: 'bar', data }] }, extra || {});
add('bar', 'br-back', "b (10) lies wholly under min 20: BarView keeps it, ignore, its shape clipped to the plot's bottom edge (height 0); a merge to 60 brings it back from there (updateProps, update timing, its row), not out of an enter",
  BR([50, 10, 70]), ['bar'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: [50, 60, 70] }] } }, ...after([0, 1, 300, 600, 999, 1001], T1)]);
add('bar', 'br-out', "c (70) goes to 5, under min: kept and ignored at once, tweening to the edge; then back to 90",
  BR([50, 30, 70]), ['bar'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: [50, 30, 5] }] } }, ...after([0, 1, 500, 1001], T1),
    { t: T1 + 2000, do: 'merge', option: { series: [{ data: [50, 30, 90] }] } }, ...after([0, 1, 500, 1001], T1 + 2000)]);
add('bar', 'br-add', "a merge adds d (5), wholly clipped: created, ignored, kept; a second merge to 80 grows it from the edge at update timing",
  BR([50, 30, 70]), ['bar'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { xAxis: { data: ['a', 'b', 'c', 'd'] }, series: [{ data: [50, 30, 70, 5] }] } },
    ...after([0, 1, 500, 1001], T1),
    { t: T1 + 2000, do: 'merge', option: { series: [{ data: [50, 30, 70, 80] }] } }, ...after([0, 1, 300, 601, 1001], T1 + 2000)]);
add('bar', 'br-cat', "the category axis starts at b (min 1): a lies left of the plot, kept, ignored, clipped to the left edge with no width; a merge to min 0 slides it in from that edge (x and width tween, update timing), not grown in place",
  BR([50, 30, 70], { xAxis: { type: 'category', data: ['a', 'b', 'c'], min: 1 } }), ['bar'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { xAxis: { min: 0 } } }, ...after([0, 1, 300, 600, 999, 1001], T1),
    { t: T1 + 2000, do: 'merge', option: { xAxis: { min: 1 } } }, ...after([0, 1, 300, 1001], T1 + 2000)]);

// ---- markers ----
const MK = (ml, extra) => Object.assign({ animation: true, legend: {}, xAxis: { type: 'category', data: ['a', 'b', 'c'] },
  yAxis: { type: 'value', min: 0, max: 40 },
  series: [Object.assign({ type: 'bar', name: 's0', data: [10, 20, 30], markLine: ml }, LIN)] }, extra || {});
add('mark', 'ml-name-swap', "markLines named a and b; a merge writes them as b then a: LineDraw's diff pairs them by id (the name), so the line at index 0 (now b) tweens from where b was",
  MK({ data: [{ name: 'a', yAxis: 10 }, { name: 'b', yAxis: 20 }] }), ['mark'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ markLine: { data: [{ name: 'b', yAxis: 25 }, { name: 'a', yAxis: 5 }] } }] } },
    ...after([0, 1, 500, 1001], T1)]);
add('mark', 'ml-unnamed', "unnamed markLines: the id is 'e' + two NULs + the index -- paired by index",
  MK({ data: [{ yAxis: 10 }, { yAxis: 20 }] }), ['mark'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ markLine: { data: [{ yAxis: 25 }, { yAxis: 5 }] } }] } },
    ...after([0, 1, 500, 1001], T1)]);
add('mark', 'ml-name-drop', "a merge drops the line named a and adds c: b moves from b, c enters (percent 0 -> 1), a is gone at once",
  MK({ data: [{ name: 'a', yAxis: 10 }, { name: 'b', yAxis: 20 }] }), ['mark'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ markLine: { data: [{ name: 'b', yAxis: 25 }, { name: 'c', yAxis: 35 }] } }] } },
    ...after([0, 1, 500, 1001], T1)]);
const MK2 = () => ({ animation: true, legend: {}, xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' },
  series: [Object.assign({ type: 'bar', name: 's0', data: [10, 20, 30] }, LIN),
    Object.assign({ type: 'bar', name: 's1', data: [50, 15, 25], markLine: { data: [{ type: 'average', name: 'avg' }] },
      markPoint: { data: [{ type: 'max', name: 'max' }] } }, LIN)] });
add('mark', 'mk-legend', "s1 (with a markLine and a markPoint) toggled off by the legend and on again: its markers' draws are kept by the marker views -- on again they update from where they were (the axis changed back), they do not enter again",
  MK2(), ['mark'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'act', action: { type: 'legendToggleSelect', name: 's1' } }, ...after([0, 1001], T1),
    { t: T1 + 2000, do: 'act', action: { type: 'legendToggleSelect', name: 's1' } }, ...after([0, 1, 16, 500, 1001], T1 + 2000)]);

// ---- setOption: notMerge and consecutive calls ----
const NM = sel => ({ animation: true, legend: sel ? { selected: sel } : {}, xAxis: { type: 'category', data: ['a', 'b', 'c'] },
  yAxis: { type: 'value', min: 0, max: 40 },
  series: [Object.assign({ type: 'bar', name: 's0', data: [10, 20, 30] }, LIN), Object.assign({ type: 'bar', name: 's1', data: [15, 25, 35] }, LIN)] });
add('setopt', 'nm-hide', "a notMerge setOption of the same series with s1 unselected in the legend: s1's view is kept (the same model id) and not rendered -- remove(): BarView._clear fades every bar out (removeElementWithFadeOut: 200 ms cubicOut) on the view's last model",
  NM(null), ['bar', 'ghost'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'set', option: NM({ s1: false }) }, ...after([0, 1, 50, 100, 199, 200, 201], T1)]);
add('setopt', 'two-merges', "two merges at the same instant: the first drops c, the second brings it back -- each setOption renders: c's old bar fades out (a ghost) and a new one enters from no height (the second render's add: initProps, enter timing)",
  { animation: true, animationDuration: 600, animationEasing: 'linear', animationDurationUpdate: 1000, animationEasingUpdate: 'linear',
    xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', min: 0, max: 40 }, series: [{ type: 'bar', data: [10, 20, 30] }] },
  ['bar', 'ghost'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'mergeq', option: { series: [{ data: [10, 20] }] } },
    { t: T1, do: 'merge', option: { series: [{ data: [10, 25, 35] }] } }, ...after([0, 1, 100, 300, 599, 600, 601, 999, 1001], T1)]);
add('setopt', 'two-merges-move', "two merges at the same instant that move every bar: the second updateProps from where the first's tween stands (its start) -- the same as one",
  { animation: true, animationDurationUpdate: 1000, animationEasingUpdate: 'linear',
    xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', min: 0, max: 40 }, series: [{ type: 'bar', data: [10, 20, 30] }] },
  ['bar'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'mergeq', option: { series: [{ data: [30, 20, 10] }] } },
    { t: T1, do: 'merge', option: { series: [{ data: [5, 35, 15] }] } }, ...after([0, 1, 500, 1001], T1)]);

// ---- bars on a polar: what updateStyle reads off the shape as it is ----
const POL = (radial, s, extra) => Object.assign({ animation: true, animationDuration: 600, animationEasing: 'linear',
  animationDurationUpdate: 1000, animationEasingUpdate: 'linear', polar: { radius: [30, 120] },
  angleAxis: radial ? { type: 'category', data: ['a', 'b', 'c'] } : { type: 'value', max: 100 },
  radiusAxis: radial ? { type: 'value', max: 100 } : { type: 'category', data: ['a', 'b', 'c'] },
  series: [Object.assign({ type: 'bar', coordinateSystem: 'polar', data: [40, 70, 90] }, s || {})] }, extra || {});
add('polar', 'pol-corner-enter', "radial bars with borderRadius '30%': the creator sets r to r0 before updateStyle, so the corners are 30% of |r0| -- and stay so after the bar has grown (nothing tweens them)",
  POL(true, { itemStyle: { borderRadius: '30%' } }), ['pol'], after([0, 1, 300, 599, 600, 601], 0));
add('polar', 'pol-corner-update', "the same, then a merge changes the values: updateStyle reads the shape before updateProps -- the corners are 30% of the old r",
  POL(true, { itemStyle: { borderRadius: ['30%', 4, '10%', 0] } }), ['pol'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: [80, 30, 60] }] } }, ...after([0, 1, 500, 1001], T1)]);
add('polar', 'pol-rot-enter', "tangential bars, labels in the middle (rotate auto): the creator sets endAngle to startAngle before updateStyle, so setSectorTextRotation turns the label by the start angle -- and it stays so",
  POL(false, { label: { show: true, position: 'middle' } }), ['pol'], after([0, 1, 300, 601], 0));
add('polar', 'pol-rot-update', "the same, then a merge: the turn read off the angles before updateProps (the old ones); end-angle labels",
  POL(false, { label: { show: true, position: 'insideEndAngle' } }), ['pol'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: [20, 90, 50] }] } }, ...after([0, 1, 500, 1001], T1)]);
add('polar', 'pol-roundcap', "tangential bars, roundCap switched on in a merge: the Sector cannot become a Sausage -- the old one fades out (leave timing), a new Sausage grows its end angle from its start (update timing, its row)",
  POL(false), ['pol', 'ghost'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ roundCap: true, data: [50, 60, 70] }] } }, ...after([0, 1, 100, 199, 200, 500, 1001], T1)]);
add('polar', 'pol-enter-delay', "radial bars with animationDelay idx * 100: the creator's initProps (no data index) has set the shape to its end, so the add's initProps at the row finds nothing to tween -- the bars grow together, the delay asked of no index",
  POL(true, { animationDelay: { $fn: 'idx*100' } }), ['pol'], after([0, 1, 100, 300, 599, 600, 601, 700], 0));
add('polar', 'pol-add', "a merge adds a radial bar: the creator's updateProps (isUpdate) grows its r from r0 at update timing with no data index",
  POL(true, { animationDelayUpdate: { $fn: 'idx*100' } }), ['pol'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { angleAxis: { data: ['a', 'b', 'c', 'd'] }, series: [{ data: [40, 70, 90, 60] }] } },
    ...after([0, 1, 100, 300, 500, 1001, 1301], T1)]);

// ---- label lines ----
const PIE = (s, extra) => Object.assign({ animation: true, animationDuration: 1000, animationEasing: 'linear',
  series: [Object.assign({ type: 'pie', radius: '50%', data: [{ name: 'a', value: 40 }, { name: 'b', value: 25 }, { name: 'c', value: 20 },
    { name: 'd', value: 15 }] }, s || {})] }, extra || {});
add('guide', 'lg-smooth-in', "a pie's label lines with smooth 0.5 drawing in (LabelManager: strokePercent 0 -> 1, enter timing): a frame draws the first part of the CURVE (PathProxy.rebuildPath: the bezier subdivided where the length runs out), not a straight prefix",
  PIE({ labelLine: { smooth: 0.5, length: 20, length2: 30, lineStyle: { color: '#336699' } } }), ['pguide'], after([0, 1, 100, 250, 500, 750, 999, 1000, 1001], 0));
add('guide', 'lg-states', "hovering a slice whose label line has an emphasis lineStyle (colour, width) and smooth: updateStates gives the line the series' stateTransition -- its stroke and width tween (300 ms cubicOut) and its smooth too",
  PIE({ labelLine: { smooth: 0.2, lineStyle: { color: '#336699' } }, emphasis: { labelLine: { smooth: 0.8, lineStyle: { color: '#ff0000', width: 4 } } } }, { animationDuration: 10 }),
  ['pguide'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'act', action: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } },
    ...after([0, 1, 50, 150, 299, 300, 301], T1),
    { t: T1 + 1000, do: 'act', action: { type: 'downplay', seriesIndex: 0, dataIndex: 1 } }, ...after([0, 1, 150, 301], T1 + 1000)], { rows: [1] });

// ---- visualMap ----
add('vmap', 'vm-blur', "the pointer over a continuous visualMap's bar shows the indicator: api.enterBlur on each handle label, whose stateTransition ({duration: 200}) fades it to its blur opacity 0.1; off the bar it fades back",
  { animation: true, xAxis: { type: 'value' }, yAxis: { type: 'value' },
    visualMap: { type: 'continuous', min: 0, max: 100, calculable: true, left: 10, bottom: 20, itemHeight: 100, itemWidth: 20 },
    series: [{ type: 'scatter', data: [[1, 10], [2, 50], [3, 90]] }] },
  ['vmlab'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'move', x: 38, y: 209 }, ...after([0, 1, 50, 100, 199, 200, 201], T1),
    { t: T1 + 1000, do: 'move', x: 300, y: 50 }, ...after([0, 1, 100, 201], T1 + 1000)]);

// ---- stateAnimation's forms ----
const SA = sa => ({ animation: true, animationDuration: 10, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value' },
  series: [{ type: 'bar', data: [10, 20], itemStyle: { color: '#3366cc' }, emphasis: { itemStyle: { color: '#ff0000' } }, stateAnimation: sa }] });
const SAEV = [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'act', action: { type: 'highlight', seriesIndex: 0, dataIndex: 0 } },
  ...after([0, 1, 50, 100, 200, 300, 399, 400, 401, 1000], T1)];
add('stanim', 'sa-dur-string', "stateAnimation.duration '400': zrender's keyframe takes the string as a number -- a 400 ms tween",
  SA({ duration: '400', easing: 'linear' }), ['bfill'], SAEV, { rows: [0] });
add('stanim', 'sa-delay-string', "stateAnimation.delay '100': Clip's start is globalTime + '100', a string -- the elapsed time is hugely negative and the tween stays at its start",
  SA({ duration: 200, easing: 'linear', delay: '100' }), ['bfill'], SAEV, { rows: [0] });
add('stanim', 'sa-delay-number', "stateAnimation.delay 100: the tween waits 100 ms",
  SA({ duration: 200, easing: 'linear', delay: 100 }), ['bfill'], SAEV, { rows: [0] });
add('stanim', 'sa-delay-fn', "stateAnimation.delay a function: Clip's start is globalTime plus a function -- not a number",
  SA({ duration: 200, easing: 'linear', delay: { $fn: 'idx*100' } }), ['bfill'], SAEV, { rows: [0] });
add('stanim', 'sa-dur-fn', "stateAnimation.duration a function: not above 0 -- no transition, the state at once",
  SA({ duration: { $fn: 'idx*100' }, easing: 'linear' }), ['bfill'], SAEV, { rows: [0] });
// ---- a rich end label counting ----
add('elabel', 'el-rich-count', "a rich end label that counts through the enter (the clip's during, 1000 ms linear, up to 120): each frame lays the block out again for the words it has -- the pieces' words and places, the value token wider as it counts past 100",
  Object.assign({ animation: true, xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', max: 150 },
    series: [{ type: 'line', showSymbol: false, data: [10, 30, 120],
      endLabel: { show: true, formatter: '{a|{c}} {b|pts}', rich: { a: { fontSize: 16, fontWeight: 'bold' }, b: { fontSize: 10, padding: [0, 0, 0, 4] } } } }] }, LIN),
  ['elab'],
  after([0, 1, 16, 100, 300, 500, 700, 800, 900, 999, 1000, 1001], 0));

// ---- an effectScatter's state over its update ----
add('esstate', 'es-hover-update', "an effectScatter's symbols grow 10 -> 20 (update, 1000 ms linear); 300 ms in the pointer hovers the second: the state transition animates the symbol path's own scale to emphasis (the new size x 1.1) from where the update has got it -- the update's scale tracks stop (one key, one element), no product of the two",
  Object.assign({ animation: true, xAxis: { type: 'value', min: 0, max: 4 }, yAxis: { type: 'value', min: 0, max: 10 },
    series: [{ type: 'effectScatter', symbolSize: 10, data: [[1, 5], [2, 8], [3, 3]], rippleEffect: { period: 4 } }] }, LIN),
  ['esym'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ symbolSize: 20 }] } }, ...after([0, 1, 100, 299], T1),
    { t: T1 + 300, do: 'move', x: 210, y: 96 }, ...after([300, 301, 400, 500, 599, 600, 601, 999, 1001, 1500], T1),
    { t: T1 + 2000, do: 'move', x: 380, y: 290 }, ...after([0, 1, 150, 301], T1 + 2000)], { rows: [1] });

// ---- the continuous phase's z order ----
add('zorder', 'zo-ripple', "an effectScatter's ripples (z 2, z2 99) under a bar series of z 3 and under a title (z 6) with a background, over a bar of z 2 (z2 0): zrender draws one display list in z order",
  { animation: true, animationDuration: 300,
    title: { text: 'T', left: 215, top: 135, backgroundColor: '#00aa00', padding: 10, textStyle: { color: '#ffffff', fontSize: 12 } },
    xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', min: 0, max: 100 },
    series: [{ type: 'effectScatter', data: [[1, 50]], symbolSize: 20, itemStyle: { color: '#ff0000' },
      rippleEffect: { scale: 8, brushType: 'fill', period: 4 } },
      { type: 'bar', z: 3, data: [0, 100, 0], barWidth: 40, itemStyle: { color: '#3366cc' } },
      { type: 'bar', data: [0, 0, 100], barWidth: 40, itemStyle: { color: '#33aa66' } }] },
  ['zord'], after([1000, 2000, 3000], 0), { pts: [[200, 175], [217, 137], [200, 120], [264, 150]] });
add('stanim', 'sa-resize', "a resize 100 ms into a 400 ms hover tween: the update ({duration: 0}) clears the states without a transition, stops every animator, and puts the states back without one -- the emphasis colour at once",
  SA({ duration: 400, easing: 'linear' }), ['bfill'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'act', action: { type: 'highlight', seriesIndex: 0, dataIndex: 0 } },
    ...after([0, 1, 100], T1), { t: T1 + 100, do: 'resize', W: 420, H: 300 }, ...after([100, 101, 200, 401, 1000], T1)], { rows: [0] });
add('stanim', 'sa-export', "an export at another pixel ratio 100 ms into a 400 ms hover tween: the SVG renderer's getDataURL (getSvgDataURL) stops every animator forwarding to its last frame -- the emphasis colour at once, no update",
  SA({ duration: 400, easing: 'linear' }), ['bfill'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'act', action: { type: 'highlight', seriesIndex: 0, dataIndex: 0 } },
    ...after([0, 1, 100], T1), { t: T1 + 100, do: 'export', pixelRatio: 2 }, ...after([100, 101, 200, 401, 1000], T1)], { rows: [0] });

// ---- a heatmap's tooltip dimension (prepareSeriesDataSchema, generateCoord 'value') ----
const HM = (data, s, extra) => Object.assign({ animation: false, xAxis: { type: 'category', data: ['a', 'b'] },
  yAxis: { type: 'category', data: ['p', 'q'] }, visualMap: { min: 0, max: 10, show: false },
  series: [Object.assign({ type: 'heatmap', data }, s || {})] }, extra || {});
const D3 = [[0, 0, 5], [1, 1, 8]];
const D4 = [[0, 0, 5, 7], [1, 1, 8, 2]];
const ONE = [{ t: 0, do: 'sample' }];
add('htip', 'ht-3', "x, y, a value: the column past x and y is generated 'value' (not extra), the last a label suits", HM(D3), ['htip'], ONE);
add('htip', 'ht-4', "four columns: the third is 'value' (generated, not extra), the fourth extra -- the third", HM(D4), ['htip'], ONE);
add('htip', 'ht-4-v3', "encode {value: 3}: the third column is generated 'value0', not extra -- the last friendly one is the fourth", HM(D4, { encode: { value: 3 } }), ['htip'], ONE);
add('htip', 'ht-4-v2', "encode {value: 2}: the fourth column is generated 'value0', not extra -- the tooltip reads the fourth, the colour the third", HM(D4, { encode: { value: 2 } }), ['htip'], ONE);
add('htip', 'ht-4-swap', "encode {x: 1, y: 0}: the value the third", HM(D4, { encode: { x: 1, y: 0 } }), ['htip'], ONE);
add('htip', 'ht-4-str', "encode {value: 2}, the fourth column strings: 'value0' guessed ordinal -- no label for it, the third",
  HM([[0, 0, 5, 'u'], [1, 1, 8, 'w']], { encode: { value: 2 } }), ['htip'], ONE);
add('htip', 'ht-4-tip', "encode {tooltip: 3}: the fourth", HM(D4, { encode: { tooltip: 3 } }), ['htip'], ONE);
add('htip', 'ht-cal', "on a calendar: time and value are the calendar's own dimensions, a third column generated -- the third",
  { animation: false, calendar: { range: '2024-01', cellSize: 10 }, visualMap: { min: 0, max: 10, show: false },
    series: [{ type: 'heatmap', coordinateSystem: 'calendar', data: [['2024-01-02', 5, 9], ['2024-01-03', 8, 1]] }] }, ['htip'], ONE);
add('htip', 'ht-cal2', "on a calendar with two columns: the value",
  { animation: false, calendar: { range: '2024-01', cellSize: 10 }, visualMap: { min: 0, max: 10, show: false },
    series: [{ type: 'heatmap', coordinateSystem: 'calendar', data: [['2024-01-02', 5], ['2024-01-03', 8]] }] }, ['htip'], ONE);

// ---- a radar's point labels and their lines ----
const RD = data => ({ animation: true, animationDurationUpdate: 1000, animationEasingUpdate: 'linear',
  radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }] },
  series: [{ type: 'radar', symbolSize: 6, label: { show: true }, labelLine: { show: true }, labelLayout: { dx: 15, dy: -10 }, data }] });
add('radar', 'rd-slide', "a radar's points with labels moved off them by labelLayout and a label line: a merge slides the symbols -- the labels ride their symbols; the lines?",
  RD([{ value: [3, 5, 7] }]), ['rsym'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: [{ value: [8, 2, 4] }] }] } }, ...after([0, 1, 500, 1001], T1)]);

// ---- a themeRiver's labels under the enter clip ----
add('river', 'rv-label-clip', "a themeRiver's layers enter under their polygon's growing clip path; each layer's label (the polygon's textContent) is cut by it too",
  { animation: true, animationDuration: 1000, animationEasing: 'linear', singleAxis: { type: 'time', top: 40, bottom: 40 },
    series: [{ type: 'themeRiver', label: { show: true }, data: [['2024-01-01', 10, 'a'], ['2024-01-02', 20, 'a'], ['2024-01-03', 15, 'a'],
      ['2024-01-01', 5, 'b'], ['2024-01-02', 8, 'b'], ['2024-01-03', 12, 'b']] }] },
  ['rvlab'], after([0, 1, 100, 500, 999, 1000, 1001], 0));

// ---- a pictorial bar's emphasis.scale ----
add('pemph', 'pe-pin', "pictorial 'pin' glyphs with emphasis.scale 2.5 (truthy): the hovered glyph's emphasis state is its scale times 1.1, about the path's own origin -- the pin's point is not its box's centre",
  { animation: true, animationDuration: 10, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value', max: 100 },
    series: [{ type: 'pictorialBar', symbol: 'pin', symbolSize: [30, 30], symbolPosition: 'end', data: [40, 70],
      emphasis: { scale: 2.5 }, stateAnimation: { duration: 200, easing: 'linear' } }] },
  ['pglyph'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'act', action: { type: 'highlight', seriesIndex: 0, dataIndex: 0 } },
    ...after([0, 1, 100, 201, 300], T1)], { rows: [0] });

// ---- funnel ----
const FN = (data, extra, s) => Object.assign({ animation: true,
  series: [Object.assign({ type: 'funnel', left: 40, width: 260, data }, LIN, s || {})] }, extra || {});
const FD1 = [{ name: 'a', value: 60 }, { name: 'b', value: 40 }, { name: 'c', value: 20 }, { name: 'd', value: 80 }];
const FD2 = [{ name: 'a', value: 30 }, { name: 'b', value: 90 }, { name: 'c', value: 20 }, { name: 'd', value: 50 }];
add('funnel', 'fn-update', "a merge changes the values (the order changes): each piece updateProps its opacity and its four points, its outer label's style x / y (update timing, its row)",
  FN(FD1), ['funnel'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: FD2 }] } }, ...after(ENTER, T1)]);
add('funnel', 'fn-inside', "the same with the labels inside",
  FN(FD1, null, { label: { position: 'inside' } }), ['funnel'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: FD2 }] } }, ...after([0, 1, 500, 1001], T1)]);
add('funnel', 'fn-delay', "animationDelayUpdate idx * 100: each piece and its label wait their row's turn",
  FN(FD1, null, { animationDelayUpdate: { $fn: 'idx*100' } }), ['funnel'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: FD2 }] } }, ...after([0, 150, 250, 350, 1101, 1301, 1350], T1)]);
add('funnel', 'fn-add', "a merge adds a row: the new piece fades in (its points set), the kept ones move to make room",
  FN(FD1), ['funnel'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: FD1.concat([{ name: 'e', value: 10 }]) }] } },
    ...after([0, 1, 500, 1001], T1)]);

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
  guard('sa-resize: mid-tween, then the emphasis colour at once', (() => {
    const a = cs('sa-resize').events.filter(q => q.do === 'sample' && q.t === T1 + 100);
    return a.length === 2 && a[0].rec['bf0/0'].n > 0 && /^#ff0000$/i.test(a[1].rec['bf0/0'].fill) && a[1].rec['bf0/0'].n === 0;
  })());
  guard('sa-export: the emphasis colour at once', /255,0,0/.test(rec('sa-export', T1 + 100, 'bf0/0').fill) && rec('sa-export', T1 + 100, 'bf0/0').n === 0);
  guard('cd-simple-enter: the boxes are simple', rec('cd-simple-enter', 0, 'cd0/0').simple);
  guard('cd-simple-enter: a simple box tweens', (() => {
    const a = rec('cd-simple-enter', 100, 'cd0/150'), b = rec('cd-simple-enter', 1001, 'cd0/150');
    return a.n > 0 && a.pts[9] !== b.pts[9];
  })());
  guard('cd-add: a new candle enters', (() => {
    const a = rec('cd-add', T1 + 100, 'cd0/5'), b = rec('cd-add', T1 + 1001, 'cd0/5');
    return a && a.n > 0 && a.pts[1] !== b.pts[1] && !a.simple;
  })());
  guard('br-back: b kept and ignored before', (() => { const a = rec('br-back', T1 - 1, 'br0/1'); return a && a.ig && n(a.sh[3]) === 0; })());
  guard('br-back: b comes back on the update timing', (() => {
    const a = rec('br-back', T1 + 600, 'br0/1'), b = rec('br-back', T1 + 999, 'br0/1');
    return a && !a.ig && a.n > 0 && b.n > 0;
  })());
  guard('ml-name-swap: index 0 starts from where b was', (() => {
    const b = rec('ml-name-swap', T1 - 1, 'ml0/1'), a = rec('ml-name-swap', T1, 'ml0/0');
    return b && a && a.sh[1] === b.sh[1] && a.id === 'b';
  })());
  guard('mk-legend: on again, the line does not enter', (() => {
    const a = rec('mk-legend', T1 + 2001, 'ml1/0');
    return a && n(a.pc) === 1;
  })());
  guard('fn-update: a piece tweens its points', (() => {
    const a = rec('fn-update', T1 - 1, 'fn0/0'), b = rec('fn-update', T1 + 500, 'fn0/0'), c = rec('fn-update', T1 + 1001, 'fn0/0');
    return b.n > 0 && a.pts[1] !== b.pts[1] && b.pts[1] !== c.pts[1];
  })());
  guard('fn-update: a label moves', (() => {
    const a = rec('fn-update', T1 - 1, 'fl0/1'), b = rec('fn-update', T1 + 500, 'fl0/1'), c = rec('fn-update', T1 + 1001, 'fl0/1');
    return a && b && c && a.y !== b.y && b.y !== c.y;
  })());
  return g;
}

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function readRec(chart, c) {
  const rec = {};
  c.probes.forEach(p => PROBES[p](chart, rec, c));
  return rec;
}
function runCase(c) {
  const chart = mk(c.W, c.H);
  try {
    const out = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: clone(c.option),
      probes: c.probes, events: [] };
    if (c.rows) out.rows = c.rows;
    if (c.pts) out.pts = c.pts;
    quiet(() => chart.setOption(materialize(clone(c.option))));
    c.events.forEach(ev => {
      NOW = T0 + ev.t;
      const o = clone(ev);
      if (ev.do === 'sample') {
        zr(chart).animation.update();
        refresh(chart);
        o.rec = readRec(chart, c);
      }
      else if (ev.do === 'frame') zr(chart).animation.update();
      else if (ev.do === 'merge' || ev.do === 'mergeq') quiet(() => chart.setOption(materialize(clone(ev.option))));
      else if (ev.do === 'set') quiet(() => chart.setOption(materialize(clone(ev.option)), true));
      else if (ev.do === 'act') quiet(() => chart.dispatchAction(clone(ev.action)));
      else if (ev.do === 'export') quiet(() => chart.getDataURL({ pixelRatio: ev.pixelRatio }));
      else if (ev.do === 'resize') quiet(() => chart.resize({ width: ev.W, height: ev.H }));
      else if (ev.do === 'move') quiet(() => zr(chart).handler.mousemove({ zrX: ev.x, zrY: ev.y, which: 1, preventDefault() {}, stopPropagation() {} }));
      else must(false, 'an event it does not know: ' + ev.do);
      out.events.push(o);
    });
    return out;
  } finally {
    chart.dispose();
  }
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
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
const deterministic = json1 === json2;
const nul = json1.indexOf('\\u0000') >= 0;
let nSamples = 0;
out1.cases.forEach(q => q.events.forEach(e => { if (e.do === 'sample') nSamples++; }));
console.log(out1.cases.length + ' cases; ' + nSamples + ' samples; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : '')
  + '; ' + warnings + ' warnings');
if (bad.length || !deterministic || nul) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
