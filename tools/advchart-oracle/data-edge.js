/*
Upstream's own answers for fix batch R2-G (spec section 224): the data edges
the port used to read its own way.

  tree     SunburstSeries' / TreemapSeries' completeTreeValue (post-order,
           `sum += childValue` from the NUMBER 0, so a string value turns the
           rest of the sum into a concatenation; the node's own value stands
           unless `== null` or isNaN, and is 0 when `< 0`), then the store's
           parseDataValue of what it left. Per data index: name, the store
           value, the raw value (getRawValue, what a label's {c} prints), the
           label text, and the sector (startAngle / endAngle / r0 / r) or the
           treemap rect.
  vmdim    a visualMap on a dimension no axis reads: the store holds it as
           upstream's dimension type has it (a guessed or declared ordinal
           keeps the text, an 'int' is an Int32Array, anything else a
           Number()); per item the store value and the fill the visual gives.
  calmargin  calendar month / year label margins written as strings: `y +
           margin` concatenates ('240' + '5' is 2405) where the label is past
           the end, `y - margin` and `-margin` read a number; dayLabel goes
           through parsePercent (parseFloat). Per label: text and the final
           global anchor.
  intdim   a dimension declared 'int': an axis' coordinate dimension is the
           axis' type (float, no truncation); any other is an Int32Array
           (ToInt32: NaN and +-Infinity are 0, the fraction dropped, 2^32
           wraps). Per item the store values and, through a continuous
           visualMap on the int dimension, the fill.
  timeinf  a time dimension holding +-Infinity (1e400 in the JSON): kept by
           parseDataValue (a number is not parsed), the extent unions skip
           it, the axis is blank when nothing finite is left.
  logbase  a log axis' logBase: `setting.logBase || 10`, so 0 / null / ''
           are 10 and 1, 0.5, -2, 'abc' are used as written. Per case the
           scale's extent, its ticks, the labels and the points.
  tz       local time in a zone with history: run in a child process with
           TZ=<zone>; per case the zone's offset transitions over the years
           the case touches (utc ms, offset minutes) and what the chart
           reads from local date strings: the store values (Date.parse) and
           the time axis' ticks and labels.

Numbers are 16 lowercase hex digits of the IEEE double (big-endian) with a
readable twin. Runs twice; the two outputs must be byte-identical. Ends with
process.exit().

  node tools/advchart-oracle/data-edge.js
*/
'use strict';
process.env.TZ = process.env.DATA_EDGE_TZ || 'UTC';
const fs = require('fs');
const path = require('path');
const childProcess = require('child_process');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-data-edge.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  if (Number.isNaN(v)) return '7ff8000000000000';
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));
function num(v) {
  return { n: hex(v), t: text(v) };
}
// a raw value as JSON can hold it: a number its num(), anything else as is
function rawRec(v) {
  if (v === undefined) return '<undef>';
  if (typeof v === 'number') return num(v);
  if (Array.isArray(v)) return v.map(rawRec);
  return v;
}

function newChart() {
  return echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
}

const CASES = [];
function add(group, id, note, option, extra) {
  CASES.push(Object.assign({ group, id, note, option }, extra || {}));
}

// ---------- tree: completeTreeValue ----------
const treeCase = (id, note, type, data, extra) => add('tree', id, note,
  { animation: false, series: [Object.assign({ type, sort: null, label: { formatter: '{b}: {c}' }, data }, extra || {})] });
treeCase('t-concat', "'5' and '3' under S concatenate to '053' (53), the root to '00538'", 'sunburst',
  [{ name: 'S', children: [{ name: 's1', value: '5' }, { name: 's2', value: '3' }] }, { name: 'U', value: '8' }]);
treeCase('t-concat-treemap', 'the same tree as a treemap: the same code, the rects by 53 and 8', 'treemap',
  [{ name: 'S', children: [{ name: 's1', value: '5' }, { name: 's2', value: '3' }] }, { name: 'U', value: '8' }],
  { label: { show: true, formatter: '{b}: {c}' }, breadcrumb: { show: false } });
treeCase('t-bool', "a word that is no number takes the sum (0); true stays true and adds as 1", 'sunburst',
  [{ name: 'A', children: [{ name: 'a1', value: 'x' }, { name: 'a2', value: 2 }] }, { name: 'B', value: true },
    { name: 'C', children: [{ name: 'c1', value: 2 }, { name: 'c2', value: true }] }]);
