// Upstream's own answers for authored text styles: the font and ink every
// visible text ends up with, and where it lands, once an author sets
//   axisLabel.{fontSize, fontWeight, fontFamily, fontStyle, color, rotate}
//   axis name + nameTextStyle.{fontSize, fontWeight, fontFamily, color}
//   the root textStyle (fonts of every text; colour of free-standing text only)
//   title.textStyle / title.subtextStyle, legend.textStyle
//   series label fonts, with and without their own
//   the root backgroundColor and darkMode (true / false / 'auto' / unset)
//   fontSize as a number, a fraction, '14' and '14px'.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer, 600x400, animation
// false, Math.random pinned to 0 before the library loads). Node has no
// canvas, so zrender measures every string with its built-in width table
// (zrender core/platform.ts:76-92): px is the number before 'px' in the font
// (the first match of /((?:\d+)?\.?\d*)px/), else 12; a font string that
// contains 'mono' measures px per UTF-16 unit; otherwise each unit of char code
// 32..126 counts ratio*px and any other unit px; a line is px high. This is
// the table grid-bounds.js and axis-names.js record, recorded here the same
// way, so TZrSsrMeasurer can replay it.
//
// The rules, as upstream has them (ECharts src/, zrender src/):
//   fonts     label/labelStyle.ts:521-524,630-640 (setTokenTextStyle): each of
//             fontStyle / fontWeight / fontSize / fontFamily is the component's
//             own value, else the ROOT textStyle's (ecModel.option.textStyle,
//             which globalDefault.ts:86-95 seeds with fontSize 12, fontStyle and
//             fontWeight 'normal', fontFamily 'Microsoft YaHei' when
//             navigator.platform starts with 'Win' -- node >= 21 has a
//             navigator; 'Win32' here -- else 'sans-serif'). Only a component
//             WITHOUT a default of its own sees the root: axisLabel has
//             fontSize 12 (axisDefault.ts:95), title textStyle 18 / bold and
//             subtextStyle 12 (title/install.ts:129-136), so a root fontSize
//             never reaches them; axis names, legend items and series labels
//             have none and follow the root.
//   font str  zrender graphic/Text.ts:969-1009 makeFont / parseFontSize: when
//             fontSize, fontFamily or fontWeight is set the font is
//             [fontStyle, fontWeight, parseFontSize(fontSize), fontFamily ||
//             'sans-serif'].join(' '), trimmed. parseFontSize keeps a string
//             containing 'px' / 'rem' / 'em' as it is ('14px'), appends 'px'
//             to anything numeric (14, '14', 13.5), else '12px'.
//   getFont   labelStyle.ts:687-698 (Model.getFont, model/mixin/textStyle.ts:
//             56-63): own || root textStyle || '' / '' / 12 / 'sans-serif', and
//             the size is (fontSize) + 'px' with no parse: '14px' gives
//             '14pxpx'. Used for the category auto-interval measure
//             (coord/axisTickLabelBuilder.ts:475) and the axis name's `font`
//             (AxisBuilder.ts:904), which makeFont then rebuilds from the
//             separate parts; the measurer still reads 14 from '14pxpx'.
//   colour    labelStyle.ts:578-583: the root textStyle.color fills a text only
//             when it is NOT attached to a host (createTextStyle isAttached
//             false) and has no colour of its own. Free-standing texts with a
//             default colour (axisLabel axisDefault.ts:96, title, subtitle,
//             legend LegendModel.ts:503-505) keep theirs through getTextColor
//             (model/mixin/textStyle.ts:46-52: own || root); the axis name has
//             none, so getTextColor hands it the root colour (AxisBuilder.ts:
//             925-926, else the axis line colour). A series label is attached:
//             its ink is zrender's automatic one (Element.ts:697-735) or its
//             own colour -- never the root's.
//   dark      darkMode is read in exactly one place, core/echarts.ts:1924-1933:
//             every update sets zr.setBackgroundColor(ecModel.get(
//             'backgroundColor') || 'transparent'), which recomputes
//             zr._darkMode = lum(bg, 1) < 0.4 (zrender zrender.ts:43-60,
//             195-205; a gradient averages its stops; no background -> false),
//             then, when ecModel.get('darkMode') is not null and not 'auto',
//             zr.setDarkMode(darkMode) forces it (zrender.ts:214-216). The
//             default is 'auto' (globalDefault.ts:36; theme/dark.ts:69 sets
//             true). zr.isDarkMode() then drives only the attached labels'
//             automatic ink: getOutsideFill '#ccc' dark / '#333' light
//             (Element.ts:781-783), getOutsideStroke the ground made opaque over
//             black / white (Element.ts:785-799), and the inside halo, the host
//             fill iff isDark == (lum(ink, 0) < 0.4) (graphic/Path.ts:289-301).
//             The inside ink itself (Path.ts:262-287) depends on the host fill
//             alone. Free texts (axis labels, names, title, legend) do not look
//             at it: their colours are the light tokens whatever the ground.
//
// The fixture, top level:
//   source    'ECharts <v>, zrender <v>'
//   platform  navigator.platform as this node reports it (the root fontFamily
//             default depends on it)
//   ratios    {firstCode, lastCode, fontSize, ratio[], ratioText[]}: the 95
//             ratios of char codes 32..126 as hex Doubles, decoded from the
//             dist's width-table string (checked against the zrender source when
//             D:/Projects/zrender, or ZRENDER_SRC, is there) and each read back
//             from a 1px Text. fontSize: what a font without 'px' measures at.
//   measure[] {text, px, mono, width, widthText, height, heightText}: every
//             distinct (line, px, mono) recorded below: the width of every
//             drawn TSpan and of a fresh Text in 'px sans-serif' (or
//             'px monospace'); the generator's reading of the rule above must
//             give the same Doubles or the run fails.
//   getFont   Model.getFont() for a few bare models (no ecModel): the fallback.
//   cases[]
//
// Per case:
//   name, note, W, H, option (as run; JSON only)
//   background  {option: the option's backgroundColor or null, model:
//               ecModel.get('backgroundColor') or null, zr: zr.getBackgroundColor(),
//               svg: the fill of the SVG's full-canvas background rect or null}
//   darkMode    {option: option.darkMode or null, model: ecModel.get('darkMode'),
//               isDark: zr.isDarkMode()}
//   globalTextStyle   ecModel.option.textStyle after the merge (defaults in)
//   grids[]     {index, rect, rectText}: coordinateSystem.getRect() of each grid
//   texts[]     every visible, non-empty zrender Text, in view order (component
//               views, then chart views, each group depth first, a host's
//               attached text right after the host):
//     component   axisLabel | axisName | title | subtitle | legend |
//                 seriesLabel | other
//     owner       '<mainType><componentIndex>' of the view it belongs to
//     attached    true for a host's textContent (series labels)
//     text        style.text
//     x, y        the text's own anchor (style.x || 0, style.y || 0) through its
//                 global transform: where zrender lays the text out
//     transform   the six numbers of the Text's global transform (null: none)
//     rotation    -atan2(m1, m0) of that transform (0 when null)
//     font        style.font as makeFont normalised it
//     fontSizeRaw style.fontSize as handed to zrender (number or string)
//     px          the size the measurer reads from font (the rule above)
//     mono        font contains 'mono' (measured px per unit)
//     fontStyle, fontWeight, fontFamily   the style's values (null if absent)
//     styleFill, styleStroke, styleLineWidth   the Text's own style (null if
//                 absent: an attached text then takes zrender's automatic one)
//     autoFill, autoStroke   an attached text's _defaultStyle fill / stroke
//                 (null for free texts)
//     fill, stroke, lineWidth   what is painted: the first TSpan's style
//                 (stroke null when none is drawn; lineWidth null then)
//     align, verticalAlign   style.align / style.verticalAlign, else the
//                 attached default (null when neither)
//     paint       {x, y (the first TSpan's style.x/y through the transform),
//                 textAlign, textBaseline}: the point and alignment SVG draws at
//     box         Text.getBoundingRect() (local frame, alignment applied): the
//                 union of its TSpans' rects, which rounds (x + w) - x, so its
//                 width can be an ulp off the measure (legend 'In': 10.0799...98
//                 against 10.08...02)
//     spanBox     the first TSpan's getBoundingRect(): its width is the measure
//   productionBuild   true when the development build threw and the case ran
//               through echarts.min.js
//
// Doubles are written as the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase) with a readable twin beside them (xText beside x, ...), because
// the Pascal JSON reader misparses integer literals above 2^63.
//
// Guards (the fixture is not written and the run exits 1 when one fails):
// expectations derived from the upstream source independently of the run --
// the root colour never reaches an attached label but does reach the axis
// name; a root fontSize leaves axis labels / title / subtitle at their own
// defaults and reaches names, legend and series labels; getFont falls back to
// 12px sans-serif and writes '14pxpx' for '14px'; parseFontSize on '14',
// '14px', 13.5; the isDark table; own label fontSize beats the root; the
// outside auto ink per mode. Plus the harness: every visible <text> in the SVG
// is a recorded text, every measured box matches the rule. Outside the
// script: run twice and diff.
//
//   node tools/advchart-oracle/text-style.js
'use strict';
Math.random = function () { return 0; };

