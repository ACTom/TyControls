/*
 * Turn Apache ECharts' official example gallery into static option JSON that
 * the TTyAdvanceChart demo can load.
 *
 * WHY EVALUATE RATHER THAN PARSE. The examples are TypeScript-ish JS, not JSON:
 * unquoted keys, single quotes, trailing commas, template strings, spread,
 * arrow functions, generated data. A regex conversion gets most of that wrong
 * quietly. Running each file and serialising the resulting object gets it right
 * by construction, and JSON.stringify drops functions for us -- which is the
 * correct answer, because the option tree this port reads is JSON and its
 * diagnostics already say so for a pasted callback.
 *
 * WHAT IS RECORDED RATHER THAN HIDDEN. Every example produces an index entry,
 * including the ones that could not be reduced: the reason goes in the entry.
 * A gallery that silently dropped a third of its examples would look complete
 * and be useless as a progress board.
 *
 * THE TIME HELPERS ARE THE REAL ONES. echarts.time.parse/format/roundTime,
 * echarts.number.parseDate and echarts.format.formatTime come from the ECharts
 * dist bundle (ECHARTS_DIST, as the oracles), not from stubs: every calendar
 * example builds its daily rows as [echarts.time.format(t, '{yyyy}-{MM}-{dd}'),
 * v], and a stub that returned '' harvested rows like ["", 9469] on which
 * upstream draws no cell at all. ECharts reads a bare 'yyyy-mm-dd' as LOCAL
 * time, so the process runs with TZ=UTC and says so by assertion -- the dates
 * then do not depend on the machine that harvested them.
 *
 * ECSTAT IS THE PORT'S, NOT A STUB. Six examples start with
 * `echarts.registerTransform(ecStat.transform.regression)` (or histogram,
 * clustering) and then name the transform in `dataset.transform` -- which is
 * exactly the option the port reads: it registers the three 'ecStat:'
 * transforms itself. So the sandbox gives `ecStat.transform.*` as names only
 * (computing nothing) and the entry records what the page registered under
 * `registersTransforms`.
 *
 * A SEQUENCE IS RECORDED, NOT GUESSED. Some examples never assign the global
 * `option`: they call myChart.setOption themselves (inside a data callback),
 * and the universal-transition ones then switch between two or more options on
 * a setInterval. Every setOption is snapshotted when it is made; the interval
 * callbacks are then ticked by hand, up to MAX_TICKS times. When the steps
 * come back round to one already seen, that is a cycle and the entry gets
 *   sequence: { interval, loopTo, steps: [{ file, opts? }] }
 * with each distinct option in its own file (<id>.json, <id>.2.json, ...: every
 * file in the gallery stays a whole option a chart can be given on its own).
 * An example that does assign `option` keeps exactly what it had; it gains a
 * sequence only when its interval cycles -- data that changes every tick
 * (random walks, clocks) is a live feed, not a sequence. An example without
 * `option` whose ticks never repeat is recorded as the fixed run of steps the
 * ticks produced, marked `fixed: true`. [R2-J] A page that has an option and
 * goes on updating it (bar-race, the gauges) is run again on a virtual clock
 * and its first updates are recorded as a sequence that plays once
 * (`live: true`, see playLive).
 *
 * [R2-J] NAMED, NOT DROPPED: a custom series' renderItem function is written
 * as '@<id>' ('@<id>#2' ...), a geo projection's project / unproject as
 * '@<id>.project' / '@<id>.unproject' (makeNamer); the entry lists them under
 * `handlers`. examples/advchart/urenderitems.pas registers a transcription of
 * every renderItem the gallery names. [R2-J2] Every other function too --
 * formatters, symbolSize, tooltip.position, animationDelay ... -- as
 * '@<id>.<key>' ('@<id>.<key>#2' ...); examples/advchart/ucallbacks.pas
 * registers those.
 *
 * [R2-J] TOO LARGE: the five that compute megabytes of data are stored
 * without it (GENERATED: `generated.fill` says what examples/advchart/
 * ugenerated.pas must fill, with a hash of the values), three that load a
 * large file are stored gzipped (SHIP_GZ: `file: '<id>.json.gz'`), the rest
 * keep their reason. A typed array under `data` is written as rows.
 *
 * Usage:  node harvest.js [pathToEchartsExamples] [outDir] [--only id,id,...]
 *                         [--seeded]
 *   --only    (or TY_GALLERY_ONLY=id,id)  harvest just these ids; every other
 *             gallery file is left alone and only their index.json entries are
 *             replaced (the rest stay byte-identical).
 *   --seeded  (or TY_GALLERY_SEEDED=1)  Math.random inside each example is the
 *             oracles' xorshift32 (seed 2463534242), reset per example, so the
 *             generated data is reproducible. Off by default.
 *   The calendar examples were re-harvested with:
 *     node harvest.js --seeded --only calendar-charts,calendar-effectscatter,
 *       calendar-graph,calendar-heatmap,calendar-simple,calendar-horizontal,
 *       calendar-vertical,calendar-pie,custom-calendar-icon
 *     (one comma-separated argument, no spaces)
 *   The ecStat examples and the setOption sequences were added, unseeded:
 *     node harvest.js --only bar-histogram,scatter-clustering,
 *       scatter-exponential-regression,scatter-linear-regression,
 *       scatter-logarithmic-regression,scatter-polynomial-regression,
 *       map-bar-morph,scatter-nebula,scatter-stream-visual,
 *       treemap-sunburst-transition,pictorialBar-bar-transition,
 *       pie-parliament-transition,scatter-aggregate-bar,scatter-symbol-morph
 *   The explicit-undefined and linearMap fixes re-harvested, unseeded:
 *     node harvest.js --only candlestick-brush,geo-seatmap-flight,
 *       geo-svg-lines,geo-svg-map,matrix-mini-bar-geo,pictorialBar-forest,
 *       sunburst-drink,sunburst-label-rotate,sunburst-monochrome,
 *       treemap-drill-down,treemap-obama,treemap-visual
 *   [R2-J] Named renderItems, the environment fixes (CDN_PATH, structuredClone,
 *   echarts.util / version / color / format the real ones, getZr().configLayer,
 *   a canvas, $.when / $.getScript, data-gl paths), queued timeouts, the live
 *   sequences, the generated and gzipped large ones, the virtual clock -- every
 *   entry these change, seeded (TY_TSC pointing at a typescript package):
 *     node harvest.js D:/Projects/echarts-examples examples/advchart/gallery
 *       --seeded --only bar-large,bar-race-country,bar-race,candlestick-large,
 *       custom-bar-trend,custom-calendar-icon,custom-cartesian-polygon,
 *       custom-error-bar,custom-error-scatter,custom-ohlc,custom-polar-heatmap,
 *       custom-profit,custom-wind,dynamic-data,dynamic-data2,flame-graph,
 *       gauge-barometer,gauge-multi-title,gauge-ring,gauge-stage,
 *       gauge-temperature,geo-svg-custom-effect,graph-force-dynamic,
 *       heatmap-large-piecewise,heatmap-large,line-race,lines-airline,
 *       lines-bmap-bus,lines-bmap-effect,map-iceland-pie,map-usa-projection,
 *       matrix-confusion,matrix-covariance,matrix-mbti,
 *       matrix-mini-bar-data-collection,matrix-periodic-table,
 *       parallel-nutrients,pictorialBar-dotted,pictorialBar-forest,
 *       pictorialBar-spirit,pie-parliament-transition,scatter-large,
 *       scatter-nebula,scatter-nutrients-matrix,scatter-nutrients,
 *       scatter-weibo,watermark,wind-barb,lines-ny
 */
