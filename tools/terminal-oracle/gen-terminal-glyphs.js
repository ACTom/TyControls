// Writes source/tyControls.Terminal.CustomGlyphs.inc: the box-drawing and block
// glyphs (U+2500-259F) xterm.js 6.0.0's WebGL addon draws itself so neighbouring
// cells join up -- addons/addon-webgl/src/customGlyphs/CustomGlyphDefinitions.ts,
// dumped from the built module, not copied by hand. Upstream path and pin:
// lib-dump.js.
//
//   node tools/terminal-oracle/gen-terminal-glyphs.js
//
// Three kinds of part occur in this range, and only these (anything else, or a part
// property other than type / data / strokeWidth, stops the script):
//   SOLID_OCTANT_BLOCK_VECTOR (0)  rectangles in eighths of the cell: x, y, w, h
//   BLOCK_PATTERN (1)              a 0/1 matrix tiled over the cell
//   PATH_FUNCTION (2)              an SVG-like path, M / L / C with comma-separated
//                                  numbers in cell units, stroked (strokeWidth) or
//                                  filled. Where data is a function, upstream calls it
//                                  at draw time with xp = 0.15 and yp = 0.15 / cell
//                                  height x cell width (CustomGlyphRasterizer.ts
//                                  drawPathFunctionCharacter); every number of every
//                                  such path is linear in yp, so it is dumped as the
//                                  pair a, b of a + b * yp -- evaluated at yp = 0 and
//                                  yp = 1 and checked at yp = 0.37 (structure and
//                                  value), or the script stops. A plain string has
//                                  b = 0.
// The generated header carries the upstream version, commit and commit date, never
// the time of the run or a path of this machine; the file holds no brace (a brace
// would open a nested comment in FPC -- checked).
'use strict';
const path = require('path');
const L = require('./lib-dump.js');

const up = L.loadUpstream();
const G = require(path.join(L.XTERM, 'addons/addon-webgl', L.OUT_DIR, 'customGlyphs/CustomGlyphDefinitions.js'));

const FIRST = 0x2500, LAST = 0x259F;
const KIND = { 0: 'block', 1: 'pattern', 2: 'path' };
const CMD = { M: 1, L: 2, C: 3 };
const XP = 0.15;

// A path string as instructions: [letter, [numbers]] -- the split upstream does
// (split(' '), then substring(1).split(','), parseFloat || parseInt). Upstream skips
// an instruction whose first or second argument is empty; none here is, checked.
function parsePath(s) {
  return s.split(' ').map(ins => {
    const letter = ins[0];
    if (!(letter in CMD)) throw new Error('path command ' + JSON.stringify(letter) + ' in ' + JSON.stringify(s));
    const args = ins.substring(1).split(',');
    if (!args[0] || !args[1]) throw new Error('an instruction upstream would skip: ' + JSON.stringify(ins));
    const nums = args.map(e => parseFloat(e) || parseInt(e));
    if (nums.some(n => !Number.isFinite(n))) throw new Error('not a number in ' + JSON.stringify(ins));
    const want = letter === 'C' ? 6 : 2;
    if (nums.length !== want) throw new Error(`${letter} with ${nums.length} numbers`);
    return [letter, nums];
  });
}

// The path of a part as [letter, [[a, b], ...]] with value = a + b * yp.
function linearPath(data) {
  if (typeof data === 'string') return parsePath(data).map(([c, n]) => [c, n.map(v => [v, 0])]);
  const p0 = parsePath(data(XP, 0));
  const p1 = parsePath(data(XP, 1));
  const pt = parsePath(data(XP, 0.37));
  const same = (a, b) => a.length === b.length && a.every((ins, k) => ins[0] === b[k][0] && ins[1].length === b[k][1].length);
  if (!same(p0, p1) || !same(p0, pt)) throw new Error('the path changes shape with yp: ' + data(XP, 0));
  const out = p0.map(([c, n], k) => [c, n.map((v, j) => [v, p1[k][1][j] - v])]);
  out.forEach(([, n], k) => n.forEach(([a, b], j) => {
    if (Math.abs(a + b * 0.37 - pt[k][1][j]) > 1e-9) throw new Error('not linear in yp: ' + data(XP, 0));
  }));
  return out;
}