const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const PROD = require(DIST.replace(/echarts\.js$/, 'echarts.min.js'));
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-text-style.json');
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
const RECT = ['x', 'y', 'width', 'height'];
const hexRect = r => ({ x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) });
const textRect = r => ({ x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) });
const finiteRect = r => r && RECT.every(k => typeof r[k] === 'number' && Number.isFinite(r[k]));
const nn = v => (v === undefined ? null : v);
const clone = o => JSON.parse(JSON.stringify(o));

// ---------- the width table (as grid-bounds.js) ----------

const FIRST_CODE = 32;
const LAST_CODE = 126;
const DEFAULT_FONT_SIZE = 12;

function decodeTable(literal, where) {
  const s = Function('"use strict"; return (' + literal + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1,
    where + ': the width table is not ' + (LAST_CODE - FIRST_CODE + 1) + ' characters');
  return s;
}
// the minified build has no named table: the string is read from the
// development build beside it, and the 1px read-back below checks it against
// the build actually loaded
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
must(Object.is(measureText('0', 'sans-serif').width, RATIO['0'.charCodeAt(0) - FIRST_CODE] * DEFAULT_FONT_SIZE),
  'a font with no px does not measure at ' + DEFAULT_FONT_SIZE);

// platform.ts:78-89, as read here
function pxOfFont(font) {
  const res = /((?:\d+)?\.?\d*)px/.exec(font);
  return (res && +res[1]) || DEFAULT_FONT_SIZE;
}
function lineWidth(line, px, mono) {
  if (mono) return px * line.length;
  let w = 0;
  for (let i = 0; i < line.length; i++) {
    const c = line.charCodeAt(i);
    const r = c >= FIRST_CODE && c <= LAST_CODE ? RATIO[c - FIRST_CODE] : null;
    w += r == null ? px : r * px;
  }
  return w;
}
function textBox(t, px, mono) {
  const lines = String(t).split('\n');
  return { width: Math.max(...lines.map(l => lineWidth(l, px, mono))), height: px * lines.length };
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

// ---------- the cases ----------

const CAT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August'];
const DATA = [120, 200, 150, 80, 70];
const xCat = o => Object.assign({ type: 'category', data: CAT }, o);
const yCat = o => Object.assign({ type: 'category', data: CAT }, o);
const val = o => Object.assign({ type: 'value' }, o);
const bar = o => Object.assign({ type: 'bar', name: 'Sales', data: DATA }, o);
const opt = o => Object.assign({ animation: false }, o);
const vbar = (xa, ya, extra) => opt(Object.assign({ xAxis: xCat(xa), yAxis: val(ya), series: [bar()] }, extra));
const hbar = (xa, ya) => opt({ xAxis: val(xa), yAxis: yCat(ya), series: [bar()] });

// the "everything" chart: title, legend, both names, top labels
function full(extra, labelOpt, axisExtra) {
  const ax = axisExtra || {};
  return opt(Object.assign({
    title: { text: 'Sales', subtext: 'Weekly' },
    legend: {},
    xAxis: xCat(Object.assign({ name: 'Day' }, ax.x)),
    yAxis: val(Object.assign({ name: 'Amount' }, ax.y)),
    series: [bar({ label: Object.assign({ show: true, position: 'top' }, labelOpt) })],
  }, extra));
}

// the darkMode chart: a dark host and a light host with inside labels, a mid
// host with top labels
function darkChart(extra) {
  return opt(Object.assign({
    xAxis: xCat({ name: 'Day' }),
    yAxis: val(),
    series: [
      bar({ name: 'Dark', data: [120, 200, 150, 80, 70], itemStyle: { color: '#2f4554' }, label: { show: true, position: 'inside' } }),
      bar({ name: 'Light', data: [90, 110, 130, 60, 100], itemStyle: { color: '#fac858' }, label: { show: true, position: 'inside' } }),
      bar({ name: 'Mid', data: [60, 70, 80, 90, 100], itemStyle: { color: '#5470c6' }, label: { show: true, position: 'top' } }),
    ],
  }, extra));
}

const ROOT_FULL = { fontSize: 14, color: '#123456', fontWeight: 'bold', fontFamily: 'serif' };

const cases = [
  // axisLabel font size, each axis kind
  { name: 'xcat-label-fs14', note: 'category x axisLabel.fontSize 14', option: vbar({ axisLabel: { fontSize: 14 } }) },
  { name: 'xcat-label-fs18', note: 'category x axisLabel.fontSize 18', option: vbar({ axisLabel: { fontSize: 18 } }) },
  { name: 'xcat-label-fs20', note: 'category x axisLabel.fontSize 20', option: vbar({ axisLabel: { fontSize: 20 } }) },
  { name: 'yval-label-fs14', note: 'value y axisLabel.fontSize 14', option: vbar({}, { axisLabel: { fontSize: 14 } }) },
  { name: 'yval-label-fs18', note: 'value y axisLabel.fontSize 18', option: vbar({}, { axisLabel: { fontSize: 18 } }) },
  { name: 'yval-label-fs20', note: 'value y axisLabel.fontSize 20', option: vbar({}, { axisLabel: { fontSize: 20 } }) },
  { name: 'ycat-label-fs16', note: 'category y axisLabel.fontSize 16 (horizontal bars)', option: hbar({}, { axisLabel: { fontSize: 16 } }) },
  { name: 'xval-label-fs16', note: 'value x axisLabel.fontSize 16 (horizontal bars)', option: hbar({ axisLabel: { fontSize: 16 } }, {}) },
  { name: 'xcat-label-rot45-fs16', note: 'category x axisLabel rotate 45, fontSize 16', option: vbar({ axisLabel: { rotate: 45, fontSize: 16 } }) },
  { name: 'yval-label-rot45-fs16', note: 'value y axisLabel rotate 45, fontSize 16', option: vbar({}, { axisLabel: { rotate: 45, fontSize: 16 } }) },
  { name: 'xcat-label-bold-serif', note: "axisLabel fontWeight 'bold', fontFamily 'serif'", option: vbar({ axisLabel: { fontWeight: 'bold', fontFamily: 'serif' } }) },
  { name: 'xcat-label-color', note: "axisLabel color '#c23531'", option: vbar({ axisLabel: { color: '#c23531' } }) },
  {
    name: 'label-mix-italic', note: 'x: 14 bold Georgia italic; y: 18, weight 600, #c23531',
    option: vbar({ axisLabel: { fontSize: 14, fontWeight: 'bold', fontFamily: 'Georgia', fontStyle: 'italic' } },
      { axisLabel: { fontSize: 18, color: '#c23531', fontWeight: 600 } }),
  },
  {
    name: 'xcat-label-fs16-months', note: 'eight month names at 16px: the auto interval measures with the author font',
    option: opt({ xAxis: xCat({ data: MONTHS, axisLabel: { fontSize: 16 } }), yAxis: val(), series: [bar({ data: [5, 20, 36, 10, 10, 20, 30, 12] })] }),
  },
  {
    name: 'xcat-label-months-default', note: 'the same eight month names at the default 12px',
    option: opt({ xAxis: xCat({ data: MONTHS }), yAxis: val(), series: [bar({ data: [5, 20, 36, 10, 10, 20, 30, 12] })] }),
  },

  // axis names
  { name: 'xname-end-fs18-color', note: "x name at 'end', nameTextStyle fontSize 18 + color", option: vbar({ name: 'Day', nameTextStyle: { fontSize: 18, color: '#2f4554' } }) },
  {
    name: 'yname-middle-rot90-fs18', note: "y name 'middle', nameRotate 90, nameGap 40, fontSize 18 + color",
    option: vbar({}, { name: 'Amount', nameLocation: 'middle', nameRotate: 90, nameGap: 40, nameTextStyle: { fontSize: 18, color: '#c23531' } }),
  },
  { name: 'xname-end-gap30-fs18', note: 'x name nameGap 30, fontSize 18', option: vbar({ name: 'Day', nameGap: 30, nameTextStyle: { fontSize: 18 } }) },
  { name: 'yname-end-bold-serif', note: "y name at 'end', nameTextStyle bold serif, no colour (axis line colour)", option: vbar({}, { name: 'Units', nameTextStyle: { fontWeight: 'bold', fontFamily: 'serif' } }) },
  { name: 'xname-middle-fs20-gap35', note: "x name 'middle', nameGap 35, fontSize 20", option: vbar({ name: 'Weekday', nameLocation: 'middle', nameGap: 35, nameTextStyle: { fontSize: 20 } }) },

  // the root textStyle
  { name: 'default-everything', note: 'title, legend, names, top labels; no text styles at all', option: full({}) },
  { name: 'root-fs16', note: 'root textStyle {fontSize: 16} only', option: full({ textStyle: { fontSize: 16 } }) },
  { name: 'root-full', note: 'root textStyle 14, #123456, bold, serif; no component overrides', option: full({ textStyle: ROOT_FULL }) },
  {
    name: 'root-full-overrides', note: 'root 14/#123456/bold/serif; axisLabel 10 #aa0000, nameTextStyle Georgia #00aa00, title 20, legend normal #0000aa, label 11 #555555',
    option: full({
      textStyle: ROOT_FULL,
      title: { text: 'Sales', subtext: 'Weekly', textStyle: { fontSize: 20 } },
      legend: { textStyle: { fontWeight: 'normal', color: '#0000aa' } },
    }, { fontSize: 11, color: '#555555' }, {
      x: { axisLabel: { fontSize: 10, color: '#aa0000' }, nameTextStyle: { fontFamily: 'Georgia', color: '#00aa00' } },
    }),
  },
  { name: 'root-italic', note: "root textStyle {fontStyle: 'italic'}", option: full({ textStyle: { fontStyle: 'italic' } }) },
  {
    name: 'root-color-only', note: "root textStyle {color: '#123456'}: who takes it; an inside and a top label series",
    option: opt({
      textStyle: { color: '#123456' },
      title: { text: 'Sales', subtext: 'Weekly' },
      legend: {},
      xAxis: xCat({ name: 'Day' }),
      yAxis: val({ name: 'Amount' }),
      series: [
        bar({ name: 'In', label: { show: true, position: 'inside' } }),
        bar({ name: 'Top', data: [60, 70, 80, 90, 100], label: { show: true, position: 'top' } }),
      ],
    }),
  },
  { name: 'root-fs13.5', note: 'root textStyle fontSize 13.5', option: full({ textStyle: { fontSize: 13.5 } }) },

  // title
  {
    name: 'title-textstyle', note: 'title textStyle {fontSize 24, color}, subtextStyle {fontSize 14}',
    option: vbar({}, {}, { title: { text: 'Sales', subtext: '2026', textStyle: { fontSize: 24, color: '#c23531' }, subtextStyle: { fontSize: 14 } } }),
  },
  { name: 'title-default', note: 'title and subtext with the defaults', option: vbar({}, {}, { title: { text: 'Sales', subtext: '2026' } }) },
  {
    name: 'title-left-fs24', note: "title left 'left' top 10, fontSize 24; subtext 14 bold #999999",
    option: vbar({}, {}, { title: { text: 'Quarterly sales', subtext: 'All regions', left: 'left', top: 10, textStyle: { fontSize: 24 }, subtextStyle: { fontSize: 14, color: '#999999', fontWeight: 'bold' } } }),
  },
  {
    name: 'title-right-root14', note: "title left 'right' under root textStyle fontSize 14 (the title keeps its own defaults)",
    option: vbar({}, {}, { textStyle: { fontSize: 14 }, title: { text: 'Sales', subtext: '2026', left: 'right' } }),
  },

  // legend
  {
    name: 'legend-textstyle', note: 'legend textStyle {fontSize 16, color}',
    option: opt({ legend: { textStyle: { fontSize: 16, color: '#61a0a8' } }, xAxis: xCat(), yAxis: val(), series: [bar({ name: 'Sales' }), bar({ name: 'Cost', data: [60, 70, 80, 90, 100] })] }),
  },
  {
    name: 'legend-default', note: 'legend with the defaults',
    option: opt({ legend: {}, xAxis: xCat(), yAxis: val(), series: [bar({ name: 'Sales' }), bar({ name: 'Cost', data: [60, 70, 80, 90, 100] })] }),
  },
  {
    name: 'legend-vertical-right-fs16', note: "legend orient vertical, right 10, top 'middle', fontSize 16",
    option: opt({ legend: { orient: 'vertical', right: 10, top: 'middle', textStyle: { fontSize: 16 } }, xAxis: xCat(), yAxis: val(), series: [bar({ name: 'Sales' }), bar({ name: 'Cost', data: [60, 70, 80, 90, 100] })] }),
  },

  // series labels
  { name: 'bar-inside-root16', note: 'inside labels, root fontSize 16', option: vbar({}, {}, { textStyle: { fontSize: 16 }, series: [bar({ label: { show: true, position: 'inside' } })] }) },
  { name: 'bar-inside-own11-root16', note: 'inside labels fontSize 11 under root 16', option: vbar({}, {}, { textStyle: { fontSize: 16 }, series: [bar({ label: { show: true, position: 'inside', fontSize: 11 } })] }) },
  { name: 'bar-top-root16', note: 'top labels, root fontSize 16', option: vbar({}, {}, { textStyle: { fontSize: 16 }, series: [bar({ label: { show: true, position: 'top' } })] }) },
  { name: 'bar-top-own11-root16', note: 'top labels fontSize 11 under root 16', option: vbar({}, {}, { textStyle: { fontSize: 16 }, series: [bar({ label: { show: true, position: 'top', fontSize: 11 } })] }) },
  { name: 'bar-inside-rootcolor', note: 'inside labels under root color #123456 (attached: ignored)', option: vbar({}, {}, { textStyle: { color: '#123456' }, series: [bar({ label: { show: true, position: 'inside' } })] }) },
  { name: 'bar-top-rootcolor', note: 'top labels under root color #123456 (attached: ignored)', option: vbar({}, {}, { textStyle: { color: '#123456' }, series: [bar({ label: { show: true, position: 'top' } })] }) },
  { name: 'bar-top-owncolor-rootcolor', note: 'top labels color #aa0000 under root color #123456', option: vbar({}, {}, { textStyle: { color: '#123456' }, series: [bar({ label: { show: true, position: 'top', color: '#aa0000' } })] }) },
  {
    name: 'bar-inside-own13-rootboldserif', note: 'inside labels fontSize 13 under root bold serif',
    option: vbar({}, {}, { textStyle: { fontWeight: 'bold', fontFamily: 'serif' }, series: [bar({ label: { show: true, position: 'inside', fontSize: 13 } })] }),
  },
  {
    name: 'line-top-root16', note: 'line series labels (top) under root fontSize 16',
    option: opt({ textStyle: { fontSize: 16 }, xAxis: xCat(), yAxis: val(), series: [{ type: 'line', name: 'Sales', data: DATA, label: { show: true } }] }),
  },
  {
    name: 'pie-outside-root16', note: 'pie outside labels under root fontSize 16 (no grid)',
    option: opt({ textStyle: { fontSize: 16 }, series: [{ type: 'pie', radius: '50%', data: [{ name: 'A', value: 40 }, { name: 'B', value: 30 }, { name: 'C', value: 30 }] }] }),
  },

  // backgroundColor x darkMode
  { name: 'bg-101010-unset', note: "backgroundColor '#101010', darkMode unset", option: darkChart({ backgroundColor: '#101010' }) },
  { name: 'bg-101010-true', note: "backgroundColor '#101010', darkMode true", option: darkChart({ backgroundColor: '#101010', darkMode: true }) },
  { name: 'bg-101010-false', note: "backgroundColor '#101010', darkMode false", option: darkChart({ backgroundColor: '#101010', darkMode: false }) },
  { name: 'bg-101010-auto', note: "backgroundColor '#101010', darkMode 'auto'", option: darkChart({ backgroundColor: '#101010', darkMode: 'auto' }) },
  { name: 'bg-fafafa-unset', note: "backgroundColor '#fafafa', darkMode unset", option: darkChart({ backgroundColor: '#fafafa' }) },
  { name: 'bg-fafafa-true', note: "backgroundColor '#fafafa', darkMode true", option: darkChart({ backgroundColor: '#fafafa', darkMode: true }) },
  { name: 'bg-fafafa-false', note: "backgroundColor '#fafafa', darkMode false", option: darkChart({ backgroundColor: '#fafafa', darkMode: false }) },
  { name: 'bg-none-unset', note: 'no backgroundColor, darkMode unset', option: darkChart({}) },
  { name: 'bg-none-true', note: 'no backgroundColor, darkMode true', option: darkChart({ darkMode: true }) },
  { name: 'bg-rgba-half-unset', note: "backgroundColor 'rgba(0,0,0,0.5)', darkMode unset", option: darkChart({ backgroundColor: 'rgba(0,0,0,0.5)' }) },
  { name: 'bg-101010-rootcolor', note: "backgroundColor '#101010' with root textStyle color '#eeeeee'", option: darkChart({ backgroundColor: '#101010', textStyle: { color: '#eeeeee' } }) },

  // fontSize as a string, a fraction, a mono family
  { name: 'xlabel-fs-str14', note: "axisLabel fontSize '14' (a string)", option: vbar({ axisLabel: { fontSize: '14' } }) },
  { name: 'xlabel-fs-str14px', note: "axisLabel fontSize '14px'", option: vbar({ axisLabel: { fontSize: '14px' } }) },
  { name: 'xname-fs-str14px', note: "nameTextStyle fontSize '14px'", option: vbar({ name: 'Day', nameTextStyle: { fontSize: '14px' } }) },
  { name: 'root-fs-str14px', note: "root textStyle fontSize '14px' (getFont writes '14pxpx')", option: full({ textStyle: { fontSize: '14px' } }) },
  { name: 'root-fs-str14', note: "root textStyle fontSize '14'", option: full({ textStyle: { fontSize: '14' } }) },
  { name: 'label-fs-str14', note: "series label fontSize '14'", option: vbar({}, {}, { series: [bar({ label: { show: true, position: 'top', fontSize: '14' } })] }) },
  { name: 'title-fs-str20px', note: "title textStyle fontSize '20px'", option: vbar({}, {}, { title: { text: 'Sales', textStyle: { fontSize: '20px' } } }) },
  { name: 'xlabel-fs13.5', note: 'axisLabel fontSize 13.5', option: vbar({ axisLabel: { fontSize: 13.5 } }) },
  { name: 'ylabel-fs13.5', note: 'value y axisLabel fontSize 13.5', option: vbar({}, { axisLabel: { fontSize: 13.5 } }) },
  {
    name: 'xlabel-monospace', note: "axisLabel fontFamily 'monospace': the SSR measurer counts px per unit when the font says 'mono'",
    option: vbar({ axisLabel: { fontFamily: 'monospace', fontSize: 14 } }),
  },
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

// every visible Text under a view's group, with its classification
function collect(view, kind, out, seen) {
  const model = view.__model;
  const owner = model.mainType + model.componentIndex;
  const mt = model.mainType;
  let titleIdx = 0;
  const visit = (el, attached, host) => {
    if (el.ignore) return;
    {
      seen.add(el);
      let component = 'other';
      if (attached) component = kind === 'chart' ? 'seriesLabel' : 'other';
      else if (mt === 'xAxis' || mt === 'yAxis') {
        if (el.anid === 'name') component = 'axisName';
        else if (typeof el.anid === 'string' && el.anid.indexOf('label_') === 0) component = 'axisLabel';
      } else if (mt === 'title') {
        component = titleIdx === 0 ? 'title' : titleIdx === 1 ? 'subtitle' : 'other';
        titleIdx++;
      } else if (mt === 'legend') component = 'legend';
      if (!el.invisible && !(attached && hidden(host)) && el.style.text != null && String(el.style.text) !== '') {
        out.push({ el, component, owner, attached });
      }
    }
  };
  // a host's own text comes right after the host's subtree
  const walk = el => {
    if (el.ignore) return;
    if (el.type === 'text') { visit(el, false, null); return; }
    if (el.childrenRef) el.childrenRef().forEach(walk);
    const tc = el.getTextContent && el.getTextContent();
    if (tc) visit(tc, true, el);
  };
  walk(view.group);
}

function recordText(t, measureSet) {
  const el = t.el;
  const s = el.style;
  const where = t.owner + ' ' + t.component + ' ' + JSON.stringify(s.text);
  const m = el.transform ? Array.from(el.transform) : null;
  const anchor = apply(m, s.x || 0, s.y || 0);
  const spans = (el.childrenRef ? el.childrenRef() : []).filter(x => x.type === 'tspan');
  must(spans.length >= 1, where + ': no TSpan');
  const sp = spans[0];
  const sm = sp.transform ? Array.from(sp.transform) : null;
  must((m === null && sm === null) || (m && sm && m.every((v, i) => Object.is(v, sm[i]))),
    where + ': the TSpan transform is not the Text transform');
  const pp = apply(sm, sp.style.x || 0, sp.style.y || 0);
  const font = s.font;
  must(typeof font === 'string' && font.length > 0, where + ': no font');
  must(makeFont(s) === font, where + ': makeFont as read here gives ' + JSON.stringify(makeFont(s)) + ', upstream ' + JSON.stringify(font));
  const px = pxOfFont(font);
  const mono = font.indexOf('mono') >= 0;
  const box = el.getBoundingRect();
  must(finiteRect(box), where + ': no finite box');
  // each TSpan's own rect is the measure (the Text's rect is their union,
  // which rounds: x + w - x); one span per line, each its own measure
  const lines = String(s.text).split('\n');
  must(spans.length === lines.length, where + ': ' + spans.length + ' spans for ' + lines.length + ' lines');
  spans.forEach((q, i) => {
    const r = q.getBoundingRect();
    const rule = textBox(lines[i], px, mono);
    must(q.style.text === lines[i], where + ': span ' + i + ' reads ' + JSON.stringify(q.style.text));
    must(Object.is(r.width, rule.width) && Object.is(r.height, rule.height),
      where + ': span ' + i + ' measures ' + r.width + ' x ' + r.height + ', the rule gives ' + rule.width + ' x ' + rule.height);
    measureSet.set(JSON.stringify([lines[i], px, mono]), { text: lines[i], px, mono, width: r.width });
  });
  const spanBox = sp.getBoundingRect();
  const ds = t.attached ? (el._defaultStyle || {}) : null;
  const stroke = sp.style.stroke == null || sp.style.stroke === 'none' ? null : sp.style.stroke;
  const rot = m ? -Math.atan2(m[1], m[0]) : 0;
  return {
    component: t.component,
    owner: t.owner,
    attached: t.attached,
    text: String(s.text),
    x: hex(anchor[0]), y: hex(anchor[1]), xText: text(anchor[0]), yText: text(anchor[1]),
    transform: m ? m.map(hex) : null, transformText: m ? m.map(text) : null,
    rotation: hex(rot), rotationText: text(rot),
    font,
    fontSizeRaw: nn(s.fontSize),
    px,
    mono,
    fontStyle: nn(s.fontStyle), fontWeight: nn(s.fontWeight), fontFamily: nn(s.fontFamily),
    styleFill: nn(s.fill), styleStroke: nn(s.stroke), styleLineWidth: nn(s.lineWidth),
    autoFill: ds ? nn(ds.fill) : null, autoStroke: ds ? nn(ds.stroke) : null,
    fill: nn(sp.style.fill), stroke, lineWidth: stroke == null ? null : nn(sp.style.lineWidth),
    align: nn(s.align != null ? s.align : ds && ds.align),
    verticalAlign: nn(s.verticalAlign != null ? s.verticalAlign : ds && ds.verticalAlign),
    paint: {
      x: hex(pp[0]), y: hex(pp[1]), xText: text(pp[0]), yText: text(pp[1]),
      textAlign: nn(sp.style.textAlign), textBaseline: nn(sp.style.textBaseline),
    },
    box: hexRect(box), boxText: textRect(box),
    spanBox: hexRect(spanBox), spanBoxText: textRect(spanBox),
  };
}

function run(lib, c, measureSet) {
  const chart = lib.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(clone(c.option));
    const svg = chart.renderToSVGString();
    const ecModel = chart.getModel();
    const zr = chart.getZr();
    const found = [];
    const seen = new Set();
    chart._componentsViews.forEach(v => v && v.__model && collect(v, 'component', found, seen));
    chart._chartsViews.forEach(v => v && v.__model && collect(v, 'chart', found, seen));
    // anything drawn that no view owns
    const walkRoot = el => {
      if (el.ignore) return;
      if (el.type === 'text') {
        if (!seen.has(el) && !el.invisible && el.style.text != null && String(el.style.text) !== '') {
          found.push({ el, component: 'other', owner: null, attached: false });
        }
        return;
      }
      if (el.childrenRef) el.childrenRef().forEach(walkRoot);
      const tc = el.getTextContent && el.getTextContent();
      if (tc && !seen.has(tc) && !tc.ignore && !tc.invisible && tc.style.text) {
        found.push({ el: tc, component: 'other', owner: null, attached: true });
      }
    };
    zr.storage.getRoots().forEach(walkRoot);
    const texts = found.map(t => recordText(t, measureSet));
    // the harness: one <text> per recorded text (a multi-line text draws one per line)
    const svgTexts = (svg.match(/<text\b/g) || []).length;
    const expected = found.reduce((n, t) => n + t.el.childrenRef().filter(x => x.type === 'tspan').length, 0);
    must(svgTexts === expected, c.name + ': the SVG has ' + svgTexts + ' <text>, the recorded texts ' + expected + ' spans');
    const grids = [];
    ecModel.eachComponent('grid', g => {
      const r = g.coordinateSystem.getRect();
      must(finiteRect(r), c.name + ': grid ' + g.componentIndex + ' has no finite rect');
      grids.push({ index: g.componentIndex, rect: hexRect(r), rectText: textRect(r) });
    });
    const bgm = /^<svg[^>]*>\s*<rect width="(\d+)" height="(\d+)" x="0" y="0"([^>]*)>/.exec(svg);
    let svgBg = null;
    if (bgm) {
      const f = /\bfill="([^"]*)"/.exec(bgm[3]);
      const fo = /\bfill-opacity="([^"]*)"/.exec(bgm[3]);
      svgBg = { fill: f ? f[1] : null, fillOpacity: fo ? fo[1] : null };
    }
    return {
      background: {
        option: nn(c.option.backgroundColor),
        model: nn(ecModel.get('backgroundColor')),
        zr: nn(zr.getBackgroundColor()),
        svg: svgBg,
      },
      darkMode: { option: nn(c.option.darkMode), model: nn(ecModel.get('darkMode')), isDark: zr.isDarkMode() },
      globalTextStyle: clone(ecModel.option.textStyle),
      grids,
      texts,
    };
  } finally {
    chart.dispose();
  }
}

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
  const rec = Object.assign({ name: c.name, note: c.note, W, H, option: c.option }, r);
  if (productionBuild) rec.productionBuild = true;
  return rec;
});
const byName = n => {
  const r = records.find(x => x.name === n);
  must(r, 'no case ' + n);
  return r;
};

