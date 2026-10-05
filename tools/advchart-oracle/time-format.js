/*
Upstream's own answers for the TIME AXIS FORMATTER -- roadmap B7, batch 104:
the 24-token template (util/time.ts format), the leveled formatter dictionary
(parseTimeAxisLabelFormatterDictionary: a string or an array of templates per
level, per unit, the cascade that fills a unit nobody wrote and the
`{primary|...}` the default templates add), the labels a time axis draws with
each form and the rich pieces they turn into (the time axis' default
axisLabel.rich.primary is `fontWeight: 'bold'`), and the two tooltip places
the same code reaches: a string tooltip.formatter under an axis trigger on a
time axis is run through the time template first (TooltipView), and the axis
tooltip's header is TimeScale.getLabel (fullLeveledFormatter by the scale's
bottom unit).

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node's server-side mode, SVG renderer, `animation: false`,
600 x 400, with process.env.TZ = 'UTC' set before anything touches Date
(checked: the script stops if it did not take). Text is measured with
zrender's SSR width table (the TZrSsrMeasurer of the Pascal tests).

  node tools/advchart-oracle/time-format.js

writes tests/fixtures/advchart-time-format.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Numbers that are positions or instants are the 16 hex digits of the IEEE
double (big-endian, lowercase) with a readable twin beside them.

Top level: source, version, tz, notes[], tokens[] (the 24 tokens in the order
format replaces them, read out of the dist's own format function), constants
{seed: defaultFormatterSeed, full: fullLeveledFormatter} (read out of the
dist), format[], dict[], charts[], tooltip[], guards[].

format[] -- echarts.time.format(ms, tpl, utc) (the dist's public `format`):
  id, ms hex + msText, tpl, utc, out.

dict[] -- the dist's own parseTimeAxisLabelFormatter, cut out of the bundle
  and run on its own: id, formatter (the option value; absent = undefined),
  kind ('dict' | 'string'), highlight (no primary unit key set), dict
  {lowest: {upper: [templates]}} for every lowest unit and every upper unit
  at or above it (null entries of an author's array as null).

charts[] -- id, note, option (as run), axis 'x' | 'y' (the time axis), labels[]
  (axis.getViewLabels(), value order): value hex + valueText, level and unit
  (tick.time.level / lowerTimeUnit), text (the label's formattedLabel: the
  markup as formatted), shown (its Text not ignored), pieces[] (the Text's
  children after the display list is updated, paint order):
    {kind 'text', text, fontWeight (as the TSpan style holds it: 'bold',
     a number, or null), fontSize, fill, align, x, y hex (in the label's
     own frame)}
    {kind 'rect', x, y, width, height hex, fill}

tooltip[] -- id, note, option, px [x, y] (the integer pixel of a data point,
  dispatched as showTip {x, y}), trigger, html (what TooltipView handed its
  rich content: the formatter's text, or the default markup), texts[] (the
  non-empty token texts of a default markup, in order), header (the axis
  tooltip's axisValueLabel, from a second run with a probe function
  formatter; null for an item trigger).

Guards: format against an independent transcription of util/time.ts format
(the chain of replacements, pad, the 12-hour rule, the invalid date); the dict
against an independent transcription of the cascade; every chart label
against dict[lower][upper][min(level, len - 1)] || '' run through format;
the token list against the transcription's; named facts; every chart and
tooltip case again under TZ = Asia/Shanghai giving the same answers (the
fixture's zone-less strings and UTC instants replay on any fixed-offset
machine); two in-process runs writing the same bytes.
*/
'use strict';
process.env.TZ = 'UTC';
if (new Date(2017, 0, 1).getTimezoneOffset() !== 0 || new Date(2017, 6, 1).getTimezoneOffset() !== 0) {
  console.log("FAILED: process.env.TZ = 'UTC' did not take effect");
  process.exit(1);
}
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-time-format.json');
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
const clone = o => (o === undefined ? undefined : JSON.parse(JSON.stringify(o)));

// ---------------------------------------------------------------------------
// the dist's own code, cut out of the bundle
// ---------------------------------------------------------------------------
const SRC = fs.readFileSync(DIST, 'utf8');
function slice(from, to) {
  const a = SRC.indexOf(from);
  must(a >= 0, 'the dist has no ' + JSON.stringify(from));
  const b = SRC.indexOf(to, a);
  must(b > a, 'the dist has no ' + JSON.stringify(to) + ' after ' + JSON.stringify(from));
  must(SRC.indexOf(from, a + 1) < 0, 'the dist has two ' + JSON.stringify(from));
  return SRC.slice(a, b);
}
const DICT_SRC = slice('var primaryTimeUnitFormatterMatchers = {', 'function pad(str, len) {');
const DIST_TIME = new Function('each', 'isObject', 'isArray', 'isString', 'isFunction',
  DICT_SRC + '\nreturn { parseTimeAxisLabelFormatter: parseTimeAxisLabelFormatter, '
  + 'parseTimeAxisLabelFormatterDictionary: parseTimeAxisLabelFormatterDictionary, '
  + 'defaultFormatterSeed: defaultFormatterSeed, fullLeveledFormatter: fullLeveledFormatter, '
  + 'primaryTimeUnits: primaryTimeUnits };')(
  echarts.util.each, echarts.util.isObject, echarts.util.isArray, echarts.util.isString,
  echarts.util.isFunction);