treeCase('t-array', "a negative string is 0; an array's first entry is the value and adds as text", 'sunburst',
  [{ name: 'A', value: '-3' }, { name: 'B', children: [{ name: 'b', value: ['4', 9] }, { name: 'b2', value: 1 }] }]);
treeCase('t-number-then-string', 'a number then a string: 1.5 + \'2\' is \'1.52\'', 'sunburst',
  [{ name: 'P', children: [{ name: 'p1', value: 1.5 }, { name: 'p2', value: '2' }] }, { name: 'Q', value: 10 }]);
treeCase('t-empty', "an empty string is no NaN (it stays ''), the store reads NaN; its parent '0' + more", 'sunburst',
  [{ name: 'E', children: [{ name: 'e1', value: '' }, { name: 'e2', value: 4 }] }, { name: 'F', value: 3 }]);
treeCase('t-own', "a parent's own value wins over its children's concatenation", 'sunburst',
  [{ name: 'G', value: 6, children: [{ name: 'g1', value: '1' }, { name: 'g2', value: '2' }] }, { name: 'H', value: 2 }]);

// ---------- vmdim: a visualMap on a dimension no axis reads ----------
// the third column guessed ordinal (its first value a word): the store keeps
// what was written and the visual's own arithmetic reads it -- '' and null
// are 0, true 1, ' 2 ' 2, a word not a number
const VM_ROWS = [[1, 2, 'b'], [3, 4, ''], [5, 6, ' 2 '], [7, 8, true], [9, 1, null], [2, 2, '1e0'], [3, 3, 'a']];
// the same column, its first value a number: a float, parsed as data is
const VM_ROWS_NUM = [[0, 0, 1]].concat(VM_ROWS);
const vmCase = (id, note, vm, rows, dims) => add('vmdim', id, note,
  { animation: false, xAxis: { type: 'value' }, yAxis: { type: 'value' }, visualMap: Object.assign({ dimension: 2 }, vm),
    series: [Object.assign({ type: 'scatter', data: rows }, dims ? { dimensions: dims } : {})] });
const CONT = { type: 'continuous', min: 0, max: 2, inRange: { color: ['#000000', '#ffffff'] } };
const PIECE = { type: 'piecewise', pieces: [{ min: 0, max: 1 }, { min: 1, max: 3 }], inRange: { color: ['#ff0000', '#00ff00'] } };
vmCase('v-cont-ordinal', 'continuous on a guessed-ordinal column: the written values, JS arithmetic', CONT, VM_ROWS);
vmCase('v-cont-float', "continuous on the same column with a number first: parsed as data, a word, '' and null not numbers", CONT, VM_ROWS_NUM);
vmCase('v-piece-ordinal', 'piecewise pieces on the guessed-ordinal column', PIECE, VM_ROWS);
vmCase('v-cont-declared', "continuous on a column declared 'ordinal'", CONT, VM_ROWS_NUM, ['x', 'y', { name: 'k', type: 'ordinal' }]);

// ---------- intdim: a dimension declared 'int' ----------
// in the option text: 1e400 is Infinity, which JSON cannot write
add('intdim', 'i-axis-and-off', "x declared 'int' on a value axis (float there), k declared 'int' off the axes (an Int32Array)", null,
  { optionText: '{"animation":false,"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"visualMap":{"type":"continuous","dimension":2,"min":-3,"max":3,"inRange":{"color":["#000000","#ffffff"]}},'
    + '"series":[{"type":"scatter","dimensions":[{"name":"x","type":"int"},"y",{"name":"k","type":"int"}],'
    + '"data":[[1.7,1,1.7],[-2.7,2,-2.7],[3.5,3,4294967297],[4,4,"abc"],[5,5,null],[6,6,1e400],[7,7,2147483649],[8,8,"2.9"]]}]}' });
add('intdim', 'i-dataset', "a dataset's 'int' column off the axes", null,
  { optionText: '{"animation":false,"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"dataset":{"dimensions":["x","y",{"name":"k","type":"int"}],"source":[[1,1,0.9],[2,2,-0.9],[3,3,2.5],[4,4,-3.5]]},'
    + '"visualMap":{"type":"continuous","dimension":2,"min":-3,"max":3,"inRange":{"color":["#000000","#ffffff"]}},'
    + '"series":[{"type":"scatter"}]}' });