// ---------- guards ----------

const failed = [];
function guard(what, cond) {
  if (!cond) failed.push(what);
}
const of = (n, comp) => byName(n).texts.filter(t => t.component === comp);
const xOf = (n, comp) => of(n, comp).filter(t => t.owner === 'xAxis0');
const all = (arr, f) => arr.length > 0 && arr.every(f);
const INKS = ['#333', '#eee', '#ccc'];

// labelStyle.ts:578-583: the root colour never reaches an attached label
['root-color-only', 'bar-inside-rootcolor', 'bar-top-rootcolor'].forEach(n => {
  guard(n + ': series labels keep no style fill and are not painted #123456 (labelStyle.ts:578-583)',
    all(of(n, 'seriesLabel'), t => t.styleFill === null && t.fill !== '#123456'));
});
guard('bar-inside-rootcolor: inside labels take a band ink (Path.ts:262-287)',
  all(of('bar-inside-rootcolor', 'seriesLabel'), t => INKS.indexOf(t.fill) >= 0));
guard('bar-top-owncolor-rootcolor: an own label colour is painted',
  all(of('bar-top-owncolor-rootcolor', 'seriesLabel'), t => t.fill === '#aa0000'));
// getTextColor: own || root; the axis name has no default colour, the rest do
guard("root-color-only: the axis names take the root colour (AxisBuilder.ts:925, textStyle.ts getTextColor)",
  all(of('root-color-only', 'axisName'), t => t.fill === '#123456'));