const FORMAT_SRC = slice('function format(\n', 'function leveledFormat(');
const DIST_TOKENS = [];
FORMAT_SRC.replace(/\.replace\(\/\{(\w+)\}\/g/g, (m, t) => { DIST_TOKENS.push(t); return m; });

const UNITS = ['year', 'month', 'day', 'hour', 'minute', 'second', 'millisecond'];
const TOKENS = ['a', 'A', 'yyyy', 'yy', 'Q', 'MMMM', 'MMM', 'MM', 'M', 'dd', 'd', 'eeee', 'ee', 'e',
  'HH', 'H', 'hh', 'h', 'mm', 'm', 'ss', 's', 'SSS', 'S'];

// ---------------------------------------------------------------------------
// the transcriptions the guards hold the dist to
// ---------------------------------------------------------------------------
const EN = {
  month: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
    'October', 'November', 'December'],
  monthAbbr: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
  dayOfWeek: ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
  dayOfWeekAbbr: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
};
function tPad(v, len) {
  const s = String(v);
  return '0000'.substr(0, len - s.length) + s;
}
// util/time.ts format, from a Date: one replaceAll per token, in the order
// above, each over what the one before left
function tFormat(date, tpl, utc) {
  const g = n => date['get' + (utc ? 'UTC' : '') + n]();
  const y = g('FullYear');
  const M = g('Month') + 1;
  const d = g('Date');
  const e = g('Day');
  const Hh = g('Hours');
  const h = (Hh - 1) % 12 + 1;
  const mi = g('Minutes');
  const s = g('Seconds');
  const S = g('Milliseconds');
  const a = Hh >= 12 ? 'pm' : 'am';
  const val = {
    a, A: a.toUpperCase(), yyyy: String(y), yy: tPad(y % 100, 2), Q: String(Math.floor((M - 1) / 3) + 1),
    MMMM: String(EN.month[M - 1]), MMM: String(EN.monthAbbr[M - 1]), MM: tPad(M, 2), M: String(M),
    dd: tPad(d, 2), d: String(d), eeee: String(EN.dayOfWeek[e]), ee: String(EN.dayOfWeekAbbr[e]),
    e: String(e), HH: tPad(Hh, 2), H: String(Hh), hh: tPad(h, 2), h: String(h), mm: tPad(mi, 2),
    m: String(mi), ss: tPad(s, 2), s: String(s), SSS: tPad(S, 3), S: String(S),
  };
  let out = tpl || '';
  for (const t of TOKENS) out = out.split('{' + t + '}').join(val[t]);
  return out;
}
const tParseNum = v => new Date(Math.round(v));
const MATCH = {
  year: ['yyyy', 'yy'], month: ['MMMM', 'MMM', 'MM', 'M'], day: ['dd', 'd'],
  hour: ['HH', 'H', 'hh', 'h'], minute: ['mm', 'm'], second: ['ss', 's'], millisecond: ['SSS', 'S'],
};
const SEED = { year: '{yyyy}', month: '{MMM}', day: '{d}', hour: '{HH}:{mm}', minute: '{HH}:{mm}',
  second: '{HH}:{mm}:{ss}', millisecond: '{HH}:{mm}:{ss} {SSS}' };
const isObj = v => typeof v === 'function' || (!!v && typeof v === 'object');
function tDict(opt) {
  const o = opt || {};
  let hl = true;
  for (const u of UNITS) if (o[u] != null) hl = false;
  const dict = {};
  UNITS.forEach((low, li) => {
    const uo = o[low];
    dict[low] = {};
    let lower = null;
    for (let ui = li; ui >= 0; ui--) {
      const up = UNITS[ui];
      const item = isObj(uo) && !Array.isArray(uo) ? uo[up] : uo;
      let arr;
      if (Array.isArray(item)) {
        arr = item.slice();
        lower = arr[0] || '';
      } else if (typeof item === 'string') {
        lower = item;
        arr = [item];
      } else {
        if (lower == null) lower = SEED[low];
        else if (!MATCH[up].some(t => String(lower).indexOf('{' + t + '}') >= 0)) lower = dict[up][up][0] + ' ' + lower;
        arr = [lower];
        if (hl) arr[1] = '{primary|' + lower + '}';
      }
      dict[low][up] = arr;
    }
  });
  return { dict, hl };
}

// ---------------------------------------------------------------------------
// the format cases
// ---------------------------------------------------------------------------
const yearMs = (y, mo, d, h, mi, s, ms) => {
  const t = new Date(Date.UTC(2000, mo, d, h, mi, s, ms));
  t.setUTCFullYear(y);
  return t.getTime();
};
const I = {
  tue: Date.UTC(2024, 2, 5, 7, 8, 9, 12),
  eve: Date.UTC(2023, 11, 31, 23, 59, 59, 999),
  noon: Date.UTC(2024, 1, 29, 12, 0, 0, 0),
  midnight: Date.UTC(2024, 0, 1, 0, 0, 0, 0),
  pm1: Date.UTC(2024, 6, 14, 13, 5, 0, 500),
  pre: Date.UTC(1969, 11, 31, 23, 59, 59, 999),
  y5: yearMs(5, 5, 6, 4, 3, 2, 1),
  y105: yearMs(105, 9, 10, 22, 0, 0, 90),
  y2000: Date.UTC(2000, 9, 1, 11, 59, 59, 0),
  y1999: Date.UTC(1999, 3, 30, 0, 30, 0, 0),
};
const FORMAT = [];
function fmt(id, ms, tpl, utc) {
  FORMAT.push({ id, ms, tpl, utc: utc !== false });
}
for (const t of TOKENS) {
  for (const k of ['tue', 'eve', 'noon', 'midnight', 'pm1', 'pre', 'y5', 'y105', 'y2000', 'y1999']) {
    fmt('tok-' + t + '-' + k, I[k], '{' + t + '}');
  }
}
const COMBINED = [
  '{yyyy}-{MM}-{dd} {HH}:{mm}:{ss} {SSS}',
  '{eeee}, {MMMM} {d}, {yyyy} {h}:{mm} {A}',
  'Q{Q} {yy} {ee} {e}',
  '{hh}:{m}:{s}.{S} {a}',
  '{M}/{d}/{yy} {H}h',
  '{yyyy}{yy}{MMMM}{MMM}{MM}{M}{dd}{d}{eeee}{ee}{e}{HH}{H}{hh}{h}{mm}{m}{ss}{s}{SSS}{S}{a}{A}{Q}',
  '{yyyy}{yyyy}',
  'x{d}y{d}z',
];
COMBINED.forEach((tpl, i) => ['tue', 'eve', 'midnight', 'pm1'].forEach(k => fmt('comb' + i + '-' + k, I[k], tpl)));
const UNKNOWN = ['{Y}', '{YYYY}', '{D}', '{DD}', '{hhh}', '{value}', '{q}', '{E}', '{MMMMM}', '{ yyyy}',
  '{yyyy }', '{YY}', '{sss}', '{SS}', '{aa}', '{AA}', '{ddd}', '{eee}', '{HHH}', '{mmm}', '{y}'];
