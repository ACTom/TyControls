#!/usr/bin/env node
/* Stage 1 of the AdvChart option-catalog pipeline.
 *
 * Reads Apache echarts-doc's own generated option schema -- the 29 MB en/zh
 * option.json produced by its build/build-doc.js -- and boils it down to a
 * compact, deduplicated intermediate that is COMMITTED to this repo.
 *
 * WHY TWO STAGES. The schema is 278 MB of build output living outside the repo,
 * and regenerating it needs node, npm and network. A fresh checkout must still
 * be able to rebuild the Pascal unit and to prove it is in sync, so the pinned
 * input has to be something the repo actually contains. This stage runs rarely
 * (when the targeted ECharts version moves); stage 2 runs from the committed
 * intermediate and is reproducible anywhere.
 *
 *   node tools/advchart/extract-catalog.js [schemaDir] [out]
 *
 * Input structure, established by measurement rather than assumption:
 *   node = { type: string[] | string, description: html, default?, uiControl?,
 *            properties?: {name:node}, items?: node, anyOf?: node[] }
 * Children hang off `properties`; homogeneous arrays off `items`; and exactly
 * five places carry `items.anyOf` -- discriminated unions whose tag is the
 * variant's own `properties.type.default` (series 23, dataZoom 2, visualMap 2,
 * graphic.elements 13, dataset.transform 3).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const schemaDir = process.argv[2] || 'D:/Projects/echarts-schema';
const outFile = process.argv[3] || path.join(__dirname, 'catalog.json');

function loadSchema(lang) {
  const p = path.join(schemaDir, lang, 'documents', 'option.json');
  return JSON.parse(fs.readFileSync(p, 'utf8')).option;
}

/* The variant tag of an anyOf member. Quoting is inconsistent in the source --
   series says "'line'" while graphic.elements says "group" -- so strip. */
function variantTag(v) {
  const d = v && v.properties && v.properties.type && v.properties.type.default;
  if (typeof d !== 'string') return null;
  return d.replace(/^'|'$/g, '');
}

/* Since-version survives only as an HTML block inside the description. */
const RE_VERSION = /<div\s+class="doc-partial-version">[\s\S]*?<code[^>]*>\s*v?([\d.]+)\s*<\/code>/;
function sinceOf(desc) {
  if (typeof desc !== 'string') return '';
  const m = desc.match(RE_VERSION);
  if (!m) return '';
  const parts = m[1].split('.');
  while (parts.length < 3) parts.push('0');   // the source carries a stray 'v5.0'
  return parts.join('.');
}

/* A one-line plain-text summary. The version div is stripped FIRST: leaving it
   in makes the summary of 291 options read "Since v6.0.0", which is exactly
   what the earlier spike shipped. */
function summarise(desc) {
  if (typeof desc !== 'string' || desc === '') return '';
  let s = desc.replace(/<div\s+class="doc-partial-version">[\s\S]*?<\/div>/g, ' ');
  s = s.replace(/<[^>]+>/g, ' ');
  s = s.replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<')
       .replace(/&gt;/g, '>').replace(/&amp;/g, '&').replace(/&nbsp;/g, ' ');
  s = s.replace(/\s+/g, ' ').trim();
  const stop = s.search(/[.!?]\s|[.!?]$|[\u3002\uFF01\uFF1F]/);
  if (stop > 0 && stop < 200) s = s.slice(0, stop + 1);
  if (s.length > 200) s = s.slice(0, 197) + '...';
  return s;
}

function typeOf(n) {
  if (!n || n.type === undefined) return '';
  return Array.isArray(n.type) ? n.type.join('|') : String(n.type);
}

function defaultOf(n) {
  if (!n || !Object.prototype.hasOwnProperty.call(n, 'default')) return null;
  const d = n.default;
  if (d === null) return 'null';
  if (typeof d === 'object') return JSON.stringify(d);
  return String(d);
}

/* ---- intern pools ---- */
const names = new Map(), namesArr = [];
const descs = new Map(), descsArr = [];
const enums = new Map(), enumsArr = [];
function intern(map, arr, s) {
  if (s === undefined || s === null) s = '';
  if (map.has(s)) return map.get(s);
  const i = arr.length; arr.push(s); map.set(s, i); return i;
}

const nodes = [];            // the DAG records
const byHash = new Map();    // canonical hash -> node index
const edges = [];            // flat (nameIdx, childIdx) pairs

let occurrences = 0, excluded = 0;
const mismatches = [];