['axisLabel', 'title', 'subtitle', 'legend'].forEach(k => guard('root-color-only: ' + k + ' keeps its own default colour',
  all(of('root-color-only', k), t => t.fill !== '#123456')));
// a root fontSize reaches only the texts without a default size of their own
[['axisLabel', 12], ['axisName', 16], ['title', 18], ['subtitle', 12], ['legend', 16], ['seriesLabel', 16]].forEach(([k, px]) => {
  guard('root-fs16: ' + k + ' at ' + px + 'px', all(of('root-fs16', k), t => t.px === px));
});
[['axisLabel', 12], ['axisName', 12], ['title', 18], ['subtitle', 12], ['legend', 12], ['seriesLabel', 12]].forEach(([k, px]) => {
  guard('default-everything: ' + k + ' at ' + px + 'px', all(of('default-everything', k), t => t.px === px));
});
guard('root-full: names, legend and labels bold serif 14',
  ['axisName', 'legend', 'seriesLabel'].every(k => all(of('root-full', k), t => t.px === 14 && t.fontWeight === 'bold' && t.fontFamily === 'serif')));
guard('root-full: axis labels keep 12px but take the root weight and family (no default for those)',
  all(of('root-full', 'axisLabel'), t => t.px === 12 && t.fontWeight === 'bold' && t.fontFamily === 'serif'));
