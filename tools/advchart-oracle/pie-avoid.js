// Upstream's own answers for a PIE'S LABEL AVOIDANCE -- chart/pie/labelLayout.ts'
// avoidOverlap with adjustSingleSide (the labels of a side sorted and shifted
// apart on y by labelLayoutHelper's shiftLayoutOnXY, then, where anything
// moved, their x solved again on an ellipse through the outermost label of
// each half), the labelLine / edge alignments, the target widths (bleedMargin,
// edgeDistance) and constrainTextWidth's truncation, and the last pass that
// stands every label line off its label again.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer). The pie's label
// layout is a module-private function, so the dist is loaded through
// Module._compile with TWO HOOKS added round the one statement that calls
// avoidOverlap (the regular expression below must match exactly once):
//   enter  -- the list pieLabelLayout built (every outer and centre label,
//             in data order), before the solver;
//   exit   -- the same list after it (or untouched, when the solver is off).
// The hooks only read; the dist's own code runs unchanged. After setOption
// the chart is rendered once to an SVG string and every pie label is read
// off the live elements: the lines zrender drew (the truncation), its
// transform, its alignment, whether LabelManager's hideOverlap (a pie's
// default labelLayout) hid it, and its label line.
//
//   node tools/advchart-oracle/pie-avoid.js
//
// writes tests/fixtures/advchart-pie-avoid.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as label-layout.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (NaN 7ff8000000000000)
//   rect     [x, y, width, height] in hex
//   mat      [m0 .. m5] in hex, or null for no transform
//   line     [[x, y] x 3] in hex, or null
//
// Top level
//   source, seed, notes[]
//   cases[]  one per chart:
//     id, note, W, H, option (as fed)
//     pies[]  one per pie series whose labels were laid out:
//       s, cx, cy, r (hex), view (rect: the series' viewRect),
//       hasLabelRotate (the LAST label's rotation, as upstream keeps it),
//       avoid (avoidLabelOverlap), ran (the solver ran)
//       items[]  pieLabelLayout's list in its order:
//         d (dataIndex), text (style.text), rich, position, alignTo,
//         len, len2, labelDistance, edgeDistance, bleedMargin (hex),
//         textAlign, offset [hex, hex] (the host's textConfig.offset),
//         labelStyleWidth (hex | null), padding ([4 hex] | null),
//         background, overflow, ellipsis, marginType, margin,
//         minTurnAngle, maxSurfaceAngle (the labelLine's, as JSON),
//         normal ([hex, hex]: the slice's surface normal),
//         entry {labelX, labelY, rotation, rect, unconstrainedWidth (hex),
//                line}
//         exit  {labelX, labelY, rect, line (before limitTurnAngle /
//                limitSurfaceAngle, which are roadmap B14), width
//                (style.width as constrainTextWidth left it, hex | null),
//                target (targetTextWidth, hex | null)}
//     labels[]  every pie label after the render, the view's traverse order:
//       s, d, text, lines (the drawn text pieces, in order), truncated,
//       ignore, mat, local (rect), align, verticalAlign,
//       guide {ignore, points (as drawn: after the two limits)} | null
//   guards[]  one per mutation of the transcription: id, mutation, named,
//             changed, ok
//
// ---------------------------------------------------------------------------
// The transcription (avoidOverlap, adjustSingleSide, recalculateX,
// shiftLayoutOnXY and constrainTextWidth, the label's rect measured by a
// zrender Text carrying a copy of the style the label had on entry) must
// reproduce every case's exit bit for bit. Self-checks (any failure: nothing
// is written, exit 1): the patch matches once; every pie is seen once; the
// transcription reproduces every case; every guard is ok; anchors; two
// generations in the process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');
const Module = require('module');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-pie-avoid.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- the dist, with the two hooks ----------
const SRC = fs.readFileSync(DIST, 'utf8');
const CALL_RE = /if \(!hasLabelRotate && seriesModel\.get\('avoidLabelOverlap'\)\) \{\s*avoidOverlap\(labelLayoutList, cx, cy, r, viewWidth, viewHeight, viewLeft, viewTop\);\s*\}/g;
const callHits = SRC.match(CALL_RE);
must(callHits && callHits.length === 1, 'the avoidOverlap call is not where it was (' + (callHits ? callHits.length : 0) + ' matches)');
const HOOK = ph => 'globalThis.__pieAvoidHook && globalThis.__pieAvoidHook(\'' + ph
  + '\', seriesModel, labelLayoutList, cx, cy, r, viewRect, hasLabelRotate);\n';
const PATCHED = SRC.replace(CALL_RE, m => HOOK('enter') + m + '\n' + HOOK('exit'));
const echarts = (() => {
  const mod = new Module(DIST, module);
  mod.filename = DIST;
  mod.paths = Module._nodeModulePaths(path.dirname(DIST));
  mod._compile(PATCHED, DIST);
  return mod.exports;
})();
must(typeof echarts.init === 'function', 'the patched dist does not load');

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

// ---------- number records ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hexOrNull = v => (v == null ? null : hex(v));
const rect4 = r => [hex(r.x), hex(r.y), hex(r.width), hex(r.height)];
const mat6 = m => (m ? Array.from(m).map(hex) : null);
const line3 = pts => (pts ? pts.map(p => [hex(p[0]), hex(p[1])]) : null);
const clone = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)));

// ECData lives in a makeInner store ('__ec_inner_<n>') on every element
let ecKey = null;
function ecData(el) {
  if (!el) return null;
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (k.indexOf('__ec_inner_') === 0 && v && typeof v === 'object'
        && ('dataIndex' in v || 'componentMainType' in v) && 'seriesIndex' in v) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}