'use strict';
// Before anything creates a Date: ECharts parses 'yyyy-mm-dd' as local time.
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const zlib = require('zlib');

if (new Date(2017, 0, 1).getTimezoneOffset() !== 0) {
  console.error('TZ=UTC did not take effect; the harvested dates would ' +
    'depend on the time zone of this machine.');
  process.exit(2);
}

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const realEcharts = require(DIST);

/* Flags anywhere on the command line; the positional arguments are the rest. */
const argv = require.main === module ? process.argv.slice(2) : [];
const positional = [];
let onlyArg = process.env.TY_GALLERY_ONLY || '';
let SEEDED = process.env.TY_GALLERY_SEEDED === '1';
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--seeded') SEEDED = true;
  else if (a === '--only') onlyArg = argv[++i] || '';
  else if (a.startsWith('--only=')) onlyArg = a.slice('--only='.length);
  else if (a.startsWith('--')) {
    console.error('unknown option ' + a);
    process.exit(2);
  }
  else positional.push(a);
}
const ONLY = onlyArg.split(',').map((x) => x.trim()).filter(Boolean);

const SRC = positional[0] || 'D:/Projects/echarts-examples';
const OUT = positional[1] ||
  'D:/Projects/ty-advchart/examples/advchart/gallery';
const TS_DIR = path.join(SRC, 'public/examples/ts');
const MAX_BYTES = Number(process.env.TY_GALLERY_MAX || 1048576);
const DATA_DIR = path.join(SRC, 'public/data');

/* The header block every example carries:
     title: Bar with Background
     category: bar
     titleCN: ...
     difficulty: 1                                                        */
function readHeader(src) {
  const m = src.match(/^\s*\/\*([\s\S]*?)\*\//);
  const out = {};
  if (!m) return out;
  for (const line of m[1].split('\n')) {
    const kv = line.match(/^\s*([A-Za-z]+)\s*:\s*(.*?)\s*$/);
    if (kv) out[kv[1]] = kv[2];
  }
  return out;
}

/* TypeScript that is not JavaScript -- TRANSPILED, not regexed.
 *
 * The first version of this stripped types with regexes and converted 18 of
 * 273 examples; the failures were `export`, `interface`, `as`, `!`, generics
 * and plain `const x: T`. Patching regexes until the count goes up is how a
 * harvester starts quietly mangling the data it cannot parse, so it asks the
 * real compiler instead. Nothing is vendored into this repo: point TY_TSC at a
 * typescript package directory, or `npm i -g typescript`.
 */
const TS_LIB = process.env.TY_TSC || 'typescript';
let ts = null;
try { ts = require(TS_LIB); }
catch (e) {
  console.error('This needs the TypeScript compiler. Either `npm i -g ' +
    'typescript`, or set TY_TSC to a typescript package directory.');
  process.exit(2);
}

function deTypeScript(src) {
  /* Every example ends with a bare `export {};`. That marker is what makes
     TypeScript treat the file as a MODULE, and it then emits
     `Object.defineProperty(exports, "__esModule", ...)` whatever ModuleKind
     says -- which is where 247 of 273 "exports is not defined" came from. The
     marker carries no meaning for us: there is nothing to export into. */
  src = src.replace(/^\s*export\s*\{\s*\}\s*;?\s*$/gm, '');
  const out = ts.transpileModule(src, {
    compilerOptions: {
      target: ts.ScriptTarget.ES2019,
      // THE ENUM, NOT THE STRING. transpileModule silently ignores an
      // unrecognised string and falls back to CommonJS, which emits
      // `exports.x = ...` -- and 247 of 273 examples then died on
      // "exports is not defined", which reads like a sandbox problem and is
      // really a compiler-option problem.
      module: ts.ModuleKind.None,
      removeComments: false
    }
  });
  return out.outputText;
}

/* LARGE DATA THE PAGE COMPUTES IS COMPUTED IN THE DEMO. Five examples make
   between 1 and 64 MB of points with a few lines of code (a random walk, a
   noise field). The gallery file keeps the option with those arrays empty,
   and the entry says which paths the demo fills (generated.fill: the path,
   the length and a hash of the values); examples/advchart/ugenerated.pas
   ports each generator, on the same seeded Math.random (harvest with
   --seeded), and the test suite holds its output to these hashes.
   THE HASH: FNV-1a (32-bit) over a walk of the value -- 'z' null, 'n' and the
   16 hex digits of a number's IEEE bits, 's' a string and NUL (ASCII only),
   '[' ... ']' around an array. */
const GENERATED = {
  /* [R2-J2] custom-wind's 5.3 MB of vectors are made from data-gl's
     winds.json (700 KB, shipped gzipped in examples/advchart/data) and the
     page's own shuffle */
  'custom-wind': ['series.data'],
  'bar-large': ['xAxis.data', 'series.0.data'],
  'candlestick-large': ['dataset.source'],
  'heatmap-large': ['xAxis.data', 'yAxis.data', 'series.0.data'],
  'heatmap-large-piecewise': ['xAxis.data', 'yAxis.data', 'series.0.data'],
  'scatter-large': ['series.0.data', 'series.1.data']
};
/* LOADED DATA, SHIPPED COMPRESSED: an option over MAX_BYTES whose gzip is
   at most GZ_MAX is written as <id>.json.gz (entry.file). Only these three:
   the bmap ones cannot draw without Baidu's online map, and scatter-nebula
   is 14 MB even compressed. [R2-J2] custom-wind is GENERATED now. */
const SHIP_GZ = new Set(['lines-airline', 'parallel-nutrients', 'scatter-weibo']);
const GZ_MAX = 640 * 1024;

function getPath(obj, p) {
  return p.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);
}
function setPath(obj, p, v) {
  const ks = p.split('.');
  const last = ks.pop();
  ks.reduce((o, k) => o[k], obj)[last] = v;
}
const hexBits = new DataView(new ArrayBuffer(8));
function fnvOf(v) {
  let h = 0x811c9dc5;
  const feed = (s) => {
    for (let i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i) & 0xff;
      h = Math.imul(h, 0x01000193) >>> 0;
    }
  };
  const walk = (x) => {
    if (x === null) feed('z');
    else if (typeof x === 'number') {
      hexBits.setFloat64(0, x);
      feed('n' + hexBits.getUint32(0).toString(16).padStart(8, '0') +
        hexBits.getUint32(4).toString(16).padStart(8, '0'));
    }
    else if (typeof x === 'string') feed('s' + x + '\0');
    else if (Array.isArray(x)) { feed('['); x.forEach(walk); feed(']'); }
    else throw new Error('cannot hash ' + typeof x);
  };
  walk(v);
  return (h >>> 0).toString(16).padStart(8, '0');
}

