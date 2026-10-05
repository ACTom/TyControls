// Upstream's own answers for zrender RICH TEXT and the plain text BOX: every
// piece a Text draws -- the whole-box background/border rect, each token's
// rect, each token's (or line's) TSpan -- in paint order, where it lands and
// how it is inked, for
//   series labels (bar, scatter) with label.rich: per-token fontSize /
//     fontWeight / color / backgroundColor / borderColor / borderWidth /
//     borderRadius / padding (1, 2, 3, 4 values) / width (number, '50%',
//     '100%', 'auto') / height / align / verticalAlign / lineHeight /
//     textShadow* / textBorder*; the block's align, verticalAlign, width,
//     height, overflow 'truncate' / 'break' / 'breakAll', lineOverflow
//     'truncate', richInheritPlainLabel; rotated; the '{name|text}' grammar
//     with nested, unmatched and invalid braces and newlines inside tokens
//   plain labels with backgroundColor / borderColor / borderWidth /
//     borderRadius / padding and width / height / overflow / ellipsis /
//     lineOverflow / lineHeight / textShadow*
//   markPoint label rich, axisLabel rich ('{a|{value}}'), axisLabel box,
//   axis name rich and box, title / subtitle rich (and the title's disabled
//   box), legend formatter + textStyle.rich, gauge detail box.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer, 600x400, animation
// false, Math.random pinned to 0 before the library loads). Node has no
// canvas, so zrender measures with its built-in width table (zrender
// core/platform.ts:61-92): px is the number before 'px' in the font (first
// match of /((?:\d+)?\.?\d*)px/), else 12; a font containing 'mono' measures
// px per UTF-16 unit; otherwise each unit of char code 32..126 counts
// ratio*px, any other unit px, summed left to right. A line's height is the
// width of '国' in that font, i.e. px (contain/text.ts:42,180-183). Character
// widths for truncation and wrapping come from measureCharWidth
// (contain/text.ts:84-95): the same table per char code 0..127 (codes 0..31
// and 127 count px), '国' for anything else. The table and every measured
// string are in the fixture, as text-style.js / grid-bounds.js record them.
//
// HOW THE PIECES ARE SEEN. The Text's own prototype methods are wrapped (on
// the development build and on echarts.min.js): _updateSubTexts starts a
// fresh log on the element, _renderBackground records (x, y, w, h, whole box
// or token) and which children it created, _placeToken records the token
// (every field of zrender's RichTextToken) with the line height, line top, x
// and textAlign it was placed with. After the render the log of each Text's
// last layout maps every child in childrenRef() (paint order: zrender
// Storage.ts:139-150 adds a Text's children in order, same z / z2, and the
// sort is stable) to the box, a token or a plain line. The whole box is read
// from a probe Text with the same style, the same default style and a
// backgroundColor added, so that it is known even when nothing is drawn.
// Lines of a rich text are reconstructed from the placement order (a line's
// tokens share lineTop and lineHeight and are placed left group ascending,
// right group descending, centre group ascending; Text.ts:730-777).
//
// The fixture, top level:
//   source, platform, ratios {firstCode, lastCode, fontSize, ratio[], ratioText[]}
//   measure[]  {text, px, mono, width, widthText, height, heightText}: every
//              drawn TSpan text and every token text, measured by a fresh Text
//              and by the rule as read here (they must agree)
//   cases[]    {name, note, W, H, option, record (which texts), texts[]}
// Per text:
//   component  seriesLabel | markerLabel | axisLabel | axisName | title |
//              subtitle | legend | chartText | other
//   owner      '<mainType><componentIndex>' of its view; attached (a host's
//              textContent); text (style.text); rich (style.rich present --
//              zrender takes the rich path iff it is, Text.ts:389-391)
//   transform  the Text's global transform (six numbers, hex + text) or null
//   anchor     style.x/y (local) and through the transform (global)
//   align, verticalAlign   style's, else the default style's (null: none;
//              zrender then treats it as left / top)
//   style      what zrender got, after normalizeTextStyle (Text.ts:1028-1058):
//              font, fontStyle/Weight/Size/Family, fill, stroke, lineWidth,
//              opacity, padding[4], width, height, lineHeight, overflow,
//              lineOverflow, ellipsis, backgroundColor, borderColor,
//              borderWidth, borderRadius, textShadow*; rich: the same per name
//   box        the outer rect (padding in, border not): local x, y, width,
//              height, the four corners global (tl, tr, br, bl) and their
//              axis-aligned bounds
//   bounds     the Text's own getBoundingRect (Text.ts:416-446), the union of
//              its children -- a bordered rect grown by its painted lineWidth
//              (strokeContainThreshold 0, so no floor), a TSpan by a stroke
//              its style gave it -- in the same shape as box
//   isTruncated
//   lines[]    rich only: {lineTop, lineHeight, tokens[] in source order:
//              {index (in the line), placeOrder, styleName, text, width,
//              height, innerHeight, contentWidth, contentHeight, lineHeight,
//              font, align, verticalAlign, padding, percentWidth,
//              isLineHolder, placeX, placeAlign, parentBgColorDrawn}}
//   pieces[]   every child in paint order:
//     {kind 'rect', of 'box' | 'token', line, token (indices), x, y, width,
//      height (local shape), corners (global), fill, fillOpacity, stroke,
//      lineWidth (as painted: doubled when fill and stroke), strokeOpacity,
//      strokeFirst, lineDash, rRaw (as given), r4 ([tl, tr, br, bl] as
//      roundRect.ts:30-54 spreads it, before its clamp) , opacity, shadow,
//      drawn (fill or stroke)}
//     {kind 'text', of 'token' | 'line', line, token, text, x, y (local),
//      gx, gy (global), font, fontStyle/Weight/Size/Family, fill, stroke,
//      lineWidth, lineDash, textAlign, textBaseline, opacity, strokeFirst,
//      shadow {blur, color, offsetX, offsetY} or null, bbox (local), mono, px}
//
// Doubles are written as the 16 hex digits of their IEEE-754 bits with a
// readable twin beside them (xText beside x), because the Pascal JSON reader
// misparses integer literals above 2^63.
//
// Guards (nothing is written and the run exits 1 when one fails): hand-derived
// geometry for plain-bg-pad4, plain-pad-nobg, rich-two-line, rich-token-box,
// rich-percent-hr and rich-token-fixed-width-align; the padding forms; the
// doubled border; the invisible lineHeight rect; the disabled title box; the
// '{name|text}' grammar cases token by token; the plain truncation against an
// independent reading of parseText.ts; richInheritPlainLabel and the shadow a
// token that does not inherit takes; no shadow without a blur; 'baseline' as
// verticalAlign's alias; a bordered token's bounds grown by exactly its
// stroke; no auto stroke
// over a background; every TSpan measure against the rule; one <text> in the
// SVG per non-empty TSpan; and the whole run done twice in-process must give
// the same JSON. Outside the script: run it twice and diff the files.
//
//   node tools/advchart-oracle/rich-text.js
'use strict';
Math.random = function () { return 0; };

const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const PROD = require(DIST.replace(/echarts\.js$/, 'echarts.min.js'));
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-rich-text.json');
const W = 600;
const H = 400;

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
const nn = v => (v === undefined ? null : v);
const clone = o => JSON.parse(JSON.stringify(o));
// a Double as hex + text twin; anything else as it is (null for undefined)
function put(o, k, v) {
  if (typeof v === 'number') {
    must(Number.isFinite(v), k + ': a non-finite number');
    o[k] = hex(v);
    o[k + 'Text'] = text(v);
  } else if (Array.isArray(v) && v.length && v.every(x => typeof x === 'number')) {
    o[k] = v.map(hex);
    o[k + 'Text'] = v.map(text);
  } else {
    o[k] = v === undefined ? null : v;
  }
  return o;
}
function pt(x, y) {
  return put(put({}, 'x', x), 'y', y);
}

// ---------- the width table (as text-style.js) ----------

const FIRST_CODE = 32;
const LAST_CODE = 126;
const DEFAULT_FONT_SIZE = 12;