// ---------- timeinf: +-Infinity on a time dimension ----------
const tiCase = (id, note, rows) => add('timeinf', id, note, null, {
  optionText: '{"animation":false,"xAxis":{"type":"time"},"yAxis":{"type":"value"},"series":[{"type":"scatter","data":' + rows + '}]}' });
tiCase('ti-plus', 'one +Infinity among finite times: kept, and the axis is blank (today)', '[[0,1],[86400000,3],[1e400,2]]');
tiCase('ti-minus', 'one -Infinity', '[[0,1],[86400000,3],[-1e400,2]]');
tiCase('ti-string', "the word 'Infinity' on a time dimension is no date: NaN, the axis keeps its data", '[[0,1],[86400000,3],["Infinity",2]]');

// ---------- logbase ----------
// [deviation] a base the logarithm cannot use: upstream's answer is recorded,
// and the port keeps ten on purpose (the test holds it to lb-null's record)
const LB_DEV = 'upstream misbehaves (every value at one tick, points off the grid or none); the port keeps base 10';
const lbCase = (id, note, lb, deviation) => add('logbase', id, note, { animation: false, xAxis: { type: 'value' },
  yAxis: Object.assign({ type: 'log' }, lb === undefined ? {} : { logBase: lb }),
  series: [{ type: 'scatter', data: [[1, 1], [2, 10], [3, 1000]] }] }, deviation ? { deviation } : {});
lbCase('lb-1', 'logBase 1: log(1) is 0', 1, LB_DEV);
lbCase('lb-half', 'logBase 0.5', 0.5, LB_DEV);
lbCase('lb-zero', 'logBase 0 is falsy: `|| 10`', 0);
lbCase('lb-neg', 'logBase -2', -2, LB_DEV);
lbCase('lb-word', "logBase 'abc': a string base, Math.log of it NaN", 'abc', LB_DEV);
lbCase('lb-numword', "logBase '2': the string, read as a number by the arithmetic", '2');
lbCase('lb-null', 'logBase null: 10', null);
lbCase('lb-two', 'logBase 2, the control', 2);


// ---------- calmargin: calendar label margins written as strings ----------
const cmCase = (id, note, cal) => add('calmargin', id, note, { animation: false,
  calendar: Object.assign({ range: '2017-02', top: 100, left: 100, cellSize: 20 }, cal) });
const NO_YEAR = { show: false };
const NO_MONTH = { show: false };
const NO_DAY = { show: false };
cmCase('cm-month-end', "month labels past the end, margin '5': y + '5' concatenates, then the span's y + 6 again",
  { monthLabel: { margin: '5', position: 'end' }, yearLabel: NO_YEAR, dayLabel: NO_DAY });
cmCase('cm-month-end-v', "vertical, month labels past the end, margin '5': the x concatenates",
  { orient: 'vertical', monthLabel: { margin: '5', position: 'end' }, yearLabel: NO_YEAR, dayLabel: NO_DAY });
cmCase('cm-month-start', "month labels at the start, margin '5': -'5' is -5",
  { monthLabel: { margin: '5', position: 'start' }, yearLabel: NO_YEAR, dayLabel: NO_DAY });
cmCase('cm-month-end-word', "margin 'abc' past the end: not a number, nothing drawn",
  { monthLabel: { margin: 'abc', position: 'end' }, yearLabel: NO_YEAR, dayLabel: NO_DAY });
cmCase('cm-month-end-centre', "past the end and centred, margin '5'",
  { monthLabel: { margin: '5', position: 'end', align: 'center' }, yearLabel: NO_YEAR, dayLabel: NO_DAY });
cmCase('cm-year-bottom', "the year at the bottom, margin '5': y + '5'",
  { yearLabel: { margin: '5', position: 'bottom' }, monthLabel: NO_MONTH, dayLabel: NO_DAY });
cmCase('cm-year-right', "the year at the right, margin '5': x + '5', turned",
  { yearLabel: { margin: '5', position: 'right' }, monthLabel: NO_MONTH, dayLabel: NO_DAY });
cmCase('cm-year-top', "the year at the top, margin '5': y - '5'",
  { yearLabel: { margin: '5', position: 'top' }, monthLabel: NO_MONTH, dayLabel: NO_DAY });