// ---------- what the hooks keep ----------
// capture.pies: the records; capture.live: the same, with what the
// transcription needs and JSON cannot carry (a copy of each label's style
// and default style, and the Text constructor)
let capture = null;
globalThis.__pieAvoidHook = function (phase, seriesModel, list, cx, cy, r, viewRect, hasLabelRotate) {
  if (!capture) return;
  if (phase === 'enter') {
    const avoid = !!seriesModel.get('avoidLabelOverlap');
    const rec = {
      s: seriesModel.seriesIndex,
      cx: cx == null ? null : hex(cx), cy: cy == null ? null : hex(cy), r: hex(r),
      view: rect4(viewRect), hasLabelRotate: !!hasLabelRotate, avoid, ran: !hasLabelRotate && avoid,
      items: [],
    };
    const live = { cx, cy, r, view: { x: viewRect.x, y: viewRect.y, width: viewRect.width, height: viewRect.height }, ran: rec.ran, items: [] };
    for (const it of list) {
      const label = it.label;
      const st = label.style;
      const host = label.__hostTarget;
      const tc = host.textConfig || {};
      const off = tc.offset || [0, 0];
      rec.items.push({
        d: ecData(host).dataIndex,
        text: String(st.text),
        rich: !!st.rich,
        position: it.position == null ? null : it.position,
        alignTo: it.labelAlignTo,
        len: hex(it.len), len2: hex(it.len2), labelDistance: hex(it.labelDistance),
        edgeDistance: hex(it.edgeDistance), bleedMargin: hex(it.bleedMargin),
        textAlign: it.textAlign,
        offset: [hex(off[0]), hex(off[1])],
        labelStyleWidth: hexOrNull(it.labelStyleWidth),
        padding: st.padding ? Array.from(st.padding).map(hex) : null,
        background: !!st.backgroundColor,
        overflow: st.overflow == null ? null : st.overflow,
        ellipsis: st.ellipsis == null ? null : st.ellipsis,
        marginType: st.__marginType == null ? null : st.__marginType,
        margin: st.margin ? Array.from(st.margin).map(hex) : null,
        // the two limits the last pass bends the line by, and the slice's
        // normal [Batch 112]
        minTurnAngle: it.minTurnAngle === undefined ? null : it.minTurnAngle,
        maxSurfaceAngle: it.maxSurfaceAngle === undefined ? null : it.maxSurfaceAngle,
        normal: [hex(it.surfaceNormal.x), hex(it.surfaceNormal.y)],
        entry: {
          labelX: hex(label.x), labelY: hex(label.y), rotation: hex(label.rotation),
          rect: rect4(it.rect), unconstrainedWidth: hex(it.unconstrainedWidth),
          line: line3(it.linePoints),
        },
      });
      live.items.push({
        ctor: label.constructor,
        style: Object.assign({}, st),
        defStyle: Object.assign({}, label._defaultStyle || {}),
        offX: off[0], offY: off[1],
      });
    }
    capture.pies.push(rec);
    capture.live.push(live);
    return;
  }
  const rec = capture.pies[capture.pies.length - 1];
  must(rec && rec.s === seriesModel.seriesIndex && !rec.items.some(i => i.exit), 'the exit hook without its entry');
  must(rec.items.length === list.length, 'the list changed length');
  list.forEach((it, i) => {
    const label = it.label;
    rec.items[i].exit = {
      labelX: hex(label.x), labelY: hex(label.y), rect: rect4(it.rect), line: line3(it.linePoints),
      width: hexOrNull(label.style.width), target: hexOrNull(it.targetTextWidth),
    };
  });
};

