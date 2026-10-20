/*
Upstream's own answers for round-2 batch R2-J2: the gallery's functions other
than renderItem -- label and axis label formatters, symbolSize, itemStyle.color,
labelLayout, a transform's itemNameFormatter. The harvest names each one
('<id>.<key>', '<id>.<key>#2', ...: the tools/advchart-gallery/harvest.js
namer) and the demo registers a Pascal transcription under that name
(examples/advchart/ucallbacks.pas). This script says, for every function the
chart CALLS while it draws (no pointer, no animation), what it answered.

HOW THE FUNCTIONS ARE GOT: as gallery-renderitem.js gets them -- harvest.js
required as a module runs each example as the harvest did (the same sandbox,
seeded Math.random, the virtual clock), the gallery file is set with every
'@name' turned back into the page's own function, and each function is
wrapped so that every answer is written down. The guard: the gallery file is
the live option as the namer writes it.

WHAT IS COMPARED: per name, the SET of distinct answers (upstream may call a
formatter more than once for one label, in layout passes the port does not
have; what must agree is what the answers are). A formatter's answers
upstream must all be among the port's (a category axis is formatted label by
label for its interval, upstream only for the labels it samples); every
other function's answers are the same set. A label formatter called with
params.status 'emphasis' (upstream preparing a hover's text) is not written
down; a formatter's number is its String(). The page's myChart answers this
chart's size. An answer is written as
  's:<text>'   a string        'n:<hex>'   a number
  'u'          undefined/null  'j:<json>'  an object or an array, numbers hex,
                                           keys sorted
The port's test wraps the demo's handlers the same way. A name upstream never
calls while drawing (a tooltip's, a hover's, an animation's) is not in the
case; the port must not call it either.

Runs the real ECharts 6.1 build (ECHARTS_DIST) in node's server-side mode
(SVG renderer), chart._ssr = false, env.node off, the clock of animation.js,
Math.random the port's xorshift32, zrender's width table measuring every
string; the maps of examples/advchart/maps (GeoJSON with its special areas;
SVG through jsdom's DOMParser). Every chart 960 x 600, the root's
`animation: false`. Examples skipped: those whose map the demo does not ship
(china, world, HK, the unlicensed SVGs), Baidu maps, and map-usa-projection
(its projection is d3's: geo.js case 'albers-usa').

  node tools/advchart-oracle/gallery-callbacks.js

writes tests/fixtures/advchart-gallery-callbacks.json (ORACLE_OUT overrides).
Top level: source, version, seed, W, H, measure {firstCode, ratio[]}, notes[],
cases[] {id, file, maps[], calls {name: [answer...] sorted}}, guards[].
Ends with process.exit().
*/
'use strict';
process.env.TZ = 'UTC';
process.env.TY_TSC = process.env.TY_TSC || 'D:/Projects/xterm.js/node_modules/typescript';
const fs = require('fs');
const path = require('path');

// ---------- the controlled clock (must precede loading the dist) ----------
const RealDate = Date;
const T0 = 1700000000000;
let NOW = T0;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;
let TIMERS = [];
let timerSeq = 0;
global.setTimeout = function (fn, ms) {
  const id = ++timerSeq;
  TIMERS.push({ id, due: NOW + (+ms || 0), fn });
  return id;
};
global.clearTimeout = function (id) {
  TIMERS = TIMERS.filter(t => t.id !== id);
};

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

const JSDOM_PATH = process.env.JSDOM_PATH || 'D:/Projects/xterm.js/node_modules/jsdom';
const { JSDOM } = require(JSDOM_PATH);
global.DOMParser = new JSDOM('').window.DOMParser;

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');
const MAPS = path.join(ROOT, 'examples', 'advchart', 'maps');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-gallery-callbacks.json');
const HARVEST = require(path.join(ROOT, 'tools', 'advchart-gallery', 'harvest.js'));
HARVEST.setSeeded(true);

const W = 960;
const H = 600;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => {};
  console.error = () => {};
  try { return fn(); } finally { console.warn = w; console.error = e; }
};

