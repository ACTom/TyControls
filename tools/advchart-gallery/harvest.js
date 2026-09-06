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
 * Usage:  node harvest.js [pathToEchartsExamples] [outDir]
 */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const SRC = process.argv[2] || 'D:/Projects/echarts-examples';
const OUT = process.argv[3] ||
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

/* Local stand-ins for what an example expects the page to provide. Anything
   that reaches the network is refused rather than faked: an example whose data
   we do not have is an example we cannot show honestly. */
function makeSandbox(collected) {
  const sandbox = {
    option: undefined,
    app: { config: {}, configParameters: {}, title: '', titleCN: '' },
    myChart: {
      setOption() {}, showLoading() {}, hideLoading() {}, on() {},
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
        formatTime: () => '', addCommas: (v) => String(v),
        encodeHTML: (s) => String(s)
      },
      number: {
        parseDate: (v) => new Date(v),
        round: (v, p) => Number(Number(v).toFixed(p == null ? 10 : p)),
        linearMap: (v) => v
      },
      time: {
        parse: (v) => new Date(v).getTime(),
        format: () => '',
        roundTime: (v) => v
      },
      util: { map: (a, f) => Array.prototype.map.call(a, f) },
      registerMap() { collected.usedMap = true; },
      getMap: () => null
    },
    ROOT_PATH: '__ROOT__',
    console: { log() {}, warn() {}, error() {} },
    Math, JSON, Date, Number, String, Array, Object, isNaN, parseInt,
    parseFloat, encodeURIComponent, decodeURIComponent
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
  sandbox.setInterval = () => 0;
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
  sandbox.XMLHttpRequest = function () {
    return { open() {}, send() {}, addEventListener() {} };
  };
  return sandbox;
}

/* JSON.stringify silently drops functions and undefined. Count them first, so
   the entry can say what was lost instead of pretending the option is whole. */
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
  const files = fs.readdirSync(TS_DIR)
    .filter((f) => f.endsWith('.ts'))
    .sort();

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
      if (option == null || typeof option !== 'object') {
        throw new Error('the file defines no option object');
      }
      entry.callbacks = countCallbacks(option, new WeakSet());
      entry.seriesTypes = seriesTypesIn(option);
      entry.components = componentsIn(option);
      const json = JSON.stringify(option, null, 1);
      entry.bytes = json.length;
      /* A CAP, AND THE REASON RECORDED. Ten examples carry between 1 and 64 MB
         of generated points -- they are the large-mode stress cases, the very
         ones this port cannot render anyway -- and bundling them would put
         120 MB of test data in a control library. Everything under the cap
         (244 of 254) is committed so the demo runs from a fresh clone. */
      if (json.length > MAX_BYTES) {
        entry.reason = 'converted, but ' +
          (json.length / 1048576).toFixed(1) + ' MB is too large to bundle';
        entry.tooBig = true;
        failed++;
      }
      else {
        fs.writeFileSync(path.join(OUT, id + '.json'), json, 'utf8');
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
