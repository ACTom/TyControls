#!/usr/bin/env node
/* Stage 2 of the AdvChart option-catalog pipeline.
 *
 *   node tools/advchart/gen-catalog.js
 *
 * Reads the committed intermediate tools/advchart/catalog.json and writes
 * source/tyControls.AdvChart.Catalog.pas -- pure data, no logic. The lookup,
 * path normalisation and validation live in a hand-written unit next to it, so
 * that they are readable and headless-testable; this follows the house split of
 * Css.Catalog (generated data) from Css.Complete (logic).
 *
 * WHAT IS NOT EMITTED: the option DESCRIPTIONS. Every other unit in this repo
 * keeps its source ASCII-safe -- no unit carries a non-ASCII string literal, no
 * codepage directive, no BOM, and translatable text goes through .po. Compiling
 * 3,629 English and Chinese summaries in would break that convention and double
 * the unit for text only a design-time editor ever shows. The editor reads them
 * from catalog.json instead, by the SAME node index this unit exposes -- which
 * is why descriptions stay part of the dedup identity upstream even though they
 * are not emitted here: it keeps the two sides' indices aligned.
 *
 * FRESHNESS. The unit carries two SHA-1 digests, following the strongest guard
 * in this repo (tyControls.Icons.Lucide + test.lucide):
 *   - over catalog.json, so an upstream re-extract that was never re-emitted is
 *     caught;
 *   - over THIS script, LF-normalised, so a generator change nobody re-ran, and
 *     a hand-edit of the generated unit, are both caught.
 * The weaker Css.Catalog guard is deliberately not copied: it only checks that
 * the catalog invents nothing, so anything ADDED upstream stays green.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const inFile = path.join(__dirname, 'catalog.json');
const outFile = path.join(__dirname, '..', '..', 'source', 'tyControls.AdvChart.Catalog.pas');

const catRaw = fs.readFileSync(inFile);
const cat = JSON.parse(catRaw.toString('utf8'));

const catalogDigest = crypto.createHash('sha1').update(catRaw).digest('hex').toUpperCase();
const selfSrc = fs.readFileSync(__filename, 'utf8').replace(/\r\n/g, '\n');
const selfDigest = crypto.createHash('sha1').update(selfSrc, 'utf8').digest('hex').toUpperCase();

/* One string pool for every ASCII field, so the Pascal side is a single array
   and every field is an index into it. Deduplication across categories is a
   free bonus. Index 0 is always the empty string, so "absent" is 0 rather than
   a sentinel every reader has to remember. */
const pool = new Map();
const poolArr = [];
function put(s) {
  if (s === undefined || s === null) s = '';
  s = String(s);
  if (pool.has(s)) return pool.get(s);
  const i = poolArr.length;
  poolArr.push(s);
  pool.set(s, i);
  return i;
}
put('');

const nonAscii = [];
function putAscii(s, where) {
  if (s === undefined || s === null) s = '';
  s = String(s);
  /* Non-ASCII is allowed but NOTICED. The schema really does carry a handful --
     node 1736's default is the play triangle U+25B6 -- and dropping them would
     lose real defaults. They are emitted as Pascal byte escapes (see pasQuote),
     so the source file stays pure ASCII BYTES and needs no codepage directive,
     which is what keeps this unit consistent with every other one here. The
     count is reported so a sudden jump is visible rather than silent. */
  if (/[^\x20-\x7E]/.test(s)) nonAscii.push(where + ': ' + JSON.stringify(s));
  return put(s);
}

const names = cat.names, enums = cat.enums;

const rows = cat.nodes.map(function (n, i) {
  return {
    ty: putAscii(n.t, 'node ' + i + '.type'),
    df: n.d === null ? -1 : putAscii(n.d, 'node ' + i + '.default'),
    ui: putAscii(n.u, 'node ' + i + '.uiControl'),
    en: n.e < 0 ? -1 : putAscii(enums[n.e], 'node ' + i + '.enum'),
    mn: putAscii(n.mn, 'node ' + i + '.min'),
    mx: putAscii(n.mx, 'node ' + i + '.max'),
    st: putAscii(n.st, 'node ' + i + '.step'),
    sv: putAscii(n.v, 'node ' + i + '.since'),
    de: n.de, dz: n.dz,
    fc: n.f, cc: n.n,
  };
});

