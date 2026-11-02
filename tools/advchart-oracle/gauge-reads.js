// Round 7 R7-D: what a gauge READS -- its rows, its 'auto' colours and the
// item keys GaugeView takes from the item's model.
//
//   Its rows (GaugeSeries.getInitialData: createSeriesDataSimply(this,
//     ['value'])). The coordinate dimensions are given as an ARRAY, so no
//     encodeDefine and no encodeDefaulter reach prepareSeriesDataSchema: the
//     `value` dimension is the first one (availDimIdx 0), whatever `encode`
//     says, and no dimension is `itemName` -- a dataset row has no name, only
//     an item object of `data` does. A first column guessOrdinal calls
//     ordinal (or declared 'ordinal') keeps its cells as written (no ordinal
//     meta: DataStore stores the raw value), so the reading is the cell
//     (formatLabel: `value + ''`, null -> '') and the dial maps it with JS
//     arithmetic (`+cell`: 'Rate' NaN -> the start angle, '7' 7, null 0).
//   Its 'auto' colours, with and without bands: getColor walks
//     axisLine.lineStyle.color, whose default is [[1, neutral10]] -- the
//     track's own colour -- so a split line's or a tick's stroke 'auto', a
//     pointer's or a progress arc's fill 'auto' (after useStyle and the
//     part's itemStyle) is the band under it, the track with none written.
//   The item's own pointer (width, length, offsetCenter, keepAspect,
//     itemStyle) and progress.itemStyle: createPointer reads
//     itemModel.getModel('pointer'), the fill pass
//     itemModel.getModel(['pointer' | 'progress', 'itemStyle']).
//   min / max / startAngle / endAngle as JS numbers (`+min`, `-startAngle /
//     180 * PI`): a numeric string is its number.
//
// From the real ECharts 6.1 dist (SSR, svg renderer, animation off, 400 x
// 300, Math.random pinned). Per case and per series:
//   band     the default band's colour (#rrggbbaa) when the series wrote no
//            axisLine.lineStyle.color -- a colour equal to it is the track's
//            (the Pascal side compares it with the skin's track); else null
//   rows[]   {value: a number's hex, 'NaN', 's:' + a string, 'b:' + a
//            boolean, null; name}
//   titles[] / details[]  the drawn Text's style.text per row ('' none,
//            null not shown)
//   pointers[] {angle: -rotation - PI / 2 as hex, fill, w, r, x, y (the
//            PointerPath's shape, hex) | null}
//   progress[] {end: shape.endAngle hex | 'NaN', start (hex), fill} | null
//   lines[]  the strokes of the split lines and ticks, in order (a case
//            shows one kind)
//   inks[]   (cases that ask) each row's reading's fill
// A case with `at` runs animated (valueAnimation's count): the clock is
// stepped to T0 + at and only the readings are recorded, as that frame
// shows them.
// Colours: echarts.color.parse as #rrggbbaa, 'x:<word>' a word it does not
// take.
//
// Guards (nothing written, exit 1 on a failure): the reading of a
// name-first table is its name and no title; encode does not move the value;
// the 'auto' strokes and fills with no bands equal the band; the item's
// pointer width is its own; the whole run twice is the same JSON.
//
// Run: node tools/advchart-oracle/gauge-reads.js -> tests/fixtures/advchart-gauge-reads.json
'use strict';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const T_BASE = 1700000000000;
let NOW = T_BASE;
class ClockDate extends RealDate {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}
global.Date = ClockDate;
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-gauge-reads.json');
Math.random = function () { return 0; };
class OracleError extends Error {}
function must(c, m) { if (!c) throw new OracleError(m); }
const W = 400;
const H = 300;

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function hex2(v) { return ('0' + Math.round(v).toString(16)).slice(-2); }
function colourOf(c) {
  if (c == null) return null;
  if (typeof c === 'object') return 'grad';
  const p = echarts.color.parse(c);
  if (!p) return 'x:' + c;
  return '#' + hex2(p[0]) + hex2(p[1]) + hex2(p[2]) + hex2(p[3] * 255);
}
function cellOf(v) {
  if (typeof v === 'number') return Number.isNaN(v) ? 'NaN' : hex(v);
  if (typeof v === 'string') return 's:' + v;
  if (typeof v === 'boolean') return 'b:' + v;
  return null;
}