guard('bar-inside-own11-root16: an own label size beats the root',
  all(of('bar-inside-own11-root16', 'seriesLabel'), t => t.px === 11));
guard('bar-top-own11-root16: an own label size beats the root',
  all(of('bar-top-own11-root16', 'seriesLabel'), t => t.px === 11));
// getFont (labelStyle.ts:687-698)
const getFont = {
  empty: new echarts.Model({}).getFont(),
  px14str: new echarts.Model({ fontSize: '14px' }).getFont(),
  str14: new echarts.Model({ fontSize: '14' }).getFont(),
  frac: new echarts.Model({ fontSize: 13.5, fontWeight: 'bold' }).getFont(),
};
guard("getFont(): '12px sans-serif'", getFont.empty === '12px sans-serif');
guard("getFont('14px'): '14pxpx sans-serif'", getFont.px14str === '14pxpx sans-serif');
guard("getFont('14'): '14px sans-serif'", getFont.str14 === '14px sans-serif');
guard("getFont(13.5 bold): 'bold 13.5px sans-serif'", getFont.frac === 'bold 13.5px sans-serif');
// parseFontSize (Text.ts:992-1009)
guard("xlabel-fs-str14: '14' -> 14px",
  all(xOf('xlabel-fs-str14', 'axisLabel'), t => t.fontSizeRaw === '14' && / 14px /.test(t.font) && t.px === 14));