const edgeRows = cat.edges.map(function (e) {
  return [putAscii(names[e[0]], 'edge name'), e[1]];
});

/* A Pascal string literal that is pure ASCII in the FILE whatever the value is.
   Printable ASCII goes inside quotes; anything else becomes #$xx byte escapes of
   its UTF-8 encoding, concatenated. An all-non-ASCII value must still emit a
   quoted part, or the result would be a bare escape run that reads oddly and an
   empty value would emit nothing at all. */
function pasQuote(s) {
  s = String(s);
  const parts = [];
  let run = '';
  const bytes = Buffer.from(s, 'utf8');
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i];
    if (b >= 0x20 && b <= 0x7E) {
      run += (b === 0x27) ? "''" : String.fromCharCode(b);
    } else {
      if (run !== '') { parts.push("'" + run + "'"); run = ''; }
      parts.push('#$' + b.toString(16).toUpperCase().padStart(2, '0'));
    }
  }
  if (run !== '' || parts.length === 0) parts.push("'" + run + "'");
  return parts.join(' + ');
}

function q(s) { return pasQuote(s); }

const L = [];
L.push('unit tyControls.AdvChart.Catalog;');
L.push('{$mode objfpc}{$H+}');
L.push('{ GENERATED FILE -- DO NOT EDIT BY HAND.');
L.push('');
L.push('  The Apache ECharts ' + cat.echartsVersion + ' option vocabulary, as a deduplicated DAG.');
L.push('  Regenerate with:  node tools/advchart/gen-catalog.js');
L.push('  and, when the targeted ECharts version moves, re-extract first with:');
L.push('                    node tools/advchart/extract-catalog.js <schemaDir>');
L.push('');
L.push('  WHY A DAG. The schema repeats itemStyle, label and textStyle physically under');
L.push('  every parent: ' + cat.occurrences.toLocaleString('en-US') + ' node occurrences collapse to ' + cat.nodes.length.toLocaleString('en-US') + ' distinct records,');
L.push('  a ' + (cat.occurrences / cat.nodes.length).toFixed(1) + 'x reduction. A flat table of every path would be tens of megabytes');
L.push('  of literals and would not compile in practice.');
L.push('');
L.push('  WHAT IS ABSENT: the option descriptions. This repo keeps its source ASCII --');
L.push('  no unit carries a non-ASCII string literal -- and translatable text goes');
L.push('  through .po. The English and Chinese summaries live in the committed');
L.push('  tools/advchart/catalog.json, indexed by the SAME node index this unit uses');
L.push('  (TyOptDescEn / TyOptDescZh below are those indices), so a design-time editor');
L.push('  reads them from there without any of it reaching a compiled runtime unit.');
L.push('');
L.push('  Lookup, path normalisation and validation are NOT here: they are hand-written');
L.push('  in tyControls.AdvChart.Complete, so they stay readable and testable while this');
L.push('  file stays pure data. Same split as Css.Catalog / Css.Complete. }');
L.push('interface');
L.push('');
L.push('type');
L.push('  { One node of the option DAG. Every string field is an index into TyOptStr;');
L.push('    0 is the empty string, so "not set" needs no sentinel. DefaultStr and');
L.push('    EnumStr use -1 for absent, because an empty default and no default are');
L.push('    different things. }');
L.push('  TTyOptNode = record');
L.push("    TypeStr: Integer;       // e.g. 'number', 'string|Array', 'Object'");
L.push('    DefaultStr: Integer;    // -1 when the schema states no default');
L.push("    UiStr: Integer;         // uiControl.type: 'color', 'percent', 'enum', ...");
L.push('    EnumStr: Integer;       // comma-separated allowed values, -1 when none');
L.push('    MinStr, MaxStr, StepStr: Integer;');
L.push("    SinceStr: Integer;      // '6.1.0' etc, 0 when the option is not versioned");
L.push("    DescEn, DescZh: Integer;// indices into catalog.json's desc pool, not into TyOptStr");
L.push('    FirstChild, ChildCount: Integer;   // slice of TyOptEdge');
L.push('  end;');
L.push('');
L.push('  { One parent -> child edge. NameStr is the property name, except for two');
L.push('    structural spellings the schema itself uses:');
L.push("      '[]'      the element type of a homogeneous array");
L.push("      '=<tag>' one member of a discriminated union, tagged by the value of");
L.push("                its own `type` option -- '=line', '=bar', '=slider'. Five");
L.push('                containers use these: series (23), graphic.elements (13),');
L.push('                dataset.transform (3), dataZoom (2), visualMap (2). }');
L.push('  TTyOptEdge = record');
L.push('    NameStr: Integer;');
L.push('    Node: Integer;');
L.push('  end;');
L.push('');
L.push('const');
L.push('  TyOptEChartsVersion = ' + q(cat.echartsVersion) + ';');
L.push('  { SHA-1 over tools/advchart/catalog.json. }');
L.push('  TyOptCatalogDigest = ' + q(catalogDigest) + ';');
L.push('  { SHA-1 over tools/advchart/gen-catalog.js with CRLF normalised to LF, so a');
L.push('    checkout with a different core.autocrlf does not turn the guard red for');
L.push('    no reason. }');
L.push('  TyOptGeneratorDigest = ' + q(selfDigest) + ';');
L.push('  TyOptRoot = ' + cat.root + ';');
L.push('  TyOptNodeCount = ' + rows.length + ';');
L.push('  TyOptEdgeCount = ' + edgeRows.length + ';');
L.push('  TyOptStrCount = ' + poolArr.length + ';');
L.push('  { Occurrences in the source schema, before deduplication -- the number the');
L.push('    drift test re-derives to prove the DAG still expands to the same tree. }');
L.push('  TyOptOccurrences = ' + cat.occurrences + ';');
L.push('');
L.push('  TyOptStr: array[0..' + (poolArr.length - 1) + '] of string = (');
for (let i = 0; i < poolArr.length; i++)
  L.push('    ' + q(poolArr[i]) + (i < poolArr.length - 1 ? ',' : ''));
