// Upstream's own answers for round-5 batch R5-D (2026-10-27): what
// MagicType.onclick (component/toolbox/feature/MagicType.ts) hands the new
// series. seriesOptGenreator builds {id, type, data, stack, markPoint,
// markLine} (line / bar) or {stack} (stack), the feature's option[type]
// merges over it, and then zrUtil.defaults(newSeriesOpt, seriesModel.option)
// fills every key it lacks from the OLD series' model option -- the author's
// keys with the old type's defaults merged in: a bar turned line keeps z 2,
// progressive 3000, its select style; a line turned bar keeps z 3,
// label.position 'top', animationEasing 'linear'.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node, SVG renderer; the icon's onclick through its path's
// 'click' handler.
//
//   node tools/advchart-oracle/magictype-defaults.js
//
// writes tests/fixtures/advchart-magictype-defaults.json (ORACLE_OUT
// overrides).
//
// Per case: id, note, option, clicks [{icon, series [the changeMagicType
// payload's newOption.series, in order -- `id` replaced by its seriesIndex, and the theme's
// colours the port takes from its skin: a bar's backgroundStyle, its
// select.itemStyle.borderColor]}].
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-magictype-defaults.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const clone = v => JSON.parse(JSON.stringify(v));
function strip(chart, o) {
  const r = clone(o);
  r.seriesIndex = chart.getModel().getSeries().findIndex(m => m.id === o.id);
  delete r.id;
  delete r.backgroundStyle;
  if (r.select && r.select.itemStyle) delete r.select.itemStyle.borderColor;
  return r;
}
const CASES = [
  {
    id: 'bar-line', note: 'a bar (with a label and an item style written) and a line: line, then bar, then stack',
    option: { animation: false, toolbox: { feature: { magicType: { type: ['line', 'bar', 'stack'] } } },
      xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: {},
      series: [{ type: 'bar', name: 'B', label: { show: true }, itemStyle: { color: '#ff0000' }, data: [1, 2, 3] },
        { type: 'line', name: 'L', label: { show: true }, data: [3, 1, 2] }] },
    clicks: ['line', 'bar', 'stack'],
  },
];
function runCase(def) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 600, height: 400 });
  try {
    chart.setOption(clone(def.option));
    chart.renderToSVGString();
    const payloads = [];
    // the payload as the feature hands it to dispatchAction: the action's
    // mergeOption builds the new series model over the very objects (its
    // mergeDefaultAndTheme writes the new type's defaults into them), so the
    // event's payload is not what was dispatched
    const tbView = chart.getViewOfComponentModel(chart.getModel().getComponent('toolbox', 0));
    const api = tbView._features.get('magicType').api;
    const disp = api.dispatchAction;
    api.dispatchAction = function (p) {
      if (p && p.type === 'changeMagicType') payloads.push(clone(p));
      return disp.apply(this, arguments);
    };
    const clicks = [];
    for (const icon of def.clicks) {
      payloads.length = 0;
      const m = chart.getModel().getComponent('toolbox', 0);
      const v = chart.getViewOfComponentModel(m);
      // the icon's path by the feature model's iconPaths
      const path = v._features.get('magicType').model.iconPaths[icon];
      must(path, 'no icon ' + icon);
      path.trigger('click', { target: path });
      chart.renderToSVGString();
      must(payloads.length === 1, icon + ': one changeMagicType');
      clicks.push({ icon, series: payloads[0].newOption.series.map(o => strip(chart, o)) });
    }
    return { id: def.id, note: def.note, option: def.option, clicks };
  } finally {
    chart.dispose();
  }
}
let cases;
let json1;
try {
  cases = CASES.map(runCase);
  const c = cases[0].clicks;
  must(c[0].series[0].z === 2 && c[0].series[0].progressive === 3000, 'bar to line keeps the bar defaults');
  must(c[1].series[1].z === 3 && c[1].series[1].label.position === 'top' && c[1].series[1].animationEasing === 'linear', 'line to bar keeps the line defaults');
  json1 = JSON.stringify({ source: 'ECharts ' + echarts.version, cases }, null, 1) + '\n';
  must(json1 === JSON.stringify({ source: 'ECharts ' + echarts.version, cases: CASES.map(runCase) }, null, 1) + '\n', 'two generations differ');
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  if (cases) console.log(JSON.stringify(cases, null, 1).slice(0, 3000));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log(cases.length + ' cases; ' + json1.length + ' bytes; wrote', OUT);
process.exit(0);