const PAL = ['#5470c6', '#91cc75', '#fac858', '#ee6666'];
// every part off but the ones a case turns on
const BARE = { axisLine: { show: false }, splitLine: { show: false }, axisTick: { show: false }, axisLabel: { show: false } };
const g = o => Object.assign({ type: 'gauge' }, BARE, o);
const opt = (series, extra) => Object.assign({ animation: false, color: PAL, series: Array.isArray(series) ? series : [series] }, extra || {});
const PROG = { progress: { show: true } };
const NAMES = [['name', 'score'], ['Rate', 37], ['Load', 64]];

function cases() {
  return [
    // ---- the rows: no encode, the first dimension, no names ----
    ['ds-names-first', "a table whose first column is names: the reading is the name, no title, the pointer at the start",
      opt(g(Object.assign({ min: -50, max: 50 }, PROG)), { dataset: { source: [['name', 'score'], ['Rate', 37]] } })],
    ['ds-rows', 'three rows of a name-first table, nested progress arcs',
      opt(g({ progress: { show: true, overlap: false } }), { dataset: { source: NAMES.concat([['Idle', 12]]) } })],
    ['ds-number-first', 'a table whose first column is the number: the values, still no names',
      opt(g(PROG), { dataset: { source: [['score', 'name'], [37, 'Rate'], [64, 'Load']] } })],
    ['ds-encode-ignored', 'encode written anyway (value, itemName, tooltip): read by nobody',
      opt(g(Object.assign({ encode: { value: 'score', itemName: 'name', tooltip: 'score' } }, PROG)), { dataset: { source: NAMES } })],
    ['ds-encode-index', 'encode.value 1 by index on a number table: still the first column',
      opt(g(Object.assign({ encode: { value: 1 } }, PROG)), { dataset: { source: [['a', 'b'], [10, 90], [20, 80]] } })],
    ['ds-layout-row', "seriesLayoutBy 'row': the first line is the first dimension",
      opt(g(Object.assign({ seriesLayoutBy: 'row' }, PROG)), { dataset: { source: [['score', 37, 64], ['name', 'Rate', 'Load']] } })],
    ['ds-layout-row-names', "seriesLayoutBy 'row' with the names' line first",
      opt(g(Object.assign({ seriesLayoutBy: 'row' }, PROG)), { dataset: { source: [['name', 'Rate', 'Load'], ['score', 37, 64]] } })],
    ['ds-series-dims', "the series' dimensions over a headless table: the first one",
      opt(g(Object.assign({ dimensions: ['v', 'n'] }, PROG)), { dataset: { source: [[37, 'Rate'], [64, 'Load']] } })],
    ['ds-dataset-dims-number', "the dataset's dimensions type 'number' on a column of words: parsed, 'Rate' NaN, '7' 7",
      opt(g(PROG), { dataset: { dimensions: [{ name: 'v', type: 'number' }, 'n'], source: [['Rate', 'x'], ['7', 'y']], sourceHeader: false } })],
    ['ds-dims-ordinal', "declared 'ordinal' over numbers: the cells as written",
      opt(g(PROG), { dataset: { dimensions: [{ name: 'v', type: 'ordinal' }], source: [[12], ['7']] } })],
    ['ds-series-dims-type', "the series' dimensions type 'number' over a column of words",
      opt(g(Object.assign({ dimensions: [{ name: 'q', type: 'number' }] }, PROG)), { dataset: { source: [['v'], ['Rate'], ['7']] } })],
    ['ds-objects', 'object rows: the first field, no names',
      opt(g(PROG), { dataset: { source: [{ name: 'Rate', score: 37 }, { name: 'Load', score: 64 }] } })],
    ['ds-mixed-column', "an ordinal column holding a word, a number, a numeric word and true",
      opt(g(PROG), { dataset: { source: [['v'], ['Rate'], [12], ['7'], [true]] } })],
    ['ds-null-empty', "an ordinal column's null and '' are 0 to the dial and '' to the reading (min -50)",
      opt(g(Object.assign({ min: -50, max: 50 }, PROG)), { dataset: { source: [['v'], ['Rate'], [null], ['']] } })],
    ['ds-formatter', "a template formatter over a name: '{value} %'",
      opt(g({ detail: { formatter: '{value} %' } }), { dataset: { source: NAMES } })],
    ['ds-no-header', 'a headless table of words and numbers',
      opt(g(PROG), { dataset: { source: [['Rate', 3], ['Load', 5]] } })],
    ['ds-header-false', 'sourceHeader false: the header line is a row',
      opt(g(PROG), { dataset: { source: [['name', 'v'], ['Rate', 3]], sourceHeader: false } })],
    ['ds-numeric-words', 'a column of numeric words is not ordinal: parsed',
      opt(g(PROG), { dataset: { source: [['v'], ['37'], [' 64 ']] } })],
    ['data-arrays-ordinal', 'data arrays whose first item starts with a word: the cells as written',
      opt(g(Object.assign({ data: [['abc', 3], [5, 6], ['7', 1]] }, PROG)))],
    ['data-dims-number', "data arrays whose first word is declared 'number' by the series' dimensions: parsed, NaN",
      opt(g(Object.assign({ dimensions: [{ name: 'v', type: 'number' }, 'w'], data: [['abc', 3], [5, 6]] }, PROG)))],
    ['ds-null-inherit', "the reading's 'inherit' over two bands: a null cell is 0 (the first band), a word NaN (the last)",
      opt(g({ min: -50, max: 50, axisLine: { show: false, lineStyle: { color: [[0.5, '#ff0000'], [1, '#0000ff']] } },
        detail: { color: 'inherit', formatter: '{value}x' } }), { dataset: { source: [['v'], [null], ['Rate'], [30]] } }), { inks: true }],
    ['ds-count-words', "valueAnimation over cells that are words: no count, the words throughout (sampled at 300 ms)",
      Object.assign(opt(g({ detail: { valueAnimation: true, formatter: '{value} %' } }), { dataset: { source: [['v'], ['Rate'], ['7'], [40]] } }),
        { animation: true }), { at: 300 }],
    ['data-encode-ignored', 'data arrays with encode.value 1: the first element',
      opt(g(Object.assign({ encode: { value: 1 }, data: [[37, 5], [64, 6]] }, PROG)))],
    ['data-objects', "items with values a number, a numeric word, a word: a number column",
      opt(g(Object.assign({ data: [{ value: 37, name: 'A' }, { value: '7', name: 'B' }, { value: 'x', name: 'C' }] }, PROG)))],
    // ---- 'auto': the band under it, the track with none ----
    ['auto-split-none', "splitLine 'auto' with no bands: the track's colour",
      opt(g({ splitLine: { show: true, lineStyle: { color: 'auto' } }, data: [{ value: 40 }] }))],
    ['auto-tick-none', "axisTick 'auto' with no bands: the track's colour",
      opt(g({ axisTick: { show: true, lineStyle: { color: 'auto' } }, data: [{ value: 40 }] }))],
    ['auto-tick-bands', "axisTick 'auto' over two bands",
      opt(g({ axisTick: { show: true, splitNumber: 2, lineStyle: { color: 'auto' } }, splitNumber: 4,
        axisLine: { show: false, lineStyle: { color: [[0.5, '#ff0000'], [1, '#0000ff']] } }, data: [{ value: 40 }] }))],
    ['auto-pointer-none', "pointer.itemStyle.color 'auto' with no bands: the track's colour",
      opt(g({ pointer: { itemStyle: { color: 'auto' } }, data: [{ value: 40 }, { value: 70 }] }))],
    ['auto-progress-none', "progress.itemStyle.color 'auto' with no bands",
      opt(g({ progress: { show: true, overlap: false, itemStyle: { color: 'auto' } }, data: [{ value: 40 }, { value: 70 }] }))],
    ['auto-item-colour', "an item's itemStyle.color 'auto': its pointer and arc take the band under its value; another item its palette colour",
      opt(g({ progress: { show: true, overlap: false }, axisLine: { show: false, lineStyle: { color: [[0.5, '#ff0000'], [1, '#0000ff']] } },
        data: [{ value: 30, itemStyle: { color: 'auto' } }, { value: 70, itemStyle: { color: 'auto' } }, { value: 50 }] }))],
    ['auto-series-colour', "the series' itemStyle.color 'auto': the palette's colour (seriesStyleTask), not the band",
      opt(g({ progress: { show: true, overlap: false }, itemStyle: { color: 'auto' },
        axisLine: { show: false, lineStyle: { color: [[0.5, '#ff0000'], [1, '#0000ff']] } }, data: [{ value: 30 }, { value: 70 }] }))],
    ['auto-item-colour-none', "an item's itemStyle.color 'auto' with no bands: the track's colour",
      opt(g({ progress: { show: true }, data: [{ value: 30, itemStyle: { color: 'auto' } }] }))],
    // ---- the item's own pointer and progress keys ----
    ['item-pointer', "items' own pointer width, length, offsetCenter; the series' for the third",
      opt(g({ pointer: { width: 4, length: '50%' }, data: [{ value: 20, pointer: { width: 12, length: '80%', offsetCenter: [0, '-10%'] } },
        { value: 60, pointer: { length: 40 } }, { value: 90 }] }))],
    ['item-pointer-colour', "items' own pointer.itemStyle and progress.itemStyle colours",
      opt(g({ progress: { show: true, overlap: false }, pointer: { itemStyle: { color: '#123456' } },
        data: [{ value: 20, pointer: { itemStyle: { color: '#ff00ff' } }, progress: { itemStyle: { color: '#00ffff' } } },
          { value: 60 }, { value: 90, pointer: { itemStyle: { color: 'auto' } }, progress: { itemStyle: { color: 'auto' } } }] }))],
    // ---- the angles and the extent as JS numbers ----
    ['string-extent', "min '10', max '210', startAngle '180', endAngle '0' written as strings",
      opt(g(Object.assign({ min: '10', max: '210', startAngle: '180', endAngle: '0', data: [{ value: 60 }, { value: 160 }] }, PROG)))],
  ];
}