UNKNOWN.forEach((tpl, i) => fmt('unknown' + i, I.tue, tpl));
const EDGES = ['{{yyyy}}', '{yyyy', 'yyyy}', '{x{yyyy}}', '{y{yy}y}', '{}', '{{}}', '{yy{yy}}',
  '}{yyyy}{', '\\{yyyy}', '{MM}{M}{MMM}', '{{a}}', '{a{A}}', '{M{d}}', '{y{yyyy}}', '{{{d}}}',
  '{yyyy}}{{MM}', 'no tokens at all', '', '{primary|{yyyy}}', '{a|{MMM}} {b|{d}}', '{\n}{d}\n{d}',
  '%{yyyy}$&{MM}$1'];
EDGES.forEach((tpl, i) => ['tue', 'pm1'].forEach(k => fmt('edge' + i + '-' + k, I[k], tpl)));
// the instant, rounded as parseDate rounds a number
[['half-up', 1709251200000.5], ['just-under', 1709251200000.4999], ['neg-half', -0.5],
  ['two-and-half', 2.5], ['neg-one-and-half', -1.5], ['zero', 0]].forEach(([k, v]) =>
  fmt('round-' + k, v, '{yyyy}-{MM}-{dd} {HH}:{mm}:{ss}.{SSS}'));
// an invalid date: every getter NaN, the names undefined
const ALL = TOKENS.map(t => '{' + t + '}').join('|');
[['nan', NaN], ['inf', Infinity], ['ninf', -Infinity]].forEach(([k, v]) => fmt('invalid-' + k, v, ALL));
// useUTC false: the machine's own clock (UTC here)
['tue', 'eve', 'midnight', 'pm1', 'pre'].forEach(k => fmt('local-' + k, I[k], ALL, false));
COMBINED.slice(0, 3).forEach((tpl, i) => fmt('local-comb' + i, I.tue, tpl, false));

function runFormat(c) {
  const out = echarts.time.format(c.ms, c.tpl, c.utc);
  return { id: c.id, ms: hex(c.ms), msText: text(c.ms), tpl: c.tpl, utc: c.utc, out };
}

// ---------------------------------------------------------------------------
// the dictionary cases
// ---------------------------------------------------------------------------
const NO = Symbol('absent');
const DICTS = [
  ['default', NO],
  ['null', null],
  ['empty-object', {}],
  ['number', 5],
  ['false', false],
  ['array', ['{yyyy}', '{MM}']],
  ['string', '{yyyy}-{MM}'],
  ['empty-string', ''],
  ['year', { year: '{yyyy}年' }],
  ['day', { day: '{d}日' }],
  ['month-array', { month: ['{MMM}', '{b|{MMM}}'] }],
  ['hour-cascade', { hour: '{H}h' }],
  ['minute', { minute: '{mm}′' }],
  ['second-matches-up', { second: '{yyyy} {s}s' }],
  ['millisecond', { millisecond: '{SSS}ms' }],
  ['full-set', { year: '{yyyy}年', month: '{M}月', day: '{d}', hour: '{HH}', minute: '{HH}:{mm}',
    second: '{ss}', millisecond: '{S}' }],
  ['nested', { day: { month: '{MMM} {d}', day: '{d}' } }],
  ['nested-missing-own', { month: { year: '{yyyy}.{M}' } }],
  ['nested-arrays', { day: { day: ['{d}', '{x|{d}}'], year: ['Y{d}'] } }],
  ['day-null', { day: null }],
  ['day-undefined-none', { none: '{yyyy}-{MM}-{dd} {hh}:{mm}:{ss} {SSS}' }],
  ['day-empty-string', { day: '' }],
  ['day-empty-array', { day: [] }],
  ['year-empty-array', { year: [] }],
  ['day-null-first', { day: [null, '{d}'] }],
  ['nested-null-first', { day: { day: [null, '{d}'] } }],
  ['day-number', { day: 5 }],
  ['day-true', { day: true }],
  ['day-object-empty', { day: {} }],
  ['levels-three', { year: ['{yyyy}', '{a|{yyyy}}', '{b|{yyyy}}'], month: ['{MMM}', '{a|{MMM}}'], day: ['{d}'] }],
];
function runDict([id, opt]) {
  const f = opt === NO ? undefined : clone(opt);
  const parsed = DIST_TIME.parseTimeAxisLabelFormatter(f);
  const rec = { id };
  if (opt !== NO) rec.formatter = clone(opt);
  if (typeof parsed === 'string') {
    rec.kind = 'string';
    rec.template = parsed;
    return rec;
  }
  rec.kind = 'dict';
  let hl = true;
  for (const u of UNITS) if ((f || {})[u] != null) hl = false;
  rec.highlight = hl;
  rec.dict = {};
  UNITS.forEach((low, li) => {
    rec.dict[low] = {};
    for (let ui = li; ui >= 0; ui--) {
      const arr = parsed[low][UNITS[ui]];
      rec.dict[low][UNITS[ui]] = arr.map(x => (x === undefined ? null : x));
    }
  });
  return rec;
}

