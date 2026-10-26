// Upstream's own answers for the data view's optionToContent /
// contentToOption (spec 237): what the panel shows when the option gives
// functions, which option object each function is handed, what Refresh does
// with one function, with both, with neither, with readOnly, when
// contentToOption answers nothing or throws, and how the changeDataView
// action merges the option a contentToOption answers.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 600 x 400. The
// browser parts of DataView.onclick are stubbed as toolbox.js stubs them:
// the chart prototype's getDom answers a fake container, `document`
// creates plain objects (the header's innerHTML, viewMain's innerHTML and
// children, the textarea's value and readOnly, the buttons' innerHTML and
// click listeners). setTimeout (the hideTip the click schedules) never
// runs. The data view is opened by triggering `click` on its icon path (the
// listener ToolboxView binds), and a button by calling its listeners.
//
// The port cannot run JavaScript: the option names registered Pascal
// handlers as '@Name'. Here each '@Name' in KNOWN is replaced by the JS
// function below; any other '@Name' stays a string (upstream then sees a
// value that is not a function -- what the port does with a name nobody
// registered). The Pascal test registers handlers of the same names that do
// the same thing to the port's arguments:
//   '@Table'     optionToContent(opt): an html table -- a row of <td> heads
//                ('Day' and each series' name), then a row per category of
//                xAxis[0].data with each series' value (an object item's
//                .value) -- built as test/dataView.html builds its own
//   '@HeadTable' optionToContent(opt): the same table with its head row in
//                <thead> of <th>, and a <caption>, then a paragraph of text
//   '@Read'      contentToOption(viewMain, opt): the <td> / <th> cells of
//                viewMain.innerHTML row by row (tags stripped, entities as
//                written); the first row names the columns; answers
//                {series: [{name: head[k], data: [+cell + 1, ...]}]} for k >= 1
//   '@ReadFull'  contentToOption(viewMain, opt): opt itself with
//                series[1].data[0] = 999 and title [{text: 'Edited'}]
//   '@Nothing'   contentToOption: answers undefined
//   '@Boom'      contentToOption: throws new Error('bad cell')
//   '@NewSeries' contentToOption: {series: [{name: 'Email', data: [1,2,3,4,5]},
//                {name: 'Extra', data: [[1,2],[3,4]]}, {data: [5,6]}],
//                title: {text: 'T'}}
//   '@Items'     contentToOption: {series: [{name: 'Ads', data: [1, 2, 3,
//                {value: 4, name: 'four'}, 5]}]}
// Every call is recorded: the function's name, and of the option it was
// handed the series' names and data and xAxis[0].data; contentToOption's
// first argument as the cells @Read reads (rows) and as text (content:
// viewMain.innerHTML when it holds no textarea, else the textarea's value).
//
//   node tools/advchart-oracle/dataview-handlers.js
//
// writes tests/fixtures/advchart-dataview-handlers.json (ORACLE_OUT overrides).
//
// A scenario
//   id, note, option (as written for the port), steps[] {step, record}
//   step     {type: 'open'} | {type: 'cell', row, col, value} (viewMain's
//            row-th <tr>'s col-th cell set to value: the user editing a
//            table the page made editable) | {type: 'text', value} (the
//            textarea's value) | {type: 'button', button (its text)}
// A record
//   panel    null (closed) | {header, custom (optionToContent ran: no
//            textarea), content (viewMain.innerHTML; null when there is a
//            textarea), textarea null | {value, readOnly}, buttons [text]}
//   calls[]  {fn, series [{name, data}], xAxisData, rows (contentToOption
//            only), content (contentToOption only)}
//   actions[] the changeDataView payloads ({type, newOption})
//   events[]  the dataviewchanged events' newOption
//   option   getOption's series [{type, name, data}] and title texts
//   error    null | the message of what the step threw
//
// Self-checks: the anchors (H-BOTH dispatches changeDataView and its option
// changes; H-ONLY-O2C and H-ONLY-C2O call nothing on Refresh and dispatch
// nothing; H-READONLY has no Refresh button; H-THROW's error starts 'Data
// view format error'); the transcription of DataView's refresh rule (R1:
// which of ignore / contentToOption / parseContents runs, from the two
// option values) agrees with every Refresh; guards G1 (the rule as "either
// given" instead of "exactly one") and G2 (readOnly not hiding Refresh)
// change the scenarios they name; two generations give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-dataview-handlers.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
function clean(v) {
  if (v === undefined) return null;
  if (typeof v === 'string') return v.split('\u0000').join('<NUL>');
  if (typeof v === 'function') return '@fn';
  if (typeof v === 'number') return Number.isFinite(v) ? v : { $num: String(v) };
  if (v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return Array.from(v, x => clean(x));
  const o = {};
  for (const k of Object.keys(v)) {
    if (v[k] === undefined) continue;
    o[k] = clean(v[k]);
  }
  return o;
}

// ---------- the browser stubs ----------
function fakeEl(tag) {
  return {
    tag, children: [], style: {}, listeners: {}, innerHTML: '', value: '', readOnly: false, clientHeight: H,
    appendChild(c) { this.children.push(c); },
    removeChild(c) { this.children = this.children.filter(x => x !== c); },
    addEventListener(t, f) { (this.listeners[t] = this.listeners[t] || []).push(f); },
    // a canvas the measurer asks for while a refresh re-renders: no context,
    // so zrender measures as it does with no document at all
    getContext() { return null; },
  };
}
let CONTAINER = null;
const DOC = { createElement: tag => fakeEl(tag), defaultView: {} };
const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
const PROTO = Object.getPrototypeOf(probe);
probe.dispose();
const origGetDom = PROTO.getDom;
PROTO.getDom = function () { return CONTAINER || origGetDom.call(this); };

// ---------- the handlers ----------
let CALLS = [];
const valOf = v => (v !== null && typeof v === 'object' && !Array.isArray(v) ? v.value : v);
function optPick(opt) {
  return {
    series: (opt.series || []).map(s => ({ name: s.name === undefined ? null : s.name, data: clean(s.data) })),
    xAxisData: opt.xAxis && opt.xAxis[0] ? clean(opt.xAxis[0].data) : null,
  };
}
// the cells of an html text, row by row: <td> and <th>, tags stripped
function cellsOf(html) {
  const rows = [];
  const trs = html.split(/<tr[^>]*>/i).slice(1);
  for (const tr of trs) {
    const body = tr.split(/<\/tr>/i)[0];
    const cells = [];
    const re = /<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi;
    let m;
    while ((m = re.exec(body))) cells.push(m[1].replace(/<[^>]*>/g, '').trim());
    rows.push(cells);
  }
  return rows;
}
function tableHtml(opt, head) {
  const axisData = opt.xAxis[0].data;
  const series = opt.series;
  let t = head ? '<table><caption>Sales</caption><thead><tr><th>Day</th>' : '<table style="width:100%;text-align:center"><tbody><tr><td>Day</td>';
  for (const s of series) t += head ? '<th>' + s.name + '</th>' : '<td>' + s.name + '</td>';
  t += head ? '</tr></thead><tbody>' : '</tr>';
  for (let i = 0; i < axisData.length; i++) {
    t += '<tr><td>' + axisData[i] + '</td>';
    for (const s of series) t += '<td>' + valOf(s.data[i]) + '</td>';
    t += '</tr>';
  }
  t += '</tbody></table>';
  if (head) t += '<p>Units: <b>k</b></p>';
  return t;
}
function contentArg(viewMain) {
  const ta = viewMain.children.find(c => c.tag === 'textarea');
  return ta ? ta.value : viewMain.innerHTML;
}
const KNOWN = {
  Table: () => function (opt) {
    CALLS.push(Object.assign({ fn: 'Table' }, optPick(opt)));
    return tableHtml(opt, false);
  },
  HeadTable: () => function (opt) {
    CALLS.push(Object.assign({ fn: 'HeadTable' }, optPick(opt)));
    return tableHtml(opt, true);
  },
  Read: () => function (viewMain, opt) {
    const content = contentArg(viewMain);
    const rows = cellsOf(viewMain.innerHTML);
    CALLS.push(Object.assign({ fn: 'Read', rows, content }, optPick(opt)));
    const series = [];
    if (rows.length) {
      for (let k = 1; k < rows[0].length; k++) series.push({ name: rows[0][k], data: rows.slice(1).map(r => +r[k] + 1) });
    }
    return { series };
  },
  ReadFull: () => function (viewMain, opt) {
    CALLS.push(Object.assign({ fn: 'ReadFull', rows: cellsOf(viewMain.innerHTML), content: contentArg(viewMain) }, optPick(opt)));
    opt.series[1].data[0] = 999;
    opt.title = [{ text: 'Edited' }];
    return opt;
  },
  Nothing: () => function (viewMain, opt) {
    CALLS.push(Object.assign({ fn: 'Nothing', rows: cellsOf(viewMain.innerHTML), content: contentArg(viewMain) }, optPick(opt)));
    return undefined;
  },
  Boom: () => function (viewMain, opt) {
    CALLS.push(Object.assign({ fn: 'Boom', rows: cellsOf(viewMain.innerHTML), content: contentArg(viewMain) }, optPick(opt)));
    throw new Error('bad cell');
  },
  NewSeries: () => function (viewMain, opt) {
    CALLS.push(Object.assign({ fn: 'NewSeries', rows: cellsOf(viewMain.innerHTML), content: contentArg(viewMain) }, optPick(opt)));
    return { series: [{ name: 'Email', data: [1, 2, 3, 4, 5] }, { name: 'Extra', data: [[1, 2], [3, 4]] }, { data: [5, 6] }], title: { text: 'T' } };
  },
  Items: () => function (viewMain, opt) {
    CALLS.push(Object.assign({ fn: 'Items', rows: cellsOf(viewMain.innerHTML), content: contentArg(viewMain) }, optPick(opt)));
    return { series: [{ name: 'Ads', data: [1, 2, 3, { value: 4, name: 'four' }, 5] }] };
  },
};
function resolveHandlers(v) {
  if (typeof v === 'string' && v[0] === '@' && KNOWN[v.slice(1)]) return KNOWN[v.slice(1)]();
  if (v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return v.map(resolveHandlers);
  const o = {};
  for (const k of Object.keys(v)) o[k] = resolveHandlers(v[k]);
  return o;
}

// ---------- the record ----------
function recordPanel() {
  if (!CONTAINER || !CONTAINER.children.length) return null;
  const root = CONTAINER.children[CONTAINER.children.length - 1];
  const viewMain = root.children[1];
  const ta = viewMain.children.find(c => c.tag === 'textarea');
  return {
    header: root.children[0].innerHTML,
    custom: !ta,
    content: ta ? null : viewMain.innerHTML,
    textarea: ta ? { value: ta.value, readOnly: !!ta.readOnly } : null,
    buttons: root.children[2].children.map(b => b.innerHTML),
  };
}
function recordOption(chart) {
  const o = chart.getOption();
  return {
    series: (o.series || []).map(s => ({ type: s.type, name: s.name === undefined ? null : s.name, data: clean(s.data) })),
    title: (o.title || []).map(t => (t.text === undefined ? null : t.text)),
  };
}
function dataViewIcon(chart) {
  let icon = null;
  chart.getModel().eachComponent('toolbox', m => {
    const view = chart.getViewOfComponentModel(m);
    const f = view._features && view._features.get('dataView');
    if (f && f.model && f.model.iconPaths) icon = icon || f.model.iconPaths.dataView;
  });
  must(icon, 'no dataView icon');
  return icon;
}
// viewMain's row-th <tr>'s col-th cell set to a value
function editCell(html, row, col, value) {
  let r = -1;
  return html.replace(/<tr[^>]*>[\s\S]*?<\/tr>/gi, tr => {
    r++;
    if (r !== row) return tr;
    let c = -1;
    return tr.replace(/(<t[dh][^>]*>)([\s\S]*?)(<\/t[dh]>)/gi, (m, a, b, z) => {
      c++;
      return c === col ? a + value + z : m;
    });
  });
}

function runScenario(def) {
  CONTAINER = null;
  CALLS = [];
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    const api = chart._api;
    let actions = [];
    let events = [];
    const origDispatch = api.dispatchAction;
    api.dispatchAction = function (payload) {
      if (payload.type === 'changeDataView') actions.push(clean({ type: payload.type, newOption: payload.newOption }));
      return origDispatch.apply(this, arguments);
    };
    chart.on('dataviewchanged', p => events.push(clean(p.newOption)));
    chart.setOption(resolveHandlers(JSON.parse(JSON.stringify(def.option))));
    const steps = [];
    for (const st of def.steps) {
      CALLS = [];
      actions = [];
      events = [];
      let error = null;
      try {
        global.document = DOC;
        try {
          if (st.type === 'open') {
            CONTAINER = CONTAINER || fakeEl('div');
            dataViewIcon(chart).trigger('click');
          } else if (st.type === 'cell') {
            const root = CONTAINER.children[CONTAINER.children.length - 1];
            root.children[1].innerHTML = editCell(root.children[1].innerHTML, st.row, st.col, st.value);
          } else if (st.type === 'text') {
            const root = CONTAINER.children[CONTAINER.children.length - 1];
            root.children[1].children.find(c => c.tag === 'textarea').value = st.value;
          } else if (st.type === 'button') {
            const root = CONTAINER.children[CONTAINER.children.length - 1];
            const btn = root.children[2].children.find(b => b.innerHTML === st.button);
            must(btn, 'no button ' + st.button);
            btn.listeners.click.forEach(f => f());
          }
        } finally {
          delete global.document;
        }
      } catch (e) {
        if (e instanceof OracleError) throw e;
        error = String(e.message);
      }
      steps.push({ step: st, record: { panel: recordPanel(), calls: clean(CALLS), actions, events, option: recordOption(chart), error } });
    }
    return { id: def.id, note: def.note, option: def.option, steps };
  } finally {
    chart.dispose();
    CONTAINER = null;
  }
}

// ---------- the scenarios ----------
const base = dv => ({
  animation: false,
  legend: { show: false },
  xAxis: { type: 'category', data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'] },
  yAxis: { type: 'value' },
  series: [
    { type: 'line', name: 'Email', data: [120, 132, 101, 134, 90] },
    { type: 'bar', name: 'Ads', data: [220, 182, { value: 191, name: 'peak', itemStyle: { color: '#f00' } }, 234, 290] },
  ],
  toolbox: { feature: { dataView: dv } },
});
const open = { type: 'open' };
const refresh = { type: 'button', button: 'Refresh' };
const close = { type: 'button', button: 'Close' };
const SCENARIOS = [
  { id: 'H-BOTH', note: 'both functions: the table, a cell edited, Refresh reads it back',
    option: base({ optionToContent: '@Table', contentToOption: '@Read' }),
    steps: [open, { type: 'cell', row: 3, col: 1, value: '105' }, refresh] },
  { id: 'H-BOTH-CLOSE', note: 'both functions, Close: nothing read back',
    option: base({ optionToContent: '@Table', contentToOption: '@Read' }), steps: [open, close] },
  { id: 'H-HEAD', note: 'a table with a thead of th, a caption and a paragraph after it',
    option: base({ optionToContent: '@HeadTable', contentToOption: '@Read' }), steps: [open, refresh] },
  { id: 'H-READONLY', note: 'both functions and readOnly: no Refresh button',
    option: base({ optionToContent: '@Table', contentToOption: '@Read', readOnly: true }), steps: [open, close] },
  { id: 'H-LANG', note: "both functions and the feature's own lang",
    option: base({ optionToContent: '@Table', contentToOption: '@Read', lang: ['Mine', 'Shut', 'Apply'] }),
    steps: [open, { type: 'button', button: 'Apply' }] },
  { id: 'H-ONLY-O2C', note: 'optionToContent alone: Refresh only closes',
    option: base({ optionToContent: '@Table' }), steps: [open, refresh] },
  { id: 'H-ONLY-C2O', note: 'contentToOption alone: the textarea, edited; Refresh only closes and calls nothing',
    option: base({ contentToOption: '@Read' }),
    steps: [open, { type: 'text', value: ' \tEmail\tAds\nMon\t1\t2' }, refresh] },
  { id: 'H-UNDEF', note: 'contentToOption answers undefined: no action',
    option: base({ optionToContent: '@Table', contentToOption: '@Nothing' }), steps: [open, refresh] },
  { id: 'H-THROW', note: 'contentToOption throws: Data view format error',
    option: base({ optionToContent: '@Table', contentToOption: '@Boom' }), steps: [open, refresh] },
  { id: 'H-FULL', note: 'contentToOption answers the whole option it was handed, changed',
    option: base({ optionToContent: '@Table', contentToOption: '@ReadFull' }), steps: [open, refresh] },
  { id: 'H-NEW', note: 'contentToOption answers a known series, a new one, a nameless one and a title',
    option: base({ optionToContent: '@Table', contentToOption: '@NewSeries' }), steps: [open, refresh] },
  { id: 'H-ITEMS', note: "contentToOption's data over object items: wrapped, defaulted, the name dropped",
    option: base({ optionToContent: '@Table', contentToOption: '@Items' }), steps: [open, refresh] },
  { id: 'H-O2C-NAME', note: 'optionToContent names no function: the textarea, and contentToOption reads it',
    option: base({ optionToContent: '@Missing', contentToOption: '@Read' }), steps: [open, refresh] },
  { id: 'H-C2O-NAME', note: "contentToOption names no function: Refresh parses the textarea's empty value",
    option: base({ optionToContent: '@Table', contentToOption: '@Missing' }), steps: [open, refresh] },
];

// ---------- the refresh rule, transcribed ----------
let mut = {};
function ruleOf(dv) {
  const o2c = dv.optionToContent == null ? null : dv.optionToContent;
  const c2o = dv.contentToOption == null ? null : dv.contentToOption;
  const isFn = v => typeof v === 'string' && v[0] === '@' && !!KNOWN[v.slice(1)];
  if (!mut.either && (c2o == null) !== (o2c == null)) return 'ignore';
  return isFn(c2o) ? 'handler' : 'parse';
}
function checkScenario(sc) {
  const diffs = [];
  const dv = sc.option.toolbox.feature.dataView;
  sc.steps.forEach((s, i) => {
    if (s.step.type === 'open') {
      const p = s.record.panel;
      const wantRefresh = mut.noReadOnly ? true : !dv.readOnly;
      if (p && p.buttons.length !== (wantRefresh ? 2 : 1)) diffs.push(sc.id + ' step ' + i + ' buttons');
      return;
    }
    if (s.step.type !== 'button' || s.step.button === 'Close' || s.step.button === 'Shut') return;
    const rule = ruleOf(dv);
    const called = s.record.calls.length > 0;
    const acted = s.record.actions.length > 0;
    if (rule === 'ignore' && (called || acted)) diffs.push(sc.id + ' step ' + i + ' ignored');
    if (rule === 'handler' && !called) diffs.push(sc.id + ' step ' + i + ' handler');
    if (rule === 'parse' && called) diffs.push(sc.id + ' step ' + i + ' parse');
  });
  return diffs;
}
const GUARDS = [
  { id: 'G1', mutation: 'Refresh runs contentToOption when either function is given', set: { either: true }, named: ['H-ONLY-C2O'] },
  { id: 'G2', mutation: 'readOnly keeps the Refresh button', set: { noReadOnly: true }, named: ['H-READONLY'] },
];

function generate() {
  const scenarios = SCENARIOS.map(runScenario);
  mut = {};
  for (const sc of scenarios) {
    const d = checkScenario(sc);
    must(d.length === 0, 'the transcription disagrees: ' + d.join('; '));
  }
  const guards = GUARDS.map(g => {
    mut = g.set;
    const changed = scenarios.filter(sc => checkScenario(sc).length).map(sc => sc.id);
    mut = {};
    return { id: g.id, mutation: g.mutation, named: g.named, changed, ok: g.named.every(n => changed.includes(n)) };
  });
  const byId = id => scenarios.find(s => s.id === id);
  const last = id => byId(id).steps[byId(id).steps.length - 1].record;
  must(last('H-BOTH').actions.length === 1 && last('H-BOTH').events.length === 1, 'H-BOTH dispatches no changeDataView');
  must(JSON.stringify(last('H-BOTH').option) !== JSON.stringify(byId('H-BOTH').steps[0].record.option), 'H-BOTH leaves the option as it was');
  must(last('H-ONLY-O2C').actions.length === 0 && last('H-ONLY-O2C').calls.length === 0, 'H-ONLY-O2C reads something back');
  must(last('H-ONLY-C2O').actions.length === 0 && last('H-ONLY-C2O').calls.length === 0, 'H-ONLY-C2O reads something back');
  must(byId('H-READONLY').steps[0].record.panel.buttons.length === 1, 'H-READONLY shows Refresh');
  must(last('H-THROW').error && last('H-THROW').error.indexOf('Data view format error') === 0, 'H-THROW does not throw');
  for (const sc of scenarios) for (const s of sc.steps) if (s.step.type === 'button') must(s.record.panel === null, sc.id + ': a button left the panel open: ' + s.record.error);
  return { source: 'ECharts 6.1 dist (' + path.basename(DIST) + '), node SSR, SVG renderer', W, H, scenarios, guards };
}

let json1;
let json2;
let out;
try {
  out = generate();
  json1 = JSON.stringify(out, null, 1) + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  json2 = JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = out.guards.filter(g => !g.ok);
out.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.id + ' (' + g.mutation + '): named '
  + g.named.join(' / ') + '; changes ' + g.changed.join(', ')));
const nSteps = out.scenarios.reduce((n, s) => n + s.steps.length, 0);
console.log(out.scenarios.length + ' scenarios, ' + nSteps + ' steps; two generations ' + (json1 === json2 ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || json1 !== json2) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