// ---------- zrender's width table (gallery-renderitem.js) ----------
const FIRST_CODE = 32;
const LAST_CODE = 126;
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = Function('"use strict"; return (' + line.slice(line.indexOf('=') + 1).trim().replace(/;$/, '') + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, 'the width table is not 95 characters');
  return s;
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);

(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk() {
  rngState = SEED;
  NOW = T0;
  TIMERS = [];
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function paint(chart) {
  chart._onframe();
  chart.getZr().storage.getDisplayList(true);
  quiet(() => chart.renderToSVGString());
}

// ---------- an answer, written down ----------
function repr(v) {
  if (v === undefined || v === null) return 'u';
  if (typeof v === 'string') return 's:' + v;
  if (typeof v === 'number') return 'n:' + hex(v);
  if (typeof v === 'boolean') return 's:' + String(v);
  return 'j:' + JSON.stringify(deep(v));
}
function deep(v) {
  if (typeof v === 'number') return hex(v);
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v).map(deep);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v).sort()) {
      if (v[k] === undefined) continue;
      o[k] = deep(v[k]);
    }
    return o;
  }
  return v;
}

// ---------- the cases ----------
const INDEX = JSON.parse(fs.readFileSync(path.join(GALLERY, 'index.json'), 'utf8'));
const MAPS_INDEX = JSON.parse(fs.readFileSync(path.join(MAPS, 'maps.json'), 'utf8'));
const SKIP = new Set(['map-usa-projection']);

// the maps an option names: those maps.json ships (by file), or why not
function mapsOf(text) {
  const out = [];
  const re = /"map": "([^"]+)"/g;
  let m;
  let bad = null;
  while ((m = re.exec(text))) {
    const name = m[1];
    const e = MAPS_INDEX.maps[name];
    if (!e) { bad = name; continue; }
    if (!out.some(x => x.name === name)) out.push({ name, file: e.file, special: e.specialAreas || null });
  }
  return { maps: out, bad };
}

function materialize(v, byName, log) {
  if (Array.isArray(v)) return v.map(x => materialize(x, byName, log));
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      const s = v[k];
      if (typeof s === 'string' && s[0] === '@' && byName.has(s.slice(1))) {
        const name = s.slice(1);
        const fn = byName.get(name);
        // a renderItem or a projection is used, not written down
        const isFormatter = /formatter$/i.test(k);
        o[k] = (k === 'renderItem' || k === 'project' || k === 'unproject') ? fn
          : function (...args) {
            const r = fn.apply(this, args);
            /* a label formatter called for the emphasis state is upstream
               preparing the hover's text: not drawn, and the port asks it
               on the hover -- not written down */
            const p = args[0];
            if (p && typeof p === 'object' && p.status === 'emphasis') return r;
            /* what a formatter answers becomes text: a number is its
               String() */
            const rr = isFormatter && typeof r === 'number' ? 's:' + String(r) : repr(r);
            (log[name] = log[name] || new Set()).add(rr);
            return r;
          };
      }
      else o[k] = materialize(s, byName, log);
    }
    return o;
  }
  return v;
}