cmCase('cm-year-left', "the year at the left, margin '7': x - '7', turned",
  { yearLabel: { margin: '7', position: 'left' }, monthLabel: NO_MONTH, dayLabel: NO_DAY });
cmCase('cm-day-px', "dayLabel margin '5px': parsePercent's parseFloat, 5",
  { dayLabel: { margin: '5px' }, yearLabel: NO_YEAR, monthLabel: NO_MONTH });
cmCase('cm-day-word', "dayLabel margin 'center': parsePercent's 50% of the smaller cell side",
  { dayLabel: { margin: 'center', position: 'end' }, yearLabel: NO_YEAR, monthLabel: NO_MONTH });

// ---------- reading ----------
function readTree(chart, c) {
  const s = chart.getModel().getSeriesByIndex(0);
  const d = s.getData();
  const rows = [];
  for (let i = 0; i < d.count(); i++) {
    const el = d.getItemGraphicEl(i);
    const lay = d.getItemLayout(i);
    const t = el && el.getTextContent ? el.getTextContent() : null;
    const row = { i, name: d.getName(i), value: num(d.get('value', i)), raw: rawRec(s.getRawValue(i)),
      label: t && !t.ignore && t.style.text != null ? String(t.style.text) : null };
    if (lay && lay.startAngle !== undefined) {
      row.sector = { startAngle: num(lay.startAngle), endAngle: num(lay.endAngle), r0: num(lay.r0), r: num(lay.r) };
    } else if (lay && lay.width !== undefined) {
      row.rect = { x: num(lay.x), y: num(lay.y), width: num(lay.width), height: num(lay.height) };
    }
    rows.push(row);
  }
  return { rows };
}

const zrColor = echarts.color;
function fillRec(c) {
  if (c == null) return null;
  const p = zrColor.parse(c);
  must(p, 'unparsed colour ' + c);
  return { r: p[0], g: p[1], b: p[2], a: num(p[3]) };
}

// per data item: the store's value in every store dimension, whether the
// symbol is drawn, its fill, its layout
function readItems(chart) {
  const s = chart.getModel().getSeriesByIndex(0);
  const d = s.getData();
  const items = [];
  for (let i = 0; i < d.count(); i++) {
    const el = d.getItemGraphicEl(i);
    const sym = el && el.childAt ? el.childAt(0) : null;
    const vals = [];
    for (const dn of d.dimensions) vals.push(rawRec(d.get(dn, i)));
    const lay = d.getItemLayout(i);
    items.push({ i, store: vals, drawn: !!(sym && !sym.invisible && !el.invisible && sym.style.fill != null),
      fill: sym ? fillRec(sym.style.fill) : null,
      layout: lay ? [rawRec(lay[0]), rawRec(lay[1])] : null });
  }
  return { dimTypes: d.dimensions.map(n => d.getDimensionInfo(n).type), items };
}

function readAxis(chart, main) {
  const ax = chart.getModel().getComponent(main, 0).axis;
  const sc = ax.scale;
  return { blank: sc.isBlank(), extent: sc.getExtent().map(num),
    ticks: sc.getTicks().map(t => num(t.value)),
    labels: ax.getViewLabels().map(l => ({ value: num(l.tick ? l.tick.value : l.tickValue), text: l.formattedLabel })) };
}

// every text of the calendar: its words, its alignment, and where its
// (one) span's middle lands -- the span's x / y and the text's transform,
// each read as a number (concatenations included)
function readCalTexts(chart) {
  const m = chart.getModel().getComponent('calendar', 0);
  const g = chart.getViewOfComponentModel(m).group;
  chart.getZr().storage.getDisplayList(true);
  const texts = [];
  g.traverse(el => {
    if (el.type !== 'text') return;
    const kids = el.childrenRef ? el.childrenRef() : [];
    must(kids.length <= 1, 'a calendar text with ' + kids.length + ' spans');
    let pt = null;
    if (kids.length) {
      const sx = Number(kids[0].style.x);
      const sy = Number(kids[0].style.y);
      const t = el.transform ? el.transform.map(Number) : [1, 0, 0, 1, 0, 0];
      pt = [num(t[0] * sx + t[2] * sy + t[4]), num(t[1] * sx + t[3] * sy + t[5])];
    }
    texts.push({ text: String(el.style.text), align: el.style.align || null,
      verticalAlign: el.style.verticalAlign || null, rotation: num(el.rotation || 0), mid: pt });
  });
  return { texts };
}