L.push('  );');
L.push('');
L.push('  TyOptNodes: array[0..' + (rows.length - 1) + '] of TTyOptNode = (');
rows.forEach(function (r, i) {
  L.push('    (TypeStr:' + r.ty + '; DefaultStr:' + r.df + '; UiStr:' + r.ui +
         '; EnumStr:' + r.en + '; MinStr:' + r.mn + '; MaxStr:' + r.mx +
         '; StepStr:' + r.st + '; SinceStr:' + r.sv + '; DescEn:' + r.de +
         '; DescZh:' + r.dz + '; FirstChild:' + r.fc + '; ChildCount:' + r.cc + ')' +
         (i < rows.length - 1 ? ',' : ''));
});
L.push('  );');
L.push('');
L.push('  TyOptEdges: array[0..' + (edgeRows.length - 1) + '] of TTyOptEdge = (');
edgeRows.forEach(function (e, i) {
  L.push('    (NameStr:' + e[0] + '; Node:' + e[1] + ')' + (i < edgeRows.length - 1 ? ',' : ''));
});
L.push('  );');
L.push('');
L.push('implementation');
L.push('');
L.push('end.');

fs.writeFileSync(outFile, L.join('\n') + '\n');
console.log('nodes ', rows.length, ' edges ', edgeRows.length, ' pool ', poolArr.length);
console.log('non-ASCII escaped:', nonAscii.length,
            nonAscii.length ? '-> ' + nonAscii.slice(0, 3).join(' | ') : '');
console.log('catalog digest  ', catalogDigest);
console.log('generator digest', selfDigest);
console.log('wrote', outFile, (fs.statSync(outFile).size / 1048576).toFixed(2), 'MB');