// ---------- the cases ----------
const cats = ['Apples', 'Bananas', 'Cherries', 'Dates', 'Elderberries', 'Figs', 'Grapes', 'Honeydew', 'Kiwis', 'Lemons', 'Mangoes', 'Nectarines'];
const nameOf = i => cats[i % cats.length] + (i >= cats.length ? ' ' + i : '');
const longName = i => 'A rather long category name ' + i;
const both = (n, nm) => Array.from({ length: n }, (_, i) => ({ name: (nm || nameOf)(i), value: (i * 7) % 11 + 1 }));
// one big slice, then many small ones crowded on one side of the pie
const skew = (n, first) => {
  const small = Array.from({ length: n }, (_, i) => ({ name: 's' + i, value: 1 + (i % 3) }));
  const big = { name: 'Big', value: 120 };
  return first ? [big].concat(small) : small.concat([big]);
};
function pie(series, extra, W, H) {
  return {
    W: W || 600, H: H || 400,
    option: Object.assign({ animation: false, series: [Object.assign({ type: 'pie', radius: '50%' }, series)] }, extra || {}),
  };
}
const CASES = [
  // ---- crowding ----
  Object.assign({ id: 'one.left', note: 'many small slices after a big one: crowded up the left side' }, pie({ data: skew(16, true) })),
  Object.assign({ id: 'one.right', note: 'many small slices before a big one: crowded down the right side' }, pie({ data: skew(16, false) })),
  Object.assign({ id: 'both', note: 'both sides crowded' }, pie({ data: both(36) })),
  Object.assign({ id: 'both.nohide', note: 'both sides crowded, labelLayout null: nothing hidden after the solver' }, pie({ data: both(36), labelLayout: null })),
  Object.assign({ id: 'many', note: 'more labels than the height holds: squeezed, then let overlap and hidden' }, pie({ data: both(70) })),
  Object.assign({ id: 'sparse', note: 'six slices: nothing moves, the line still stands off the label again' }, pie({ data: both(6) })),
  Object.assign({ id: 'pair', note: 'one label a side: adjustSingleSide returns at once' }, pie({ data: [{ name: 'Left', value: 1 }, { name: 'Right', value: 1 }], startAngle: 0 })),
  // ---- alignTo ----
  Object.assign({ id: 'labelLine', note: 'alignTo labelLine, crowded: every label to the farthest x first' }, pie({ data: both(30), label: { alignTo: 'labelLine' } })),
  Object.assign({ id: 'labelLine.sparse', note: 'alignTo labelLine on six slices' }, pie({ data: both(6), label: { alignTo: 'labelLine' } })),
  Object.assign({ id: 'edge', note: 'alignTo edge, crowded (default edgeDistance 25%)' }, pie({ data: both(30), label: { alignTo: 'edge' } })),
  Object.assign({ id: 'edge.px', note: 'alignTo edge, edgeDistance 20 px' }, pie({ data: both(20), label: { alignTo: 'edge', edgeDistance: 20 } })),
  Object.assign({ id: 'edge.pct', note: 'alignTo edge, edgeDistance 10%' }, pie({ data: both(20, longName), label: { alignTo: 'edge', edgeDistance: '10%' } })),
  // ---- the target width ----
  Object.assign({ id: 'bleed', note: 'bleedMargin 60 cuts long names' }, pie({ data: both(14, longName), label: { bleedMargin: 60 } })),
  Object.assign({ id: 'small', note: 'a view under 200 px: bleedMargin 2 by default' }, pie({ data: both(10), radius: '35%' }, null, 190, 180)),
  Object.assign({ id: 'narrow', note: 'long names in a narrow chart: truncated' }, pie({ data: both(20, longName) }, null, 320, 300)),
  Object.assign({ id: 'narrow.edge', note: 'alignTo edge in a narrow chart' }, pie({ data: both(16, longName), label: { alignTo: 'edge' } }, null, 320, 300)),
  Object.assign({ id: 'narrow.labelLine', note: 'alignTo labelLine in a narrow chart' }, pie({ data: both(16, longName), label: { alignTo: 'labelLine' } }, null, 320, 300)),
  Object.assign({ id: 'narrow.width', note: 'an author label.width: never constrained' }, pie({ data: both(16, longName), label: { width: 70 } }, null, 320, 300)),
  // ---- the label line ----
  Object.assign({ id: 'len', note: 'labelLine length 40, length2 8' }, pie({ data: both(30), labelLine: { length: 40, length2: 8 } })),
  Object.assign({ id: 'len.pct', note: 'labelLine length 6%, length2 3% (of the view width)' }, pie({ data: both(30), labelLine: { length: '6%', length2: '3%' } })),
  Object.assign({ id: 'distance', note: 'distanceToLabelLine 12' }, pie({ data: both(30), label: { distanceToLabelLine: 12 } })),
  Object.assign({ id: 'noline', note: 'labelLine.show false: the points still steer the labels' }, pie({ data: both(30), labelLine: { show: false } })),
  // ---- geometry ----
  Object.assign({ id: 'rose.radius', note: 'roseType radius' }, pie({ data: both(24), roseType: 'radius', radius: ['10%', '55%'] })),
  Object.assign({ id: 'rose.area', note: 'roseType area' }, pie({ data: both(24), roseType: 'area' })),
  Object.assign({ id: 'start0', note: 'startAngle 0' }, pie({ data: skew(14, true), startAngle: 0 })),
  Object.assign({ id: 'ccw', note: 'clockwise false' }, pie({ data: skew(14, true), clockwise: false })),
  Object.assign({ id: 'start200.ccw', note: 'startAngle 200, counter-clockwise' }, pie({ data: both(30), startAngle: 200, clockwise: false })),
  Object.assign({ id: 'centre', note: 'the centre off the middle' }, pie({ data: both(24), center: ['35%', '62%'], radius: '35%' })),
  Object.assign({ id: 'donut', note: 'a ring' }, pie({ data: both(30), radius: ['30%', '50%'] })),
  Object.assign({ id: 'view', note: 'a view rect of its own (left / top / width / height)' }, pie({ data: both(24), left: 80, top: 40, width: 360, height: 300 })),
  // ---- text ----
  Object.assign({ id: 'rich', note: 'rich labels' }, pie({ data: both(24), label: { formatter: '{a|{b}}{c|{c}}', rich: { a: { fontSize: 13 }, c: { color: '#999', padding: [0, 0, 0, 4] } } } })),
  Object.assign({ id: 'rich.narrow', note: 'rich labels cut in a narrow chart' }, pie({ data: both(16, longName), label: { formatter: '{a|{b}}', rich: { a: { fontSize: 11 } } } }, null, 320, 300)),
  Object.assign({ id: 'box', note: 'labels in a box: padding and background' }, pie({ data: both(20, longName), label: { backgroundColor: '#eee', padding: [2, 6] } }, null, 360, 320)),
  Object.assign({ id: 'minMargin', note: 'minMargin 8: the rect grows on y, not on x' }, pie({ data: both(24), label: { minMargin: 8 } })),
  Object.assign({ id: 'offset', note: 'label.offset rides in the rect the solver shifts' }, pie({ data: both(30), label: { offset: [4, -3] } })),
  Object.assign({ id: 'top', note: 'position top: the outer placement without a line' }, pie({ data: both(24), label: { position: 'top' } })),
  Object.assign({ id: 'minShow', note: 'minShowLabelAngle 4 drops the thinnest' }, pie({ data: both(60), minShowLabelAngle: 4 })),
  Object.assign({ id: 'center', note: 'position center: in the list, never moved' }, pie({ data: both(12), radius: ['40%', '55%'], label: { position: 'center' } })),
  Object.assign({ id: 'outside.labelLine', note: 'position outside with alignTo labelLine: only the literal outer goes to the farthest x' }, pie({ data: both(30), label: { position: 'outside', alignTo: 'labelLine' } })),
  Object.assign({ id: 'box.edge', note: 'labels in a box aligned to the edge: the real width counts the padding once' }, pie({ data: both(20, longName), label: { alignTo: 'edge', backgroundColor: '#eee', padding: [2, 6] } }, null, 360, 320)),
  Object.assign({ id: 'pad.edge', note: 'padding without a background, aligned to the edge' }, pie({ data: both(20, longName), label: { alignTo: 'edge', padding: [2, 6] } }, null, 360, 320)),
  Object.assign({ id: 'ellipsis', note: 'label.ellipsis ~ on cut labels' }, pie({ data: both(20, longName), label: { ellipsis: '~' } }, null, 320, 300)),
  Object.assign({ id: 'box.sparse', note: 'six labels in a box, nothing shifted: the first constraint is the last' }, pie({ data: both(6, i => 'Name number ' + i), label: { backgroundColor: '#eee', padding: [2, 8] } }, null, 316, 300)),
  Object.assign({ id: 'offset.many', note: 'label.offset on a pie crowded past the view: the offset rides in the rects the bounds see' }, pie({ data: both(70), label: { offset: [3, 10] } })),
  Object.assign({ id: 'ellipsis.edge', note: 'label.ellipsis ~ on edge-aligned cut labels: the line ends at the cut width' }, pie({ data: both(16, longName), label: { alignTo: 'edge', ellipsis: '~' } }, null, 320, 300)),
  Object.assign({ id: 'minMargin.hide', note: 'minMargin 14 with the solver off: hideOverlap counts the margin' }, pie({ data: both(30), avoidLabelOverlap: false, label: { minMargin: 14 } })),
  Object.assign({ id: 'textMargin.hide', note: 'textMargin with the solver on: its rects and hideOverlap count it' }, pie({ data: both(50), label: { textMargin: [6, 2] } })),
  Object.assign({ id: 'bounds', note: 'a big pie whose few labels stand past the view: moved in by the bounds alone, then solved again' }, pie({ data: [{ name: 'Top', value: 1 }, { name: 'Right', value: 6 }, { name: 'Bottom', value: 1 }, { name: 'Left', value: 6 }], startAngle: 95, radius: '100%' }, null, 400, 300)),
  Object.assign({ id: 'view.crowded', note: 'a view rect off the top, crowded past it: the shift is bounded by the view' }, pie({ data: both(60), top: 90, height: 230, radius: '40%' })),
  Object.assign({ id: 'box.wide', note: 'labels in a box with room to spare: a constraint only where the box is wider than the room' }, pie({ data: both(20, i => 'Name number ' + i), label: { backgroundColor: '#eee', padding: [2, 8] } }, null, 420, 320)),
  Object.assign({ id: 'box.bleed', note: 'labels in a box, bleedMargin 30' }, pie({ data: both(16, i => 'Category ' + i), label: { backgroundColor: '#eee', padding: [2, 10], bleedMargin: 30 } }, null, 380, 320)),
  // ---- the solver off ----
  Object.assign({ id: 'off', note: 'avoidLabelOverlap false: the labels stay, hideOverlap hides' }, pie({ data: both(36), avoidLabelOverlap: false })),
  Object.assign({ id: 'off.narrow', note: 'avoidLabelOverlap false in a narrow chart: nothing is cut' }, pie({ data: both(16, longName), avoidLabelOverlap: false }, null, 320, 300)),
  Object.assign({ id: 'radial', note: 'rotate radial: the solver does not run' }, pie({ data: both(24), label: { rotate: 'radial' } })),
  Object.assign({ id: 'inside', note: 'inside labels never enter the list' }, pie({ data: both(12), label: { position: 'inside' } })),
  Object.assign({ id: 'two', note: 'two pies, each laid out on its own' }, {
    W: 600, H: 400,
    option: { animation: false, series: [
      { type: 'pie', radius: '30%', center: ['25%', '50%'], data: both(20) },
      { type: 'pie', radius: '30%', center: ['75%', '50%'], data: skew(12, true) }] },
  }),
];