function readCase(c) {
  const chart = newChart();
  try {
    chart.setOption(c.option || JSON.parse(c.optionText));
    const rec = { group: c.group, id: c.id, note: c.note, W, H };
    if (c.deviation) rec.deviation = c.deviation;
    if (c.option) rec.option = c.option;
    else rec.optionText = c.optionText;
    if (c.group === 'tree') Object.assign(rec, readTree(chart, c));
    else if (c.group === 'vmdim' || c.group === 'intdim') Object.assign(rec, readItems(chart, c));
    else if (c.group === 'calmargin') Object.assign(rec, readCalTexts(chart));
    else if (c.group === 'timeinf') {
      Object.assign(rec, readItems(chart, c));
      // today's extent changes from day to day: only blankness and which
      // points have a place are recorded
      rec.xBlank = readAxis(chart, 'xAxis').blank;
      rec.items.forEach(it => {
        it.placed = !!(it.layout && Number.isFinite(Number(it.layout[0].t)));
        delete it.layout;
      });
    } else if (c.group === 'logbase') {
      rec.yAxis = readAxis(chart, 'yAxis');
      rec.base = rawRec(chart.getModel().getComponent('yAxis', 0).axis.scale.base);
      Object.assign(rec, readItems(chart, c));
    }
    return rec;
  } finally {
    chart.dispose();
  }
}

// ---------- guards ----------
function guards(recs) {
  const g = [];
  const by = id => recs.find(r => r.id === id);
  const check = (name, ok) => { g.push({ name, ok }); };
  const row = (id, nm) => by(id).rows.find(r => r.name === nm);
  check("t-concat: S's raw value is the concatenation '053'", row('t-concat', 'S').raw === '053');
  check("t-concat: S's store value is 53", row('t-concat', 'S').value.t === '53');
  check("t-concat: S's label prints the raw text", row('t-concat', 'S').label === 'S: 053');
  check("t-bool: B stays true, its store value 1", row('t-bool', 'B').raw === true && row('t-bool', 'B').value.t === '1');
  check("t-array: A '-3' is 0", row('t-array', 'A').raw.t === '0');
  check("t-number-then-string: P is '1.52'", row('t-number-then-string', 'P').raw === '1.52');
  check("t-empty: e1 '' stays, its store value NaN", row('t-empty', 'e1').raw === '' && row('t-empty', 'e1').value.t === 'NaN');
  check("t-own: G's own 6 stands", row('t-own', 'G').raw.t === '6');
  const it = (id, i) => by(id).items[i];
  check("v-cont-ordinal: '' is in range (0), black", it('v-cont-ordinal', 1).drawn && it('v-cont-ordinal', 1).fill.r === 0);
  check('v-cont-ordinal: null is in range (0)', it('v-cont-ordinal', 4).drawn);
  check('v-cont-ordinal: a word is drawn by nothing', !it('v-cont-ordinal', 0).drawn);
  check("v-cont-float: '' is not a number there", !it('v-cont-float', 2).drawn);
  check('i-axis-and-off: x 1.7 stays 1.7 on the axis', it('i-axis-and-off', 0).store[0].t === '1.7');
  check('i-axis-and-off: k 1.7 is 1 off the axes', it('i-axis-and-off', 0).store[2].t === '1');
  check('i-axis-and-off: k 4294967297 wraps to 1', it('i-axis-and-off', 2).store[2].t === '1');
  check("i-axis-and-off: k 'abc' and Infinity are 0", it('i-axis-and-off', 3).store[2].t === '0' && it('i-axis-and-off', 5).store[2].t === '0');
  check('i-axis-and-off: k 2147483649 wraps negative', it('i-axis-and-off', 6).store[2].t === '-2147483647');
  check('ti-plus: the axis is blank', by('ti-plus').xBlank === true);
  check('ti-plus: the infinity is kept in the store', it('ti-plus', 2).store[0].t === 'Infinity');
  check("ti-string: the word is NaN, the axis not blank", it('ti-string', 2).store[0].t === 'NaN' && by('ti-string').xBlank === false);
  check('lb-zero: base 10', by('lb-zero').base.t === '10');
  check("lb-word: base 'abc'", by('lb-word').base === 'abc');
  check('lb-1: base 1', by('lb-1').base.t === '1');
  const mid = (id, k) => by(id).texts[k].mid;
  check("cm-month-end: '240' + '5', then + '6': 24056", mid('cm-month-end', 0)[1].t === '24056');
  check('cm-month-start: 100 - 5', mid('cm-month-start', 0)[1].t === '89');
  check("cm-month-end-word: NaN", mid('cm-month-end-word', 0)[1].t === 'NaN');
  check("cm-year-bottom: the year's transform reads '002405'", mid('cm-year-bottom', 0)[1].t === '2415');
  check("cm-day-px: '5px' is 5", by('cm-day-px').texts.length === 7);
  check('tz-years@Asia/Shanghai: 1900-01-01 is read in local mean time (+8:05:43)',
    by('tz-years@Asia/Shanghai').values[0].t === '-2209017943000');
  check('tz-years@Asia/Shanghai: 1988-07-01 12:00 in summer time (+9)',
    by('tz-years@Asia/Shanghai').values[3].t === String(Date.UTC(1988, 6, 1, 3)));
  check('tz-years@Europe/Berlin: the skipped 02:30 reads with the offset before (+1)',
    by('tz-years@Europe/Berlin').values[5].t === String(Date.UTC(2017, 2, 26, 1, 30)));
  check('tz-years@Europe/Berlin: the repeated 02:30 reads with the offset before (+2)',
    by('tz-years@Europe/Berlin').values[6].t === String(Date.UTC(2017, 9, 29, 0, 30)));

  return g;
}