// ---------------------------------------------------------------------------
// the charts
// ---------------------------------------------------------------------------
const U = (...a) => Date.UTC(...a);
const line = (pts, utc, axis, extra) => {
  const time = Object.assign({ type: 'time' }, axis || {});
  const value = { type: 'value' };
  const opt = {
    animation: false,
    xAxis: extra && extra.vertical ? value : time,
    yAxis: extra && extra.vertical ? time : value,
    series: [{ type: 'line', data: pts.map((t, i) => (extra && extra.vertical ? [i + 1, t] : [t, i + 1])) }],
  };
  if (utc) opt.useUTC = true;
  if (extra && extra.textStyle) opt.textStyle = extra.textStyle;
  return opt;
};
const SPANS = {
  years: [U(2001, 5, 1), U(2030, 2, 1)],
  months: [U(2023, 2, 15), U(2025, 1, 10)],
  days: [U(2024, 0, 20), U(2024, 1, 12)],
  hours: [U(2024, 2, 1, 5), U(2024, 2, 3, 19)],
  minutes: [U(2024, 2, 1, 23, 50), U(2024, 2, 2, 0, 40)],
  seconds: [U(2024, 2, 1, 10, 0, 50), U(2024, 2, 1, 10, 1, 40)],
  ms: [U(2024, 2, 1, 10, 0, 0, 250), U(2024, 2, 1, 10, 0, 4, 750)],
  newyear: [U(2023, 11, 20), U(2024, 1, 10)],
  levels3: [U(2023, 10, 25), U(2024, 2, 20)],
};
const ENDS = { showMinLabel: true, showMaxLabel: true };
const CHARTS = [];
function chart(id, note, option, axis) {
  CHARTS.push({ id, note, option, axis: axis || 'x' });
}
for (const k of Object.keys(SPANS)) {
  chart('default-' + k, 'the default formatter over ' + k, line(SPANS[k], true));
}
chart('default-ms-ends', 'ragged millisecond ends, shown', line(SPANS.ms, true, { axisLabel: ENDS }));
chart('default-days-ends', 'ragged ends shown: the extent values in their own unit', line(SPANS.days, true, { axisLabel: ENDS }));
chart('default-y', 'a vertical time axis', line(SPANS.days, true, null, { vertical: true }), 'y');
chart('default-rotate', 'rotate 30 with the primary', line(SPANS.newyear, true, { axisLabel: { rotate: 30 } }));
// strings
chart('string-plain', 'one template for every level: no primary', line(SPANS.days, true, { axisLabel: { formatter: '{yyyy}-{MM}-{dd}' } }));
chart('string-primary', 'an author\'s {primary|} in a string: the default bold', line(SPANS.days, true, { axisLabel: { formatter: '{primary|{MMM}} {d}' } }));
chart('string-unknown-style', 'a style name nobody defined: plain', line(SPANS.days, true, { axisLabel: { formatter: '{foo|{d}}' } }));
chart('string-value', '{value} is not a time token', line(SPANS.days, true, { axisLabel: { formatter: '{value} {d}' } }));
chart('string-empty', 'an empty string formatter: empty labels', line(SPANS.days, true, { axisLabel: { formatter: '' } }));
chart('string-nested', 'braces round a token', line(SPANS.days, true, { axisLabel: { formatter: '{x{d}}' } }));
chart('string-twelve', 'the 12-hour clock', line(SPANS.hours, true, { axisLabel: { formatter: '{h} {A}' } }));
// dictionaries
chart('dict-day', 'day only: nothing gets the primary', line(SPANS.days, true, { axisLabel: { formatter: { day: '{d}日' } } }));
chart('dict-month-array', 'month [plain, rich] with rich.b', line(SPANS.days, true, { axisLabel: { formatter: { month: ['{MMM}', '{b|{MMM}}'] }, rich: { b: { color: '#cc0000', fontWeight: 'bold' } } } }));
chart('dict-full', 'every unit written', line(SPANS.newyear, true, { axisLabel: { formatter: { year: '{yyyy}年', month: '{M}月', day: '{d}' } } }));
chart('dict-short-array', 'level beyond the array: its last entry', line(SPANS.newyear, true, { axisLabel: { formatter: { year: ['{yyyy}'], month: ['{MMM}'], day: ['{d}'] } } }));
chart('dict-levels-three', 'three entries per unit, three levels', line(SPANS.newyear, true, { axisLabel: { formatter: { year: ['{yyyy}', '{a|{yyyy}}', '{b|{yyyy}}'], month: ['{MMM}', '{a|{MMM}}', '{b|{MMM}}'], day: ['{d}', '{a|{d}}'] }, rich: { a: { fontWeight: 'bold' }, b: { fontSize: 16 } } } }));
chart('dict-nested', 'a unit\'s own entry inside an object', line(SPANS.days, true, { axisLabel: { formatter: { month: { month: '{MMMM}' } } } }));
chart('dict-nested-missing', 'an object without the unit\'s own key: the seed, no primary', line(SPANS.days, true, { axisLabel: { formatter: { month: { year: 'Y' } } } }));
chart('dict-null', 'a null unit keeps the primary', line(SPANS.days, true, { axisLabel: { formatter: { day: null } } }));
chart('dict-none', '`none` is not a unit: the primary stays', line(SPANS.days, true, { axisLabel: { formatter: { none: '{yyyy}' } } }));
chart('dict-empty-string', 'day: \'\'', line(SPANS.days, true, { axisLabel: { formatter: { day: '' } } }));
chart('dict-empty-array', 'day: []', line(SPANS.days, true, { axisLabel: { formatter: { day: [] } } }));
chart('dict-null-first', 'day: [null, \'{d}\']', line(SPANS.days, true, { axisLabel: { formatter: { day: [null, '{d}'] } } }));
chart('dict-number', 'formatter 5: the defaults', line(SPANS.days, true, { axisLabel: { formatter: 5 } }));
chart('dict-hour', 'hour {H}h, days above it', line(SPANS.hours, true, { axisLabel: { formatter: { hour: '{H}h' } } }));
chart('dict-minute-second', 'minute and second', line(SPANS.seconds, true, { axisLabel: { formatter: { minute: '{H}:{mm}', second: '{s}s' } } }));
chart('dict-ms-ends', 'millisecond entry on the shown ends', line(SPANS.ms, true, { axisLabel: Object.assign({ formatter: { millisecond: '{s}.{SSS}', second: '{s}s' } }, ENDS) }));
// the primary's style
chart('rich-primary-colour', 'rich.primary colour and size', line(SPANS.days, true, { axisLabel: { rich: { primary: { color: '#cc0000', fontSize: 16 } } } }));
chart('rich-primary-normal', 'rich.primary fontWeight normal', line(SPANS.days, true, { axisLabel: { rich: { primary: { fontWeight: 'normal' } } } }));
chart('rich-primary-box', 'rich.primary with a box', line(SPANS.days, true, { axisLabel: { rich: { primary: { backgroundColor: '#eeeeee', padding: [2, 4], borderRadius: 3 } } } }));
chart('rich-label-colour', 'axisLabel colour: the primary inherits it', line(SPANS.days, true, { axisLabel: { color: '#336699' } }));
chart('rich-label-bold', 'axisLabel fontWeight bold with a light primary', line(SPANS.days, true, { axisLabel: { fontWeight: 'bold', rich: { primary: { fontWeight: 'lighter' } } } }));
chart('rich-root-colour', 'root textStyle colour: a free text\'s rich takes it', line(SPANS.days, true, null, { textStyle: { color: '#aa0000' } }));
chart('rich-inherit-off', 'richInheritPlainLabel false', line(SPANS.days, true, { axisLabel: { fontSize: 15, richInheritPlainLabel: false } }));
chart('rich-false', 'rich false: the default stays out, the tag is text', line(SPANS.days, true, { axisLabel: { rich: false } }));
chart('rich-null', 'rich null: likewise', line(SPANS.days, true, { axisLabel: { rich: null } }));
// the machine's clock: zone-less strings, useUTC off
const local = (a, b, axis) => {
  const o = line([0, 1], false, axis);
  o.series[0].data = [[a, 1], [b, 2]];
  return o;
};
chart('local-days', 'useUTC off, zone-less strings', local('2024-01-20', '2024-02-12'));
chart('local-hours', 'useUTC off, zone-less strings, hours', local('2024-03-01 05:00', '2024-03-03 19:00'));
chart('local-newyear-dict', 'useUTC off, a dictionary', local('2023-12-20', '2024-02-10', { axisLabel: { formatter: { year: '{yyyy}', month: ['{MMMM}', '{primary|{MMMM}}'] } } }));
chart('utc-z-strings', 'useUTC on, Z strings', (() => {
  const o = line([0, 1], true);
  o.series[0].data = [['2024-03-01T05:00:00Z', 1], ['2024-03-03T19:00:00Z', 2]];
  return o;
})());