// ---------- one case ----------
function runCase(c) {
  rngState = SEED;
  capture = { pies: [], live: [] };
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: c.W, height: c.H });
  try {
    chart.setOption(c.option);
    const pies = capture.pies;
    const live = capture.live;
    capture = null;
    chart.renderToSVGString();
    must(pies.every(p => p.items.every(i => i.exit)), c.id + ': a pie without its exit');
    const labels = [];
    chart.getModel().eachSeries(s => {
      const view = chart.getViewOfSeriesModel(s);
      view.group.traverse(el => {
        if (el.ignore) return true;
        const t = el.getTextContent && el.getTextContent();
        if (!t) return;
        const d = ecData(el);
        const ds = t._defaultStyle || {};
        const g = el.getTextGuideLine && el.getTextGuideLine();
        const kids = t.childrenRef ? t.childrenRef() : [];
        labels.push({
          s: s.seriesIndex,
          d: d && d.dataIndex != null ? d.dataIndex : null,
          text: String(t.style.text),
          lines: kids.filter(k => k.type === 'tspan').map(k => String(k.style.text)),
          truncated: !!t.isTruncated,
          ignore: !!t.ignore,
          mat: mat6(t.getComputedTransform()),
          local: rect4(t.getBoundingRect()),
          align: t.style.align || ds.align || 'left',
          verticalAlign: t.style.verticalAlign || ds.verticalAlign || 'top',
          guide: g ? { ignore: !!g.ignore, points: (g.shape.points || []).map(p => [hex(p[0]), hex(p[1])]) } : null,
        });
      });
    });
    return { rec: { id: c.id, note: c.note, W: c.W, H: c.H, option: clone(c.option), pies, labels }, live };
  } finally {
    capture = null;
    chart.dispose();
  }
}