/* The oracles' seeded Math.random (the port's xorshift32), as a fresh Math for
   one example: the host's Math.random is never replaced. */
const SEED = 2463534242;
function seededMath() {
  let state = SEED;
  const m = Object.create(Math);
  m.random = function () {
    let x = state;
    x ^= x << 13; x >>>= 0;
    x ^= x >>> 17;
    x ^= x << 5; x >>>= 0;
    state = x;
    return x / 4294967296;
  };
  return m;
}

/* A RENDERITEM IS NAMED, NOT DROPPED. Upstream's renderItem is a function;
   the port's is a handler registered under a name, and an option names it as
   `renderItem: '@name'`. The demo registers a Pascal transcription of every
   gallery renderItem under `<id>` -- the example's id -- and, when the page
   has more than one distinct function, `<id>#2`, `<id>#3` in the order the
   stringifier meets them (series order). The same function object (a page
   that hands one renderItem to two series) is one name. A geo projection's
   `project` / `unproject` are named the same way, `<id>.project` /
   `<id>.unproject`.
   [R2-J2] EVERY OTHER FUNCTION IS NAMED TOO, by the key that holds it:
   `<id>.<key>` ('@matrix-confusion.formatter', '@bubble-gradient.symbolSize'),
   a second distinct function under the same key `<id>.<key>#2`, and so on,
   in the order the stringifier meets them; the same function object is one
   name wherever it is met. A formatter was dropped before, and a chart whose
   labels come from one drew no text at all (matrix-confusion,
   matrix-periodic-table); examples/advchart/ucallbacks.pas registers a
   transcription of every one. The renderItem names stay as they were (their
   own numbering: a page's first renderItem is `<id>` whatever else it has). */
function makeNamer(id) {
  const names = new Map();
  /* how many distinct functions each key has had */
  const perKey = new Map();
  let renderItems = 0;
  return {
    names,
    replacer(key, value) {
      if (typeof value === 'function') {
        if (key === 'renderItem') {
          if (!names.has(value)) {
            renderItems++;
            const n = renderItems > 1 ? id + '#' + renderItems : id;
            names.set(value, n);
          }
          return '@' + names.get(value);
        }
        if ((key === 'project' || key === 'unproject') &&
            this && typeof this.project === 'function' &&
            typeof this.unproject === 'function') {
          const n = id + '.' + key;
          names.set(value, n);
          return '@' + n;
        }
        if (!names.has(value)) {
          const k = perKey.has(key) ? perKey.get(key) + 1 : 1;
          perKey.set(key, k);
          names.set(value, id + '.' + key + (k > 1 ? '#' + k : ''));
        }
        return '@' + names.get(value);
      }
      /* A TYPED ARRAY IS ROWS. JSON.stringify writes a Float32Array as an
         object {"0": x, "1": y, ...}, which no option reads. Upstream takes a
         typed array under `data` as flat rows of `dimensions.length`
         values (scatter-large, scatter-nebula); the JSON spelling of the same
         rows is an array of tuples, each value the typed array's own (a
         float32 written as the double it is). */
      if (ArrayBuffer.isView(value) && !(value instanceof DataView)) {
        const dims = this && key === 'data' && Array.isArray(this.dimensions)
          ? this.dimensions.length : 1;
        const flat = Array.from(value);
        if (dims <= 1) return flat;
        const rows = [];
        for (let i = 0; i + dims <= flat.length; i += dims) {
          rows.push(flat.slice(i, i + dims));
        }
        return rows;
      }
      return keepExplicitUndefined(key, value);
    }
  };
}

/* How many of the functions the namer named (they are not lost): [R2-J2]
   every one the stringifier reaches. An object written through its own
   toJSON (watermark's canvas) is not walked: its methods never reach the
   stringifier and stay counted as lost. */
function countNamed(node, seen) {
  if (node === null || typeof node !== 'object') return 0;
  if (seen.has(node)) return 0;
  seen.add(node);
  if (typeof node.toJSON === 'function') return 0;
  let n = 0;
  for (const k of Object.keys(node)) {
    const v = node[k];
    if (typeof v === 'function') n++;
    else n += countNamed(v, seen);
  }
  return n;
}

/* EVERY setOption THE PAGE MAKES, SNAPSHOTTED WHEN IT IS MADE: the examples
   that switch between options hand the same object back later, and the ones
   that stream data mutate theirs in place. `opts` is upstream's second
   argument as it was written: `true` is notMerge, an object is passed through
   (it is what TTyAdvanceChart.SetOption takes as its options text). */
