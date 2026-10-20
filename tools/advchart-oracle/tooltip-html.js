/*
Upstream's own answers for round-2 batch R2-I8: WHAT AN HTML TOOLTIP IS
HANDED. In a browser, getTooltipRenderMode('auto') is 'html' and TooltipView
gives a formatter and a template html:

  1. params.marker is format.getTooltipMarker({color, type, renderMode:
     'html'}) -- the inline-block span the box shows as the dot (an item's
     10 x 10, radius 10, a 4px right margin; a sub-item's 4 x 4 between a 3px
     left and an 8px right margin), its colour through encodeHTML;
  2. a string formatter goes through formatTpl(html, params, true): every
     value the template takes is encodeHTML'd (& < > " '), in both render
     modes;
  3. encodeHTML itself.

The port draws the html it is handed (tyControls.AdvChart.TipHtml); these
are the strings it must be handed. The layout of the html is the browser's
-- CSS, not ECharts -- and is not recorded here.

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node: only echarts.format is used, no chart.

  node tools/advchart-oracle/tooltip-html.js

writes tests/fixtures/advchart-tooltip-html.json (ORACLE_OUT overrides).
Top level: source, version, markers[] {color, type, html}, encode[] {in,
out}, tpl[] {id, tpl, params[] {seriesName, name, value}, out}, guards[].
Ends with process.exit().
*/
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-tooltip-html.json');

class OracleError extends Error {}

const COLORS = ['#5470c6', '#91cc75', '#ee6666', 'rgba(84,112,198,0.5)', 'rgba(0,0,0,0.25)'];
const ENCODE = ['plain', 'a<b>&c', '"quoted" & \'single\'', '<span style="color:red">x</span>', '&nbsp;', ''];
const TPLS = [
  {
    id: 'item', tpl: '{a}<br/>{b}: {c}',
    params: [{ seriesName: 's<1>', name: 'A&B', value: 5 }],
  },
  {
    id: 'item-quotes', tpl: '<b>{b}</b> {c} ({a})',
    params: [{ seriesName: 'it\'s "q"', name: '<i>n</i>', value: 'x<y' }],
  },
  {
    id: 'axis', tpl: '{b0}<br/>{a0}: {c0}<br/>{a1}: {c1}',
    params: [{ seriesName: 'p&q', name: 'cat<1>', value: 3 }, { seriesName: 'r>s', name: 'cat<1>', value: 4 }],
  },
  {
    id: 'axis-short', tpl: '{a}: {c} / {a1}: {c1}',
    params: [{ seriesName: 'one', name: 'c', value: 1 }, { seriesName: '<two>', name: 'c', value: 2 }],
  },
];

function generate() {
  const markers = [];
  for (const color of COLORS) {
    for (const type of ['item', 'subItem']) {
      markers.push({ color, type, html: echarts.format.getTooltipMarker({ color, type, renderMode: 'html' }) });
    }
  }
  const encode = ENCODE.map(s => ({ in: s, out: echarts.format.encodeHTML(s) }));
  const tpl = TPLS.map(t => {
    const params = t.params.map(p => Object.assign({}, p, { $vars: ['seriesName', 'name', 'value'] }));
    return { id: t.id, tpl: t.tpl, params: t.params, out: echarts.format.formatTpl(t.tpl, params, true) };
  });
  return { markers, encode, tpl };
}

const g1 = generate();
const g2 = generate();
const guards = [];
function guard(id, ok, what) {
  guards.push({ id, ok: !!ok, what });
  console.log((ok ? 'guard ok   ' : 'GUARD FAIL ') + id + ': ' + what);
}
guard('mk-span', g1.markers[0].html.indexOf('<span style="display:inline-block;margin-right:4px;') === 0,
  'an item marker is the inline-block span');
guard('mk-sub', g1.markers[1].html.indexOf('width:4px;height:4px') > 0, 'a sub-item marker is 4 x 4');
guard('enc-lt', g1.encode[1].out === 'a&lt;b&gt;&amp;c', 'encodeHTML escapes < > &');
guard('tpl-enc', g1.tpl[0].out === 's&lt;1&gt;<br/>A&amp;B: 5', 'formatTpl(.., true) encodes the values, not the template');

const json1 = JSON.stringify(g1);
const json2 = JSON.stringify(g2);
if (json1 !== json2) {
  console.error('two generations differ');
  process.exit(1);
}
const out = Object.assign({
  source: 'tools/advchart-oracle/tooltip-html.js',
  version: echarts.version,
}, g1, { guards });
const text = JSON.stringify(out, null, 1) + '\n';
fs.writeFileSync(OUT, text);
const bad = guards.filter(x => !x.ok).length;
console.log(g1.markers.length + ' markers, ' + g1.encode.length + ' encodes, ' + g1.tpl.length + ' templates; '
  + (guards.length - bad) + '/' + guards.length + ' guards; two generations identical; ' + text.length + ' bytes');
console.log('wrote ' + OUT);
if (bad) process.exit(1);
process.exit(0);