/* Bottom-up hash-consing. Descriptions ARE part of the identity: leaving them
   out merges nodes that differ only in their prose, which would then have to
   carry a description per EDGE instead of per node -- more machinery than the
   40 % record saving is worth on a table this small. */
function build(en, zh, pathKey) {
  occurrences++;

  const kids = [];
  const props = (en && en.properties) || null;
  if (props) {
    for (const k of Object.keys(props)) {
      /* renderItem.return_* documents the JS return value of a callback, not an
         option path. Offering it in completion would be a lie. */
      if (/^return_/.test(k)) { excluded++; continue; }
      const zhChild = zh && zh.properties ? zh.properties[k] : null;
      const childKey = pathKey ? pathKey + '.' + k : k;
      kids.push([intern(names, namesArr, k), build(props[k], zhChild, childKey)]);
    }
  }

  /* Homogeneous array: descend into items under the '[]' edge. */
  if (en && en.items && !en.items.anyOf) {
    const zhItems = zh && zh.items && !zh.items.anyOf ? zh.items : null;
    kids.push([intern(names, namesArr, '[]'), build(en.items, zhItems, pathKey)]);
  }

  /* Discriminated union: pair EN and ZH BY TAG, never by index. The earlier
     spike paired by index, which silently gave two graphic.elements subtrees
     the wrong language's text -- graphic's variant order differs between the
     two files. */
  if (en && en.items && en.items.anyOf) {
    const zhByTag = new Map();
    if (zh && zh.items && zh.items.anyOf)
      for (const v of zh.items.anyOf) { const t = variantTag(v); if (t) zhByTag.set(t, v); }
    const enTags = [];
    for (const v of en.items.anyOf) {
      const tag = variantTag(v);
      if (!tag) continue;
      enTags.push(tag);
      const zhV = zhByTag.get(tag) || null;
      if (!zhV) mismatches.push(pathKey + ' variant ' + tag + ' missing in zh');
      kids.push([intern(names, namesArr, '=' + tag),
                 build(v, zhV, pathKey + '-' + tag)]);
    }
    for (const t of zhByTag.keys())
      if (!enTags.includes(t)) mismatches.push(pathKey + ' variant ' + t + ' only in zh');
  }

  const ui = (en && en.uiControl) || {};
  const rec = {
    t: typeOf(en),
    d: defaultOf(en),
    u: ui.type || '',
    e: ui.options ? intern(enums, enumsArr, ui.options) : -1,
    mn: ui.min !== undefined ? String(ui.min) : '',
    mx: ui.max !== undefined ? String(ui.max) : '',
    st: ui.step !== undefined ? String(ui.step) : '',
    v: sinceOf(en && en.description),
    de: intern(descs, descsArr, summarise(en && en.description)),
    dz: intern(descs, descsArr, summarise(zh && zh.description)),
    c: kids,
  };

  const h = crypto.createHash('sha1')
    .update(JSON.stringify([rec.t, rec.d, rec.u, rec.e, rec.mn, rec.mx, rec.st,
                            rec.v, rec.de, rec.dz, rec.c]))
    .digest('hex');
  if (byHash.has(h)) return byHash.get(h);

  const idx = nodes.length;
  nodes.push(rec);
  byHash.set(h, idx);
  return idx;
}

const enRoot = loadSchema('en');
const zhRoot = loadSchema('zh');
const root = build(enRoot, zhRoot, '');

/* Flatten the child lists into one edge array, so the Pascal side is two flat
   const arrays rather than a nested structure it cannot express. */
for (const n of nodes) {
  n.f = edges.length;
  for (const pair of n.c) edges.push(pair);
  n.n = n.c.length;
  delete n.c;
}

const out = {
  generator: 'tools/advchart/extract-catalog.js',
  echartsVersion: '6.1.0',
  occurrences: occurrences,
  excludedRenderItemReturn: excluded,
  root: root,
  names: namesArr, descs: descsArr, enums: enumsArr,
  nodes: nodes, edges: edges,
  variantMismatches: mismatches,
};
fs.writeFileSync(outFile, JSON.stringify(out));
console.log('occurrences   ', occurrences);
console.log('excluded      ', excluded, '(renderItem.return_*)');
console.log('DAG nodes     ', nodes.length);
console.log('DAG edges     ', edges.length);
console.log('names         ', namesArr.length);
console.log('descriptions  ', descsArr.length);
console.log('enum lists    ', enumsArr.length);
console.log('variant issues', mismatches.length, mismatches.slice(0, 5).join('; '));
console.log('out           ', outFile, (fs.statSync(outFile).size / 1048576).toFixed(2), 'MB');