function decodeTable(literal, where) {
  const s = Function('"use strict"; return (' + literal + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1,
    where + ': the width table is not ' + (LAST_CODE - FIRST_CODE + 1) + ' characters');
  return s;
}
const TABLE_DIST = DIST.replace(/echarts\.min\.js$/, 'echarts.js');
const mapStr = (() => {
  const line = fs.readFileSync(TABLE_DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, TABLE_DIST + ': no defaultWidthMapStr');
  const s = decodeTable(line.slice(line.indexOf('=') + 1).trim().replace(/;$/, ''), TABLE_DIST);
  if (fs.existsSync(ZRENDER_SRC)) {
    const m = /const defaultWidthMapStr = (`[^`]*`)/.exec(fs.readFileSync(ZRENDER_SRC, 'utf8'));
    must(m, ZRENDER_SRC + ': no defaultWidthMapStr');
    must(decodeTable(m[1], ZRENDER_SRC) === s, 'the dist and the zrender source disagree on the width table');
  } else {
    console.log('no zrender source at ' + ZRENDER_SRC + ': the width table is read from the dist only');
  }
  return s;
})();
const RATIO = Array.from(mapStr, ch => (ch.charCodeAt(0) - 20) / 100);

function measureText(t, font) {
  return new echarts.graphic.Text({ style: { text: t, font } }).getBoundingRect();
}
RATIO.forEach((r, i) => {
  const ch = String.fromCharCode(FIRST_CODE + i);
  const w = measureText(ch, '1px sans-serif').width;
  must(Object.is(w, r), 'char code ' + (FIRST_CODE + i) + ': the table says ' + r + ', a 1px Text measures ' + w);
});

// platform.ts:78-89, as read here
function pxOfFont(font) {
  const res = /((?:\d+)?\.?\d*)px/.exec(font || '12px sans-serif');
  return (res && +res[1]) || DEFAULT_FONT_SIZE;
}
const isMono = font => (font || '').indexOf('mono') >= 0;
function ruleWidth(line, font) {
  const px = pxOfFont(font);
  if (isMono(font)) return px * line.length;
  let w = 0;
  for (let i = 0; i < line.length; i++) {
    const c = line.charCodeAt(i);
    const r = c >= FIRST_CODE && c <= LAST_CODE ? RATIO[c - FIRST_CODE] : null;
    w += r == null ? px : r * px;
  }
  return w;
}
// contain/text.ts:84-95 in SSR: the per-char width
function ruleCharWidth(code, font) {
  const px = pxOfFont(font);
  if (code >= 0 && code <= 127) return ruleWidth(String.fromCharCode(code), font);
  return isMono(font) ? px : px;
}
// zrender graphic/Text.ts:969-1009, as read here
function parseFontSize(fontSize) {
  if (typeof fontSize === 'string'
    && (fontSize.indexOf('px') !== -1 || fontSize.indexOf('rem') !== -1 || fontSize.indexOf('em') !== -1)) {
    return fontSize;
  }
  if (!isNaN(+fontSize)) return fontSize + 'px';
  return DEFAULT_FONT_SIZE + 'px';
}
function makeFont(s) {
  let font = '';
  if (s.fontSize != null || s.fontFamily || s.fontWeight) {
    font = [s.fontStyle, s.fontWeight, parseFontSize(s.fontSize), s.fontFamily || 'sans-serif'].join(' ');
  }
  return (font && font.trim()) || s.textFont || s.font;
}
// parseText.ts:88-172, as read here (independent of the run)
function ruleTruncateLine(line, containerWidth, font, ellipsis, minChar) {
  if (!containerWidth) return '';
  ellipsis = ellipsis == null ? '...' : ellipsis;
  minChar = minChar == null ? 0 : minChar;
  const asc = ruleCharWidth('a'.charCodeAt(0), font);
  let contentWidth = containerWidth = Math.max(0, containerWidth - 1);
  for (let i = 0; i < minChar && contentWidth >= asc; i++) contentWidth -= asc;
  let ellW = ruleWidth(ellipsis, font);
  if (ellW > contentWidth) { ellipsis = ''; ellW = 0; }
  contentWidth = containerWidth - ellW;
  let lw = ruleWidth(line, font);
  if (lw <= containerWidth) return line;
  for (let j = 0; ; j++) {
    if (lw <= contentWidth || j >= 2) { line += ellipsis; break; }
    let sub;
    if (j === 0) {
      let w = 0;
      sub = 0;
      for (; sub < line.length && w < contentWidth; sub++) w += ruleCharWidth(line.charCodeAt(sub), font);
    } else {
      sub = lw > 0 ? Math.floor(line.length * contentWidth / lw) : 0;
    }
    line = line.substr(0, sub);
    lw = ruleWidth(line, font);
  }
  return line;
}

// ---------- the hooks ----------

function install(lib) {
  const P = lib.graphic.Text.prototype;
  if (P.__richOracle) return;
  P.__richOracle = true;
  const upd = P._updateSubTexts;
  const bg = P._renderBackground;
  const tok = P._placeToken;
  const plain = P._updatePlainTexts;
  const rich = P._updateRichTexts;
  must(upd && bg && tok && plain && rich, 'the Text prototype does not have the methods this oracle wraps');
  P._updateSubTexts = function () {
    this.__richLog = { mode: null, bgs: [], tokens: [], cur: null };
    return upd.apply(this, arguments);
  };
  P._updatePlainTexts = function () {
    this.__richLog.mode = 'plain';
    return plain.apply(this, arguments);
  };
  P._updateRichTexts = function () {
    this.__richLog.mode = 'rich';
    return rich.apply(this, arguments);
  };
  P._renderBackground = function (style, topStyle, x, y, w, h) {
    const log = this.__richLog;
    const from = this._childCursor;
    const r = bg.apply(this, arguments);
    log.bgs.push({ isBox: style === topStyle && log.cur == null, token: log.cur, x, y, w, h, from, to: this._childCursor });
    return r;
  };
  P._placeToken = function (token, style, lineHeight, lineTop, x, textAlign, parentBgColorDrawn) {
    const log = this.__richLog;
    const seq = log.tokens.length;
    const rec = {
      seq,
      styleName: nn(token.styleName),
      text: token.text,
      width: token.width, height: token.height, innerHeight: token.innerHeight,
      contentWidth: token.contentWidth, contentHeight: token.contentHeight,
      lineHeight: token.lineHeight, font: token.font,
      align: nn(token.align), verticalAlign: nn(token.verticalAlign),
      padding: token.textPadding ? token.textPadding.slice() : null,
      percentWidth: nn(token.percentWidth),
      isLineHolder: !!token.isLineHolder,
      lineLineHeight: lineHeight, lineTop, placeX: x, placeAlign: textAlign,
      parentBgColorDrawn: !!parentBgColorDrawn,
      from: this._childCursor,
    };
    log.tokens.push(rec);
    log.cur = seq;
    const r = tok.apply(this, arguments);
    log.cur = null;
    rec.to = this._childCursor;
    return r;
  };
}
install(echarts);
install(PROD);

// ---------- the cases ----------

const CAT = ['Mon', 'Tue', 'Wed'];
const DATA = [120, 200, 150];
const opt = o => Object.assign({ animation: false }, o);
const xCat = o => Object.assign({ type: 'category', data: CAT }, o);
const val = o => Object.assign({ type: 'value' }, o);
function barLabel(label, extra, series) {
  return opt(Object.assign({
    xAxis: xCat(),
    yAxis: val(),
    series: [Object.assign({ type: 'bar', name: 'Sales', data: DATA, label: Object.assign({ show: true, position: 'top' }, label) }, series)],
  }, extra));
}
const TWO = '{a|{b}}\n{v|{c}}';

const cases = [
  // ---- rich series labels ----
  { name: 'rich-two-line', note: "top labels '{a|{b}}\\n{v|{c}}': a 14px #c23531, v bold #333",
    option: barLabel({ formatter: TWO, rich: { a: { fontSize: 14, color: '#c23531' }, v: { fontWeight: 'bold', color: '#333' } } }) },
  { name: 'rich-token-box', note: 'token bg #eeeeee, border #333333 1, radius 4, padding [2,4]',
    option: barLabel({ formatter: '{a|{c}}', rich: { a: { backgroundColor: '#eeeeee', borderColor: '#333333', borderWidth: 1, borderRadius: 4, padding: [2, 4] } } }) },
  { name: 'rich-token-bg-only', note: 'token bg #fac858, padding 3',
    option: barLabel({ formatter: '{a|{c}}', rich: { a: { backgroundColor: '#fac858', padding: 3 } } }) },
  { name: 'rich-token-border-only', note: 'token border #5470c6 2, padding [2,4,2,4], no bg',
    option: barLabel({ formatter: '{a|{c}}', rich: { a: { borderColor: '#5470c6', borderWidth: 2, padding: [2, 4, 2, 4] } } }) },
  { name: 'rich-token-radius-array', note: 'token bg, borderRadius [6,0,6,0], padding [3,6]',
    option: barLabel({ formatter: '{a|{c}}', rich: { a: { backgroundColor: '#91cc75', borderRadius: [6, 0, 6, 0], padding: [3, 6] } } }) },
  { name: 'rich-token-padding-3', note: 'token bg, padding [1,2,3]',
    option: barLabel({ formatter: '{a|{c}}', rich: { a: { backgroundColor: '#eeeeee', padding: [1, 2, 3] } } }) },
  { name: 'rich-token-padding-4', note: 'token bg, padding [1,2,3,4]',
    option: barLabel({ formatter: '{a|{c}}', rich: { a: { backgroundColor: '#eeeeee', padding: [1, 2, 3, 4] } } }) },
  { name: 'rich-token-fixed-width-align', note: "block width 120; tokens width 30 aligned left / center / right, each with a bg",
    option: barLabel({ formatter: '{l|L}{c|C}{r|R}', width: 120,
      rich: { l: { width: 30, align: 'left', backgroundColor: '#ffeeee' }, c: { width: 30, align: 'center', backgroundColor: '#eeffee' }, r: { width: 30, align: 'right', backgroundColor: '#eeeeff' } } }) },
  { name: 'rich-token-valign', note: 'tokens verticalAlign top / middle / bottom beside a 24px token',
    option: barLabel({ formatter: '{t|top}{m|mid}{b|bot}{big|Big}',
      rich: { t: { verticalAlign: 'top', backgroundColor: '#ffeeee' }, m: { verticalAlign: 'middle', backgroundColor: '#eeffee' }, b: { verticalAlign: 'bottom', backgroundColor: '#eeeeff' }, big: { fontSize: 24 } } }) },
  { name: 'rich-token-height', note: 'token height 30, verticalAlign top, bg; a plain token beside it',
    option: barLabel({ formatter: '{a|{c}}{b|x}', rich: { a: { height: 30, backgroundColor: '#eeeeee', verticalAlign: 'top' }, b: {} } }) },
  { name: 'rich-token-lineHeight', note: 'token lineHeight 30 on line 1, lineHeight 10 + fontSize 16 on line 2',
    option: barLabel({ formatter: '{a|{b}}\n{c|{c}}', rich: { a: { lineHeight: 30 }, c: { lineHeight: 10, fontSize: 16 } } }) },
  { name: 'rich-block-lineHeight', note: 'label lineHeight 24 (the block gets a Rect with no fill, no stroke); a plain second line',
    option: barLabel({ formatter: '{a|{b}}\n{c}', lineHeight: 24, rich: { a: { color: '#c23531' } } }) },
  { name: 'rich-percent-hr', note: "the separator idiom: hr {width '100%', height 0, borderColor, borderWidth 0.5}",
    option: barLabel({ formatter: '{t|{b}}\n{hr|}\n{v|{c}}', rich: { t: { fontSize: 14 }, hr: { borderColor: '#777777', width: '100%', borderWidth: 0.5, height: 0 }, v: {} } }) },
  { name: 'rich-percent-50', note: "token width '50%' with padding [0,4] and bg (the padding is lost)",
    option: barLabel({ formatter: '{a|{b} sales}{p|x}', rich: { a: {}, p: { width: '50%', backgroundColor: '#eeeeee', padding: [0, 4] } } }) },
  { name: 'rich-auto-width', note: "token width 'auto' with bg",
    option: barLabel({ formatter: '{a|{c}}', rich: { a: { width: 'auto', backgroundColor: '#eeeeee' } } }) },
  { name: 'rich-inherit-plain', note: 'label 16 bold #123456 shadow; a: {} inherits font + shadow, b: 10px #c23531',
    option: barLabel({ formatter: '{a|{c}}{b|!}', fontSize: 16, fontWeight: 'bold', color: '#123456', textShadowBlur: 2, textShadowColor: '#999999',
      rich: { a: {}, b: { color: '#c23531', fontSize: 10 } } }) },
  { name: 'rich-inherit-off', note: 'the same with label.richInheritPlainLabel false',
    option: barLabel({ formatter: '{a|{c}}{b|!}', fontSize: 16, fontWeight: 'bold', color: '#123456', textShadowBlur: 2, textShadowColor: '#999999', richInheritPlainLabel: false,
      rich: { a: {}, b: { color: '#c23531', fontSize: 10 } } }) },
  { name: 'rich-inherit-off-root', note: 'the same with the root option richInheritPlainLabel false',
    option: barLabel({ formatter: '{a|{c}}{b|!}', fontSize: 16, fontWeight: 'bold', color: '#123456', textShadowBlur: 2, textShadowColor: '#999999',
      rich: { a: {}, b: { color: '#c23531', fontSize: 10 } } }, { richInheritPlainLabel: false }) },
  // a token that does not inherit the plain label takes the root textStyle's
  // shadow parts (labelStyle.ts:624-640), and what it has none of falls to the
  // block's in zrender (Text.ts:850-861): colour and offsets from the root,
  // blur from the label -- not the label's colour and offsets
  { name: 'rich-inherit-off-shadow', note: "richInheritPlainLabel false; label shadow blur 2 #999999 offsetX 3; root textStyle shadow #ff0000 offset 5,4; a: {} , b: own #0000ff",
    option: barLabel({ formatter: '{a|{c}}{b|!}', textShadowBlur: 2, textShadowColor: '#999999', textShadowOffsetX: 3, richInheritPlainLabel: false,
      rich: { a: {}, b: { textShadowColor: '#0000ff' } } }, { textStyle: { textShadowColor: '#ff0000', textShadowOffsetX: 5, textShadowOffsetY: 4 } }) },
  { name: 'rich-baseline-alias', note: "tokens baseline 'top' / 'bottom' (verticalAlign's alias, labelStyle.ts:647-652) beside a 24px token",
    option: barLabel({ formatter: '{t|top}{b|bot}{big|Big}',
      rich: { t: { baseline: 'top', backgroundColor: '#ffeeee' }, b: { baseline: 'bottom', backgroundColor: '#eeeeff' }, big: { fontSize: 24 } } }) },
  { name: 'plain-shadow-offset-only', note: 'textShadowColor #ff0000 offset 2,2 and no blur: zrender sets no shadow (Text.ts:611)',
    option: barLabel({ textShadowColor: '#ff0000', textShadowOffsetX: 2, textShadowOffsetY: 2 }) },
  { name: 'rich-block-box', note: 'block bg #ffffee, border #999999 1, radius 3, padding 6; tokens a 14px, v bg + padding 2',
    option: barLabel({ formatter: TWO, backgroundColor: '#ffffee', borderColor: '#999999', borderWidth: 1, borderRadius: 3, padding: 6,
      rich: { a: { fontSize: 14 }, v: { backgroundColor: '#eeeeee', padding: 2 } } }) },
  { name: 'rich-align-right', note: "block align 'right'; a 16px, v plain",
    option: barLabel({ formatter: TWO, align: 'right', rich: { a: { fontSize: 16 }, v: {} } }) },
  { name: 'rich-align-left-valign-top', note: "block align 'left', verticalAlign 'top'; v bg",
    option: barLabel({ formatter: TWO, align: 'left', verticalAlign: 'top', rich: { a: { fontSize: 16 }, v: { backgroundColor: '#eeeeee' } } }) },
  { name: 'rich-valign-middle-bg', note: "block verticalAlign 'middle', block bg + padding [4,8]",
    option: barLabel({ formatter: TWO, verticalAlign: 'middle', backgroundColor: '#eeeeee', padding: [4, 8], rich: { a: { fontSize: 14 }, v: {} } }) },
  { name: 'rich-rotated', note: 'label rotate 30; v bg, padding 2, radius 2',
    option: barLabel({ formatter: TWO, rotate: 30, rich: { a: {}, v: { backgroundColor: '#eeeeee', padding: 2, borderRadius: 2 } } }) },
  { name: 'rich-overflow-truncate', note: "block width 40 overflow 'truncate'; '{a|Weekday}{b|{c}}', b bg",
    option: barLabel({ formatter: '{a|Weekday}{b|{c}}', width: 40, overflow: 'truncate', rich: { a: { color: '#c23531' }, b: { backgroundColor: '#eeeeee' } } }) },
  { name: 'rich-overflow-truncate-fixedwidth', note: "block width 40 truncate; a fixed-width token that does not fit is emptied",
    option: barLabel({ formatter: '{a|AB}{b|CDEFGH}', width: 40, overflow: 'truncate', rich: { a: {}, b: { width: 30, backgroundColor: '#eeeeee' } } }) },
  { name: 'rich-overflow-break', note: "block width 50 overflow 'break'",
    option: barLabel({ formatter: '{a|Sales on} {b|{b} were {c}}', width: 50, overflow: 'break', rich: { a: { color: '#c23531' }, b: { fontWeight: 'bold' } } }) },
  { name: 'rich-overflow-breakAll', note: "block width 50 overflow 'breakAll'",
    option: barLabel({ formatter: '{a|Sales on} {b|{b} were {c}}', width: 50, overflow: 'breakAll', rich: { a: { color: '#c23531' }, b: { fontWeight: 'bold' } } }) },
  { name: 'rich-lineOverflow-truncate', note: "block height 30 lineOverflow 'truncate': three 12px lines, two fit",
    option: barLabel({ formatter: '{a|one}\n{b|two}\n{a|three}', height: 30, lineOverflow: 'truncate', rich: { a: { color: '#c23531' }, b: {} } }) },
  { name: 'rich-overflow-break-word', note: "block width 60 overflow 'break': a long word crossing the edge after other words -- the word moves down, the line keeps its width without it -- which the token's box shows",
    option: barLabel({ formatter: '{a|ab cd Wednesday} {b|x}', width: 60, overflow: 'break', rich: { a: { color: '#c23531', backgroundColor: '#eeeeee' }, b: {} } }) },
  { name: 'rich-name-digits', note: 'a style name with digits and an underscore: {a1_2|...}',
    option: barLabel({ formatter: '{a1_2|{c}}', rich: { a1_2: { color: '#c23531', fontSize: 14 } } }) },
  { name: 'rich-lineOverflow-mid-line', note: "block height 20 lineOverflow 'truncate': the second token of line two is taller than what is left -- the line is cut before it and kept",
    option: barLabel({ formatter: '{a|one}\n{a|two}{b|BIG}', height: 20, lineOverflow: 'truncate', rich: { a: { fontSize: 8 }, b: { fontSize: 20 } } }) },
  { name: 'rich-textShadow', note: 'token textShadowBlur 4 #ff0000 offset 1,2; a token without',
    option: barLabel({ formatter: '{a|{c}}{b|x}', rich: { a: { textShadowBlur: 4, textShadowColor: '#ff0000', textShadowOffsetX: 1, textShadowOffsetY: 2 }, b: {} } }) },
  { name: 'rich-token-stroke', note: 'inside labels; token textBorderColor #ffffff width 3 color #000000; a token without',
    option: barLabel({ position: 'inside', formatter: '{a|{c}}{b|x}', rich: { a: { textBorderColor: '#ffffff', textBorderWidth: 3, color: '#000000' }, b: {} } }) },
  { name: 'rich-inside-auto', note: 'inside labels: the auto ink and stroke per token, none over a token bg',
    option: barLabel({ position: 'inside', formatter: '{a|{c}}\n{b|{b}}', rich: { a: { fontWeight: 'bold' }, b: { backgroundColor: '#ffffff' } } }) },
  { name: 'rich-bg-inherit', note: "token backgroundColor 'inherit'; block borderColor 'inherit' width 1 padding 2",
    option: barLabel({ formatter: '{a|{c}}', borderColor: 'inherit', borderWidth: 1, padding: 2, rich: { a: { backgroundColor: 'inherit', color: '#ffffff', padding: 2 } } }) },
  { name: 'rich-braces-nested', note: "'{a|one {b|two} three}': the token runs to the first '}'",
    option: barLabel({ formatter: '{a|one {b|two} three}', rich: { a: { color: '#c23531' }, b: { color: '#5470c6' } } }) },
  { name: 'rich-braces-unmatched', note: "'{a|ok} tail {a|abc': no closing brace is plain text",
    option: barLabel({ formatter: '{a|ok} tail {a|abc', rich: { a: { color: '#c23531' } } }) },
  { name: 'rich-invalid-name', note: "'{a b|x} {zz|unknown} {a|ok}': a space is no name; an unknown name is unstyled",
    option: barLabel({ formatter: '{a b|x} {zz|unknown} {a|ok}', rich: { a: { color: '#c23531' } } }) },
  { name: 'rich-token-newline', note: "'{a|one\\ntwo}{b|three}\\n\\n{a|}': a newline inside a token, an empty line, an empty token",
    option: barLabel({ formatter: '{a|one\ntwo}{b|three}\n\n{a|}', rich: { a: { color: '#c23531', backgroundColor: '#eeeeee' }, b: {} } }) },
  { name: 'rich-empty-token-box', note: "'{icon|}{a|{c}}': a 14x14 round swatch token with no text",
    option: barLabel({ formatter: '{icon|}{a|{c}}', rich: { icon: { width: 14, height: 14, backgroundColor: '#c23531', borderRadius: 7 }, a: { padding: [0, 0, 0, 4] } } }) },
  { name: 'rich-mono', note: "token fontFamily 'monospace' 13px",
    option: barLabel({ formatter: '{a|{c}}{b|kg}', rich: { a: { fontFamily: 'monospace', fontSize: 13 }, b: {} } }) },
  { name: 'rich-fontsize-string', note: "token fontSize '15px'",
    option: barLabel({ formatter: '{a|{c}}', rich: { a: { fontSize: '15px' } } }) },

  // ---- plain series labels ----
  { name: 'plain-bg-pad4', note: 'backgroundColor #eeeeee, padding 4', option: barLabel({ backgroundColor: '#eeeeee', padding: 4 }) },
  { name: 'plain-border-pad2', note: 'border #333333 1, radius 3, padding [2,6], no bg', option: barLabel({ borderColor: '#333333', borderWidth: 1, borderRadius: 3, padding: [2, 6] }) },
  { name: 'plain-bg-border', note: 'bg + border 1: the border is painted 2 wide under the fill', option: barLabel({ backgroundColor: '#eeeeee', borderColor: '#333333', borderWidth: 1, padding: 3 }) },
  { name: 'plain-pad-3', note: 'bg, padding [1,2,3]', option: barLabel({ backgroundColor: '#eeeeee', padding: [1, 2, 3] }) },
  { name: 'plain-pad-4', note: 'bg, padding [1,2,3,4]', option: barLabel({ backgroundColor: '#eeeeee', padding: [1, 2, 3, 4] }) },
  { name: 'plain-pad-nobg', note: 'padding [4,8], nothing drawn: the text moves', option: barLabel({ padding: [4, 8] }) },
  { name: 'plain-radius-array', note: 'bg, radius [8,0,8,0], padding 4', option: barLabel({ backgroundColor: '#eeeeee', borderRadius: [8, 0, 8, 0], padding: 4 }) },
  { name: 'plain-truncate', note: "width 30 overflow 'truncate'", option: barLabel({ formatter: '{b} sales {c}', width: 30, overflow: 'truncate' }) },
  { name: 'plain-truncate-ellipsis', note: "width 30 truncate, ellipsis '~'", option: barLabel({ formatter: '{b} sales {c}', width: 30, overflow: 'truncate', ellipsis: '~' }) },
  { name: 'plain-break', note: "width 40 overflow 'break'", option: barLabel({ formatter: '{b} sales were {c}', width: 40, overflow: 'break' }) },
  { name: 'plain-breakAll', note: "width 40 overflow 'breakAll'", option: barLabel({ formatter: '{b} sales were {c}', width: 40, overflow: 'breakAll' }) },
  { name: 'plain-lineOverflow', note: "height 20 lineOverflow 'truncate', three lines", option: barLabel({ formatter: '{b}\n{c}\nend', height: 20, lineOverflow: 'truncate' }) },
  { name: 'plain-width-height-bg', note: 'width 80 height 30 bg: the box is the given size', option: barLabel({ width: 80, height: 30, backgroundColor: '#eeeeee' }) },
  { name: 'plain-textShadow', note: 'textShadowBlur 3 #ff0000 offset 1,2', option: barLabel({ textShadowBlur: 3, textShadowColor: '#ff0000', textShadowOffsetX: 1, textShadowOffsetY: 2 }) },
  { name: 'plain-lineHeight-bg', note: 'lineHeight 30, bg, two lines', option: barLabel({ formatter: '{b}\n{c}', lineHeight: 30, backgroundColor: '#eeeeee' }) },
  { name: 'plain-align-left-top-bg', note: "align 'left' verticalAlign 'top', bg, padding [2,4]", option: barLabel({ align: 'left', verticalAlign: 'top', backgroundColor: '#eeeeee', padding: [2, 4] }) },
  { name: 'plain-rotated-bg', note: 'rotate 45, bg, padding 3, radius 2', option: barLabel({ rotate: 45, backgroundColor: '#eeeeee', padding: 3, borderRadius: 2 }) },
  { name: 'plain-bg-inherit', note: "backgroundColor 'inherit', borderColor 'inherit' width 2, color #ffffff, padding 2",
    option: barLabel({ backgroundColor: 'inherit', borderColor: 'inherit', borderWidth: 2, color: '#ffffff', padding: 2 }) },
  { name: 'plain-inside-bg', note: 'inside labels over a bg: no auto stroke', option: barLabel({ position: 'inside', backgroundColor: '#ffffff', padding: 2 }) },
  { name: 'scatter-rich-right', note: "scatter labels position 'right', rich with a token box",
    option: opt({ xAxis: val(), yAxis: val(), series: [{ type: 'scatter', data: [[10, 20], [30, 50], [50, 30]], symbolSize: 12,
      label: { show: true, position: 'right', formatter: '{a|{c}}', rich: { a: { backgroundColor: '#eeeeee', padding: [2, 4], borderRadius: 3, borderColor: '#999999', borderWidth: 1 } } } }] }) },

  // ---- other components ----
  { name: 'markpoint-rich', note: 'markPoint max/min, label rich with a token box', record: ['markerLabel'],
    option: barLabel({ show: false }, {}, { markPoint: { data: [{ type: 'max' }, { type: 'min' }],
      label: { formatter: '{a|{c}}', rich: { a: { color: '#ffffff', fontWeight: 'bold', backgroundColor: '#333333', padding: 2, borderRadius: 2 } } } } }) },
  { name: 'xaxis-label-rich', note: "axisLabel formatter '{a|{value}}', a: #c23531 bold, bg, padding [2,4], radius 2", record: ['axisLabel@xAxis0'],
    option: opt({ xAxis: xCat({ axisLabel: { formatter: '{a|{value}}', rich: { a: { color: '#c23531', fontWeight: 'bold', backgroundColor: '#eeeeee', padding: [2, 4], borderRadius: 2 } } } }),
      yAxis: val(), series: [{ type: 'bar', data: DATA }] }) },
  { name: 'xaxis-label-rich-two-line', note: "axisLabel '{a|{value}}\\n{b|day}': a 14px, b 10px #999999", record: ['axisLabel@xAxis0'],
    option: opt({ xAxis: xCat({ axisLabel: { formatter: '{a|{value}}\n{b|day}', rich: { a: { fontSize: 14 }, b: { color: '#999999', fontSize: 10 } } } }),
      yAxis: val(), series: [{ type: 'bar', data: DATA }] }) },
  { name: 'yaxis-label-plain-box', note: 'value axisLabel bg, padding [2,4], border #999999 1, radius 3', record: ['axisLabel@yAxis0'],
    option: opt({ xAxis: xCat(), yAxis: val({ axisLabel: { backgroundColor: '#eeeeee', padding: [2, 4], borderColor: '#999999', borderWidth: 1, borderRadius: 3 } }),
      series: [{ type: 'bar', data: DATA }] }) },
  { name: 'axis-name-rich', note: "x name '{a|Day}{b| (d)}': a bold 14, b #999999", record: ['axisName'],
    option: opt({ xAxis: xCat({ name: '{a|Day}{b| (d)}', nameTextStyle: { rich: { a: { fontWeight: 'bold', fontSize: 14 }, b: { color: '#999999' } } } }),
      yAxis: val(), series: [{ type: 'bar', data: DATA }] }) },
  { name: 'axis-name-middle-rich', note: "y name 'middle' nameGap 40, rich with a token bg", record: ['axisName'],
    option: opt({ xAxis: xCat(), yAxis: val({ name: '{a|Amount}{b|kg}', nameLocation: 'middle', nameGap: 40, nameTextStyle: { rich: { a: {}, b: { backgroundColor: '#eeeeee', padding: [0, 2] } } } }),
      series: [{ type: 'bar', data: DATA }] }) },
  { name: 'axis-name-plain-box', note: 'y name bg, padding [2,4], border #333333 1, radius 2', record: ['axisName'],
    option: opt({ xAxis: xCat(), yAxis: val({ name: 'Amount', nameTextStyle: { backgroundColor: '#eeeeee', padding: [2, 4], borderColor: '#333333', borderWidth: 1, borderRadius: 2 } }),
      series: [{ type: 'bar', data: DATA }] }) },
  { name: 'title-rich', note: "title '{a|Sales}{b| 2026}' rich (b bg, padding [2,4]); subtext '{c|weekly}' rich", record: ['title', 'subtitle'],
    option: opt({ title: { text: '{a|Sales}{b| 2026}', subtext: '{c|weekly}', left: 'center',
      textStyle: { rich: { a: { fontSize: 22, color: '#c23531' }, b: { fontSize: 12, color: '#999999', backgroundColor: '#eeeeee', padding: [2, 4] } } },
      subtextStyle: { rich: { c: { fontStyle: 'italic', color: '#5470c6' } } } },
      xAxis: xCat(), yAxis: val(), series: [{ type: 'bar', data: DATA }] }) },
  { name: 'title-box-disabled', note: 'title textStyle bg / padding / border: disableBox, nothing drawn', record: ['title'],
    option: opt({ title: { text: 'Sales', textStyle: { backgroundColor: '#eeeeee', padding: 5, borderColor: '#333333', borderWidth: 1 } },
      xAxis: xCat(), yAxis: val(), series: [{ type: 'bar', data: DATA }] }) },
  { name: 'legend-formatter-rich', note: "legend formatter '{a|{name}} {b|!}': a bold, b bg 'inherit' + #ffffff", record: ['legend'],
    option: opt({ legend: { formatter: '{a|{name}} {b|!}', textStyle: { rich: { a: { fontWeight: 'bold' }, b: { color: '#ffffff', backgroundColor: 'inherit', padding: [0, 3] } } } },
      xAxis: xCat(), yAxis: val(), series: [{ type: 'bar', name: 'Sales', data: DATA }, { type: 'bar', name: 'Cost', data: [60, 70, 80] }] }) },
  { name: 'legend-rich-root-color', note: 'root textStyle color #123456: a free text token with no colour takes it; the plain part keeps the legend colour', record: ['legend', 'title'],
    option: opt({ textStyle: { color: '#123456' }, title: { text: '{a|T}itle', textStyle: { rich: { a: { fontSize: 20 } } } },
      legend: { formatter: '{a|{name}}!', textStyle: { rich: { a: { fontWeight: 'bold' } } } },
      xAxis: xCat(), yAxis: val(), series: [{ type: 'bar', name: 'Sales', data: DATA }] }) },
  // the legend lays its items out by their group's bounds (legend/LegendView.ts,
  // layoutUtil.box over getBoundingRect), which a bordered token rect grows by
  // its stroke -- no more, since zrender gives a text's box rect
  // strokeContainThreshold 0 (Text.ts:952, Path.ts:372-384)
  { name: 'legend-rich-token-border', note: "legend formatter '{a|{name}}': a border #333333 1, padding [0,2], no bg", record: ['legend'],
    option: opt({ legend: { formatter: '{a|{name}}', textStyle: { rich: { a: { borderColor: '#333333', borderWidth: 1, padding: [0, 2] } } } },
      xAxis: xCat(), yAxis: val(), series: [{ type: 'bar', name: 'Sales', data: DATA }, { type: 'bar', name: 'Cost', data: [60, 70, 80] }, { type: 'bar', name: 'Profit', data: [30, 40, 50] }] }) },
  { name: 'legend-rich-token-border-bg', note: "the same with a bg #eeeeee: the border painted 2 wide, the box grown by 2", record: ['legend'],
    option: opt({ legend: { formatter: '{a|{name}}', textStyle: { rich: { a: { borderColor: '#333333', borderWidth: 1, backgroundColor: '#eeeeee', padding: [0, 2] } } } },
      xAxis: xCat(), yAxis: val(), series: [{ type: 'bar', name: 'Sales', data: DATA }, { type: 'bar', name: 'Cost', data: [60, 70, 80] }, { type: 'bar', name: 'Profit', data: [30, 40, 50] }] }) },
  { name: 'gauge-detail-box', note: "gauge detail bg, radius 3, padding [4,8], formatter '{a|{value}}%' rich; title plain", record: ['chartText'], match: '%|^Speed$',
    option: opt({ series: [{ type: 'gauge', data: [{ value: 62, name: 'Speed' }],
      detail: { formatter: '{a|{value}}%', backgroundColor: '#eeeeee', borderRadius: 3, padding: [4, 8], fontSize: 20, rich: { a: { color: '#c23531', fontSize: 24 } } } }] }) },
];

// ---------- running upstream ----------

function assertJson(v, where) {
  if (typeof v === 'function' || v === undefined) throw new OracleError(where + ': not JSON');
  if (typeof v === 'number') must(Number.isFinite(v), where + ': a non-finite number');
  if (v && typeof v === 'object') Object.keys(v).forEach(k => assertJson(v[k], where + '.' + k));
}
function apply(m, x, y) {
  return m ? [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]] : [x, y];
}
function hidden(el) {
  for (let n = el; n; n = n.parent) if (n.ignore) return true;
  return false;
}
function visible(el, attached, host) {
  return !el.invisible && !(attached && hidden(host)) && el.style.text != null && String(el.style.text) !== '';
}

function collect(view, kind, out, seen) {
  const model = view.__model;
  const owner = model.mainType + model.componentIndex;
  const mt = model.mainType;
  let titleIdx = 0;
  const visit = (el, attached, host) => {
    if (el.ignore) return;
    seen.add(el);
    let component = 'other';
    if (attached) component = kind === 'chart' ? 'seriesLabel' : /^mark/.test(mt) ? 'markerLabel' : 'other';
    else if (kind === 'chart') component = 'chartText';
    else if (mt === 'xAxis' || mt === 'yAxis') {
      if (el.anid === 'name') component = 'axisName';
      else if (typeof el.anid === 'string' && el.anid.indexOf('label_') === 0) component = 'axisLabel';
    } else if (mt === 'title') {
      component = titleIdx === 0 ? 'title' : titleIdx === 1 ? 'subtitle' : 'other';
      titleIdx++;
    } else if (mt === 'legend') component = 'legend';
    if (visible(el, attached, host)) out.push({ el, component, owner, attached });
  };
  const walk = el => {
    if (el.ignore) return;
    if (el.type === 'text') { visit(el, false, null); return; }
    if (el.childrenRef) el.childrenRef().forEach(walk);
    const tc = el.getTextContent && el.getTextContent();
    if (tc) visit(tc, true, el);
  };
  walk(view.group);
}

const STYLE_KEYS = ['font', 'fontStyle', 'fontWeight', 'fontSize', 'fontFamily', 'fill', 'stroke', 'lineWidth', 'opacity',
  'padding', 'width', 'height', 'lineHeight', 'align', 'verticalAlign', 'overflow', 'lineOverflow', 'ellipsis',
  'backgroundColor', 'borderColor', 'borderWidth', 'borderRadius',
  'textShadowColor', 'textShadowBlur', 'textShadowOffsetX', 'textShadowOffsetY',
  'shadowColor', 'shadowBlur', 'shadowOffsetX', 'shadowOffsetY'];
function styleOf(s) {
  const o = {};
  STYLE_KEYS.forEach(k => {
    const v = s[k];
    if (v === undefined) return;
    if (k === 'fontSize' && typeof v === 'string') { o[k] = v; return; }
    put(o, k, v);
  });
  return o;
}
function corners(m, x, y, w, h) {
  const c = [apply(m, x, y), apply(m, x + w, y), apply(m, x + w, y + h), apply(m, x, y + h)];
  const xs = c.map(p => p[0]);
  const ys = c.map(p => p[1]);
  const minX = Math.min(...xs);
  const minY = Math.min(...ys);
  return {
    corners: c.map(p => pt(p[0], p[1])),
    aabb: put(put(put(put({}, 'x', minX), 'y', minY), 'width', Math.max(...xs) - minX), 'height', Math.max(...ys) - minY),
  };
}
function r4(r) {
  if (typeof r === 'number') return [r, r, r, r];
  if (Array.isArray(r)) {
    if (r.length === 1) return [r[0], r[0], r[0], r[0]];
    if (r.length === 2) return [r[0], r[1], r[0], r[1]];
    if (r.length === 3) return [r[0], r[1], r[2], r[1]];
    return r.slice(0, 4);
  }
  return [0, 0, 0, 0];
}
function shadowOf(s) {
  if (!(s.shadowBlur > 0) && !s.shadowOffsetX && !s.shadowOffsetY) return null;
  const o = {};
  put(o, 'blur', s.shadowBlur || 0);
  put(o, 'color', nn(s.shadowColor));
  put(o, 'offsetX', s.shadowOffsetX || 0);
  put(o, 'offsetY', s.shadowOffsetY || 0);
  return o;
}
function sameM(a, b) {
  return (a === null && b === null) || (a && b && a.length === b.length && a.every((v, i) => Object.is(v, b[i])));
}

// the outer box, from a probe with the same style and a background
function probeBox(lib, el) {
  const probe = new lib.graphic.Text();
  probe.setDefaultTextStyle(el._defaultStyle);
  const st = Object.assign({}, el.style);
  if (st.rich) {
    const rich = {};
    Object.keys(st.rich).forEach(k => { rich[k] = Object.assign({}, st.rich[k]); });
    st.rich = rich;
  }
  if (st.padding) st.padding = st.padding.slice();
  st.backgroundColor = '#010203';
  probe.useStyle(st);
  probe.getBoundingRect();
  const b = probe.__richLog.bgs.filter(x => x.isBox);
  must(b.length === 1, 'the probe drew ' + b.length + ' boxes');
  return b[0];
}

function recordText(lib, t, measureSet) {
  const el = t.el;
  const s = el.style;
  const where = t.owner + ' ' + t.component + ' ' + JSON.stringify(s.text);
  const log = el.__richLog;
  must(log && log.mode, where + ': no layout log');
  must((log.mode === 'rich') === !!s.rich, where + ': the path taken is not the one style.rich says');
  const m = el.transform ? Array.from(el.transform) : null;
  const children = el.childrenRef();
  children.forEach((c, i) => {
    const cm = c.transform ? Array.from(c.transform) : null;
    must(sameM(m, cm), where + ': child ' + i + ' has its own transform');
  });
  const ds = el._defaultStyle || {};
  const align = nn(s.align || ds.align);
  const verticalAlign = nn(s.verticalAlign || ds.verticalAlign);
  const anchor = apply(m, s.x || 0, s.y || 0);

  // the box
  const pb = probeBox(lib, el);
  const box = put(put(put(put({}, 'x', pb.x), 'y', pb.y), 'width', pb.w), 'height', pb.h);
  Object.assign(box, corners(m, pb.x, pb.y, pb.w, pb.h));
  const drawnBox = log.bgs.filter(b => b.isBox);
  must(drawnBox.length <= 1, where + ': two boxes');
  if (drawnBox.length) {
    const d = drawnBox[0];
    must(Object.is(d.x, pb.x) && Object.is(d.y, pb.y) && Object.is(d.w, pb.w) && Object.is(d.h, pb.h),
      where + ': the probe box is not the drawn box');
  }
  // the Text's own bounds, what a legend lays out and labelLayout overlaps:
  // the union of its children's (Text.ts:416-446) -- a stroked rect grown by
  // its lineWidth as painted, a TSpan by a stroke the style gave it
  const gbr = el.getBoundingRect();
  must(el.__richLog === log, where + ': asking the bounds laid the text out again');
  const bounds = put(put(put(put({}, 'x', gbr.x), 'y', gbr.y), 'width', gbr.width), 'height', gbr.height);
  Object.assign(bounds, corners(m, gbr.x, gbr.y, gbr.width, gbr.height));

  // rich lines, rebuilt from the placement order
  const lines = [];
  const tokenPos = new Map();
  if (log.mode === 'rich') {
    const PH = { left: 0, right: 1, center: 2 };
    let cur = null;
    log.tokens.forEach(tk => {
      const ph = PH[tk.placeAlign];
      if (!cur || !Object.is(cur.lineTop, tk.lineTop) || !Object.is(cur.lineHeight, tk.lineLineHeight) || ph < cur.phase) {
        cur = { lineTop: tk.lineTop, lineHeight: tk.lineLineHeight, phase: ph, placed: [] };
        lines.push(cur);
      }
      cur.phase = ph;
      cur.placed.push(tk);
    });
    lines.forEach((ln, li) => {
      const lefts = ln.placed.filter(x => x.placeAlign === 'left');
      const rights = ln.placed.filter(x => x.placeAlign === 'right');
      const centers = ln.placed.filter(x => x.placeAlign === 'center');
      const ordered = lefts.concat(centers, rights.slice().reverse());
      ln.tokens = ordered.map((tk, ti) => {
        tokenPos.set(tk.seq, { line: li, token: ti });
        const o = { index: ti, placeOrder: ln.placed.indexOf(tk), styleName: tk.styleName, text: tk.text };
        ['width', 'height', 'innerHeight', 'contentWidth', 'contentHeight', 'lineHeight'].forEach(k => put(o, k, tk[k]));
        o.font = tk.font;
        o.align = tk.align;
        o.verticalAlign = tk.verticalAlign;
        put(o, 'padding', tk.padding);
        o.percentWidth = tk.percentWidth;
        o.isLineHolder = tk.isLineHolder;
        put(o, 'placeX', tk.placeX);
        o.placeAlign = tk.placeAlign;
        o.parentBgColorDrawn = tk.parentBgColorDrawn;
        // the token's font is makeFont of its rich style (Text.ts:1037, parseText.ts:463)
        const ts = tk.styleName && s.rich[tk.styleName];
        must(tk.font === ((ts && ts.font) || s.font), where + ': token font ' + tk.font);
        must(Object.is(tk.contentWidth, ruleWidth(tk.text, tk.font)),
          where + ': token ' + JSON.stringify(tk.text) + ' contentWidth ' + tk.contentWidth + ', the rule ' + ruleWidth(tk.text, tk.font));
        measureSet.set(JSON.stringify([tk.text, pxOfFont(tk.font), isMono(tk.font)]), { text: tk.text, font: tk.font });
        return o;
      });
    });
  }

  // pieces in paint order
  const ownerOf = i => {
    for (const b of log.bgs) {
      if (b.isBox && i >= b.from && i < b.to) return { of: 'box' };
    }
    for (const tk of log.tokens) {
      if (i >= tk.from && i < tk.to) return Object.assign({ of: 'token' }, tokenPos.get(tk.seq));
    }
    return null;
  };
  let plainLine = 0;
  const pieces = children.map((c, i) => {
    const cs = c.style;
    if (c.type === 'tspan') {
      let own = ownerOf(i);
      if (log.mode === 'plain') {
        must(!own, where + ': a plain TSpan inside a background');
        own = { of: 'line', line: plainLine++, token: null };
      }
      must(own && own.of !== 'box', where + ': a TSpan with no token');
      const g = apply(m, cs.x || 0, cs.y || 0);
      const stroke = cs.stroke == null || cs.stroke === 'none' ? null : cs.stroke;
      const bb = c.getBoundingRect();
      const lw = stroke ? cs.lineWidth : 0;
      // the TSpan rect is the measure, grown by a user stroke (parseText.ts:916-945);
      // a plain line's rect carries the block's contentWidth -- the WIDEST line
      // (Text.ts:658-660), not its own
      const tw = log.mode === 'plain'
        ? Math.max(0, ...children.filter(x => x.type === 'tspan').map(x => ruleWidth(String(x.style.text), x.style.font)))
        : ruleWidth(String(cs.text), cs.font);
      const grow = (stroke && cs.lineWidth > 0 && bb.width !== tw) ? cs.lineWidth : 0;
      must(Object.is(bb.width, tw + grow) || Object.is(bb.width - grow, tw),
        where + ': TSpan ' + JSON.stringify(cs.text) + ' measures ' + bb.width + ', the rule ' + tw);
      measureSet.set(JSON.stringify([String(cs.text), pxOfFont(cs.font), isMono(cs.font)]), { text: String(cs.text), font: cs.font });
      const o = { kind: 'text', of: own.of, line: nn(own.line), token: nn(own.token), text: String(cs.text) };
      put(o, 'x', cs.x || 0); put(o, 'y', cs.y || 0);
      put(o, 'gx', g[0]); put(o, 'gy', g[1]);
      o.font = cs.font;
      o.px = pxOfFont(cs.font);
      o.mono = isMono(cs.font);
      o.fontStyle = nn(cs.fontStyle); o.fontWeight = nn(cs.fontWeight);
      o.fontSize = typeof cs.fontSize === 'number' ? put({}, 'v', cs.fontSize).vText : nn(cs.fontSize);
      o.fontFamily = nn(cs.fontFamily);
      o.fill = nn(cs.fill);
      o.stroke = stroke;
      put(o, 'lineWidth', stroke ? cs.lineWidth : null);
      put(o, 'lineDash', stroke && cs.lineDash ? cs.lineDash : null);
      o.textAlign = nn(cs.textAlign);
      o.textBaseline = nn(cs.textBaseline);
      put(o, 'opacity', cs.opacity == null ? 1 : cs.opacity);
      o.strokeFirst = !!cs.strokeFirst;
      o.shadow = shadowOf(cs);
      o.bbox = put(put(put(put({}, 'x', bb.x), 'y', bb.y), 'width', bb.width), 'height', bb.height);
      void lw;
      return o;
    }
    if (c.type === 'rect') {
      const own = ownerOf(i);
      must(own, where + ': a Rect with no owner');
      const sh = c.shape;
      const o = { kind: 'rect', of: own.of, line: nn(own.line), token: nn(own.token) };
      put(o, 'x', sh.x); put(o, 'y', sh.y); put(o, 'width', sh.width); put(o, 'height', sh.height);
      Object.assign(o, corners(m, sh.x, sh.y, sh.width, sh.height));
      o.fill = nn(cs.fill);
      put(o, 'fillOpacity', cs.fillOpacity);
      o.stroke = cs.stroke == null || cs.stroke === 'none' ? null : cs.stroke;
      put(o, 'lineWidth', o.stroke ? cs.lineWidth : null);
      put(o, 'strokeOpacity', o.stroke ? cs.strokeOpacity : null);
      o.strokeFirst = !!cs.strokeFirst;
      put(o, 'lineDash', cs.lineDash || null);
      put(o, 'rRaw', sh.r == null ? null : sh.r);
      put(o, 'r4', r4(sh.r));
      put(o, 'opacity', cs.opacity == null ? 1 : cs.opacity);
      o.shadow = shadowOf(cs);
      o.drawn = o.fill != null || o.stroke != null;
      return o;
    }
    throw new OracleError(where + ': a child of type ' + c.type);
  });

  const rich = s.rich ? {} : null;
  if (rich) Object.keys(s.rich).sort().forEach(k => { rich[k] = styleOf(s.rich[k]); });
  const out = {
    component: t.component,
    owner: t.owner,
    attached: t.attached,
    text: String(s.text),
    rich: !!s.rich,
    transform: m ? m.map(hex) : null, transformText: m ? m.map(text) : null,
    anchor: Object.assign(pt(s.x || 0, s.y || 0), { g: pt(anchor[0], anchor[1]) }),
    align, verticalAlign,
    defaultStyle: t.attached ? { fill: nn(ds.fill), stroke: nn(ds.stroke), autoStroke: nn(ds.autoStroke), align: nn(ds.align), verticalAlign: nn(ds.verticalAlign), overflowRect: ds.overflowRect ? true : false } : null,
    style: styleOf(s),
    richStyles: rich,
    box,
    bounds,
    isTruncated: !!el.isTruncated,
    lines: log.mode === 'rich' ? lines.map(ln => Object.assign(put(put({}, 'lineTop', ln.lineTop), 'lineHeight', ln.lineHeight), { tokens: ln.tokens })) : null,
    pieces,
  };
  // raw handles for the guards (stripped before writing)
  Object.defineProperty(out, '__raw', { value: { el, log, pb, m }, enumerable: false });
  return out;
}

function wanted(c, t) {
  const list = c.record || ['seriesLabel'];
  if (c.match && !new RegExp(c.match).test(String(t.el.style.text))) return false;
  return list.some(w => {
    const [c, o] = w.split('@');
    return t.component === c && (!o || t.owner === o);
  });
}

function run(lib, c, measureSet) {
  const chart = lib.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(clone(c.option));
    const svg = chart.renderToSVGString();
    const zr = chart.getZr();
    const found = [];
    const seen = new Set();
    chart._componentsViews.forEach(v => v && v.__model && collect(v, 'component', found, seen));
    chart._chartsViews.forEach(v => v && v.__model && collect(v, 'chart', found, seen));
    const walkRoot = el => {
      if (el.ignore) return;
      if (el.type === 'text') {
        if (!seen.has(el) && visible(el, false, null)) found.push({ el, component: 'other', owner: null, attached: false });
        return;
      }
      if (el.childrenRef) el.childrenRef().forEach(walkRoot);
      const tc = el.getTextContent && el.getTextContent();
      if (tc && !seen.has(tc) && !tc.ignore && visible(tc, true, el)) found.push({ el: tc, component: 'other', owner: null, attached: true });
    };
    zr.storage.getRoots().forEach(walkRoot);
    // the harness: one <text> per non-empty TSpan of every visible text
    const svgTexts = (svg.match(/<text\b/g) || []).length;
    const spans = found.reduce((n, t) => n + t.el.childrenRef().filter(x => x.type === 'tspan' && x.style.text != null && String(x.style.text) !== '').length, 0);
    must(svgTexts === spans, c.name + ': the SVG has ' + svgTexts + ' <text>, the visible texts ' + spans + ' non-empty spans');
    const texts = found.filter(t => wanted(c, t)).map(t => recordText(lib, t, measureSet));
    must(texts.length > 0, c.name + ': nothing recorded');
    return { texts };
  } finally {
    chart.dispose();
  }
}

function runAll() {
  const measureSet = new Map();
  const names = new Set();
  const records = cases.map(c => {
    must(!names.has(c.name), 'two cases named ' + c.name);
    names.add(c.name);
    assertJson(c.option, c.name + '.option');
    let r;
    let productionBuild = false;
    try {
      r = run(echarts, c, measureSet);
    } catch (e) {
      if (e instanceof OracleError) throw e;
      console.log(c.name + ': the development build threw (' + e.message + '); running echarts.min.js');
      r = run(PROD, c, measureSet);
      productionBuild = true;
    }
    const rec = Object.assign({ name: c.name, note: c.note, W, H, option: c.option, record: c.record || ['seriesLabel'], match: c.match || null }, r);
    if (productionBuild) rec.productionBuild = true;
    return rec;
  });
  return { records, measureSet };
}

const first = runAll();
const second = runAll();
const records = first.records;
must(JSON.stringify(records) === JSON.stringify(second.records), 'two runs in one process do not agree');

// ---------- guards ----------

const failed = [];
function guard(what, cond) {
  if (!cond) failed.push(what);
}
const byName = n => {
  const r = records.find(x => x.name === n);
  must(r, 'no case ' + n);
  return r;
};
const eq = (a, b) => Object.is(a, b);
const H2D = h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); };
const rects = t => t.pieces.filter(p => p.kind === 'rect');
const spansOf = t => t.pieces.filter(p => p.kind === 'text');
const raw = t => t.__raw;
const FONT12 = '12px Microsoft YaHei';

// plain-bg-pad4 (Text.ts:519-678): box and line from the anchor, by hand
byName('plain-bg-pad4').texts.forEach(t => {
  const { el } = raw(t);
  const s = el.style;
  const ax = s.x || 0;
  const ay = s.y || 0;
  const tw = ruleWidth(s.text, s.font);
  const px = pxOfFont(s.font);
  const w = tw + (4 + 4);
  const h = px + (4 + 4);
  guard('plain-bg-pad4 ' + s.text + ': align center / bottom', t.align === 'center' && t.verticalAlign === 'bottom');
  const r = rects(t);
  guard('plain-bg-pad4 ' + s.text + ': one filled rect, the box', r.length === 1 && r[0].of === 'box' && r[0].fill === '#eeeeee' && r[0].stroke === null);
  guard('plain-bg-pad4 ' + s.text + ': box x', r.length && eq(H2D(r[0].x), ax - w / 2));
  guard('plain-bg-pad4 ' + s.text + ': box y', r.length && eq(H2D(r[0].y), ay - h));
  guard('plain-bg-pad4 ' + s.text + ': box w/h', r.length && eq(H2D(r[0].width), w) && eq(H2D(r[0].height), h));
  const sp = spansOf(t);
  guard('plain-bg-pad4 ' + s.text + ': the TSpan x', sp.length === 1 && eq(H2D(sp[0].x), ax + 4 / 2 - 4 / 2));
  guard('plain-bg-pad4 ' + s.text + ': the TSpan y', sp.length === 1 && eq(H2D(sp[0].y), ay - px + px / 2 - 4));
  guard('plain-bg-pad4 ' + s.text + ': middle baseline, centre align', sp[0].textBaseline === 'middle' && sp[0].textAlign === 'center');
  guard('plain-bg-pad4 ' + s.text + ': no auto stroke over a background', sp[0].stroke === null);
  guard('plain-bg-pad4 ' + s.text + ': the rect is painted before the text', t.pieces[0].kind === 'rect');
});
// plain-pad-nobg: padding moves the text, nothing is drawn
byName('plain-pad-nobg').texts.forEach(t => {
  const { el } = raw(t);
  const s = el.style;
  const ay = s.y || 0;
  const px = pxOfFont(s.font);
  guard('plain-pad-nobg: no rect', rects(t).length === 0);
  guard('plain-pad-nobg: padding [4,8] normalised to [4,8,4,8]', JSON.stringify(t.style.paddingText) === '["4","8","4","8"]');
  guard('plain-pad-nobg: TSpan y', eq(H2D(spansOf(t)[0].y), ay - px + px / 2 - 4));
});
// plain width/height: the box is the given size, the line keeps to the
// anchor by its content height (Text.ts:554-572)
byName('plain-width-height-bg').texts.forEach(t => {
  const { el } = raw(t);
  const s = el.style;
  const r = rects(t);
  guard('plain-width-height-bg: box 80 x 30', r.length === 1 && eq(H2D(r[0].width), 80) && eq(H2D(r[0].height), 30)
    && eq(H2D(r[0].x), (s.x || 0) - 80 / 2) && eq(H2D(r[0].y), (s.y || 0) - 30));
  guard('plain-width-height-bg: the line sits by its own height', eq(H2D(spansOf(t)[0].y), (s.y || 0) - 12 + 12 / 2));
});
// the padding forms (util.ts:641-655)
guard('plain-pad-3: [1,2,3] -> [1,2,3,2]', byName('plain-pad-3').texts.every(t => JSON.stringify(t.style.paddingText) === '["1","2","3","2"]'));
guard('plain-pad-4: [1,2,3,4] kept', byName('plain-pad-4').texts.every(t => JSON.stringify(t.style.paddingText) === '["1","2","3","4"]'));
guard('plain-bg-pad4: 4 -> [4,4,4,4]', byName('plain-bg-pad4').texts.every(t => JSON.stringify(t.style.paddingText) === '["4","4","4","4"]'));
guard('rich-token-padding-3: token padding [1,2,3] -> [1,2,3,2]',
  byName('rich-token-padding-3').texts.every(t => JSON.stringify(t.lines[0].tokens[0].paddingText) === '["1","2","3","2"]'));
// bg + border: the stroke doubled and drawn first (Text.ts:945-959)
byName('plain-bg-border').texts.forEach(t => {
  const r = rects(t);
  guard('plain-bg-border: one rect, fill and stroke', r.length === 1 && r[0].fill === '#eeeeee' && r[0].stroke === '#333333');
  guard('plain-bg-border: lineWidth 2 (1 doubled), strokeFirst', r.length && eq(H2D(r[0].lineWidth), 2) && r[0].strokeFirst === true);
});
byName('plain-border-pad2').texts.forEach(t => {
  const r = rects(t);
  guard('plain-border-pad2: stroke only, lineWidth 1, not stroke-first', r.length === 1 && r[0].fill === null && eq(H2D(r[0].lineWidth), 1) && r[0].strokeFirst === false);
  guard('plain-border-pad2: radius 3 spread to four', r.length && JSON.stringify(r[0].r4Text) === '["3","3","3","3"]');
});
// a block lineHeight draws a Rect with neither fill nor stroke (Text.ts:725-727, 912-924, 1106-1111)
byName('rich-block-lineHeight').texts.forEach(t => {
  const r = rects(t);
  guard('rich-block-lineHeight: one undrawn box rect', r.length === 1 && r[0].of === 'box' && r[0].drawn === false);
});
// the title's box is disabled (title/install.ts:166-182)
byName('title-box-disabled').texts.forEach(t => {
  guard('title-box-disabled: no rect, no padding', rects(t).length === 0 && t.style.padding === undefined);
});
// rich-two-line, by hand (parseText.ts:385-580, Text.ts:681-892)
byName('rich-two-line').texts.forEach(t => {
  const { el } = raw(t);
  const s = el.style;
  const ax = s.x || 0;
  const ay = s.y || 0;
  const fa = s.rich.a.font;
  const fv = s.rich.v.font;
  guard('rich-two-line: a is 14px, v 12px bold', pxOfFont(fa) === 14 && pxOfFont(fv) === 12 && / bold /.test(' ' + fv + ' '));
  const lines = s.text.split('\n').map(l => /^\{\w\|(.*)\}$/.exec(l)[1]);
  const w1 = ruleWidth(lines[0], fa);
  const w2 = ruleWidth(lines[1], fv);
  const cw = Math.max(0, w1, w2);
  const boxX = ax - cw / 2;
  const boxY = ay - (14 + 12);
  guard('rich-two-line: box', eq(H2D(t.box.x), boxX) && eq(H2D(t.box.y), boxY) && eq(H2D(t.box.width), cw) && eq(H2D(t.box.height), 26));
  const sp = spansOf(t);
  const xOf = w => (boxX + (cw - 0 - 0 - w) / 2) + w / 2;
  guard('rich-two-line: two spans', sp.length === 2);
  guard('rich-two-line: line 1 x, y', eq(H2D(sp[0].x), xOf(w1)) && eq(H2D(sp[0].y), boxY + 14 / 2));
  guard('rich-two-line: line 2 x, y', eq(H2D(sp[1].x), xOf(w2)) && eq(H2D(sp[1].y), boxY + 14 + 12 / 2));
  guard('rich-two-line: inks', sp[0].fill === '#c23531' && sp[1].fill === '#333');
  guard('rich-two-line: centre-aligned tokens', sp.every(p => p.textAlign === 'center' && p.textBaseline === 'middle'));
});
// rich-token-box, by hand: the token rect and the padded text
byName('rich-token-box').texts.forEach(t => {
  const { el } = raw(t);
  const s = el.style;
  const ax = s.x || 0;
  const ay = s.y || 0;
  const f = s.rich.a.font;
  const tw = ruleWidth(/^\{a\|(.*)\}$/.exec(s.text)[1], f);
  const w = tw + (4 + 4);
  const h = 12 + (2 + 2);
  const boxX = ax - w / 2;
  const boxY = ay - h;
  const r = rects(t);
  guard('rich-token-box: one token rect', r.length === 1 && r[0].of === 'token');
  guard('rich-token-box: rect geometry', r.length && eq(H2D(r[0].x), (boxX + (w - 0 - 0 - w) / 2 + w / 2) - w / 2)
    && eq(H2D(r[0].y), (boxY + h / 2) - h / 2) && eq(H2D(r[0].width), w) && eq(H2D(r[0].height), h));
  guard('rich-token-box: fill, doubled stroke, radius', r.length && r[0].fill === '#eeeeee' && r[0].stroke === '#333333'
    && eq(H2D(r[0].lineWidth), 2) && r[0].strokeFirst && JSON.stringify(r[0].r4Text) === '["4","4","4","4"]');
  const sp = spansOf(t)[0];
  const cx = boxX + (w - 0 - 0 - w) / 2 + w / 2;
  guard('rich-token-box: text x (centre, padding 4/4)', eq(H2D(sp.x), cx + 4 / 2 - 4 / 2));
  guard('rich-token-box: text y', eq(H2D(sp.y), (boxY + h / 2) - (h / 2 - 2 - 12 / 2)));
  guard('rich-token-box: no auto stroke over the token bg', sp.stroke === null);
});
// rich-percent-hr: '100%' of the block width, padding-free; height 0 takes no line
byName('rich-percent-hr').texts.forEach(t => {
  const hr = t.lines.map(l => l.tokens.find(k => k.styleName === 'hr')).find(Boolean);
  guard('rich-percent-hr: the hr token is 100% of the block width', hr && eq(H2D(hr.width), H2D(t.box.width)));
  guard('rich-percent-hr: the hr line has lineHeight 0', t.lines.length === 3 && eq(H2D(t.lines[1].lineHeight), 0));
  // the percent width is set after the line widths are summed (parseText.ts:
  // 555, 572-577), so the centred hr line still counts 0 wide and its rect
  // starts at the block's centre, not its left
  const hrRect = rects(t).find(p => p.of === 'token');
  guard('rich-percent-hr: the hr rect starts at the block centre',
    hrRect && eq(H2D(hrRect.x), (H2D(t.box.x) + (H2D(t.box.width) - 0 - 0 - 0) / 2 + H2D(hr.width) / 2) - H2D(hr.width) / 2));
  const r = rects(t).filter(p => p.of === 'token');
  guard('rich-percent-hr: one stroked, unfilled 0-high rect', r.length === 1 && r[0].fill === null && r[0].stroke === '#777777'
    && eq(H2D(r[0].height), 0) && eq(H2D(r[0].lineWidth), 0.5));
});
// rich-token-fixed-width-align: the left token at the box's left, the right at its right
byName('rich-token-fixed-width-align').texts.forEach(t => {
  const r = rects(t);
  const bx = H2D(t.box.x);
  const bw = H2D(t.box.width);
  guard('rich-token-fixed-width-align: box width 120', eq(bw, 120));
  guard('rich-token-fixed-width-align: three token rects', r.length === 3);
  const L = r.find(p => p.token === 0);
  const C = r.find(p => p.token === 1);
  const R = r.find(p => p.token === 2);
  guard('rich-token-fixed-width-align: left at the box left', L && eq(H2D(L.x), bx));
  guard('rich-token-fixed-width-align: right at the box right', R && eq(H2D(R.x), (bx + 120) - 30));
  guard('rich-token-fixed-width-align: centre in what is left', C && eq(H2D(C.x), ((bx + 30) + (120 - 30 - 30 - 30) / 2 + 30 / 2) - 30 / 2));
});
// the '{name|text}' grammar (parseText.ts:18, 385-430, 584-668)
const tokensOf = t => t.lines.map(l => l.tokens.map(k => [k.styleName, k.text]));
guard('rich-braces-nested: [a "one {b|two"] [plain " three}"]',
  byName('rich-braces-nested').texts.every(t => JSON.stringify(tokensOf(t)) === JSON.stringify([[['a', 'one {b|two'], [null, ' three}']]])));
guard('rich-braces-unmatched: [a "ok"] [plain " tail {a|abc"]',
  byName('rich-braces-unmatched').texts.every(t => JSON.stringify(tokensOf(t)) === JSON.stringify([[['a', 'ok'], [null, ' tail {a|abc']]])));
guard('rich-invalid-name: plain "{a b|x} ", zz "unknown", plain " ", a "ok"',
  byName('rich-invalid-name').texts.every(t => JSON.stringify(tokensOf(t)) === JSON.stringify([[[null, '{a b|x} '], ['zz', 'unknown'], [null, ' '], ['a', 'ok']]])));
byName('rich-token-newline').texts.forEach(t => guard('rich-token-newline: got ' + JSON.stringify(tokensOf(t)),
  JSON.stringify(tokensOf(t)) === JSON.stringify([[['a', 'one']], [['a', 'two'], ['b', 'three']], [[null, '']], [['a', '']]])));
// the empty line is a plain line holder (no box); the trailing '{a|}' replaces
// the next holder and, not being a holder, draws its box 0 wide
byName('rich-token-newline').texts.forEach(t => {
  const holder = t.lines[2] && t.lines[2].tokens[0];
  const empty = t.lines[3] && t.lines[3].tokens[0];
  guard('rich-token-newline: line 3 is a line holder, line 4 is not',
    holder && holder.isLineHolder === true && empty && empty.isLineHolder === false);
  const r = rects(t).filter(p => p.line === 3);
  guard('rich-token-newline: the empty a token draws a 0-wide rect', r.length === 1 && eq(H2D(r[0].width), 0));
  guard('rich-token-newline: no rect on the holder line', rects(t).every(p => p.line !== 2));
});
// the plain truncation (parseText.ts:213-317) against the reading above
['plain-truncate', 'plain-truncate-ellipsis'].forEach(n => byName(n).texts.forEach(t => {
  const { el } = raw(t);
  const s = el.style;
  const full = CAT[DATA.indexOf(+/(\d+)$/.exec(s.text)[1])] + ' sales ' + /(\d+)$/.exec(s.text)[1];
  const exp = ruleTruncateLine(full, 30, s.font, s.ellipsis, s.truncateMinChar);
  const sp = spansOf(t);
  guard(n + ' ' + full + ': truncated to ' + JSON.stringify(exp), sp.length === 1 && sp[0].text === exp && t.isTruncated === (exp !== full));
}));
// richInheritPlainLabel (labelStyle.ts:520-523, 624-640)
guard('rich-inherit-plain: token a takes the label 16px bold and shadow',
  byName('rich-inherit-plain').texts.every(t => { const a = spansOf(t)[0]; return a.px === 16 && a.fontWeight === 'bold' && a.shadow && a.shadow.color === '#999999'; }));
guard('rich-inherit-plain: token a has no own fill, so the label colour reaches it through zrender',
  byName('rich-inherit-plain').texts.every(t => t.richStyles.a.fill === undefined && spansOf(t)[0].fill === '#123456'));
['rich-inherit-off', 'rich-inherit-off-root'].forEach(n => guard(n + ': token a falls back to the root 12px normal',
  byName(n).texts.every(t => { const a = spansOf(t)[0]; return a.px === 12 && a.fontWeight === 'normal'; })));
// a token that does not inherit: the root's shadow colour and offsets, the
// block's blur (labelStyle.ts:624-640, Text.ts:850-861)
byName('rich-inherit-off-shadow').texts.forEach(t => {
  const sp = spansOf(t);
  const sh = k => sp[k] && sp[k].shadow;
  guard('rich-inherit-off-shadow: token a is the root colour and offsets, the label blur',
    sh(0) && sh(0).color === '#ff0000' && sh(0).offsetXText === '5' && sh(0).offsetYText === '4' && sh(0).blurText === '2');
  guard('rich-inherit-off-shadow: token b keeps its own colour',
    sh(1) && sh(1).color === '#0000ff' && sh(1).offsetXText === '5');
});
guard('plain-shadow-offset-only: no blur, no shadow',
  byName('plain-shadow-offset-only').texts.every(t => spansOf(t).every(p => p.shadow === null)));
// 'baseline' is verticalAlign's alias: the top token at the line top, the
// bottom one at its bottom
byName('rich-baseline-alias').texts.forEach(t => {
  const tk = t.lines[0].tokens;
  guard('rich-baseline-alias: the tokens read top / bottom',
    tk[0].verticalAlign === 'top' && tk[1].verticalAlign === 'bottom');
  const r = rects(t);
  const top = H2D(t.lines[0].lineTop);
  const lh = H2D(t.lines[0].lineHeight);
  guard('rich-baseline-alias: t at the top, b at the bottom of a 24px line',
    r.length === 2 && eq(lh, 24) && eq(H2D(r[0].y), top) && eq(H2D(r[1].y) + H2D(r[1].height), top + lh));
});
// a text's bounds grow by a bordered rect's stroke, by exactly its width:
// no floor of 4 where it has no fill
byName('legend-rich-token-border').texts.forEach(t => {
  const r = rects(t);
  guard('legend-rich-token-border: one unfilled 1-wide rect', r.length === 1 && r[0].fill === null && eq(H2D(r[0].lineWidth), 1));
  guard('legend-rich-token-border: the bounds are the rect grown by 1',
    r.length === 1 && eq(H2D(t.bounds.x), H2D(r[0].x) - 0.5) && eq(H2D(t.bounds.y), H2D(r[0].y) - 0.5)
    && eq(H2D(t.bounds.width), H2D(r[0].width) + 1) && eq(H2D(t.bounds.height), H2D(r[0].height) + 1));
});
byName('legend-rich-token-border-bg').texts.forEach(t => {
  const r = rects(t);
  guard('legend-rich-token-border-bg: the bounds are the rect grown by the doubled 2',
    r.length === 1 && eq(H2D(r[0].lineWidth), 2) && eq(H2D(t.bounds.x), H2D(r[0].x) - 1)
    && eq(H2D(t.bounds.width), H2D(r[0].width) + 2));
});
// every recorded TSpan's font is makeFont of the style it came from
records.forEach(r => r.texts.forEach(t => {
  const s = raw(t).el.style;
  guard(r.name + ': style font is makeFont', makeFont(s) === s.font);
  if (s.rich) Object.keys(s.rich).forEach(k => guard(r.name + ': rich ' + k + ' font is makeFont', makeFont(s.rich[k]) === s.rich[k].font));
}));
void FONT12;

// ---------- the measure table ----------

const measure = Array.from(first.measureSet.values())
  .map(m => ({ text: m.text, px: pxOfFont(m.font), mono: isMono(m.font) }))
  .sort((a, b) => (a.px - b.px) || (a.mono - b.mono) || (a.text < b.text ? -1 : a.text > b.text ? 1 : 0))
  .map(m => {
    const r = measureText(m.text, (m.mono ? m.px + 'px monospace' : m.px + 'px sans-serif'));
    const f = ruleWidth(m.text, m.mono ? m.px + 'px monospace' : m.px + 'px sans-serif');
    must(Object.is(r.width, f), JSON.stringify(m.text) + ' at ' + m.px + 'px: Text measures ' + r.width + ', the rule ' + f);
    const o = { text: m.text, px: m.px, mono: m.mono };
    put(o, 'width', r.width);
    put(o, 'height', r.height);
    return o;
  });

if (failed.length) {
  failed.forEach(f => console.log('guard failed: ' + f));
  console.log(failed.length + ' guards failed; nothing written');
  process.exit(1);
}

const out = {
  source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version,
  platform: typeof navigator !== 'undefined' ? nn(navigator.platform) : null,
  ratios: {
    firstCode: FIRST_CODE,
    lastCode: LAST_CODE,
    fontSize: DEFAULT_FONT_SIZE,
    ratio: RATIO.map(hex),
    ratioText: RATIO.map(text),
  },
  measure,
  cases: records,
};

const BIG = 9223372036854775808;
const json = JSON.stringify(out, (k, v) => (typeof v === 'number' && Number.isFinite(v)
  && Math.abs(v) >= BIG && Math.abs(v) < 1e21 ? '@@num:' + v.toExponential() + '@@' : v), 1)
  .replace(/"@@num:([^"@]+)@@"/g, '$1');
fs.writeFileSync(OUT, json + '\n');
const nTexts = records.reduce((n, r) => n + r.texts.length, 0);
const nPieces = records.reduce((n, r) => n + r.texts.reduce((k, t) => k + t.pieces.length, 0), 0);
const prod = records.filter(r => r.productionBuild).map(r => r.name);
if (prod.length) console.log('through the production build:', prod.join(', '));
console.log('wrote', OUT, records.length + ' cases, ' + nTexts + ' texts, ' + nPieces + ' pieces, ' + measure.length + ' measured strings');
process.exit(0);
