// Upstream's own answers for the automatic ink and halo of a label attached to
// a mark: whether it is inside the mark, which of the three inside inks it
// takes, the outside ink, and the text stroke ("halo") drawn under the glyphs,
// its colour and width, for the port to be held to (batch 47 audit,
// wf47/audit47.md SS1 and SS3).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer, 400x300,
// animation false), one chart per case, one labelled datum per chart. The
// label's formatter is a literal unique text 'L<k>' (series level, so the port
// can find the caption by its words). Emphasis = dispatchAction highlight
// {seriesIndex 0, dataIndex 0} then chart._onframe() (SSR has no frame loop;
// the states are applied there). Reads the live elements: the host's
// style.fill and textConfig, the label's style and _defaultStyle, and the first
// TSpan's style (what is painted). The SVG <text> attributes are a cross-check
// only.
//
// The recipe (SS1; L(c, bg) = (0.299 r + 0.587 g + 0.114 b) * a / 255 + (1 -
// a) * bg, bytes r g b, a in 0..1, evaluated in doubles left to right -- the
// order matters at the edges: #333333 gives 0.19999999999999998, not 0.2):
//   mode    isDark = option.darkMode ?? L(backgroundColor, 1) < 0.4
//   host    bar / scatter / graph / pie / funnel: itemStyle.color; line: '#fff'
//           (the emptyCircle symbol's inner fill); pictorialBar: 'transparent'
//           (the label rides a transparent Rect). Emphasis: emphasis.itemStyle
//           .color ?? lift(fill), lift = each channel * 1.1 | 0, clamped at
//           255, alpha kept ('none' and gradients as they are)
//   inside  raw: pie position in {inside, inner}; funnel position in {inner,
//           inside, center, insideLeft, insideRight}; the rest a STRING
//           position containing 'inside' (an array never). Default position:
//           line 'top', pie / funnel 'outer', the rest 'inside'. Emphasis:
//           emphasis.label.position ?? the normal one. inside = raw && the
//           host has a fill (fill != null && fill !== 'none'; 'transparent'
//           and gradients count as filled)
//   ink     inside, string fill: L(fill, 0) > 0.5 band 0 '#333', > 0.2 band 1
//           '#eee', else band 2 '#ccc'; gradient: band 2. Outside: isDark ?
//           '#ccc' : '#333'
//   stroke  inside: the host fill string, exactly, iff it is a string and
//           isDark == (band == 0); gradient: none. Outside: the ground made
//           opaque, c * a + (isDark ? 0 : 255) * (1 - a) per channel, as
//           'rgba(r,g,b,1)'. Width 2
//   user    label.color literal: that ink, no automatic halo. 'inherit': the
//           host's NORMAL visual colour, no halo -- except funnel, which has
//           no inheritColor: inside keeps the band ink and FORCES a halo of
//           the host fill at width 2 (even on a light host); outside inks in
//           the host colour and keeps the ground halo.
//           textBorderColor c: stroke c at width textBorderWidth || 0 (0 =
//           nothing drawn), 'none' / 'transparent' = no stroke.
//           textBorderWidth w alone: the automatic halo (when there is one) at
//           w || 2 (so 0 keeps 2). A label backgroundColor removes the
//           automatic halo. emphasis.label.X overrides X in emphasis only;
//           a normal-state colour / border carries into emphasis
//   paint   stroke first, then the ink on top (paint-order stroke); the
//           element opacity (scatter 0.8) multiplies ink and stroke
//
// The fixture, top level:
//   source   'ECharts <version>'
//   inks     {band: ['#333', '#eee', '#ccc'], outsideLight: '#333',
//            outsideDark: '#ccc'} (upstream's constants)
//   cases[]  below
//
// Per case:
//   id          short unique name
//   note        what the case is for
//   series      the series type
//   bites[]     the divergences (audit SS2) whose port-today model answers any
//               record of this case differently (computed: see self-check c)
//   documentary true: recorded for the reader, no port assertion
//   deferred    true: the port does not model it (option darkMode, rich
//               labels, an alpha tie); `why` says which. Recorded, not asserted
//   isDark      upstream's mode (zr.isDarkMode())
//   ground      [r, g, b, a255]: the port's G for the case; the option sets
//               backgroundColor to the same colour. Dark-ground cases
//               (#1E1E1E) are unit-level only on the Pascal side
//   highlight   {seriesIndex, dataIndex} | null
//   option      the option as run (JSON), fed to setOption
//   labels[]    the normal record of every label, then (highlight) the
//               emphasis record of the highlighted one:
//     text        'L<k>'
//     state       'normal' | 'emphasis'
//     hostFill    the host's fill string | 'gradient' | 'none'
//     hostFillBytes  [r, g, b, a255] | null (gradient, none)
//     inside      Element.ts:698-705, canBeInsideText included
//     band        0 | 1 | 2 | null (null = outside / literal / inherit ink)
//     inkRole     'band' | 'outside' | 'literal' | 'inherit'
//     fill, fillBytes      the painted ink (TSpan) and its bytes
//     stroke, strokeBytes  the painted stroke (TSpan) or null (both)
//     strokeRole  'host' | 'ground' | 'literal' | null
//     lineWidth   logical px when stroke != null (0 recorded as is), else null;
//                 lineWidthHex / lineWidthText: the IEEE twin (null, null
//                 when lineWidth is null)
//     opacity     the element opacity multiplying ink and stroke;
//                 opacityHex / opacityText: the IEEE twin
//     svg         {fill, fo, stroke, sw, so, po}: the <text> attributes, each
//                 the attribute string or null when absent (cross-check only)
//
// Colour bytes are integers [r, g, b, a255], a255 = alpha * 255 (never a
// fraction outside a deferred case). A Double's twin: `kHex` = the 16
// lowercase hex digits of its IEEE-754 bits (big-endian), `kText` = String(v).
//
// Self-checks (the fixture is not written and the run exits 1 when a case not
// declared deferred fails any):
//   a  an independent re-implementation of the recipe above, from the option
//      (and the mode it implies) alone, predicts every record field by field:
//      hostFill (bytes in emphasis), inside, band, inkRole, fill, stroke,
//      strokeRole, lineWidth, opacity
//   b  the SVG <text> attributes agree with the TSpan: fill / stroke through
//      svg normalizeColor (an rgba splits into rgb() + opacity), fo / so =
//      alpha * opacity (absent when 1), sw = lineWidth (absent when 1),
//      paint-order 'stroke' iff there is a stroke
//   c  every divergence D1..D10 is bitten by a compared case: the recipe
//      with that one divergence switched to the port's current behaviour
//      (Labels.pas:393-412 plus no stroke; the audit's SS2 column) answers
//      some label differently from the recipe itself (inside, band, inkRole,
//      ink, stroke, strokeRole, width; a stroke of alpha 0 counts as none);
//      each case's declared aims must be among its computed bites
//   d  both sides of both band edges appear inside, in the normal state:
//      #808080 / #7f7f7f (0.5) and #343434 / #333333 (0.2), and each edge
//      exactly (#04c26d lum 0.5 -> band 1, #033992 lum 0.2 -> band 2, both
//      lums checked to be exact doubles); the 0.4 halo test
//      is seen through the bands in both modes (light: band 0 bare, band 1
//      haloed; dark: band 0 haloed, band 1 bare)
//   e  every label is found exactly once, shown (not ignore / invisible), has
//      a TSpan; the highlighted host is in the emphasis state; every chart is
//      disposed in a finally (created == disposed)
//   f  every colour's alpha * 255 is an integer (no .5 ties), and the band
//      from the bytes (the port's model) equals the band from the string
//   g  every emphasis host fill equals lift(normal) (or the declared
//      emphasis.itemStyle.color) byte for byte
//   the whole fixture is generated twice in the process and the two JSON texts
//   must be byte-identical
//
//   node tools/advchart-oracle/inside-label.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-inside-label.json');