function collectTexts(root, out) {
  if (root.isGroup) {
    root.eachChild(ch => collectTexts(ch, out));
    return out;
  }
  if (root.type === 'text') out.push(root);
  return out;
}
function runChart(c) {
  const ch = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    ch.setOption(clone(c.option));
    ch.getZr().storage.getDisplayList(true);
    const am = ch.getModel().getComponent(c.axis + 'Axis', 0);
    must(am.axis.type === 'time', c.id + ': the axis is not a time axis');
    const views = am.axis.getViewLabels();
    const els = collectTexts(ch.getViewOfComponentModel(am).group, []);
    const labels = views.map(l => {
      const el = els.find(t => t.anid === 'label_' + l.tick.value);
      must(el, c.id + ': no Text for the label at ' + l.tick.value);
      must(el.style.text === l.formattedLabel, c.id + ': the Text says ' + JSON.stringify(el.style.text));
      must(!!el.style.rich || /^rich-(false|null)$/.test(c.id), c.id + ': a time axis label without rich');
      const pieces = el.childrenRef().map(p => {
        if (p.type === 'tspan') {
          return { kind: 'text', text: p.style.text, fontWeight: p.style.fontWeight == null ? null : p.style.fontWeight,
            fontSize: p.style.fontSize == null ? null : p.style.fontSize, font: p.style.font,
            fill: p.style.fill == null ? null : p.style.fill, align: p.style.textAlign,
            x: hex(p.style.x), xText: text(p.style.x), y: hex(p.style.y), yText: text(p.style.y) };
        }
        must(p.type === 'rect', c.id + ': a ' + p.type + ' piece');
        return { kind: 'rect', x: hex(p.shape.x), y: hex(p.shape.y), width: hex(p.shape.width),
          height: hex(p.shape.height), rectText: [p.shape.x, p.shape.y, p.shape.width, p.shape.height].map(text).join(' '),
          fill: p.style.fill == null ? null : p.style.fill };
      });
      return {
        value: hex(l.tick.value), valueText: text(l.tick.value),
        level: l.tick.time ? l.tick.time.level : null,
        unit: l.tick.time ? l.tick.time.lowerTimeUnit : null,
        upper: l.tick.time ? l.tick.time.upperTimeUnit : null,
        notNice: !!l.tick.notNice,
        text: l.formattedLabel, shown: !el.ignore, rich: !!el.style.rich, pieces,
      };
    });
    return { id: c.id, note: c.note, W, H, option: clone(c.option), axis: c.axis,
      utc: !!c.option.useUTC, formatter: clone(am.get(['axisLabel', 'formatter'])), labels };
  } finally {
    ch.dispose();
  }
}