// ---------- tz: local time in a zone with history ----------
// Run in a child process per zone (DATA_EDGE_TZ=<zone>; Git Bash drops a TZ
// passed from outside, so the variable has another name and the script sets
// TZ itself before anything reads a Date).
const TZ_ZONES = ['Asia/Shanghai', 'Europe/Berlin', 'America/New_York'];
const TZ_FROM = Date.UTC(1890, 0, 1);
const TZ_TO = Date.UTC(2031, 0, 1);
// local minus UTC at a UTC instant, to the millisecond (LMT has seconds)
function tzOffset(ms) {
  const d = new Date(ms);
  return Date.UTC(d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), d.getMinutes(),
    d.getSeconds(), d.getMilliseconds()) - ms;
}
// every change of the offset between TZ_FROM and TZ_TO: sampled every six
// hours, each change bisected to the first millisecond of the new offset
function tzTransitions() {
  const out = [{ at: null, off: tzOffset(TZ_FROM) }];
  const STEP = 6 * 3600 * 1000;
  let prev = out[0].off;
  for (let t = TZ_FROM + STEP; t <= TZ_TO; t += STEP) {
    const o = tzOffset(t);
    if (o === prev) continue;
    let lo = t - STEP;
    let hi = t;
    while (hi - lo > 1) {
      const mid = Math.floor((lo + hi) / 2);
      if (tzOffset(mid) === prev) lo = mid; else hi = mid;
    }
    out.push({ at: hi, off: tzOffset(hi) });
    prev = o;
  }
  return out;
}
const TZ_CASES = [
  { id: 'tz-years', note: 'local date strings across the zone\'s history: LMT, war time, summer time, a skipped and a repeated half hour',
    option: { animation: false, xAxis: { type: 'time' }, yAxis: { type: 'value' },
      series: [{ type: 'scatter', data: [['1900-01-01', 1], ['1920-06-01 12:00', 2], ['1942-07-01', 3], ['1988-07-01 12:00', 4],
        ['2017-03-12 02:30', 5], ['2017-03-26 02:30', 6], ['2017-10-29 02:30', 7], ['2017-11-05 01:30', 8], ['2017-07-01', 9]] }] } },
  { id: 'tz-days', note: 'a time axis over the spring change: the ticks at local midnights, their labels',
    option: { animation: false, xAxis: { type: 'time' }, yAxis: { type: 'value' },
      series: [{ type: 'scatter', data: [['2017-03-08', 1], ['2017-03-31', 2]] }] } },
  { id: 'tz-hours', note: 'hours across the autumn change in Berlin: the ticks and their local labels',
    option: { animation: false, xAxis: { type: 'time' }, yAxis: { type: 'value' },
      series: [{ type: 'scatter', data: [['2017-10-28 22:00', 1], ['2017-10-29 06:00', 2]] }] } },
  { id: 'tz-1988', note: 'a time axis over 1988 (Shanghai kept summer time): month ticks and labels',
    option: { animation: false, xAxis: { type: 'time' }, yAxis: { type: 'value' },
      series: [{ type: 'scatter', data: [['1988-01-01', 1], ['1988-12-31', 2]] }] } }
];
// a calendar month across a change: each day's cell centre and the range
const TZ_CALS = [
  { id: 'tz-cal-2017-03', note: 'March 2017 (Berlin and New York change the clocks)', range: '2017-03' },
  { id: 'tz-cal-1988-04', note: 'April 1988 (Shanghai changed its clocks on the 10th)', range: '1988-04' },
  { id: 'tz-cal-1900-01', note: 'January 1900 (local mean time everywhere)', range: '1900-01' }
];
function pad2(n) { return (n < 10 ? '0' : '') + n; }
function tzCalendar(c) {
  const chart = newChart();
  try {
    const option = { animation: false, calendar: { range: c.range, cellSize: 'auto', left: 40, top: 60, right: 40, bottom: 40 } };
    chart.setOption(option);
    const cs = chart.getModel().getComponent('calendar', 0).coordinateSystem;
    const ri = cs.getRangeInfo();
    const days = [];
    const y = +c.range.slice(0, 4);
    const m = +c.range.slice(5, 7);
    const n = new Date(Date.UTC(y, m, 0)).getUTCDate();
    for (let d = 1; d <= n; d++) {
      const text = c.range + '-' + pad2(d);
      const p = chart.convertToPixel({ calendarIndex: 0 }, text);
      days.push({ text, time: num(+echarts.time.parse(text)), point: p.map(num) });
    }
    return { group: 'tz', id: c.id + '@' + process.env.TZ, zone: process.env.TZ, note: c.note, W, H, option,
      calendar: { weeks: num(ri.weeks), allDay: num(ri.allDay), fweek: num(ri.fweek), lweek: num(ri.lweek),
        nthWeek: num(ri.nthWeek), start: num(ri.start.time), end: num(ri.end.time) }, days };
  } finally {
    chart.dispose();
  }
}
function tzChild() {
  const recs = TZ_CASES.map(c => {
    const chart = newChart();
    try {
      chart.setOption(c.option);
      const s = chart.getModel().getSeriesByIndex(0);
      const d = s.getData();
      const values = [];
      for (let i = 0; i < d.count(); i++) values.push(num(d.get(d.mapDimension('x'), i)));
      return { group: 'tz', id: c.id + '@' + process.env.TZ, zone: process.env.TZ, note: c.note, W, H, option: c.option,
        values, xAxis: readAxis(chart, 'xAxis') };
    } finally {
      chart.dispose();
    }
  });
  TZ_CALS.forEach(c => recs.push(tzCalendar(c)));
  return { zone: process.env.TZ, transitions: tzTransitions(), cases: recs };
}
function tzRecords() {
  const zones = [];
  const cases = [];
  for (const zone of TZ_ZONES) {
    const out = childProcess.execFileSync(process.execPath, [__filename],
      { env: Object.assign({}, process.env, { DATA_EDGE_TZ: zone, DATA_EDGE_CHILD: '1' }), maxBuffer: 64 << 20 }).toString();
    const r = JSON.parse(out);
    must(r.zone === zone, 'the child ran in ' + r.zone + ', not ' + zone);
    zones.push({ zone, from: TZ_FROM, to: TZ_TO, transitions: r.transitions });
    r.cases.forEach(x => cases.push(x));
  }
  return { zones, cases };
}
if (process.env.DATA_EDGE_CHILD) {
  process.stdout.write(JSON.stringify(tzChild()));
  process.exit(0);
}

function generate() {
  const recs = CASES.map(readCase);
  const tzr = tzRecords();
  tzr.cases.forEach(x => recs.push(x));
  return { source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version, tz: process.env.TZ, W, H,
    zones: tzr.zones, cases: recs, guards: guards(recs) };
}

let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = out1.guards.filter(x => !x.ok);
out1.guards.forEach(x => console.log('guard ' + (x.ok ? 'ok  ' : 'FAIL') + ' ' + x.name));
const deterministic = json1 === json2;
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic || json1.includes('\\u0000')) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