function recordSetOption(collected, opt, opts) {
  if (opt == null || typeof opt !== 'object') return;
  let o = null;
  if (typeof opts === 'boolean') {
    if (opts) o = { notMerge: true };
  }
  else if (opts && typeof opts === 'object') {
    o = JSON.parse(JSON.stringify(opts, keepExplicitUndefined));
    if (!Object.keys(o).length) o = null;
  }
  collected.calls = collected.calls || [];
  collected.calls.push({
    option: opt,
    json: JSON.stringify(opt, collected.namer.replacer, 1),
    opts: o
  });
}

/* scatter-symbol-morph steps through eleven options; a sequence longer than
   this is not one anybody will step through by hand. */
const MAX_TICKS = 24;

/* Tick the page's setInterval callbacks by hand and collect what they set.
   `steps` is what the page showed before the first tick. Answers the steps
   and where the cycle closes (loopTo), or null when there is no sequence to
   record: no interval, a callback that throws, or -- when `mustCycle` -- ticks
   that never come back round. */
function playIntervals(collected, steps, mustCycle) {
  const intervals = collected.intervals || [];
  if (!intervals.length) return null;
  const key = (s) => s.json + '\u0000' + JSON.stringify(s.opts);
  const seen = new Map();
  steps.forEach((s, i) => { if (!seen.has(key(s))) seen.set(key(s), i); });
  const out = steps.slice();
  for (let t = 0; t < MAX_TICKS; t++) {
    const before = (collected.calls || []).length;
    try {
      for (const iv of intervals) iv.fn();
    }
    catch (e) {
      return null;
    }
    for (const s of (collected.calls || []).slice(before)) {
      const k = key(s);
      if (seen.has(k)) {
        const at = seen.get(k);
        /* THE SAME OPTION AGAIN IS NOT A CYCLE. A clock re-sets its hands
           every tick and, ticked faster than time moves, sets the very same
           option twice: that is a live feed standing still. */
        if (at === out.length - 1) {
          if (mustCycle || out.length < 2) return null;
          return { steps: out, loopTo: null, interval: intervals[0].ms };
        }
        return { steps: out, loopTo: at, interval: intervals[0].ms };
      }
      seen.set(k, out.length);
      out.push(s);
    }
  }
  if (mustCycle || out.length < 2) return null;
  return { steps: out, loopTo: 0, interval: intervals[0].ms, fixed: true };
}

/* A PAGE THAT KEEPS UPDATING ITSELF. bar-race sets its option and then, every
   three seconds, adds random amounts to the bars; the gauges draw a new
   reading every two; bar-race-country queues one setTimeout per year. None of
   that cycles, so playIntervals (rightly) records no sequence -- and the demo
   showed the first frame of a race that never ran. Such a page is run again
   from scratch with its timers on a virtual clock: the option it set is step
   one, and every setOption its timers make, in the order the clock would fire
   them (a timeout at its due time, an interval every `ms`), is the next step,
   up to LIVE_STEPS (and no more than LIVE_BYTES of step files: dynamic-data2
   shifts a thousand points a second, 133 KB a step). Math.random is whatever the run was given (`--seeded` for
   a reproducible gallery), and `new Date()` reads the virtual clock, so the
   steps say what the page would have shown at those moments.
   The sequence plays once and stops (loopTo null) at the page's own rhythm:
   the interval of its setInterval, else the gap between its timeouts.
   NOT RECORDED: a page whose update sets what it set the tick before (a feed
   standing still), and the LIVE_SKIP pages -- gauge-clock shows the time it
   is NOW, which no recorded step can. */
const LIVE_STEPS = 30;
const LIVE_BYTES = 640 * 1024;
const LIVE_SKIP = new Set(['gauge-clock']);

function playLive(collected, first) {
  const intervals = collected.intervals || [];
  const clock = collected.clock;
  const out = [first];
  const times = [0];
  const nextIv = intervals.map((iv) => (iv.ms > 0 ? iv.ms : 1));
  let guard = 0;
  let bytes = 0;
  while (out.length < LIVE_STEPS && bytes <= LIVE_BYTES && guard++ < 10000) {
    /* the earliest event: a queued timeout, else an interval */
    let tAt = Infinity, tIdx = -1;
    (collected.timeouts || []).forEach((t, i) => {
      if (t.due < tAt || (t.due === tAt && tIdx >= 0 &&
          t.seq < collected.timeouts[tIdx].seq)) { tAt = t.due; tIdx = i; }
    });
    let iAt = Infinity, iIdx = -1;
    nextIv.forEach((d, i) => { if (d < iAt) { iAt = d; iIdx = i; } });
    if (tIdx < 0 && iIdx < 0) break;
    const before = (collected.calls || []).length;
    let at;
    try {
      if (tIdx >= 0 && tAt <= iAt) {
        const t = collected.timeouts.splice(tIdx, 1)[0];
        at = t.due;
        clock.now = clock.base + at;
        t.fn();
      }
      else {
        at = iAt;
        clock.now = clock.base + at;
        nextIv[iIdx] += intervals[iIdx].ms > 0 ? intervals[iIdx].ms : 1;
        intervals[iIdx].fn();
      }
    }
    catch (e) {
      return null;
    }
    for (const s of (collected.calls || []).slice(before)) {
      const prev = out[out.length - 1];
      if (s.json === prev.json &&
          JSON.stringify(s.opts) === JSON.stringify(prev.opts)) return null;
      bytes += s.json.length;
      if (bytes > LIVE_BYTES) break;
      out.push(s);
      times.push(at);
      if (out.length >= LIVE_STEPS) break;
    }
  }
  if (out.length < 3) return null;
  const gaps = [];
  for (let i = 1; i < times.length; i++) {
    if (times[i] > times[i - 1]) gaps.push(times[i] - times[i - 1]);
  }
  gaps.sort((a, b) => a - b);
  const interval = gaps.length ? gaps[Math.floor(gaps.length / 2)] : 0;
  return { steps: out, loopTo: null, interval, live: true };
}

/* The pending timeouts, run in the order a browser would (due time, then the
   order they were set), those they set included. */
function runTimeouts(collected) {
  let guard = 0;
  while ((collected.timeouts || []).length && guard++ < 10000) {
    let idx = 0;
    collected.timeouts.forEach((t, i) => {
      const b = collected.timeouts[idx];
      if (t.due < b.due || (t.due === b.due && t.seq < b.seq)) idx = i;
    });
    const t = collected.timeouts.splice(idx, 1)[0];
    t.fn();
  }
}