// ---------- the transcription ----------
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const unrect = a => ({ x: num(a[0]), y: num(a[1]), width: num(a[2]), height: num(a[3]) });
const unline = a => (a ? a.map(p => [num(p[0]), num(p[1])]) : null);
// expandOrShrinkRect(rect, delta, false, false)
function expandOnDim(r, delta, xy, wh, lt, rb) {
  const deltaSum = delta[rb] + delta[lt];
  const oldSize = r[wh];
  r[wh] += deltaSum;
  const minSize = Math.max(0, Math.min(0, oldSize));
  if (r[wh] < minSize) {
    r[wh] = minSize;
    r[xy] += (delta[lt] >= 0 ? -delta[lt]
      : delta[rb] >= 0 ? oldSize + delta[rb]
        : Math.abs(deltaSum) > 1e-8 ? (oldSize - minSize) * delta[lt] / deltaSum : 0);
  } else {
    r[xy] -= delta[lt];
  }
}
function expandRect(r, delta) {
  expandOnDim(r, delta, 'x', 'width', 3, 1);
  expandOnDim(r, delta, 'y', 'height', 0, 2);
}
function applyTransform(out, m) {
  if (!m) return;
  if (m[1] < 1e-5 && m[1] > -1e-5 && m[2] < 1e-5 && m[2] > -1e-5) {
    const sx = m[0];
    const sy = m[3];
    const tx = m[4];
    const ty = m[5];
    out.x = out.x * sx + tx;
    out.y = out.y * sy + ty;
    out.width = out.width * sx;
    out.height = out.height * sy;
    if (out.width < 0) {
      out.x += out.width;
      out.width = -out.width;
    }
    if (out.height < 0) {
      out.y += out.height;
      out.height = -out.height;
    }
    return;
  }
  const pts = [[out.x, out.y], [out.x + out.width, out.y], [out.x + out.width, out.y + out.height], [out.x, out.y + out.height]];
  const tr = pts.map(p => [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]]);
  let minX = tr[0][0];
  let minY = tr[0][1];
  let maxX = tr[0][0];
  let maxY = tr[0][1];
  for (let i = 1; i < 4; i++) {
    minX = Math.min(minX, tr[i][0]);
    minY = Math.min(minY, tr[i][1]);
    maxX = Math.max(maxX, tr[i][0]);
    maxY = Math.max(maxY, tr[i][1]);
  }
  out.x = minX;
  out.y = minY;
  out.width = maxX - minX;
  out.height = maxY - minY;
}
// Transformable.getLocalTransform with needLocalTransform's 5e-5 test
const around0 = v => v > -5e-5 && v < 5e-5;
function localTransform(x, y, ox, oy, rotation) {
  if (around0(rotation) && around0(x) && around0(y)) return null;
  const m = [1, 0, 0, 1, 0, 0];
  if (ox || oy) {
    m[4] = -ox * 1 - 0 * oy * 1;
    m[5] = -oy * 1 - 0 * ox * 1;
  } else {
    m[4] = m[5] = 0;
  }
  m[0] = 1;
  m[3] = 1;
  m[1] = 0 * 1;
  m[2] = 0 * 1;
  if (rotation) {
    const aa = m[0];
    const ac = m[2];
    const atx = m[4];
    const ab = m[1];
    const ad = m[3];
    const aty = m[5];
    const st = Math.sin(rotation);
    const ct = Math.cos(rotation);
    m[0] = aa * ct + ab * st;
    m[1] = -aa * st + ab * ct;
    m[2] = ac * ct + ad * st;
    m[3] = -ac * st + ct * ad;
    m[4] = ct * (atx - 0) + st * (aty - 0) + 0;
    m[5] = ct * (aty - 0) - st * (atx - 0) + 0;
  }
  m[4] += ox + x;
  m[5] += oy + y;
  return m;
}
// computeLabelGlobalRect: computeLabelGeometry with minMarginForce
// [null, 0, null, 0] and marginDefault [1, 0, 1, 0], the label measured by a
// Text carrying the entry style with the width constrainTextWidth set
function globalRect(it, mut) {
  const T = it.live.ctor;
  const t = new T();
  const st = Object.assign({}, it.live.style);
  if (it.width === undefined) delete st.width;
  else st.width = it.width;
  t.useStyle(st);
  t.setDefaultTextStyle(it.live.defStyle);
  const raw = t.getBoundingRect();
  const local = { x: raw.x, y: raw.y, width: raw.width, height: raw.height };
  let marginType = st.__marginType;
  let margin = st.margin;
  if (marginType == null) {
    margin = [1, 0, 1, 0];
    marginType = 2;
  }
  const mg = [0, 0, 0, 0];
  const minForce = [null, 0, null, 0];
  for (let i = 0; i < 4; i++) {
    mg[i] = marginType === 1 && minForce[i] != null && !mut.noMinForce ? minForce[i] : (margin ? margin[i] : 0);
  }
  if (marginType === 2) expandRect(local, mg);
  const ox = mut.noOffsetRect ? 0 : it.live.offX;
  const oy = mut.noOffsetRect ? 0 : it.live.offY;
  const m = localTransform(it.labelX + ox, it.labelY + oy, -ox, -oy, it.rotation);
  applyTransform(local, m);
  if (marginType === 1) expandRect(local, mg);
  return local;
}
function constrainTextWidth(it, availableWidth, force, mut) {
  if (it.labelStyleWidth != null) return;
  if (mut.noConstrain) return;
  const st = it.live.style;
  const bg = st.backgroundColor;
  const padding = st.padding;
  const paddingH = padding && !mut.noPadding ? padding[1] + padding[3] : 0;
  const overflow = st.overflow;
  const oldOuterWidth = it.rect.width + (bg && !mut.oldOuterPad ? 0 : paddingH);
  if (availableWidth < oldOuterWidth || force) {
    must(!(overflow && overflow.match('break')), 'overflow break is not transcribed');
    const inner = availableWidth - paddingH;
    it.width = availableWidth < oldOuterWidth ? inner
      : force ? (inner > it.unconstrainedWidth && !mut.alwaysConstrain ? null : inner)
        : null;
    if (it.width === null) it.width = undefined;
    it.rect = globalRect(it, mut);
  }
}
function shiftLayoutOnXY(list, minBound, maxBound, mut) {
  const len = list.length;
  if (len < 2) return false;
  list.sort((a, b) => a.rect.y - b.rect.y);
  let lastPos = 0;
  let delta;
  let adjusted = false;
  for (let i = 0; i < len; i++) {
    const item = list[i];
    const rect = item.rect;
    delta = rect.y - lastPos;
    if (delta < 0) {
      rect.y -= delta;
      item.labelY -= delta;
      adjusted = true;
    }
    lastPos = rect.y + rect.height;
  }
  const first = list[0];
  const last = list[len - 1];
  let minGap;
  let maxGap;
  function updateMinMaxGap() {
    minGap = first.rect.y - minBound;
    maxGap = maxBound - last.rect.y - last.rect.height;
  }
  function shiftList(d, start, end) {
    if (d !== 0 && !mut.noShiftAdjusted) adjusted = true;
    for (let i = start; i < end; i++) {
      list[i].rect.y += d;
      list[i].labelY += d;
    }
  }
  function squeezeGaps(d, maxPct) {
    const gaps = [];
    let totalGaps = 0;
    for (let i = 1; i < len; i++) {
      const prev = list[i - 1].rect;
      const gap = Math.max(list[i].rect.y - prev.y - prev.height, 0);
      gaps.push(gap);
      totalGaps += gap;
    }
    if (!totalGaps) return;
    const pct = Math.min(Math.abs(d) / totalGaps, maxPct);
    if (d > 0) {
      for (let i = 0; i < len - 1; i++) shiftList(gaps[i] * pct, 0, i + 1);
    } else {
      for (let i = len - 1; i > 0; i--) shiftList(-gaps[i - 1] * pct, i, len);
    }
  }
  function takeBoundsGap(gapThis, gapOther, dir) {
    if (gapThis < 0) {
      const moveFromMaxGap = Math.min(gapOther, -gapThis);
      if (moveFromMaxGap > 0) {
        shiftList(moveFromMaxGap * dir, 0, len);
        const remained = moveFromMaxGap + gapThis;
        if (remained < 0) squeezeGaps(-remained * dir, 1);
      } else {
        squeezeGaps(-gapThis * dir, 1);
      }
    }
  }
  function squeezeWhenBailout(d) {
    const dir = d < 0 ? -1 : 1;
    d = Math.abs(d);
    const each = Math.ceil(d / (len - 1));
    for (let i = 0; i < len - 1; i++) {
      if (dir > 0) shiftList(each, 0, i + 1);
      else shiftList(-each, len - i - 1, len);
      d -= each;
      if (d <= 0) return;
    }
  }
  updateMinMaxGap();
  minGap < 0 && squeezeGaps(-minGap, 0.8);
  maxGap < 0 && squeezeGaps(maxGap, 0.8);
  updateMinMaxGap();
  takeBoundsGap(minGap, maxGap, 1);
  takeBoundsGap(maxGap, minGap, -1);
  updateMinMaxGap();
  if (minGap < 0) squeezeWhenBailout(-minGap);
  if (maxGap < 0) squeezeWhenBailout(maxGap);
  return adjusted;
}
function adjustSingleSide(list, cx, cy, r, dir, view, farthestX, mut) {
  if (list.length < 2) return;
  function onSemi(semi) {
    const rB = semi.rB;
    const rB2 = rB * rB;
    for (const item of semi.list) {
      const dy = Math.abs(item.labelY - cy);
      const rA = r + (mut.ellipseR ? 0 : item.len);
      const rA2 = rA * rA;
      const dx = Math.sqrt(Math.abs((1 - dy * dy / rB2) * rA2));
      const newX = cx + (dx + (mut.noLen2 ? 0 : item.len2)) * dir;
      const deltaX = newX - item.labelX;
      const newTarget = item.target - deltaX * dir;
      constrainTextWidth(item, newTarget, !mut.noForce, mut);
      item.labelX = newX;
    }
  }
  function recalculateX(items) {
    const top = { list: [], maxY: 0 };
    const bottom = mut.oneSemi ? top : { list: [], maxY: 0 };
    for (const item of items) {
      if (item.alignTo !== 'none') continue;
      const semi = item.labelY > cy ? bottom : top;
      const dy = Math.abs(item.labelY - cy);
      if (dy >= semi.maxY) {
        const dx = item.labelX - cx - item.len2 * dir;
        const rA = r + item.len;
        const rB = Math.abs(dx) < rA ? Math.sqrt(dy * dy / (1 - dx * dx / rA / rA)) : rA;
        semi.rB = rB;
        semi.maxY = dy;
      }
      semi.list.push(item);
    }
    onSemi(top);
    if (bottom !== top) onSemi(bottom);
  }
  if (!mut.noFarthest) {
    for (const item of list) {
      if ((item.position === 'outer' || mut.anyOuter) && item.alignTo === 'labelLine') {
        const dx = item.labelX - farthestX;
        item.line[1][0] += dx;
        item.labelX = farthestX;
      }
    }
  }
  if (mut.noShift) return;
  if (shiftLayoutOnXY(list, mut.viewTop0 ? 0 : view.y, view.y + view.height, mut) && !mut.noRecalcX) recalculateX(list);
}
function transcribe(pieRec, live, mut) {
  const cx = live.cx;
  const cy = live.cy;
  const r = live.r;
  const view = live.view;
  const items = pieRec.items.map((rec, i) => ({
    live: live.items[i],
    position: rec.position, alignTo: rec.alignTo,
    len: num(rec.len), len2: num(rec.len2), labelDistance: num(rec.labelDistance),
    edgeDistance: num(rec.edgeDistance), bleedMargin: num(rec.bleedMargin),
    labelStyleWidth: rec.labelStyleWidth == null ? null : num(rec.labelStyleWidth),
    labelX: num(rec.entry.labelX), labelY: num(rec.entry.labelY), rotation: num(rec.entry.rotation),
    rect: unrect(rec.entry.rect), unconstrainedWidth: num(rec.entry.unconstrainedWidth),
    line: unline(rec.entry.line), width: live.items[i].style.width, target: undefined,
  }));
  // the entry rect is what the transcription's measurement gives too
  items.forEach((it, i) => {
    const g = globalRect(it, {});
    must(rect4(g).join() === pieRec.items[i].entry.rect.join(), 'the entry rect of item ' + i + ' is not reproduced');
  });
  if (pieRec.ran) {
    const isCentre = it => it.position === 'center' && !mut.centreIn;
    const left = [];
    const right = [];
    let leftmostX = Number.MAX_VALUE;
    let rightmostX = -Number.MAX_VALUE;
    for (const it of items) {
      if (isCentre(it)) continue;
      if (it.labelX < cx) {
        leftmostX = Math.min(leftmostX, it.labelX);
        left.push(it);
      } else {
        rightmostX = Math.max(rightmostX, it.labelX);
        right.push(it);
      }
    }
    for (const it of items) {
      if (isCentre(it) || !it.line) continue;
      if (it.labelStyleWidth != null) continue;
      const bleed = mut.noBleed ? 0 : it.bleedMargin;
      const edgeD = mut.noEdgeDistance ? 0 : it.edgeDistance;
      let target;
      if (it.alignTo === 'edge') {
        target = it.labelX < cx ? it.line[2][0] - it.labelDistance - view.x - edgeD
          : view.x + view.width - edgeD - it.line[2][0] - it.labelDistance;
      } else if (it.alignTo === 'labelLine') {
        target = it.labelX < cx ? leftmostX - view.x - bleed : view.x + view.width - rightmostX - bleed;
      } else {
        target = it.labelX < cx ? it.labelX - view.x - bleed : view.x + view.width - it.labelX - bleed;
      }
      it.target = target;
      constrainTextWidth(it, target, false, mut);
    }
    adjustSingleSide(right, cx, cy, r, 1, view, rightmostX, mut);
    adjustSingleSide(left, cx, cy, r, -1, view, leftmostX, mut);
    for (const it of items) {
      if (isCentre(it) || !it.line) continue;
      const st = it.live.style;
      const padding = st.padding;
      const paddingH = padding && !mut.noPadding ? padding[1] + padding[3] : 0;
      const extra = st.backgroundColor && !mut.padTwice ? 0 : paddingH;
      const real = it.rect.width + extra;
      const dist = it.line[1][0] - it.line[2][0];
      if (it.alignTo === 'edge' && !mut.edgeLikeNone) {
        it.line[2][0] = it.labelX < cx ? view.x + it.edgeDistance + real + it.labelDistance
          : view.x + view.width - it.edgeDistance - real - it.labelDistance;
      } else {
        it.line[2][0] = it.labelX < cx ? it.labelX + it.labelDistance : it.labelX - it.labelDistance;
        if (!mut.noDist) it.line[1][0] = it.line[2][0] + dist;
      }
      if (!mut.noLineY) it.line[1][1] = it.line[2][1] = it.labelY;
    }
  }
  return items.map(it => ({
    labelX: hex(it.labelX), labelY: hex(it.labelY), rect: rect4(it.rect), line: line3(it.line),
    width: hexOrNull(it.width), target: hexOrNull(it.target),
  }));
}
const sameExit = (a, b) => a.labelX === b.labelX && a.labelY === b.labelY && a.rect.join() === b.rect.join()
  && JSON.stringify(a.line) === JSON.stringify(b.line) && a.width === b.width && a.target === b.target;