// ---------------------------------------------------------------------------
// the tooltip
// ---------------------------------------------------------------------------
const TT = d => Date.UTC(2024, 2, d, 6);
const TIPS = [];
function tip(id, note, option, at) {
  TIPS.push({ id, note, option, at });
}
const tlData = [[TT(1), 5], [TT(2), 7], [TT(3), 9]];
const tl = (tooltip, extra) => Object.assign({ animation: false, useUTC: true, tooltip: Object.assign({ renderMode: 'richText' }, tooltip),
  xAxis: { type: 'time' }, yAxis: { type: 'value' }, series: [{ type: 'line', name: 'S', data: tlData }] }, extra || {});
tip('axis-tokens', 'every token in an axis-trigger template', tl({ trigger: 'axis', formatter: ALL }), 1);
tip('axis-clash', '{a} {d} {e} are time tokens first; {a0} {b} {c} are left to formatTpl', tl({ trigger: 'axis', formatter: '{yyyy}-{MM}-{dd} {HH} {a} {a0} {b} {c} {d} {e}' }), 1);
tip('axis-pm', 'the afternoon', tl({ trigger: 'axis', formatter: '{h}:{mm} {A} / {a}' }, { series: [{ type: 'line', name: 'S', data: [[Date.UTC(2024, 2, 1, 15, 30), 1], [Date.UTC(2024, 2, 1, 16, 45), 2], [Date.UTC(2024, 2, 1, 18), 3]] }] }), 1);
tip('axis-y-time', 'the time axis is y', Object.assign(tl({ trigger: 'axis', formatter: '{a}|{A}|{yyyy}|{MMMM}' }), {
  xAxis: { type: 'value' }, yAxis: { type: 'time' },
  series: [{ type: 'line', name: 'S', data: [[1, Date.UTC(2024, 0, 1)], [2, Date.UTC(2024, 5, 1)], [3, Date.UTC(2024, 8, 1)]] }] }), 1);
tip('axis-local', 'useUTC off, zone-less strings', Object.assign(tl({ trigger: 'axis', formatter: '{yyyy}/{M}/{d} {H}:{mm} {eeee}' }), {
  useUTC: false, series: [{ type: 'line', name: 'S', data: [['2024-03-01 06:00', 5], ['2024-03-02 18:30', 7], ['2024-03-03 06:00', 9]] }] }), 1);
tip('axis-value-axis', 'a value base axis: no time format', Object.assign(tl({ trigger: 'axis', formatter: '{yyyy} {a} {c}' }), {
  xAxis: { type: 'value' }, series: [{ type: 'line', name: 'S', data: [[1, 5], [2, 7], [3, 9]] }] }), 1);
tip('item-template', 'an item trigger is never time formatted', Object.assign(tl({ trigger: 'item', formatter: '{yyyy} {a} {c}' }), {
  series: [{ type: 'scatter', name: 'S', data: tlData }] }), 1);
tip('axis-header-hours', 'the default content: the header at second precision', tl({ trigger: 'axis' }), 1);
tip('axis-header-months', 'the header at day precision', Object.assign(tl({ trigger: 'axis' }), {
  series: [{ type: 'line', name: 'S', data: [[Date.UTC(2024, 0, 1), 1], [Date.UTC(2024, 5, 1), 2], [Date.UTC(2024, 8, 1), 3]] }] }), 1);
tip('item-readable', 'a time dimension in an item tooltip: makeValueReadable', Object.assign(tl({ trigger: 'item' }), {
  series: [{ type: 'scatter', name: 'S', encode: { x: 0, y: 1, tooltip: [0, 1] }, data: tlData }] }), 1);