/* Local stand-ins for what an example expects the page to provide. Anything
   that reaches the network is refused rather than faked: an example whose data
   we do not have is an example we cannot show honestly. */
/* THE VIRTUAL CLOCK. `new Date()` and Date.now() read it (a Date made from
   arguments is untouched): a page that labels its points with the time of day
   or counts from today harvests the same option on every machine and every
   day, and the live steps (playLive) see the time move by the page's own
   interval. Monday 5 January 2026, 09:30 UTC. */
const CLOCK_BASE = Date.UTC(2026, 0, 5, 9, 30, 0);
function makeClockDate(clock) {
  return class ClockDate extends Date {
    constructor(...a) {
      if (a.length === 0) super(clock.now);
      else super(...a);
    }
    static now() { return clock.now; }
  };
}

/* What a page draws on a canvas of its own (watermark's pattern) cannot be
   carried in JSON: the 2D context answers every call and draws nothing, and
   the canvas is written as null where the option holds it, the loss named in
   the entry. */
function makeCanvas(collected) {
  const ctx = new Proxy({}, {
    get(target, k) {
      if (k in target) return target[k];
      if (k === 'measureText') return (s) => ({ width: String(s).length * 6 });
      return () => {};
    },
    set(target, k, v) { target[k] = v; return true; }
  });
  return {
    style: {}, width: 300, height: 150,
    getContext: () => ctx,
    toDataURL: () => '',
    toJSON() {
      collected.lost = collected.lost || [];
      if (collected.lost.indexOf('canvas') < 0) collected.lost.push('canvas');
      return null;
    }
  };
}

/* REMOTE FILES THAT ONLY CALLBACKS READ. bar-race-country fetches emoji
   flags from a CDN, and the only reader is a yAxis.axisLabel.formatter --
   a function, dropped by the harvest whatever the flags were. Answering the
   fetch with an empty list therefore changes nothing that is harvested, and
   lets the rest of the page run; the entry still names the file
   (`stubbedRemote`). Anything a written option would read stays refused. */
const CALLBACK_ONLY_REMOTE = {
  'emoji-flags@1.3.0/data.json': []
};
/* Scripts from a CDN whose only use is inside callbacks: map-usa-projection
   builds d3.geoAlbersUsa() and calls it only from projection.project /
   unproject. The stand-in answers the calls the page makes while it builds
   its option and nothing else. */
function makeD3Stub() {
  const projection = function () { return [NaN, NaN]; };
  projection.invert = function () { return [NaN, NaN]; };
  return { geoAlbersUsa: () => projection };
}