function seriesOut(chart, s, more) {
  const data = s.getData();
  const view = chart.getViewOfSeriesModel(s);
  const vd = data.mapDimension('value');
  const out = { index: s.seriesIndex };
  // with no colour list of the series' own, the default one: its colour is
  // the track's
  const list = s.get(['axisLine', 'lineStyle', 'color']);
  out.band = s.__r7dOwnBands ? null : colourOf(list[list.length - 1][1]);
  out.rows = [];
  out.titles = [];
  out.details = [];
  out.pointers = [];
  out.progress = [];
  for (let i = 0; i < data.count(); i++) {
    out.rows.push({ value: cellOf(data.get(vd, i)), name: data.getName(i) });
    const t = view._titleEls && view._titleEls[i];
    out.titles.push(t && t.parent ? String(t.style.text) : null);
    const d = view._detailEls && view._detailEls[i];
    out.details.push(d && d.parent ? String(d.style.text) : null);
    const p = data.getItemGraphicEl(i);
    if (p && p.parent) {
      const o = { angle: hex(-p.rotation - Math.PI / 2), fill: colourOf(p.style.fill) };
      if (p.type === 'pointer') ['width', 'r', 'x', 'y'].forEach(k => { o[k === 'width' ? 'w' : k] = hex(p.shape[k]); });
      out.pointers.push(o);
    } else out.pointers.push(null);
    const pr = view._progressEls && view._progressEls[i];
    if (pr && pr.parent) {
      out.progress.push({ end: Number.isNaN(pr.shape.endAngle) ? 'NaN' : hex(pr.shape.endAngle), start: hex(pr.shape.startAngle),
        fill: colourOf(pr.style.fill) });
    } else out.progress.push(null);
  }
  out.lines = [];
  view.group.traverse(e => { if (e.type === 'line') out.lines.push(colourOf(e.style.stroke)); });
  if (more.inks) out.inks = (view._detailEls || []).map(d => (d && d.parent ? colourOf(d.style.fill) : null));
  if (more.at != null) {
    // a frame of the count: its readings only
    return { index: out.index, band: out.band, rows: out.rows, details: out.details };
  }
  return out;
}