guard("xlabel-fs-str14px: '14px' kept",
  all(xOf('xlabel-fs-str14px', 'axisLabel'), t => t.fontSizeRaw === '14px' && / 14px /.test(t.font) && t.px === 14));
guard("root-fs-str14px: the axis name font is rebuilt from the parts ('14px', not '14pxpx')",
  all(of('root-fs-str14px', 'axisName'), t => / 14px /.test(t.font) && t.font.indexOf('pxpx') < 0));
guard('xlabel-fs13.5: 13.5px', all(xOf('xlabel-fs13.5', 'axisLabel'), t => / 13\.5px /.test(t.font) && t.px === 13.5));
// isDark (echarts.ts:1924-1933, zrender.ts:43-60, 214-216)
[['bg-101010-unset', true], ['bg-101010-true', true], ['bg-101010-false', false], ['bg-101010-auto', true],
  ['bg-fafafa-unset', false], ['bg-fafafa-true', true], ['bg-fafafa-false', false],
  ['bg-none-unset', false], ['bg-none-true', true]].forEach(([n, d]) => {
  guard(n + ': isDark ' + d, byName(n).darkMode.isDark === d);
});
// the outside auto ink (Element.ts:781-783)
[['bg-101010-unset', '#ccc'], ['bg-101010-false', '#333'], ['bg-fafafa-unset', '#333'], ['bg-fafafa-true', '#ccc']].forEach(([n, ink]) => {
  guard(n + ': top labels painted ' + ink,
    all(byName(n).texts.filter(t => t.component === 'seriesLabel' && t.owner === 'series2'), t => t.fill === ink));
});
// free texts do not follow the mode
guard('bg-101010-unset vs bg-fafafa-unset: axis label and name inks are the same',
  JSON.stringify(of('bg-101010-unset', 'axisLabel').concat(of('bg-101010-unset', 'axisName')).map(t => t.fill))
  === JSON.stringify(of('bg-fafafa-unset', 'axisLabel').concat(of('bg-fafafa-unset', 'axisName')).map(t => t.fill)));