let tipProto = null;
function newTipChart() {
  const c = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  c._ssr = false;
  return c;
}
function withTooltips(fn) {
  const probe = newTipChart();
  tipProto = Object.getPrototypeOf(probe);
  probe.dispose();
  const hadOwn = Object.prototype.hasOwnProperty.call(tipProto, 'getDom');
  const oldGetDom = tipProto.getDom;
  const oldNode = echarts.env.node;
  const dom = {};
  tipProto.getDom = function () { return dom; };
  echarts.env.node = false;
  try {
    return fn();
  } finally {
    if (hadOwn) tipProto.getDom = oldGetDom;
    else delete tipProto.getDom;
    echarts.env.node = oldNode;
  }
}
// the default markup's style names carry a process-wide counter
const normHtml = h => String(h).replace(/\{__EC_aUTo_\d+\|/g, '{_|');
const RICH_TOKEN = /\{([a-zA-Z0-9_]+)\|([^}]*)\}/g;
function tokenTexts(html) {
  const out = [];
  String(html).replace(RICH_TOKEN, (m, n, t) => { if (t !== '') out.push(t); return m; });
  return out;
}
function runTipOnce(c, probe) {
  const ch = newTipChart();
  try {
    const opt = clone(c.option);
    let header = null;
    if (probe) {
      opt.tooltip.formatter = function (params) {
        const p0 = Array.isArray(params) ? params[0] : params;
        header = p0 && p0.axisValueLabel != null ? String(p0.axisValueLabel) : null;
        return 'probe';
      };
    }
    ch.setOption(opt);
    ch.renderToSVGString();
    const m = ch.getModel().getComponent('tooltip', 0);
    const view = ch.getViewOfComponentModel(m);
    const content = view._tooltipContent;
    must(content, c.id + ': no tooltip content');
    let html = null;
    const orig = content.setContent;
    content.setContent = function (h) { html = h; return orig.apply(this, arguments); };
    const s = ch.getModel().getSeriesByIndex(0);
    const d = s.getData().getValues(['x', 'y'].map(dim => s.getData().mapDimension(dim)), c.at);
    const px = ch.convertToPixel({ seriesIndex: 0 }, d).map(Math.round);
    ch.dispatchAction({ type: 'showTip', x: px[0], y: px[1] });
    must(html != null, c.id + ': nothing was shown');
    return { html, header, px };
  } finally {
    ch.dispose();
  }
}
function runTip(c) {
  return withTooltips(() => {
    const a = runTipOnce(c, false);
    const b = runTipOnce(c, true);
    must(a.px[0] === b.px[0] && a.px[1] === b.px[1], c.id + ': the two runs aimed at different pixels');
    const trig = c.option.tooltip.trigger;
    return { id: c.id, note: c.note, option: clone(c.option), px: a.px, trigger: trig,
      formatter: c.option.tooltip.formatter == null ? null : c.option.tooltip.formatter,
      html: normHtml(a.html), texts: c.option.tooltip.formatter == null ? tokenTexts(a.html) : null,
      header: trig === 'axis' ? b.header : null };
  });
}