function run(c) {
  const [name, note, option] = c;
  const more = c[3] || {};
  NOW = T_BASE;
  echarts.env.node = more.at == null;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    if (more.at != null) chart._ssr = false;
    chart.setOption(JSON.parse(JSON.stringify(option)));
    if (more.at != null) {
      NOW = T_BASE + more.at;
      chart.getZr().animation.update();
    } else chart.renderToSVGString();
    const series = [];
    chart.getModel().eachSeries(s => {
      const raw = (option.series || [])[s.seriesIndex] || {};
      s.__r7dOwnBands = !!(raw.axisLine && raw.axisLine.lineStyle && raw.axisLine.lineStyle.color);
      series.push(seriesOut(chart, s, more));
    });
    const rec = { name, note, option, series };
    if (more.at != null) rec.at = more.at;
    return rec;
  } finally {
    chart.dispose();
    echarts.env.node = true;
  }
}

function runAll() {
  return { source: 'ECharts ' + echarts.version + ' (' + path.basename(DIST) + ')', W, H, cases: cases().map(run) };
}

function guards(out) {
  const c = n => out.cases.find(x => x.name === n).series[0];
  const g1 = c('ds-names-first');
  must(g1.details[0] === 'Rate' && g1.titles[0] === '' && g1.rows[0].value === 's:Rate', 'a name-first table reads its name');
  must(g1.progress[0].end === 'NaN', 'the name maps to NaN');
  const g2 = c('ds-encode-ignored');
  must(g2.details.join() === 'Rate,Load', 'encode moves nothing');
  must(c('ds-encode-index').details.join() === '10,20', 'encode by index moves nothing');
  const sp = c('auto-split-none');
  must(sp.lines.length > 0 && sp.lines.every(x => x === sp.band), 'an auto split line with no bands is the band');
  const tk = c('auto-tick-none');
  must(tk.lines.length > 0 && tk.lines.every(x => x === tk.band), 'an auto tick with no bands is the band');
  const pt = c('auto-pointer-none');
  must(pt.pointers.every(p => p.fill === pt.band), 'an auto pointer with no bands is the band');
  const pg = c('auto-progress-none');
  must(pg.progress.every(p => p.fill === pg.band), 'an auto arc with no bands is the band');
  const ip = c('item-pointer');
  must(ip.pointers[0].w !== ip.pointers[2].w, "an item's pointer width is its own");
  const ct = c('ds-count-words');
  must(ct.details[2] !== '40 %', 'a number counts');
  must(ct.details[0] === 'Rate %' && ct.details[1] === '7 %', 'words do not count');
  const ni = c('ds-null-inherit');
  must(ni.inks[0] === '#ff0000ff' && ni.inks[1] === '#0000ffff', 'null inherits the first band, a word the last');
  const mx = c('ds-null-empty');
  must(mx.rows[1].value === null && mx.details[1] === '' && mx.pointers[1].angle !== mx.pointers[0].angle, 'null is 0 to the dial');
}

function main() {
  const a = runAll();
  guards(a);
  const b = runAll();
  const ja = JSON.stringify(a, null, 1);
  must(ja === JSON.stringify(b, null, 1), 'two runs differ');
  fs.writeFileSync(OUT, ja + '\n');
  console.log('wrote ' + OUT + ' ' + a.cases.length + ' cases');
}

try {
  main();
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'GUARD: ' + e.message : e);
  process.exit(1);
}