class OracleError extends Error {}
function must(cond, msg) { if (!cond) throw new OracleError(msg); }
const clone = v => JSON.parse(JSON.stringify(v));
const dig = (o, ks) => { for (const k of ks) { if (o == null) return undefined; o = o[k]; } return o; };

const warnings = [];
console.warn = (...a) => warnings.push(a.join(' '));

// ---------- number writing ----------

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function putNum(o, k, v) {
  o[k] = v;
  if (v == null) { o[k + 'Hex'] = null; o[k + 'Text'] = null; return o; }
  must(typeof v === 'number' && Number.isFinite(v), k + ': not a finite number ' + JSON.stringify(v));
  o[k + 'Hex'] = hex(v);
  o[k + 'Text'] = Object.is(v, -0) ? '-0' : String(v);
  return o;
}

// ---------- colours (own parser, cross-checked against zrender's) ----------

// [r, g, b, alpha 0..1] or null ('none', null); throws on anything else
function parseRaw(s) {
  if (s == null || s === 'none') return null;
  must(typeof s === 'string', 'a colour that is not a string: ' + JSON.stringify(s));
  let r, g, b, a = 1, m;
  if (s === 'transparent') { r = g = b = 0; a = 0; }
  else if ((m = /^#([0-9a-f]{3})$/i.exec(s))) [r, g, b] = m[1].split('').map(h => parseInt(h + h, 16));
  else if ((m = /^#([0-9a-f]{6})$/i.exec(s))) { r = parseInt(m[1].slice(0, 2), 16); g = parseInt(m[1].slice(2, 4), 16); b = parseInt(m[1].slice(4, 6), 16); }
  else if ((m = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$/.exec(s))) { r = +m[1]; g = +m[2]; b = +m[3]; if (m[4] != null) a = +m[4]; }
  else throw new OracleError('an unparsed colour ' + s);
  const z = echarts.color.parse(s);
  must(z && z[0] === r && z[1] === g && z[2] === b && z[3] === a, 'colour parsers disagree on ' + s + ': ' + JSON.stringify(z));
  return [r, g, b, a];
}
// the fixture's bytes: a255 = a * 255 as is (self-check f wants an integer)
function bytesOf(s) { const c = parseRaw(s); return c && [c[0], c[1], c[2], c[3] * 255]; }
const lumRaw = (c, bg) => (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) * c[3] / 255 + (1 - c[3]) * bg;
const lumBytes = b => (0.299 * b[0] + 0.587 * b[1] + 0.114 * b[2]) * (b[3] / 255) / 255;   // the port's byte model
const bandOfLum = L => (L > 0.5 ? 0 : L > 0.2 ? 1 : 2);
// states.ts liftColor = zrender lift(c, -0.1)
const liftBytes = b => b.slice(0, 3).map(c => Math.min(255, Math.max(0, c * (1 - (-0.1)) | 0))).concat([b[3]]);
const sameBytes = (a, b) => (a == null ? b == null : b != null && a.length === b.length && a.every((v, i) => v === b[i]));
const INK = ['#333', '#eee', '#ccc'];

// ---------- the live chart ----------

let created = 0, disposed = 0;
function mk() { created++; return echarts.init(null, null, { renderer: 'svg', ssr: true, width: 400, height: 300 }); }
function kill(chart) { chart.dispose(); disposed++; }

const TEXT_RE = /^(?:\{[a-z]+\|)?(L\d+)\}?$/;
function hosts(chart) {
  const zr = chart.getZr();
  zr.storage.getDisplayList(true);   // updateInnerText runs here
  const out = [];
  const walk = el => {
    if (el.getTextContent && el.getTextContent() && el.type !== 'text') out.push(el);
    if (el.childrenRef) el.childrenRef().forEach(walk);
  };
  zr.storage.getRoots().forEach(walk);
  return out.filter(h => TEXT_RE.test(String(h.getTextContent().style.text)));
}
function svgTexts(svg) {
  const res = {};
  const re = /<text\b([^>]*)>([^<]*)<\/text>/g;
  let m;
  while ((m = re.exec(svg))) {
    if (!/^L\d+$/.test(m[2])) continue;
    const a = m[1];
    const g = n => { const mm = new RegExp('(?:^|\\s)' + n + '="([^"]*)"').exec(a); return mm ? mm[1] : null; };
    must(!(m[2] in res), 'two <text> elements read ' + m[2]);
    res[m[2]] = { fill: g('fill'), fo: g('fill-opacity'), stroke: g('stroke'), sw: g('stroke-width'), so: g('stroke-opacity'), po: g('paint-order') };
  }
  return res;
}

// one live label -> the record (from the live elements only; the option only
// names an 'inherit' ink as such)
function snap(c, host, state, svg, e) {
  const text = host.getTextContent();
  const t = TEXT_RE.exec(String(text.style.text))[1];
  if (text.ignore || text.invisible) e.push(t + ' ' + state + ': not shown');
  const spans = (text.childrenRef ? text.childrenRef() : []).filter(x => x.type === 'tspan');
  if (!spans.length) { e.push(t + ' ' + state + ': no TSpan'); }
  const sp = spans.length ? spans[0].style : {};
  const hf = host.style.fill;
  const o = { text: t, state };
  if (hf != null && typeof hf === 'object') { o.hostFill = 'gradient'; o.hostFillBytes = null; }
  else if (hf == null || hf === 'none') { o.hostFill = 'none'; o.hostFillBytes = null; }
  else { o.hostFill = hf; o.hostFillBytes = bytesOf(hf); }
  const tc = host.textConfig || {};
  const raw = tc.inside == null ? typeof tc.position === 'string' && tc.position.indexOf('inside') >= 0 : !!tc.inside;
  o.inside = !!(raw && host.canBeInsideText());
  const ds = text._defaultStyle || {};
  const s = c.option.series[0];
  const colourOpt = (state === 'emphasis' ? dig(s, ['emphasis', 'label', 'color']) : undefined) ?? dig(s, ['label', 'color']);
  if ('fill' in text.style) { o.inkRole = colourOpt === 'inherit' ? 'inherit' : 'literal'; o.band = null; }
  else if (o.inside) {
    o.inkRole = 'band'; o.band = INK.indexOf(ds.fill);
    must(o.band >= 0, t + ': an inside default ink off the table ' + ds.fill);
  } else {
    o.inkRole = tc.outsideFill == null || tc.outsideFill === 'auto' ? 'outside' : 'inherit';
    o.band = null;
  }
  must(typeof sp.fill === 'string', t + ': a painted ink that is not a string');
  o.fill = sp.fill; o.fillBytes = bytesOf(sp.fill);
  const stroke = sp.stroke == null || sp.stroke === 'none' ? null : sp.stroke;
  must(stroke === null || typeof stroke === 'string', t + ': a stroke that is not a string');
  o.stroke = stroke; o.strokeBytes = stroke && bytesOf(stroke);
  o.strokeRole = stroke == null ? null : 'stroke' in text.style ? 'literal' : o.inside ? 'host' : 'ground';
  putNum(o, 'lineWidth', stroke == null ? null : sp.lineWidth);
  putNum(o, 'opacity', sp.opacity == null ? 1 : sp.opacity);
  const sv = svg[t];
  if (!sv) e.push(t + ' ' + state + ': no <text> in the SVG');
  o.svg = sv || null;
  return o;
}

function drive(c) {
  const chart = mk();
  const labels = [];
  const e = [];
  try {
    chart.setOption(clone(c.option));
    c.isDark = chart.getZr().isDarkMode();
    const read = state => {
      const hs = hosts(chart);
      const svg = svgTexts(chart.renderToSVGString());
      return hs.map(h => ({ h, rec: snap(c, h, state, svg, e) }));
    };
    const normal = read('normal');
    const texts = normal.map(x => x.rec.text);
    if (JSON.stringify(texts) !== JSON.stringify(c.texts)) e.push('labels ' + JSON.stringify(texts) + ', expected ' + JSON.stringify(c.texts));
    normal.forEach(x => labels.push(x.rec));
    if (c.highlight) {
      chart.dispatchAction(Object.assign({ type: 'highlight' }, c.highlight));
      chart._onframe();
      const emph = read('emphasis');
      const hl = emph.filter(x => (x.h.currentStates || []).indexOf('emphasis') >= 0);
      if (hl.length !== 1) e.push(hl.length + ' hosts in emphasis');
      hl.forEach(x => labels.push(x.rec));
      // the others are untouched
      emph.filter(x => hl.indexOf(x) < 0).forEach(x => {
        const n = normal.find(q => q.rec.text === x.rec.text);
        const a = Object.assign({}, x.rec, { state: 'normal' });
        if (JSON.stringify(a) !== JSON.stringify(n.rec)) e.push(x.rec.text + ': a label not highlighted changed');
      });
    }
  } finally {
    kill(chart);
  }
  return { labels, e };
}

// ---------- the reference predictor (SS1, from the option alone) ----------
//
// mut: the divergences D1..D10 switched to the port's current behaviour, one
// at a time (audit SS2), for self-check c.

const PIE_IN = ['inside', 'inner'];
const FUNNEL_IN = ['inner', 'inside', 'center', 'insideLeft', 'insideRight'];
function isDarkOf(option) {
  if (option.darkMode != null && option.darkMode !== 'auto') return !!option.darkMode;
  const bg = parseRaw(option.backgroundColor || 'transparent');
  return lumRaw(bg || [255, 255, 255, 1], 1) < 0.4;
}
function groundStroke(option, isDark) {
  const bg = parseRaw(option.backgroundColor || 'transparent') || [255, 255, 255, 1];
  const base = isDark ? 0 : 255;
  const ch = bg.slice(0, 3).map(v => v * bg[3] + base * (1 - bg[3]));
  return 'rgba(' + ch.join(',') + ',1)';
}

function predict(c, state, mut) {
  const o = c.option;
  const s = o.series[0];
  const lab = s.label || {};
  const em = s.emphasis || {};
  const eml = em.label || {};
  const type = s.type;
  const isDark = isDarkOf(o);
  const fillOpt = dig(s, ['itemStyle', 'color']);
  const p = {};
  // the host fill (normal, then emphasis)
  let host = type === 'pictorialBar' ? 'transparent' : type === 'line' ? '#fff' : fillOpt != null && typeof fillOpt === 'object' ? 'gradient' : fillOpt;
  const normalHost = host;
  let hostBytes = host === 'gradient' ? null : bytesOf(host);
  if (state === 'emphasis') {
    const ec = dig(em, ['itemStyle', 'color']);
    if (ec != null) { host = ec; hostBytes = bytesOf(ec); p.hostFill = ec; }
    else if (host !== 'gradient' && hostBytes) {
      // zrender lift -> stringify(.., 'rgba'): the lifted channels, the alpha as parsed
      const raw = parseRaw(host);
      const up = liftBytes(raw);
      host = 'rgba(' + up.join(',') + ')';
      hostBytes = bytesOf(host);
      p.hostFill = host;
    }
    else p.hostFill = host;
  } else p.hostFill = host === 'gradient' ? 'gradient' : host == null ? 'none' : host;
  p.hostFillBytes = hostBytes;
  // D9: the caption is frozen at expansion: its look is the normal one
  const st = mut.D9 ? 'normal' : state;
  let lHost = host, lBytes = hostBytes;
  if (mut.D9) { lHost = normalHost; lBytes = normalHost === 'gradient' ? null : bytesOf(normalHost); }
  // the host fill string the halo copies
  const hostString = lHost;

  // position and inside
  let pos = lab.position;
  if (st === 'emphasis' && eml.position != null) pos = eml.position;
  if (pos == null) pos = type === 'line' ? (mut.D8 ? 'inside' : 'top') : type === 'pie' || type === 'funnel' ? 'outer' : 'inside';
  const raw = type === 'pie' ? PIE_IN.includes(pos) : type === 'funnel' ? FUNNEL_IN.includes(pos) : typeof pos === 'string' && pos.indexOf('inside') >= 0;
  const unfilled = lHost == null || lHost === 'none';
  let inside = raw && !unfilled;
  let forcedBand0 = false;
  if (raw && unfilled && mut.D3) { inside = true; forcedBand0 = true; }
  if (raw && type === 'pictorialBar' && mut.D4) forcedBand0 = true;

  // the user's keys (emphasis over normal; a normal key carries into emphasis)
  let colour = (st === 'emphasis' ? eml.color : undefined) ?? lab.color;
  if (mut.D7 && colour != null && (colour !== 'inherit' || type === 'pie' || type === 'funnel')) colour = undefined;
  let bc = (st === 'emphasis' ? eml.textBorderColor : undefined) ?? lab.textBorderColor;
  let bw = (st === 'emphasis' ? eml.textBorderWidth : undefined) ?? lab.textBorderWidth ?? dig(o, ['textStyle', 'textBorderWidth']);
  if (mut.D10) { bc = undefined; bw = undefined; }
  const funnelInherit = type === 'funnel' && colour === 'inherit';

  // Element.updateInnerText: the default ink and stroke
  let dFill, dStroke, dStrokeBytes = null, autoStroke = true, inkRole, band = null, dRole;
  if (inside) {
    inkRole = 'band';
    let fb = lBytes, isString = lHost !== 'gradient', strokeStr = hostString;
    if (lHost === 'gradient' && mut.D5) {
      const first = fillOpt.colorStops[0].color;
      fb = bytesOf(first); isString = true; strokeStr = first;
    }
    if (forcedBand0) { band = 0; isString = false; }
    else if (!isString) band = 2;
    else band = bandOfLum(lumRaw([fb[0], fb[1], fb[2], fb[3] / 255], 0));
    dFill = INK[band];
    if (isString && isDark === (band === 0)) { dStroke = strokeStr; dStrokeBytes = fb; }
    if (funnelInherit) { dStroke = normalHost; dStrokeBytes = bytesOf(normalHost); autoStroke = false; }
    dRole = 'host';
    if (mut.D6 && isDark) dFill = band === 0 ? '#e5e7eb' : '#1e1e1e';   // the dark skin's inverted inks
  } else {
    dFill = isDark ? '#ccc' : '#333';
    inkRole = 'outside';
    if (funnelInherit) { dFill = normalHost; inkRole = 'inherit'; }
    dStroke = groundStroke(o, isDark); dStrokeBytes = bytesOf(dStroke);
    dRole = 'ground';
  }
  // ZRText: plain text
  const useDefaultFill = colour == null || type === 'funnel';
  let fill = dFill;
  if (!useDefaultFill) {
    fill = colour === 'inherit' ? normalHost : colour;
    inkRole = colour === 'inherit' ? 'inherit' : 'literal';
    band = null;
  }
  let stroke, strokeBytes, role, defaultLW = 0;
  if (bc != null) { stroke = bc; strokeBytes = bytesOf(bc); role = 'literal'; }
  else if (!lab.backgroundColor && (!autoStroke || useDefaultFill)) { stroke = dStroke; strokeBytes = dStrokeBytes; role = dRole; defaultLW = 2; }
  if (stroke == null || stroke === 'none' || stroke === 'transparent') { stroke = null; strokeBytes = null; role = null; }
  if ((mut.D1 && role === 'host') || (mut.D2 && role === 'ground')) { stroke = null; strokeBytes = null; role = null; }
  p.inside = inside;
  p.band = band;
  p.inkRole = inkRole;
  p.fill = fill;
  p.fillBytes = bytesOf(fill);
  p.stroke = stroke;
  p.strokeBytes = strokeBytes;
  p.strokeRole = role || null;
  p.lineWidth = stroke === null ? null : (bw || defaultLW);
  const op = dig(s, ['itemStyle', 'opacity']);
  p.opacity = op != null ? op : type === 'scatter' ? 0.8 : 1;
  return p;
}
const FIELDS = ['hostFill', 'hostFillBytes', 'inside', 'band', 'inkRole', 'fill', 'fillBytes', 'stroke', 'strokeBytes', 'strokeRole', 'lineWidth', 'opacity'];
function diffRec(p, r) {
  const out = [];
  for (const k of FIELDS) {
    if (p[k] === undefined) continue;
    const a = p[k], b = r[k];
    const same = Array.isArray(a) || Array.isArray(b) ? sameBytes(a, b) : a === b;
    if (!same) out.push(r.text + ' ' + r.state + ' ' + k + ': expected ' + JSON.stringify(a) + ', got ' + JSON.stringify(b));
  }
  return out;
}
const LABEL_FIELDS = ['inside', 'band', 'inkRole', 'fill', 'fillBytes', 'stroke', 'strokeBytes', 'strokeRole', 'lineWidth'];
// a stroke whose alpha byte is 0 draws nothing: the same look as no stroke
function seen(p) {
  const o = Object.assign({}, p);
  if (o.strokeBytes && o.strokeBytes[3] === 0) { o.stroke = null; o.strokeBytes = null; o.strokeRole = null; o.lineWidth = null; }
  return o;
}
// the port-today model q against the reference p (both predictions, so a
// deferred case the recipe misses still reports what it bites)
function differsAsPort(q, p) {
  q = seen(q); p = seen(p);
  return LABEL_FIELDS.some(k => {
    const a = q[k], b = p[k];
    return Array.isArray(a) || Array.isArray(b) ? !sameBytes(a, b) : a !== b;
  });
}

// ---------- self-check b: the SVG ----------

function svgColour(s) {
  if (s.indexOf('rgba') > -1) { const c = parseRaw(s); return { color: 'rgb(' + c[0] + ',' + c[1] + ',' + c[2] + ')', a: c[3] }; }
  return { color: s, a: 1 };
}
function checkSvg(r) {
  const out = [];
  const v = r.svg;
  if (!v) return [r.text + ': no svg'];
  const num = (k, want) => {
    const got = v[k];
    if (want === null) { if (got !== null) out.push(r.text + ' ' + r.state + ' svg ' + k + '=' + got + ', expected none'); return; }
    if (got === null || Math.abs(parseFloat(got) - want) > 1e-9) out.push(r.text + ' ' + r.state + ' svg ' + k + '=' + got + ', expected ' + want);
  };
  const f = svgColour(r.fill);
  if (v.fill !== f.color) out.push(r.text + ' svg fill ' + v.fill + ', expected ' + f.color);
  const fo = f.a * r.opacity;
  num('fo', fo < 1 ? fo : null);
  if (r.stroke == null) {
    if (v.stroke !== null || v.sw !== null || v.so !== null || v.po !== null) out.push(r.text + ' ' + r.state + ': svg stroke attributes without a stroke');
  } else {
    const sc = svgColour(r.stroke);
    if (v.stroke !== sc.color) out.push(r.text + ' svg stroke ' + v.stroke + ', expected ' + sc.color);
    num('sw', r.lineWidth !== 1 ? r.lineWidth : null);
    const so = sc.a * r.opacity;
    num('so', so < 1 ? so : null);
    if (v.po !== 'stroke') out.push(r.text + ' ' + r.state + ' svg paint-order ' + v.po);
  }
  return out;
}

// ---------- the cases ----------

const LIGHT = '#FFFFFF', DARK = '#1E1E1E';
let seq = 0;
const cases = [];
const GRADIENT = { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#fff' }, { offset: 1, color: '#000' }] };
function seriesOf(type, fill, label, extra) {
  const text = 'L' + (++seq);
  const lab = Object.assign({ show: true }, label || {});
  lab.formatter = lab.rich ? '{a|' + text + '}' : text;
  const base = {
    bar: { type: 'bar', data: [10] },
    line: { type: 'line', data: [10] },
    pictorialBar: { type: 'pictorialBar', symbol: 'rect', data: [10] },
    scatter: { type: 'scatter', symbolSize: 40, data: [[1, 1]] },
    graph: { type: 'graph', layout: 'none', symbolSize: 40, data: [{ name: 'n', x: 0, y: 0 }], links: [] },
    pie: { type: 'pie', radius: '60%', data: [{ name: 'p', value: 1 }] },
    funnel: { type: 'funnel', data: [{ name: 'f', value: 1 }] },
  }[type];
  must(base, 'no series type ' + type);
  return { text, series: Object.assign({}, clone(base), { itemStyle: { color: fill }, label: lab }, extra || {}) };
}
function axesOf(type) {
  if (type === 'bar' || type === 'line' || type === 'pictorialBar') return { xAxis: { type: 'category', data: ['c'] }, yAxis: { type: 'value' } };
  if (type === 'scatter') return { xAxis: { type: 'value' }, yAxis: { type: 'value' } };
  return {};
}
// add(id, note, type, fill, label, flags): flags {ground, highlight, extra
// (series keys), root (option keys), aims ['Dk'], deferred, documentary}
function add(id, note, type, fill, label, flags) {
  flags = flags || {};
  const ground = flags.ground || LIGHT;
  const { text, series } = seriesOf(type, fill, label, flags.extra);
  const option = Object.assign({ animation: false, backgroundColor: ground }, flags.root || {}, axesOf(type), { series: [series] });
  cases.push({ id, note, type, option, texts: [text], groundColour: ground,
    highlight: flags.highlight ? { seriesIndex: 0, dataIndex: 0 } : null,
    aims: flags.aims || [], deferred: flags.deferred || null, documentary: !!flags.documentary });
}

// light ground: bar inside over the band table
[
  ['#f5f5a0', 'a light bar: band 0, no halo in light mode'],
  ['#808080', '0.50196 > 0.5: band 0 (the 0.5 edge from above)'],
  ['#7f7f7f', '0.49804: band 1 plus the host halo (the 0.5 edge from below)'],
  ['#5470c6', 'a mid bar: band 1 plus the host halo'],
  ['#04c26d', 'lum exactly 0.5 in doubles (0.299*4 + 0.587*194 + 0.114*109 = 127.5): not > 0.5, band 1 plus the halo'],
  ['#343434', '0.20392 > 0.2: band 1 plus the halo (the 0.2 edge from above)'],
  ['#333333', 'lum 0.19999999999999998 in doubles (NOT 0.2): band 2 plus the halo (the 0.2 edge from below)'],
  ['#033992', 'lum exactly 0.2 in doubles (0.299*3 + 0.587*57 + 0.114*146 = 51): not > 0.2, band 2 plus the halo'],
  ['#1a1a40', 'a dark bar: band 2 plus the halo'],
  ['rgba(80,112,221,0.4)', 'translucent (a255 = 102): lum over black 0.18, band 2, the halo is the rgba string'],
].forEach(([f, n]) => add('bar-inside-' + f.replace(/[^0-9a-z.]/gi, ''), n, 'bar', f, {}, { aims: f === '#f5f5a0' || f === '#808080' ? [] : ['D1'] }));
add('bar-insideTopLeft', "any string position containing 'inside' is inside", 'bar', '#5470c6', { position: 'insideTopLeft' }, { aims: ['D1'] });
add('bar-top', "outside: '#333' plus the opaque ground halo, whatever the bar", 'bar', '#5470c6', { position: 'top' }, { aims: ['D2'] });
add('bar-array-position', 'an array position is never inside, even over a dark bar', 'bar', '#1a1a40', { position: ['50%', '50%'] }, { aims: ['D2'] });
add('bar-gradient', 'a gradient host: band 2 and no halo, whatever the stops (the port reads the first stop)', 'bar', GRADIENT, {}, { aims: ['D5'] });
add('bar-fill-none', "an unfilled host sends an inside label down the OUTSIDE branch", 'bar', 'none', {}, { aims: ['D3'] });
add('pictorialBar-default', "the label rides a transparent Rect: filled, band 2 '#ccc', the 'transparent' halo is dropped", 'pictorialBar', '#5470c6', {}, { aims: ['D4'] });
add('line-default', "line defaults to 'top': outside ink plus the ground halo", 'line', '#5470c6', {}, { aims: ['D8'] });
add('line-inside', "line 'inside': over the emptyCircle's '#fff' inner fill, band 0, no halo", 'line', '#5470c6', { position: 'inside' });
add('scatter-default', 'scatter default inside at the symbol opacity 0.8 (ink and halo both)', 'scatter', '#5470c6', {}, { aims: ['D1'] });
add('graph-default', 'a graph node: default inside', 'graph', '#5470c6', {}, { aims: ['D1'] });
add('graph-right', "a graph node 'right': outside", 'graph', '#5470c6', { position: 'right' }, { aims: ['D2'] });
[['inside', true], ['inner', true], ['center', false], ['outer', false]].forEach(([pos, n]) =>
  add('pie-' + pos, "pie '" + pos + "': " + (n ? 'inside' : "OUTSIDE ('center' too)"), 'pie', '#5470c6', { position: pos }, { aims: [n ? 'D1' : 'D2'] }));
[['inside', true], ['center', true], ['insideLeft', true], ['left', false], [null, false]].forEach(([pos, n]) =>
  add('funnel-' + (pos || 'default'), 'funnel ' + (pos ? "'" + pos + "'" : "default ('outer')") + ': ' + (n ? 'inside' : 'outside'), 'funnel', '#5470c6',
    pos ? { position: pos } : {}, { aims: [n ? 'D1' : 'D2'] }));

// overrides on bar inside #5470c6 and bar top
[
  ['color-literal', { color: '#f00' }, 'a literal ink: that ink and no automatic halo', ['D7']],
  ['color-inherit', { color: 'inherit' }, "'inherit': the bar's own colour, no halo", []],
  ['border-width-3', { textBorderWidth: 3 }, 'textBorderWidth alone re-widths the automatic halo', ['D10']],
  ['border-width-0', { textBorderWidth: 0 }, 'textBorderWidth 0 keeps width 2 (0 || 2)', []],
  ['border-colour', { textBorderColor: '#0f0' }, 'textBorderColor alone: stroke at width 0, nothing drawn', ['D10']],
  ['border-colour-width-3', { textBorderColor: '#0f0', textBorderWidth: 3 }, 'textBorderColor with width 3: that stroke', ['D10']],
  ['border-colour-none', { textBorderColor: 'none' }, "textBorderColor 'none' removes the halo", ['D10']],
  ['color-literal-width-3', { color: '#f00', textBorderWidth: 3 }, 'a literal ink kills the automatic halo even with a width', ['D7']],
].forEach(([id, lab, n, aims]) => {
  add('bar-inside-' + id, n + ' (inside)', 'bar', '#5470c6', lab, { aims });
  add('bar-top-' + id, n + ' (top)', 'bar', '#5470c6', Object.assign({ position: 'top' }, lab), { aims });
});
add('pie-outer-inherit', "pie outer 'inherit': the sector colour, no halo", 'pie', '#5470c6', { color: 'inherit' }, { aims: ['D7'] });
add('pie-inside-inherit', "pie inside 'inherit': the sector colour, no halo", 'pie', '#5470c6', { position: 'inside', color: 'inherit' }, { aims: ['D7'] });
add('funnel-inside-inherit', "funnel inside 'inherit': the band ink stays and a halo of the host is FORCED, even on a light host", 'funnel', '#f5f5a0',
  { position: 'inside', color: 'inherit' }, { aims: ['D7'] });
add('funnel-outer-inherit', "funnel outer 'inherit': the host colour ink, the ground halo stays", 'funnel', '#5470c6', { color: 'inherit' }, { aims: ['D7'] });

// dark ground #1E1E1E (auto dark: lum 0.118 < 0.4)
['#f5f5a0', '#808080', '#7f7f7f', '#5470c6', '#343434', '#333333', '#1a1a40'].forEach(f =>
  add('dark-bar-inside-' + f.slice(1), 'dark ground: the halo test flips (band 0 haloed, bands 1 and 2 bare)', 'bar', f, {}, { ground: DARK, aims: ['D6'] }));
add('dark-bar-top', "dark ground, outside: '#ccc' plus the ground made opaque", 'bar', '#f5f5a0', { position: 'top' }, { ground: DARK, aims: ['D2'] });

// emphasis
add('emph-5470c6', 'hover: the host lifts to rgba(92,123,217,1), band 1 stays, the halo is the lifted colour', 'bar', '#5470c6', {}, { highlight: true, aims: ['D9'] });
add('emph-7f7f7f', 'hover: rgba(139,139,139,1) flips to band 0, no halo', 'bar', '#7f7f7f', {}, { highlight: true, aims: ['D9'] });
add('emph-303030', 'hover: rgba(52,52,52,1) moves band 2 -> 1', 'bar', '#303030', {}, { highlight: true, aims: ['D9'] });
add('emph-itemStyle-000', "emphasis.itemStyle.color '#000' replaces the lift: band 2, halo '#000'", 'bar', '#f5f5a0', {},
  { highlight: true, extra: { emphasis: { itemStyle: { color: '#000' } } }, aims: ['D9'] });
add('emph-label-color', "emphasis.label.color '#0f0': that ink and no halo in emphasis only", 'bar', '#5470c6', {},
  { highlight: true, extra: { emphasis: { label: { color: '#0f0' } } }, aims: ['D9'] });
add('emph-label-top', "emphasis.label.position 'top': outside in emphasis", 'bar', '#5470c6', {},
  { highlight: true, extra: { emphasis: { label: { position: 'top' } } }, aims: ['D9'] });
add('emph-label-width-4', 'emphasis.label.textBorderWidth 4: the lifted halo at 4 in emphasis', 'bar', '#5470c6', {},
  { highlight: true, extra: { emphasis: { label: { textBorderWidth: 4 } } } });
add('emph-pictorialBar', "pictorialBar hover: 'transparent' lifts to rgba(0,0,0,0), a halo of alpha 0 (nothing drawn)", 'pictorialBar', '#5470c6', {},
  { highlight: true });
add('dark-emph-7f7f7f', 'dark ground hover: #7f7f7f flips to band 0 and GAINS the lifted halo', 'bar', '#7f7f7f', {}, { ground: DARK, highlight: true, aims: ['D9'] });

// documentary (SS4 OUT)
add('doc-label-background', 'a label backgroundColor removes the automatic halo (label boxes are OUT)', 'bar', '#5470c6', { backgroundColor: '#ff0' },
  { documentary: true });
add('doc-global-textStyle-width', 'global textStyle.textBorderWidth 5 re-widths the automatic halo (global textStyle is OUT)', 'bar', '#5470c6', {},
  { documentary: true, root: { textStyle: { textBorderWidth: 5 } } });

// deferred
add('deferred-darkMode-option', "option darkMode true on a white ground: '#f5f5a0' inside gets '#333' plus the host halo", 'bar', '#f5f5a0', {},
  { root: { darkMode: true }, deferred: 'the port takes the mode from its skin, never from option darkMode (SS4 OUT)' });
add('deferred-rich-width-0', 'a rich label with textBorderWidth 0: retrieve3 keeps the 0 (plain text would draw 2)', 'bar', '#5470c6',
  { rich: { a: {} }, textBorderWidth: 0 }, { deferred: 'rich labels are OUT (SS4); the plain-text recipe predicts width 2' });
add('deferred-alpha-tie', 'rgba(255,255,255,0.5): lum exactly 0.5, band 1 upstream; the port rounds the alpha to 128 and lands in band 0 (D12)', 'bar',
  'rgba(255,255,255,0.5)', {}, { deferred: 'D12 (Keep): an alpha whose a*255 is a .5 tie' });

// ---------- run, check, write ----------

{
  const ids = new Set();
  for (const c of cases) { must(!ids.has(c.id), 'two cases named ' + c.id); ids.add(c.id); }
}
const DS = ['D1', 'D2', 'D3', 'D4', 'D5', 'D6', 'D7', 'D8', 'D9', 'D10'];
const CHECKS = ['a', 'b', 'e', 'f', 'g'];

function encLabel(r) {
  const o = { text: r.text, state: r.state, hostFill: r.hostFill, hostFillBytes: r.hostFillBytes, inside: r.inside, band: r.band, inkRole: r.inkRole,
    fill: r.fill, fillBytes: r.fillBytes, stroke: r.stroke, strokeBytes: r.strokeBytes, strokeRole: r.strokeRole };
  putNum(o, 'lineWidth', r.lineWidth);
  putNum(o, 'opacity', r.opacity);
  o.svg = r.svg;
  return o;
}

function generate() {
  const tally = {};
  CHECKS.forEach(k => { tally[k] = [0, 0]; });
  const failed = [];
  const bitten = {};
  DS.forEach(d => { bitten[d] = 0; });
  const all = [];
  const recs = cases.map(c => {
    let run;
    try { run = drive(c); } catch (e) { if (e instanceof OracleError) e.message = c.id + ': ' + e.message; throw e; }
    const labels = run.labels;
    const f = { a: [], b: [], e: run.e.slice(), f: [], g: [] };
    // a: the recipe
    labels.forEach(r => diffRec(predict(c, r.state, {}), r).forEach(d => f.a.push(d)));
    if (c.isDark !== isDarkOf(c.option)) f.a.push('mode: upstream isDark ' + c.isDark);
    // b: the svg
    labels.forEach(r => checkSvg(r).forEach(d => f.b.push(d)));
    // f: integer alpha bytes; the byte band equals the string band
    labels.forEach(r => {
      [r.hostFillBytes, r.fillBytes, r.strokeBytes].forEach(b => { if (b && !Number.isInteger(b[3])) f.f.push(r.text + ': a255 ' + b[3]); });
      if (r.inkRole === 'band' && r.hostFillBytes && r.hostFill !== 'gradient') {
        const byteBand = bandOfLum(lumBytes(r.hostFillBytes.map(Math.round)));
        const strBand = bandOfLum(lumRaw(parseRaw(r.hostFill), 0));
        if (byteBand !== strBand) f.f.push(r.text + ' ' + r.state + ': the byte model bands ' + byteBand + ', the string ' + strBand);
      }
    });
    const ground = bytesOf(c.groundColour);
    if (!Number.isInteger(ground[3])) f.f.push('ground a255 ' + ground[3]);
    // g: the emphasis host
    labels.filter(r => r.state === 'emphasis').forEach(r => {
      const n = labels.find(q => q.state === 'normal' && q.text === r.text);
      const ec = dig(c.option.series[0], ['emphasis', 'itemStyle', 'color']);
      const want = ec != null ? bytesOf(ec) : n.hostFillBytes && liftBytes(n.hostFillBytes);
      if (!sameBytes(want, r.hostFillBytes)) f.g.push(r.text + ': emphasis host ' + JSON.stringify(r.hostFillBytes) + ', expected ' + JSON.stringify(want));
    });
    if (c.highlight && !labels.some(r => r.state === 'emphasis')) f.g.push('no emphasis record');
    // c: the port-today models, one divergence at a time
    const bites = DS.filter(d => labels.some(r => differsAsPort(predict(c, r.state, { [d]: true }), predict(c, r.state, {}))));
    const compared = !c.deferred && !c.documentary;
    c.aims.forEach(d => { if (!bites.includes(d)) f.a.push('aims ' + d + ' but does not bite it'); });
    if (compared) bites.forEach(d => { bitten[d]++; });
    let miss = '';
    CHECKS.forEach(k => {
      if (k === 'g' && !c.highlight) return;
      tally[k][f[k].length ? 1 : 0]++;
      if (f[k].length) miss += (miss ? ' | ' : '') + 'self-check ' + k + ': ' + f[k].slice(0, 3).join('; ') + (f[k].length > 3 ? ' (+' + (f[k].length - 3) + ' more)' : '');
    });
    if (miss && !c.deferred) failed.push(c.id + ': ' + miss);
    labels.forEach(r => all.push({ c, r }));
    const rec = { id: c.id, note: c.note, series: c.type, bites, documentary: c.documentary, deferred: !!c.deferred };
    if (c.deferred) rec.why = c.deferred + (miss ? '; first differences: ' + miss : '; (no self-check failed)');
    rec.isDark = c.isDark;
    rec.ground = ground;
    rec.highlight = c.highlight;
    rec.option = c.option;
    rec.labels = labels.map(encLabel);
    return rec;
  });
  // d: the band edges and the 0.4 halo test, compared cases only
  const d = [];
  const cmp = all.filter(x => !x.c.deferred && !x.c.documentary && x.r.state === 'normal' && x.r.inkRole === 'band');
  const hasBand = (bytes, band, dark) => cmp.some(x => sameBytes(x.r.hostFillBytes, bytes) && x.r.band === band && (dark == null || x.c.isDark === dark));
  [[[128, 128, 128, 255], 0], [[127, 127, 127, 255], 1], [[52, 52, 52, 255], 1], [[51, 51, 51, 255], 2],
    [[4, 194, 109, 255], 1], [[3, 57, 146, 255], 2]].forEach(([b, band]) => {
    if (!hasBand(b, band, false)) d.push('no light-mode ' + JSON.stringify(b) + ' in band ' + band);
  });
  [[false, 0, false], [false, 1, true], [true, 0, true], [true, 1, false]].forEach(([dark, band, halo]) => {
    if (!cmp.some(x => x.c.isDark === dark && x.r.band === band && (x.r.stroke != null) === halo)) d.push('no ' + (dark ? 'dark' : 'light') + ' band ' + band + (halo ? ' haloed' : ' bare'));
  });
  if (lumRaw([4, 194, 109, 1], 0) !== 0.5) d.push('#04c26d is not exactly 0.5');
  if (lumRaw([3, 57, 146, 1], 0) !== 0.2) d.push('#033992 is not exactly 0.2');
  const unbitten = DS.filter(k => bitten[k] < 1);
  return { out: { source: 'ECharts ' + echarts.version, inks: { band: INK, outsideLight: '#333', outsideDark: '#ccc' }, cases: recs },
    tally, failed, bitten, unbitten, d };
}

// the compact writer of roam.js
const LINE = 250;
function oneLine(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + v.map(oneLine).join(',') + ']';
  return '{' + Object.keys(v).filter(k => v[k] !== undefined).map(k => JSON.stringify(k) + ':' + oneLine(v[k])).join(',') + '}';
}
function fmt(v, ind) {
  const flat = oneLine(v);
  if (flat.length + ind.length <= LINE || v === null || typeof v !== 'object') return flat;
  const inner = ind + ' ';
  if (Array.isArray(v)) {
    const items = v.map(x => fmt(x, inner));
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
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner)).join(',\n')
    + '\n' + ind + '}';
}

let g1, json1;
try {
  g1 = generate();
  json1 = fmt(g1.out, '') + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  process.exit(1);
}
const json2 = fmt(generate().out, '') + '\n';
const deterministic = json1 === json2;
const allDisposed = created === disposed && created === 2 * cases.length;

const { tally, failed, bitten, unbitten, d } = g1;
failed.forEach(f => console.log('self-check failed: ' + f));
console.log('self-checks (pass/cases): ' + CHECKS.map(k => k + ' ' + tally[k][0] + '/' + (tally[k][0] + tally[k][1])).join(', ')
  + ', c ' + (DS.length - unbitten.length) + '/' + DS.length + ' divergences bitten, d ' + (d.length ? 'MISSING' : 'both sides')
  + ', charts ' + disposed + '/' + created + ' disposed, twice ' + (deterministic ? 'identical' : 'DIFFERENT'));
console.log('bitten by compared cases: ' + JSON.stringify(bitten));
if (unbitten.length) console.log('self-check c failed: no compared case bites ' + unbitten.join(', '));
d.forEach(x => console.log('self-check d failed: ' + x));
if (warnings.length) console.log(warnings.length + ' upstream warnings (e.g. ' + warnings[0].slice(0, 100) + ')');
const cs = g1.out.cases;
const nDef = cs.filter(c => c.deferred).length;
const nDoc = cs.filter(c => c.documentary && !c.deferred).length;
const nLab = cs.reduce((n, c) => n + c.labels.length, 0);
console.log((cs.length - nDef - nDoc) + ' compared + ' + nDoc + ' documentary + ' + nDef + ' deferred cases; ' + nLab + ' label records; '
  + json1.length + ' bytes');
if (failed.length || unbitten.length || d.length || !deterministic || !allDisposed) {
  if (process.env.ORACLE_REJECTS) fs.writeFileSync(process.env.ORACLE_REJECTS, json1);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