function runCase(entry) {
  const file = entry.sequence ? entry.sequence.steps[0].file : (entry.file || entry.id + '.json');
  const text = fs.readFileSync(path.join(GALLERY, file), 'utf8');
  const src = fs.readFileSync(path.join(HARVEST.TS_DIR, entry.id + '.ts'), 'utf8');
  const collected = {};
  const run = HARVEST.runExample(src, entry.id + '.ts', collected);
  const namer = collected.namer;
  /* the page's myChart is the harvest's stand-in, 600 x 400: a function
     that asks its size (labelLayout's myChart.getWidth()) asks this chart's */
  run.sandbox.myChart.getWidth = () => W;
  run.sandbox.myChart.getHeight = () => H;
  const live = run.shown[0].option;
  /* the gallery file is the live option as the namer writes it -- or, for
     the few shipped from an unseeded harvest (their random data is not
     reproducible), names the very same functions at the very same places */
  const liveText = JSON.stringify(live, namer.replacer, 1);
  const grafted = liveText !== text;
  if (grafted) {
    const refs = t => {
      const out = [];
      const walk = (v, p) => {
        if (Array.isArray(v)) v.forEach((x, i) => walk(x, p + '.' + i));
        else if (v && typeof v === 'object') Object.keys(v).forEach(k => walk(v[k], p + '.' + k));
        else if (typeof v === 'string' && v[0] === '@') out.push(p + '=' + v);
      };
      walk(JSON.parse(t), '');
      return out.join('|');
    };
    must(refs(liveText) === refs(text), entry.id + ': ' + file + ' does not name the live functions where the live option has them');
  }
  const byName = new Map();
  namer.names.forEach((name, fn) => byName.set(name, fn));
  const mp = mapsOf(text);
  mp.maps.forEach(m => {
    const body = fs.readFileSync(path.join(MAPS, m.file), 'utf8');
    if (/\.svg$/i.test(m.file)) echarts.registerMap(m.name, { svg: body });
    else echarts.registerMap(m.name, JSON.parse(body), m.special || undefined);
  });
  const log = {};
  const chart = mk();
  try {
    const opt = materialize(JSON.parse(text), byName, log);
    quiet(() => chart.setOption(Object.assign({ animation: false }, opt)));
    paint(chart);
  } finally {
    chart.dispose();
  }
  const calls = {};
  Object.keys(log).sort().forEach(k => { calls[k] = Array.from(log[k]).sort(); });
  return { id: entry.id, file, grafted, maps: mp.maps.map(m => m.name), calls };
}

function eligible(e) {
  if (!e.ok || !e.handlers || SKIP.has(e.id)) return false;
  if (!e.handlers.some(h => h.indexOf('.') >= 0 && !/\.(project|unproject)$/.test(h))) return false;
  const file = e.sequence ? e.sequence.steps[0].file : (e.file || e.id + '.json');
  if (/\.gz$/.test(file)) return false;
  const text = fs.readFileSync(path.join(GALLERY, file), 'utf8');
  if (text.indexOf('"bmap"') >= 0) return false;
  return !mapsOf(text).bad;
}

function guards(out) {
  const g = [];
  const add = (name, ok) => g.push({ name, ok: !!ok });
  const c = id => out.cases.find(x => x.id === id);
  add('matrix-confusion: its label formatter answers rich text',
    c('matrix-confusion').calls['matrix-confusion.formatter'].some(s => s.startsWith('s:{name|')));
  add('bubble-gradient: a symbolSize per bubble',
    c('bubble-gradient').calls['bubble-gradient.symbolSize'].length > 5);
  add('bar-race-country: a colour per country', c('bar-race-country').calls['bar-race-country.color'].length > 3);
  add('line-race: end labels', c('line-race').calls['line-race.formatter'].length > 0);
  add('boxplot-light-velocity2: its boxes named', c('boxplot-light-velocity2').calls['boxplot-light-velocity2.itemNameFormatter'].length > 3);
  add('no tooltip formatter is called while drawing',
    out.cases.every(x => Object.keys(x.calls).every(k => !/(position|valueFormatter)$/.test(k))));
  add('every case calls something or says nothing (a hover-only case)', out.cases.length > 30);
  return g;
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED, W, H,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: chart._ssr false, env.node off, ' + W + ' x ' + H + ', the option\'s root animation false; the first file of a sequence.',
      'calls: per function name, the distinct answers it gave while the chart was set and drawn once.',
    ],
    cases: INDEX.entries.filter(eligible).map(runCase),
  };
  out.guards = guards(out);
  return out;
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
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
const nul = json1.indexOf('\\u0000') >= 0;
console.log(out1.cases.length + ' cases (' + out1.cases.map(c => c.id + ' ' + Object.keys(c.calls).length).join(', ') + '); '
  + (out1.guards.length - bad.length) + '/' + out1.guards.length + ' guards; two runs '
  + (json1 === json2 ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || json1 !== json2 || nul) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