function makeSandbox(collected) {
  const clock = collected.clock ||
    (collected.clock = { base: CLOCK_BASE, now: CLOCK_BASE });
  const realEc = realEcharts;
  const sandbox = {
    option: undefined,
    app: { config: {}, configParameters: {}, title: '', titleCN: '' },
    myChart: {
      setOption(opt, opts) { recordSetOption(collected, opt, opts); },
      showLoading() {}, hideLoading() {}, on() {}, off() {},
      getWidth: () => 600, getHeight: () => 400, resize() {}, dispose() {},
      getZr: () => ({ on() {}, off() {}, add() {}, remove() {},
                      configLayer() {}, refresh() {},
                      getWidth: () => 600, getHeight: () => 400 }),
      getModel: () => null, setOption2: () => {}, appendData() {},
      dispatchAction() {}, convertToPixel: () => [0, 0],
      convertFromPixel: () => [0, 0],
      getOption: () => sandbox.option || {}
    },
    echarts: {
      // Enough surface for the option literals that call into it.
      graphic: {
        LinearGradient: function (x, y, x2, y2, stops) {
          return { type: 'linear', x, y, x2, y2, colorStops: stops };
        },
        RadialGradient: function (x, y, r, stops) {
          return { type: 'radial', x, y, r, colorStops: stops };
        }
      },
      /* THE REAL HELPERS, not stand-ins: an identity modifyHSL harvested
         one colour for every nutrient group, and addCommas wrote titles
         as "500000 Data" where the page says "500,000 Data". */
      color: realEc.color,
      format: {
        formatTime: realEc.format.formatTime,
        addCommas: realEc.format.addCommas,
        encodeHTML: realEc.format.encodeHTML
      },
      number: {
        parseDate: realEc.number.parseDate,
        round: realEc.number.round,
        // The real one: treemap-visual scales its colour dimension with it,
        // and an identity stub harvested the raw growth percentages instead.
        linearMap: realEc.number.linearMap
      },
      time: {
        parse: realEc.time.parse,
        format: realEc.time.format,
        roundTime: realEc.time.roundTime
      },
      util: realEc.util,
      version: realEc.version,
      registerMap() { collected.usedMap = true; },
      registerTransform(t) {
        collected.transforms = collected.transforms || [];
        collected.transforms.push(String(t && t.type));
      },
      getMap: () => null
    },
    ROOT_PATH: '__ROOT__',
    CDN_PATH: '__CDN__/',
    console: { log() {}, warn() {}, error() {} },
    Math: SEEDED ? seededMath() : Math, JSON, Date: makeClockDate(clock),
    Number, String, Array, Object, isNaN, parseInt,
    parseFloat, encodeURIComponent, decodeURIComponent,
    structuredClone: (v) => JSON.parse(JSON.stringify(v)),
    innerWidth: 600, innerHeight: 400
  };
  /* echarts-stat, as far as the examples touch it: a transform each, known by
     its name. The computing is the port's own (see the header). */
  const statTransform = (name) => ({
    type: 'ecStat:' + name,
    transform() {
      throw new Error('ecStat runs in the chart, not in the harvester');
    }
  });
  sandbox.ecStat = {
    transform: {
      regression: statTransform('regression'),
      histogram: statTransform('histogram'),
      clustering: statTransform('clustering')
    }
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  /* Belt and braces for any file that still transpiles to a CommonJS
     preamble: an `exports` object nobody reads is harmless, and a missing one
     kills the whole example over a marker. */
  sandbox.exports = {};
  sandbox.module = { exports: sandbox.exports };
  const refuse = (what) => () => {
    collected.needsNetwork = what;
    throw new Error('example loads data at runtime (' + what + ')');
  };
  /* A URL under ROOT_PATH is a file in the examples clone. Anything else is
     genuinely remote and stays refused -- a harvester that invented data would
     produce a gallery that looks right and shows nothing real. */
  /* `__ROOT__/x` is the clone's public/x (data/, data-gl/, ...); an older
     spelling without ROOT_PATH is looked up under public/data/. */
  const localFor = (url) => {
    const u = String(url).split('?')[0];
    if (u.startsWith('__ROOT__/')) {
      const p = path.join(SRC, 'public', u.slice('__ROOT__/'.length));
      return fs.existsSync(p) ? p : null;
    }
    const at = u.indexOf('/data/');
    if (at < 0) return null;
    const rel = u.slice(at + '/data/'.length);
    const p = path.join(DATA_DIR, rel);
    return fs.existsSync(p) ? p : null;
  };
  const loadSync = (url) => {
    const u = String(url);
    if (u.startsWith('__CDN__/') &&
        Object.prototype.hasOwnProperty.call(CALLBACK_ONLY_REMOTE,
          u.slice('__CDN__/'.length))) {
      collected.stubbedRemote = collected.stubbedRemote || [];
      collected.stubbedRemote.push(u.slice('__CDN__/'.length));
      return JSON.parse(JSON.stringify(
        CALLBACK_ONLY_REMOTE[u.slice('__CDN__/'.length)]));
    }
    const p = localFor(url);
    if (!p) {
      /* a file of the examples site the clone does not carry (data-gl's
         winds.json) is said as such, not as a network fetch */
      if (u.startsWith('__ROOT__/')) {
        collected.missingLocal = u.slice('__ROOT__/'.length).split('?')[0];
      }
      else collected.needsNetwork = String(url).slice(0, 80);
      throw new Error('data is not in the examples clone');
    }
    const text = fs.readFileSync(p, 'utf8');
    collected.usedData = (collected.usedData || 0) + 1;
    if (/\.json$/i.test(p)) return JSON.parse(text);
    return text;
  };
  /* jQuery's two shapes: the callback argument, and the .done()/.then()
     chain. Both resolve immediately. */
  const resolved = (data) => {
    const chain = {
      /* what $.when hands a done callback per request: jQuery's
         [data, statusText, jqXHR] */
      jqArgs: [data, 'success', {}],
      done: (f) => { f(data); return chain; },
      then: (f) => { f(data); return chain; },
      fail: () => chain,
      always: (f) => { f(data); return chain; }
    };
    return chain;
  };
  const jqLike = (url, cb) => {
    const data = loadSync(url);
    if (typeof cb === 'function') cb(data);
    return resolved(data);
  };
  /* $.getScript: only the callback-only CDN scripts (makeD3Stub). */
  const getScript = (url) => {
    const u = String(url);
    if (/^__CDN__\/d3-(geo|array)@/.test(u)) {
      sandbox.d3 = sandbox.d3 || makeD3Stub();
      collected.stubbedRemote = collected.stubbedRemote || [];
      collected.stubbedRemote.push(u.slice('__CDN__/'.length));
      return resolved('');
    }
    collected.needsNetwork = u.slice(0, 80);
    throw new Error('example loads a script at runtime');
  };
  /* $.when(a, b, ...).done(f): f(argsOfA, argsOfB, ...); with a single
     request jQuery spreads its arguments instead. */
  const when = (...reqs) => {
    const args = reqs.length === 1
      ? (reqs[0] && reqs[0].jqArgs) || [reqs[0]]
      : reqs.map((r) => (r && r.jqArgs) || r);
    const chain = {
      done: (f) => { f(...args); return chain; },
      then: (f) => { f(...args); return chain; },
      fail: () => chain,
      always: (f) => { f(...args); return chain; }
    };
    return chain;
  };
  sandbox.$ = { get: jqLike, getJSON: jqLike, getScript, when,
                ajax: (opt) => jqLike(opt && opt.url, opt && opt.success) };
  sandbox.fetch = (url) => {
    const data = loadSync(url);
    const res = {
      ok: true,
      json: () => Promise.resolve(data),
      text: () => Promise.resolve(typeof data === 'string'
        ? data : JSON.stringify(data))
    };
    return Promise.resolve(res);
  };
  /* QUEUED, NOT RUN INLINE. A browser runs a timeout after the page's script
     -- after the gallery has set the page's `option` -- so bar-race's
     `setTimeout(run, 0)` must not add to the bars before the first frame is
     written down (run inline, it did, and the race's first frame was its
     second). The queue is run once the option is recorded (runTimeouts), or
     on the virtual clock by playLive. */
  sandbox.setTimeout = (f, ms) => {
    if (typeof f !== 'function') return 0;
    collected.timeouts = collected.timeouts || [];
    collected.seq = (collected.seq || 0) + 1;
    collected.timeouts.push({ fn: f, seq: collected.seq,
      due: (clock.now - clock.base) + (Number(ms) || 0) });
    return collected.seq;
  };
  /* Kept, not run: the sequence ticker (playIntervals) runs them, after the
     option the page showed first has been written down. */
  sandbox.setInterval = (fn, ms) => {
    if (typeof fn !== 'function') return 0;
    collected.intervals = collected.intervals || [];
    collected.intervals.push({ fn, ms: Number(ms) || 0 });
    return collected.intervals.length;
  };
  sandbox.clearInterval = () => {};
  sandbox.clearTimeout = () => {};
  sandbox.require = refuse('require');
  sandbox.Promise = Promise;
  sandbox.Image = function () { return { src: '', onload: null }; };
  sandbox.document = {
    createElement: (tag) => (String(tag).toLowerCase() === 'canvas'
      ? makeCanvas(collected) : { getContext: () => ({}), style: {} }),
    addEventListener() {}, getElementById: () => null
  };
  sandbox.addEventListener = () => {};
  /* The same local files as $.get, for the examples that read binary data:
     send() answers at once, from the examples clone or not at all. */
  sandbox.XMLHttpRequest = function () {
    const xhr = {
      responseType: '', response: null, responseText: '',
      status: 0, readyState: 0, onload: null, onreadystatechange: null,
      url: '',
      open(method, url) { xhr.url = url; },
      setRequestHeader() {},
      addEventListener(type, fn) { if (type === 'load') xhr.onload = fn; },
      send() {
        const p = localFor(xhr.url);
        if (!p) {
          collected.needsNetwork = String(xhr.url).slice(0, 80);
          throw new Error('data is not in the examples clone');
        }
        const buf = fs.readFileSync(p);
        collected.usedData = (collected.usedData || 0) + 1;
        if (xhr.responseType === 'arraybuffer') {
          xhr.response = buf.buffer.slice(buf.byteOffset,
                                          buf.byteOffset + buf.length);
        }
        else {
          xhr.responseText = buf.toString('utf8');
          xhr.response = xhr.responseType === 'json'
            ? JSON.parse(xhr.responseText) : xhr.responseText;
        }
        xhr.status = 200;
        xhr.readyState = 4;
        if (typeof xhr.onload === 'function') xhr.onload.call(xhr, { target: xhr });
        if (typeof xhr.onreadystatechange === 'function') {
          xhr.onreadystatechange.call(xhr);
        }
      }
    };
    return xhr;
  };
  return sandbox;
}

/* JSON.stringify silently drops functions (an explicit undefined is kept as
   null, below). Count them first, so the entry can say what was lost instead
   of pretending the option is whole. */
function countCallbacks(node, seen) {
  if (node === null || typeof node !== 'object') {
    return typeof node === 'function' ? 1 : 0;
  }
  if (seen.has(node)) return 0;
  seen.add(node);
  let n = 0;
  for (const k of Object.keys(node)) {
    const v = node[k];
    if (typeof v === 'function') n++;
    else n += countCallbacks(v, seen);
  }
  return n;
}

/* AN EXPLICIT undefined IS WRITTEN AS null. JSON.stringify drops an own key
   whose value is undefined, and upstream can tell the two apart: sunburst's
   `sort: undefined` means "do not sort" (the key is present, so the 'desc'
   default never merges in), while an absent `sort` sorts descending. The same
   holds for every key: zrender's merge keeps a present key whatever its value
   (`key in target`), and Model.get tests `== null`, so null and undefined are
   one answer upstream -- the SSR of every file this rule changed is identical
   either way, and candlestick-brush's differs from the key dropped. Functions
   still vanish -- they are callbacks, counted above. The rule is general, not
   a list of keys: the stringifier only visits own enumerable keys, so
   everything it turns into null was written into the option by the example. */
function keepExplicitUndefined(key, value) {
  return value === undefined && key !== '' ? null : value;
}

function seriesTypesIn(option) {
  const out = new Set();
  const s = option && option.series;
  const list = Array.isArray(s) ? s : (s ? [s] : []);
  for (const one of list) if (one && one.type) out.add(String(one.type));
  return Array.from(out).sort();
}

function componentsIn(option) {
  const known = ['title', 'legend', 'tooltip', 'grid', 'xAxis', 'yAxis',
                 'polar', 'radar', 'geo', 'dataZoom', 'visualMap', 'toolbox',
                 'timeline', 'graphic', 'calendar', 'dataset', 'matrix',
                 'axisPointer', 'brush', 'parallel', 'singleAxis', 'angleAxis',
                 'radiusAxis'];
  return known.filter((k) => option && option[k] != null);
}

/* One run of an example's script in a fresh sandbox: what it showed first
   (`shown`: its option, snapshotted before any timer runs -- or, without one,
   every setOption it made, its timeouts run). `keepTimers` leaves a page with
   an option its timeouts queued, for playLive. */
function runExample(src, file, collected, keepTimers) {
  collected.namer = makeNamer(file.replace(/\.ts$/, ''));
  const sandbox = makeSandbox(collected);
  vm.createContext(sandbox);
  new vm.Script(deTypeScript(src), { filename: file })
    .runInContext(sandbox, { timeout: 5000 });
  const option = sandbox.option;
  const hasOption = option != null && typeof option === 'object';
  let shown;
  if (hasOption) {
    shown = [{ option,
      json: JSON.stringify(option, collected.namer.replacer, 1), opts: null }];
    collected.pendingTimeouts = (collected.timeouts || []).length;
    if (!keepTimers) collected.timeouts = [];
  }
  else {
    runTimeouts(collected);
    shown = (collected.calls || []).slice();
    if (!shown.length) throw new Error('the file defines no option object');
  }
  return { option, hasOption, shown, sandbox };
}

function main() {
  fs.mkdirSync(OUT, { recursive: true });
  let files = fs.readdirSync(TS_DIR)
    .filter((f) => f.endsWith('.ts'))
    .sort();
  if (ONLY.length) {
    const missing = ONLY.filter((id) => !files.includes(id + '.ts'));
    if (missing.length) {
      console.error('no such example: ' + missing.join(', '));
      process.exit(2);
    }
    files = files.filter((f) => ONLY.includes(f.replace(/\.ts$/, '')));
  }

  const index = [];
  let ok = 0, failed = 0;

  for (const file of files) {
    const id = file.replace(/\.ts$/, '');
    const src = fs.readFileSync(path.join(TS_DIR, file), 'utf8');
    const head = readHeader(src);
    const entry = {
      id,
      title: head.title || id,
      titleCN: head.titleCN || '',
      category: head.category || id.split('-')[0],
      difficulty: Number(head.difficulty || 0),
      ok: false,
      reason: '',
      seriesTypes: [],
      components: [],
      callbacks: 0
    };

    let collected = {};
    try {
      let run = runExample(src, file, collected);
      const hasOption = run.hasOption;
      /* What the page shows first: its `option`, written down BEFORE any tick
         can mutate it -- or, without one, the setOption calls it made. */
      let seq = playIntervals(collected, run.shown, hasOption);
      /* a page that goes on updating itself: run it again on the clock */
      if (!seq && hasOption && !LIVE_SKIP.has(id) &&
          ((collected.intervals || []).length ||
           (collected.pendingTimeouts || 0) > 0)) {
        const fresh = {};
        const again = runExample(src, file, fresh, true);
        const live = playLive(fresh, again.shown[0]);
        if (live) {
          collected = fresh;
          run = again;
          seq = live;
        }
      }
      if (!seq) seq = { steps: run.shown, interval: 0, loopTo: null };
      /* each distinct option once, in order of first use */
      const files = [];
      const fileOf = new Map();
      for (const s of seq.steps) {
        if (fileOf.has(s.json)) continue;
        const name = files.length ? id + '.' + (files.length + 1) + '.json'
                                  : id + '.json';
        fileOf.set(s.json, name);
        files.push({ name, json: s.json, option: s.option });
      }
      let types = [], comps = [];
      for (const fl of files) {
        entry.callbacks += countCallbacks(fl.option, new WeakSet()) -
          countNamed(fl.option, new WeakSet());
        types = types.concat(seriesTypesIn(fl.option));
        comps = comps.concat(componentsIn(fl.option));
      }
      /* the handlers the files name, for the demo to register */
      if (collected.namer.names.size) {
        entry.handlers = Array.from(new Set(collected.namer.names.values()));
      }
      if (collected.lost && collected.lost.length) entry.lost = collected.lost;
      if (collected.stubbedRemote && collected.stubbedRemote.length) {
        entry.stubbedRemote = Array.from(new Set(collected.stubbedRemote));
      }
      entry.seriesTypes = Array.from(new Set(types)).sort();
      entry.components = componentsIn(Object.fromEntries(
        comps.map((k) => [k, true])));
      if (collected.transforms && collected.transforms.length) {
        entry.registersTransforms = collected.transforms;
      }
      entry.bytes = files.reduce((n, fl) => n + fl.json.length, 0);
      if (files.length > 1 || seq.steps.length > 1) {
        entry.sequence = { interval: seq.interval || 0, loopTo: seq.loopTo,
          steps: seq.steps.map((s) => s.opts
            ? { file: fileOf.get(s.json), opts: s.opts }
            : { file: fileOf.get(s.json) }) };
        if (seq.fixed) entry.sequence.fixed = true;
        if (seq.live) entry.sequence.live = true;
      }
      /* A CAP, AND THE REASON RECORDED. Eleven examples carry between 1 and
         64 MB of generated points -- they are the large-mode stress cases,
         the very ones this port cannot render anyway -- and bundling them
         would put 180 MB of test data in a control library. Everything under
         the cap (253 of 264) is committed so the demo runs from a fresh
         clone. A sequence is capped on its largest file. */
      const biggest = Math.max(...files.map((fl) => fl.json.length));
      if (GENERATED[id] && files.length === 1) {
        /* THE DATA IS MADE IN THE DEMO (see GENERATED): the option without
           it, and what the Pascal generator must give back */
        const opt = JSON.parse(files[0].json);
        const fill = [];
        for (const p of GENERATED[id]) {
          const v = getPath(opt, p);
          if (!Array.isArray(v)) throw new Error('no array at ' + p);
          fill.push({ path: p, count: v.length, hash: fnvOf(v) });
          setPath(opt, p, []);
        }
        const json = JSON.stringify(opt, null, 1);
        fs.writeFileSync(path.join(OUT, files[0].name), json, 'utf8');
        entry.generated = { bytes: files[0].json.length, fill };
        entry.bytes = json.length;
        entry.ok = true;
        ok++;
      }
      else if (biggest > MAX_BYTES && files.length === 1 && SHIP_GZ.has(id) &&
               zlib.gzipSync(files[0].json, { level: 9 }).length <= GZ_MAX) {
        /* COMPRESSED: data the page loads, small once gzipped */
        const gz = zlib.gzipSync(files[0].json, { level: 9 });
        fs.writeFileSync(path.join(OUT, id + '.json.gz'), gz);
        entry.file = id + '.json.gz';
        entry.gzBytes = gz.length;
        entry.ok = true;
        ok++;
      }
      else if (biggest > MAX_BYTES) {
        entry.reason = 'converted, but ' +
          (biggest / 1048576).toFixed(1) + ' MB is too large to bundle';
        if (files.some((fl) => fl.option && fl.option.bmap)) {
          entry.reason += '; it also draws on Baidu Map (bmap), which needs ' +
            'the online Baidu Maps API';
        }
        entry.tooBig = true;
        failed++;
      }
      else {
        for (const fl of files) {
          fs.writeFileSync(path.join(OUT, fl.name), fl.json, 'utf8');
        }
        entry.ok = true;
        ok++;
      }
    }
    catch (e) {
      entry.reason = collected.missingLocal
        ? 'needs ' + collected.missingLocal +
          ', which the examples clone does not carry'
        : collected.needsNetwork
          ? 'loads its data at runtime (' + collected.needsNetwork + ')'
          : String(e.message || e).slice(0, 200);
      failed++;
    }
    index.push(entry);
  }

  if (ONLY.length) {
    /* A partial run replaces just its own entries, in place; every other entry
       is re-serialised exactly as the full run wrote it (same stringify). */
    const indexPath = path.join(OUT, 'index.json');
    const whole = JSON.parse(fs.readFileSync(indexPath, 'utf8'));
    for (const e of index) {
      const at = whole.entries.findIndex((x) => x.id === e.id);
      if (at < 0) whole.entries.push(e);
      else whole.entries[at] = e;
    }
    whole.total = whole.entries.length;
    whole.converted = whole.entries.filter((x) => x.ok).length;
    fs.writeFileSync(indexPath, JSON.stringify(whole, null, 1), 'utf8');
    console.log('harvested ' + files.length + ' (' + ok + ' converted' +
                (SEEDED ? ', seeded' : '') + '): ' +
                index.map((e) => e.id + (e.ok ? '' : ' [' + e.reason + ']'))
                  .join(', '));
    process.exit(0);
  }

  fs.writeFileSync(path.join(OUT, 'index.json'),
    JSON.stringify({ source: 'apache/echarts-examples', total: files.length,
                     converted: ok, entries: index }, null, 1), 'utf8');

  const byCat = {};
  for (const e of index) {
    byCat[e.category] = byCat[e.category] || { n: 0, ok: 0 };
    byCat[e.category].n++;
    if (e.ok) byCat[e.category].ok++;
  }
  console.log('examples: ' + files.length + ', converted: ' + ok +
              ', not converted: ' + failed);
  const cats = Object.keys(byCat).sort();
  for (const c of cats) {
    console.log('  ' + c.padEnd(16) + byCat[c].ok + '/' + byCat[c].n);
  }
}

/* Run as a script it harvests; required (the gallery renderItem oracle,
   tools/advchart-oracle/gallery-renderitem.js) it hands over the sandbox, so
   the oracle evaluates an example exactly as the harvest did and gets the
   live functions the harvest named. */
if (require.main === module) {
  main();
  process.exit(0);
}
else {
  module.exports = {
    SRC, TS_DIR, readHeader, runExample,
    setSeeded(v) { SEEDED = !!v; }
  };
}