function pieChanged(pieRec, live, mut) {
  const got = transcribe(pieRec, live, mut);
  return got.some((g, i) => !sameExit(g, pieRec.items[i].exit));
}

const GUARDS = [
  { id: 'noShift', mutation: 'no shiftLayoutOnXY (and so no recalculateX)', mut: { noShift: true }, named: ['both', 'one.left', 'one.right', 'many'] },
  { id: 'noRecalcX', mutation: 'shifted but x never solved on the ellipse', mut: { noRecalcX: true }, named: ['both', 'one.left', 'one.right'] },
  { id: 'ellipseR', mutation: 'the ellipse\'s horizontal semi-axis r, not r + length', mut: { ellipseR: true }, named: ['both', 'one.left'] },
  { id: 'noLen2', mutation: 'the new x without length2', mut: { noLen2: true }, named: ['both', 'one.right'] },
  { id: 'oneSemi', mutation: 'one ellipse for both halves', mut: { oneSemi: true }, named: ['both'] },
  { id: 'noBleed', mutation: 'bleedMargin ignored', mut: { noBleed: true }, named: ['bleed', 'narrow', 'small'] },
  { id: 'noEdgeDistance', mutation: 'edgeDistance left out of the edge target', mut: { noEdgeDistance: true }, named: ['narrow.edge', 'edge.pct'] },
  { id: 'noFarthest', mutation: 'alignTo labelLine does not move labels to the farthest x', mut: { noFarthest: true }, named: ['labelLine', 'labelLine.sparse'] },
  { id: 'noConstrain', mutation: 'constrainTextWidth sets nothing', mut: { noConstrain: true }, named: ['narrow', 'bleed', 'narrow.edge'] },
  { id: 'noForce', mutation: 'recalculateX does not force a new width', mut: { noForce: true }, named: ['narrow'] },
  { id: 'alwaysConstrain', mutation: 'a forced width never released when the text fits', mut: { alwaysConstrain: true }, named: ['both'] },
  { id: 'edgeLikeNone', mutation: 'alignTo edge\'s line end from the label x, as the others', mut: { edgeLikeNone: true }, named: ['edge', 'edge.px'] },
  { id: 'noDist', mutation: 'the middle point does not keep its distance from the end', mut: { noDist: true }, named: ['both', 'labelLine.sparse'] },
  { id: 'noLineY', mutation: 'the line\'s last segment not moved to the label y', mut: { noLineY: true }, named: ['both'] },
  { id: 'noPadding', mutation: 'padding left out of the widths', mut: { noPadding: true }, named: ['box'] },
  { id: 'noMinForce', mutation: 'minMargin keeps its x margins', mut: { noMinForce: true }, named: ['minMargin'] },
  { id: 'centreIn', mutation: 'centre labels shifted with the outer ones', mut: { centreIn: true }, named: ['center'] },
  { id: 'anyOuter', mutation: 'every position goes to the farthest x, not only the literal outer', mut: { anyOuter: true }, named: ['outside.labelLine'] },
  { id: 'oldOuterPad', mutation: 'the old outer width of a label with a background counts the padding again', mut: { oldOuterPad: true }, named: ['box.sparse'] },
  { id: 'noOffsetRect', mutation: 'the rect measured without the offset', mut: { noOffsetRect: true }, named: ['offset.many'] },
  { id: 'noShiftAdjusted', mutation: 'only the first pass counts as a move', mut: { noShiftAdjusted: true }, named: ['bounds'] },
  { id: 'viewTop0', mutation: 'the shift bounded by the chart top, not by the top of the view', mut: { viewTop0: true }, named: ['view.crowded'] },
  { id: 'padTwice', mutation: 'the real width of a label with a background counts the padding again', mut: { padTwice: true }, named: ['box.edge'] },
];

