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
 * ticks produced, marked `fixed: true`.
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
 */
'use strict';
// Before anything creates a Date: ECharts parses 'yyyy-mm-dd' as local time.
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

if (new Date(2017, 0, 1).getTimezoneOffset() !== 0) {
  console.error('TZ=UTC did not take effect; the harvested dates would ' +
    'depend on the time zone of this machine.');
  process.exit(2);
}

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const realEcharts = require(DIST);

/* Flags anywhere on the command line; the positional arguments are the rest. */
const argv = process.argv.slice(2);
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
    json: JSON.stringify(opt, keepExplicitUndefined, 1),
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

/* Local stand-ins for what an example expects the page to provide. Anything
   that reaches the network is refused rather than faked: an example whose data
   we do not have is an example we cannot show honestly. */
function makeSandbox(collected) {
  const sandbox = {
    option: undefined,
    app: { config: {}, configParameters: {}, title: '', titleCN: '' },
    myChart: {
      setOption(opt, opts) { recordSetOption(collected, opt, opts); },
      showLoading() {}, hideLoading() {}, on() {},
      getWidth: () => 600, getHeight: () => 400, resize() {}, dispose() {},
      getZr: () => ({ on() {}, off() {}, add() {}, remove() {},
                      getWidth: () => 600, getHeight: () => 400 }),
      getModel: () => null, setOption2: () => {}, appendData() {},
      dispatchAction() {}, convertToPixel: () => [0, 0],
      convertFromPixel: () => [0, 0]
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
      color: { modifyHSL: (c) => c, lift: (c) => c },
      format: {
        formatTime: realEcharts.format.formatTime,
        addCommas: (v) => String(v),
        encodeHTML: (s) => String(s)
      },
      number: {
        parseDate: realEcharts.number.parseDate,
        round: (v, p) => Number(Number(v).toFixed(p == null ? 10 : p)),
        // The real one: treemap-visual scales its colour dimension with it,
        // and an identity stub harvested the raw growth percentages instead.
        linearMap: realEcharts.number.linearMap
      },
      time: {
        parse: realEcharts.time.parse,
        format: realEcharts.time.format,
        roundTime: realEcharts.time.roundTime
      },
      util: { map: (a, f) => Array.prototype.map.call(a, f) },
      registerMap() { collected.usedMap = true; },
      registerTransform(t) {
        collected.transforms = collected.transforms || [];
        collected.transforms.push(String(t && t.type));
      },
      getMap: () => null
    },
    ROOT_PATH: '__ROOT__',
    console: { log() {}, warn() {}, error() {} },
    Math: SEEDED ? seededMath() : Math, JSON, Date, Number, String, Array, Object, isNaN, parseInt,
    parseFloat, encodeURIComponent, decodeURIComponent
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
  const localFor = (url) => {
    const u = String(url);
    const at = u.indexOf('/data/');
    if (at < 0) return null;
    const rel = u.slice(at + '/data/'.length).split('?')[0];
    const p = path.join(DATA_DIR, rel);
    return fs.existsSync(p) ? p : null;
  };
  const loadSync = (url) => {
    const p = localFor(url);
    if (!p) {
      collected.needsNetwork = String(url).slice(0, 80);
      throw new Error('data is not in the examples clone');
    }
    const text = fs.readFileSync(p, 'utf8');
    collected.usedData = (collected.usedData || 0) + 1;
    if (/\.json$/i.test(p)) return JSON.parse(text);
    return text;
  };
  /* jQuery's two shapes: the callback argument, and the .done()/.then()
     chain. Both resolve immediately. */
  const jqLike = (url, cb) => {
    const data = loadSync(url);
    if (typeof cb === 'function') cb(data);
    const chain = {
      done: (f) => { f(data); return chain; },
      then: (f) => { f(data); return chain; },
      fail: () => chain,
      always: (f) => { f(data); return chain; }
    };
    return chain;
  };
  sandbox.$ = { get: jqLike, getJSON: jqLike,
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
  sandbox.setTimeout = (f) => { if (typeof f === 'function') f(); return 0; };
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
    createElement: () => ({ getContext: () => ({}), style: {} }),
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

    const collected = {};
    try {
      const sandbox = makeSandbox(collected);
      vm.createContext(sandbox);
      new vm.Script(deTypeScript(src), { filename: file })
        .runInContext(sandbox, { timeout: 5000 });
      const option = sandbox.option;
      const hasOption = option != null && typeof option === 'object';
      const calls = collected.calls || [];
      if (!hasOption && !calls.length) {
        throw new Error('the file defines no option object');
      }
      /* What the page shows first: its `option`, written down BEFORE any tick
         can mutate it -- or, without one, the setOption calls it made. */
      const shown = hasOption
        ? [{ option, json: JSON.stringify(option, keepExplicitUndefined, 1),
             opts: null }]
        : calls.slice();
      const seq = playIntervals(collected, shown, hasOption) ||
        { steps: shown, interval: 0, loopTo: null };
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
        entry.callbacks += countCallbacks(fl.option, new WeakSet());
        types = types.concat(seriesTypesIn(fl.option));
        comps = comps.concat(componentsIn(fl.option));
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
      }
      /* A CAP, AND THE REASON RECORDED. Eleven examples carry between 1 and
         64 MB of generated points -- they are the large-mode stress cases,
         the very ones this port cannot render anyway -- and bundling them
         would put 180 MB of test data in a control library. Everything under
         the cap (253 of 264) is committed so the demo runs from a fresh
         clone. A sequence is capped on its largest file. */
      const biggest = Math.max(...files.map((fl) => fl.json.length));
      if (biggest > MAX_BYTES) {
        entry.reason = 'converted, but ' +
          (biggest / 1048576).toFixed(1) + ' MB is too large to bundle';
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
      entry.reason = collected.needsNetwork
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

main();
process.exit(0);