// every case classified something and has the grids it should
records.forEach(r => {
  guard(r.name + ': no unowned texts', r.texts.every(t => t.component !== 'other'));
  guard(r.name + ': a grid unless pie', r.option.series[0].type === 'pie' ? r.grids.length === 0 : r.grids.length === 1);
});

// ---------- the measure table ----------

const measure = Array.from(measureSet.values())
  .sort((a, b) => (a.px - b.px) || (a.mono - b.mono) || (a.text < b.text ? -1 : a.text > b.text ? 1 : 0))
  .map(m => {
    const r = measureText(m.text, (m.mono ? m.px + 'px monospace' : m.px + 'px sans-serif'));
    const f = textBox(m.text, m.px, m.mono);
    must(Object.is(r.width, f.width) && Object.is(r.height, f.height) && Object.is(r.width, m.width),
      JSON.stringify(m.text) + ' at ' + m.px + 'px: Text measures ' + r.width + ', the rule ' + f.width);
    return { text: m.text, px: m.px, mono: m.mono, width: hex(r.width), widthText: text(r.width), height: hex(r.height), heightText: text(r.height) };
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
  getFont,
  cases: records,
};

const BIG = 9223372036854775808;
const json = JSON.stringify(out, (k, v) => (typeof v === 'number' && Number.isFinite(v)
  && Math.abs(v) >= BIG && Math.abs(v) < 1e21 ? '@@num:' + v.toExponential() + '@@' : v), 1)
  .replace(/"@@num:([^"@]+)@@"/g, '$1');
fs.writeFileSync(OUT, json + '\n');
const nTexts = records.reduce((n, r) => n + r.texts.length, 0);
const prod = records.filter(r => r.productionBuild).map(r => r.name);
if (prod.length) console.log('through the production build:', prod.join(', '));
console.log('wrote', OUT, records.length + ' cases, ' + nTexts + ' texts, ' + measure.length + ' measured strings');
process.exit(0);