// ---------- generation ----------
function generate() {
  const runs = CASES.map(runCase);
  const cases = runs.map(r => r.rec);
  // the transcription reproduces every pie
  for (const run of runs) {
    run.rec.pies.forEach((p, k) => {
      const got = transcribe(p, run.live[k], {});
      got.forEach((g, i) => must(sameExit(g, p.items[i].exit), run.rec.id + ' pie ' + k + ': the transcription disagrees at item '
        + i + ': ' + JSON.stringify(g) + ' vs ' + JSON.stringify(p.items[i].exit)));
    });
  }
  const byId = {};
  for (const c of cases) byId[c.id] = c;
  const moved = id => byId[id].pies.some(p => p.items.some(i => i.exit.labelY !== i.entry.labelY));
  const cut = id => byId[id].labels.some(l => l.truncated);
  const hidden = id => byId[id].labels.some(l => l.ignore);
  // anchors
  must(moved('both') && moved('one.left') && moved('one.right') && moved('many'), 'anchor: crowded labels are shifted');
  must(!moved('sparse') && !moved('off') && !moved('radial'), 'anchor: sparse, off and radial labels stay');
  must(byId['radial'].pies.every(p => p.hasLabelRotate && !p.ran), 'anchor: radial labels switch the solver off');
  must(byId['off'].pies.every(p => !p.ran), 'anchor: avoidLabelOverlap false switches the solver off');
  must(cut('narrow') && cut('bleed') && !cut('off.narrow'), 'anchor: narrow charts truncate, the solver off does not');
  must(!cut('narrow.width') || byId['narrow.width'].pies.every(p => p.items.every(i => i.exit.width === null || i.labelStyleWidth !== null)),
    'anchor: an author width is never constrained');
  must(hidden('many') && !hidden('both.nohide'), 'anchor: hideOverlap hides after the solver, labelLayout null does not');
  must(byId['inside'].pies.every(p => p.items.length === 0), 'anchor: inside labels are not in the list');
  must(byId['two'].pies.length === 2, 'anchor: two pies, two lists');
  must(byId['small'].pies.every(p => p.items.every(i => num(i.bleedMargin) === 2)), 'anchor: a small view bleeds 2');
  must(cases.some(c => c.labels.some(l => l.guide && !l.guide.ignore && c.pies.some(p => p.items.some(i => i.d === l.d && i.exit.line
    && JSON.stringify(i.exit.line) !== JSON.stringify(l.guide.points))))), 'anchor: some lines are bent again by the turn limits (B14)');
  // guards
  const guards = GUARDS.map(g => {
    const changed = runs.filter(run => run.rec.pies.some((p, k) => pieChanged(p, run.live[k], g.mut))).map(run => run.rec.id);
    const ok = g.named.every(n => changed.indexOf(n) >= 0) && changed.length > 0;
    return { id: g.id, mutation: g.mutation, named: g.named, changed, ok };
  });
  if (process.env.PA_DEBUG) {
    for (const c of cases) {
      console.error(c.id, 'pies', c.pies.length, 'items', c.pies.reduce((a, p) => a + p.items.length, 0),
        'moved', c.pies.reduce((a, p) => a + p.items.filter(i => i.exit.labelY !== i.entry.labelY).length, 0),
        'cut', c.labels.filter(l => l.truncated).length, 'hidden', c.labels.filter(l => l.ignore).length);
    }
    for (const g of guards) console.error('guard', g.id, g.ok, JSON.stringify(g.changed));
  }
  for (const g of guards) must(g.ok, 'guard ' + g.id + ' does not change ' + (g.changed.length ? g.named.filter(n => g.changed.indexOf(n) < 0).join(', ') : 'anything'));
  return {
    source: 'echarts ' + echarts.version + ' (' + path.basename(DIST) + ', two read-only hooks round the avoidOverlap call), node SSR, SVG renderer',
    seed: SEED,
    notes: [
      'pies[].items[] is pieLabelLayout\'s list (outer and centre labels, data order); entry before avoidOverlap, exit after it.',
      'exit.line is before limitTurnAngle / limitSurfaceAngle (roadmap B14); labels[].guide.points is as drawn.',
      'labels[].ignore includes LabelManager\'s hideOverlap (a pie\'s default labelLayout).',
    ],
    cases,
    guards,
  };
}

try {
  const a = JSON.stringify(generate(), null, 1);
  const b = JSON.stringify(generate(), null, 1);
  must(a === b, 'two generations differ');
  fs.writeFileSync(OUT, a + '\n');
  const n = JSON.parse(a).cases.length;
  console.log('wrote ' + OUT + ' (' + n + ' cases)');
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e);
  process.exit(1);
}