const index = [];     // [firstPart, partCount] per code point
const parts = [];     // [kind, strokeWidth, firstData, dataCount]
const data = [];      // numbers
const count = { block: 0, pattern: 0, path: 0 };
let withYp = 0;
for (let cp = FIRST; cp <= LAST; cp++) {
  const def = G.customGlyphDefinitions[String.fromCodePoint(cp)];
  if (!def) { index.push([parts.length, 0]); continue; }
  const list = Array.isArray(def) ? def : [def];
  index.push([parts.length, list.length]);
  let usesYp = false;
  for (const part of list) {
    for (const k of Object.keys(part)) {
      if (!['type', 'data', 'strokeWidth'].includes(k)) throw new Error(`U+${cp.toString(16)}: part property ${k}`);
    }
    if (!(part.type in KIND)) throw new Error(`U+${cp.toString(16)}: part type ${part.type}`);
    const sw = part.strokeWidth === undefined ? 0 : part.strokeWidth;
    if (!Number.isInteger(sw) || sw < 0) throw new Error(`U+${cp.toString(16)}: strokeWidth ${part.strokeWidth}`);
    const start = data.length;
    if (part.type === 0) {
      for (const r of part.data) {
        for (const k of Object.keys(r)) if (!['x', 'y', 'w', 'h'].includes(k)) throw new Error('block field ' + k);
        data.push(r.x, r.y, r.w, r.h);
      }
    } else if (part.type === 1) {
      const rows = part.data.length, cols = part.data[0].length;
      data.push(rows, cols);
      for (const row of part.data) {
        if (row.length !== cols) throw new Error(`U+${cp.toString(16)}: ragged pattern`);
        for (const bit of row) { if (bit !== 0 && bit !== 1) throw new Error('pattern value ' + bit); data.push(bit); }
      }
    } else {
      if (typeof part.data === 'function') usesYp = true;
      for (const [c, nums] of linearPath(part.data)) {
        data.push(CMD[c], nums.length);
        for (const [a, b] of nums) data.push(a, b);
      }
    }
    parts.push([part.type, sw, start, data.length - start]);
    count[KIND[part.type]]++;
  }
  if (usesYp) withYp++;
}

// The shade patterns tile from the surface's origin: a row of pixels moved up or down
// keeps its look only by a multiple of every pattern's height (phase 5, the view's
// row reuse). Their least common multiple, kept small.
const gcd = (a, b) => (b ? gcd(b, a % b) : a);
let periodY = 1;
for (const p of parts) if (p[0] === 1) periodY = periodY / gcd(periodY, data[p[2]]) * data[p[2]];
if (!Number.isInteger(periodY) || periodY > 16) throw new Error('pattern period ' + periodY);

const i = up.info;
const header = [
  'GENERATED by tools/terminal-oracle/gen-terminal-glyphs.js -- do NOT edit by hand;',
  'change the script and rerun it. Upstream: xterm.js ' + i.version + ', commit ' + i.commit,
  `(${i.commitDate}), addons/addon-webgl/src/customGlyphs/CustomGlyphDefinitions.ts,`,
  'code points U+2500-259F.',
  '',
  'TyTermGlyphIndex[cp]: first part, part count (0 = none).',
  'TyTermGlyphPatternPeriodY: the least common multiple of the pattern heights (a',
  '  row moved by a multiple of it keeps its shade phase).',
  'TyTermGlyphParts[p]: kind (0 block, 1 pattern, 2 path), stroke width (0 = filled),',
  '  first number in TyTermGlyphData, how many.',
  'TyTermGlyphData, per kind:',
  '  block    x, y, w, h per rectangle, in eighths of the cell',
  '  pattern  rows, columns, then the 0/1 cells row by row',
  '  path     per instruction: command (1 M, 2 L, 3 C), argument count, then each',
  '           argument as a, b -- its value is a + b * yp, yp = 0.15 / cell height x',
  '           cell width (a plain path has b = 0); x arguments are in cell widths,',
  '           y arguments in cell heights',
  '',
  'Derived from xterm.js, MIT:',
  '  Copyright (c) 2021 The xterm.js authors (CustomGlyphDefinitions.ts)',
  '  Copyright (c) 2018, The xterm.js authors (addons/addon-webgl/LICENSE)',
  'Full text: THIRD-PARTY-NOTICES.md.',
];

const num = n => {
  const s = String(n);
  return s.startsWith('.') ? '0' + s : s.startsWith('-.') ? '-0' + s.slice(1) : s;
};
const rows = (arr, per, fmt) => {
  const out = [];
  for (let k = 0; k < arr.length; k += per) out.push('    ' + arr.slice(k, k + per).map(fmt).join(', '));
  return out.join(',\n');
};
let out = header.map(l => ('// ' + l).trimEnd()).join('\n') + '\n\nconst\n';
out += `  TyTermGlyphFirst = $${FIRST.toString(16).toUpperCase()};\n`;
out += `  TyTermGlyphLast = $${LAST.toString(16).toUpperCase()};\n`;
out += `  TyTermGlyphPartCount = ${parts.length};\n`;
out += `  TyTermGlyphDataCount = ${data.length};\n`;
out += `  TyTermGlyphPatternPeriodY = ${periodY};\n`;
out += `  TyTermGlyphIndex: array[TyTermGlyphFirst..TyTermGlyphLast, 0..1] of Word = (\n`;
out += rows(index, 8, ([a, b]) => `(${a}, ${b})`) + ');\n';
out += `  TyTermGlyphParts: array[0..${parts.length - 1}, 0..3] of Word = (\n`;
out += rows(parts, 4, p => `(${p.join(', ')})`) + ');\n';
out += `  TyTermGlyphData: array[0..${data.length - 1}] of Double = (\n`;
out += rows(data, 12, num) + ');\n';
if (/[{}]/.test(out)) throw new Error('a brace in the generated include');
L.writeGenerated('source/tyControls.Terminal.CustomGlyphs.inc', out);
console.log(`blocks ${count.block}, patterns ${count.pattern}, paths ${count.path} (${withYp} code points with yp); parts ${parts.length}, numbers ${data.length}`);
process.exit(0);