// ---------------------------------------------------------------------------
// guards
// ---------------------------------------------------------------------------
function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  guard('the dist replaces the 24 tokens in the transcription\'s order', JSON.stringify(DIST_TOKENS) === JSON.stringify(TOKENS));
  guard('the dist\'s seed is the transcription\'s', JSON.stringify(DIST_TIME.defaultFormatterSeed) === JSON.stringify(SEED));
  guard('the dist\'s units are the transcription\'s', JSON.stringify(DIST_TIME.primaryTimeUnits) === JSON.stringify(UNITS));
  // format
  let bad = out.format.filter(f => {
    const want = tFormat(tParseNum(Number(f.msText === '-0' ? -0 : f.msText)), f.tpl, f.utc);
    return want !== f.out;
  });
  guard('format: every case is the transcription (' + bad.map(b => b.id).join(',') + ')', bad.length === 0);
  const F = id => out.format.find(f => f.id === id).out;
  guard('a token inside braces is still replaced', F('edge3-tue') === '{x2024}');
  guard('midnight is hour 0 on the 12-hour clock too', F('tok-h-midnight') === '0' && F('tok-hh-midnight') === '00');
  guard('noon is 12 and pm', F('tok-h-noon') === '12' && F('tok-a-noon') === 'pm');
  guard('the year is not padded, yy is', F('tok-yyyy-y5') === '5' && F('tok-yy-y5') === '05' && F('tok-yy-y2000') === '00');
  guard('an invalid date names undefined months and is am', F('invalid-nan').split('|')[5] === 'undefined' && F('invalid-nan').split('|')[0] === 'am');
  guard('a half rounds up, -0.5 to 0', F('round-half-up').endsWith('.001') && F('round-neg-half') === '1970-01-01 00:00:00.000');
  guard('unknown tokens stay', out.format.filter(f => f.id.startsWith('unknown')).every(f => f.out === f.tpl));
  guard('$ patterns in the template are literal', F('edge22-tue') === '%2024$&03$1');
  // dict
  bad = out.dict.filter(d => {
    if (d.kind !== 'dict') return false;
    const t = tDict('formatter' in d ? d.formatter : undefined);
    return JSON.stringify(t.dict).replace(/null/g, '"~"') !== JSON.stringify(d.dict).replace(/null/g, '"~"') || t.hl !== d.highlight;
  });
  guard('dict: every case is the transcription (' + bad.map(b => b.id).join(',') + ')', bad.length === 0);
  const D = id => out.dict.find(d => d.id === id);
  guard('the default adds the primary', D('default').dict.month.month[1] === '{primary|{MMM}}');
  guard('any unit written takes the primary away', D('day').dict.month.month.length === 1);
  guard('null keeps it, none is no unit', D('day-null').highlight && D('day-undefined-none').highlight);
  guard('a string entry is every upper unit\'s',D('hour-cascade').dict.hour.day[0] === '{H}h' && D('hour-cascade').dict.hour.year[0] === '{H}h');
  guard('the cascade prefixes the upper unit', D('nested').dict.day.year[0] === '{yyyy} {MMM} {d}' && D('nested').dict.day.year.length === 1);
  guard('an empty upper array cascades as undefined', D('year-empty-array').dict.month.year[0] === 'undefined {MMM}');
  guard('a falsy first entry carries up as empty', D('nested-null-first').dict.day.month[0] === '{MMM} ');
  guard('a string is a template, not a dictionary', D('string').kind === 'string' && D('empty-string').kind === 'string');
  // charts
  const dictOf = f => DIST_TIME.parseTimeAxisLabelFormatter(clone(f));
  bad = [];
  for (const c of out.charts) {
    const f = dictOf(c.formatter);
    for (const l of c.labels) {
      let tpl;
      if (typeof f === 'string') tpl = f;
      else {
        const arr = f[l.unit][l.upper];
        tpl = arr[Math.min(l.level, arr.length - 1)] || '';
      }
      if (tFormat(new Date(Number(l.valueText)), tpl, c.utc) !== l.text) bad.push(c.id + '@' + l.valueText);
      if (l.unit !== l.upper) bad.push(c.id + ' break tick');
    }
  }
  guard('charts: every label is dict[unit][unit][min(level, len - 1)] formatted (' + bad.slice(0, 5).join(',') + ')', bad.length === 0);
  const C = id => out.charts.find(c => c.id === id);
  const prim = c => c.labels.filter(l => l.text.indexOf('{primary|') >= 0);
  guard('the default marks the coarser levels with the primary', ['default-days', 'default-months', 'default-hours', 'default-newyear']
    .every(id => prim(C(id)).length > 0 && prim(C(id)).every(l => l.level >= 1) && C(id).labels.filter(l => l.level >= 1).every(l => l.text.indexOf('{primary|') === 0)));
  guard('the primary piece is bold by default', prim(C('default-days')).every(l => l.pieces.some(p => p.kind === 'text' && p.fontWeight === 'bold')));
  guard('a string formatter has no primary', prim(C('string-plain')).length === 0);
  guard('a dictionary with any unit has no primary', prim(C('dict-day')).length === 0 && prim(C('dict-full')).length === 0);
  guard('three levels reach the third entry', C('dict-levels-three').labels.some(l => l.level === 2 && l.text.indexOf('{b|') === 0));
  guard('the unknown style name draws its text plain', C('string-unknown-style').labels.every(l => l.pieces.length === 1 && l.pieces[0].fontWeight == null));
  guard('the not-nice ends are hidden by default', C('default-days').labels.filter(l => l.notNice).every(l => !l.shown));
  guard('a millisecond unit appears on the shown ends', C('default-ms-ends').labels.some(l => l.unit === 'millisecond' && l.shown));
  guard('every level appears somewhere', UNITS.every(u => out.charts.some(c => c.labels.some(l => l.unit === u))));
  guard('the primary takes the root colour', prim(C('rich-root-colour')).every(l => l.pieces.some(p => p.kind === 'text' && p.fill === '#aa0000')));
  guard('a rich that is not an object keeps the tag as text', ['rich-false', 'rich-null'].every(id => prim(C(id)).every(l => l.pieces.length === 1 && l.pieces[0].text === l.text)));
  guard('the primary inherits the label colour', prim(C('rich-label-colour')).every(l => l.pieces.some(p => p.kind === 'text' && p.fill === '#336699')));
  // tooltip
  const T = id => out.tooltip.find(t => t.id === id);
  guard('{a} under a time axis is am / pm', T('axis-clash').html.indexOf(' am S ') > 0);
  guard('an item trigger keeps the tokens', T('item-template').html.indexOf('{yyyy}') === 0);
  guard('a value base axis keeps the tokens', T('axis-value-axis').html.indexOf('{yyyy}') === 0);
  guard('the header is second precision over hours', T('axis-header-hours').header === '2024-03-02 06:00:00');
  guard('the header is day precision over months', T('axis-header-months').header === '2024-06-01');
  guard('a time dimension reads as a date', T('item-readable').texts.some(s => s.indexOf('2024-03-02 06:00:00') === 0));
  // zone independence
  const prev = process.env.TZ;
  process.env.TZ = 'Asia/Shanghai';
  let zoned = [];
  try {
    must(new Date(2017, 0, 1).getTimezoneOffset() === -480, 'TZ = Asia/Shanghai did not take effect');
    // what a label says, not where its instant is: a zone-less string is a
    // different instant at UTC+8 and the same wall clock
    const said = c => JSON.stringify(c.labels.map(l => [l.text, l.shown, l.level, l.unit, l.notNice,
      l.pieces.map(p => Object.assign({}, p, { fill: null }))]));
    zoned = CHARTS.map(runChart).filter((c, i) => said(c) !== said(out.charts[i])).map(c => c.id)
      .concat(TIPS.map(runTip).filter((t, i) => JSON.stringify(t) !== JSON.stringify(out.tooltip[i])).map(t => t.id));
  } finally {
    process.env.TZ = prev;
  }
  must(new Date(2017, 0, 1).getTimezoneOffset() === 0, 'TZ = UTC did not come back');
  guard('every chart and tooltip is the same at UTC+8 (' + zoned.join(',') + ')', zoned.length === 0);
  return g;
}

function generate() {
  const out = {
    source: DIST, version: echarts.version, tz: 'UTC',
    notes: [
      'format: echarts.time.format, the dist\'s public util/time.ts format. utc false reads the machine clock, UTC here.',
      'dict: parseTimeAxisLabelFormatter cut out of the dist bundle and run on its own.',
      'charts: axis.getViewLabels(); the Text found by anid label_<value>; pieces are its children after storage.getDisplayList(true).',
      'tooltip: TooltipView with env.node off and getDom stubbed; html is what it handed TooltipRichContent.setContent; header comes from a second run whose formatter is a probe function.',
    ],
    tokens: DIST_TOKENS.slice(),
    constants: { seed: clone(DIST_TIME.defaultFormatterSeed), full: clone(DIST_TIME.fullLeveledFormatter) },
    format: FORMAT.map(runFormat),
    dict: DICTS.map(runDict),
    charts: CHARTS.map(runChart),
    tooltip: TIPS.map(runTip),
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
if (process.env.ORACLE_FORCE) fs.writeFileSync(OUT, json1);
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name));
const deterministic = json1 === json2;
console.log(out1.format.length + ' format, ' + out1.dict.length + ' dict, ' + out1.charts.length + ' charts, '
  + out1.tooltip.length + ' tooltip cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
