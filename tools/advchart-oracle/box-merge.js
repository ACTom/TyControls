// Upstream's own answers for the title's and the legend's box: which of
// left/right/top/bottom survive mergeLayoutParam's ignoreSize branch, and where
// the box then lands through getLayoutRect (batch 52 audit, wf52/audit52.md
// section 3 step 1).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 400 x 300, renders
// once per case and reads the models and views directly -- never the SVG text.
// Every chart is disposed in a finally.
//
// Node has no canvas, so every string is measured by zrender's built-in width
// table. The measured widths and heights are RECORDED (with the font string the
// element carried): the Pascal side builds a table measurer from them and never
// re-measures, so the fixture's layout is the layout the port is fed.
//
// The rules (every step one IEEE double operation, JS evaluation order; they are
// transcribed below and the transcription must give every recorded value bit for
// bit):
//   own        the user's own box keys, before the theme/default merge
//              (Component.ts:164-176). JSON null counts as own.
//   merge      title defaults {left:'center', top:15}, legend {left:'center',
//              bottom:15}; zrender merge only fills a key the option does not
//              have. Then, per direction (A = left/top, B = right/bottom):
//              hasValue(k) = own[k] != null && own[k] !== 'auto';
//              hasValue(A) -> B := null, else hasValue(B) -> A := null; the size
//              is never touched (layout.ts:711-719, 748-750).
//   parse      parsePositionOption (number.ts:132-175): exact 'center'/'middle'
//              -> '50%', 'left'/'top' -> '0%', 'right'/'bottom' -> '100%'; a
//              string whose trim ends in '%' -> parseFloat/100*base + 0; other
//              strings parseFloat; null/undefined NaN; anything else +v.
//   word       the switch word: (A || B) when it is a string, else ''
//              (layout.ts:352-367; install.ts:227, 241 read the same value).
//   rect       getLayoutRect verbatim (layout.ts:290-388), including the final
//              BoundingRect sign flip (BoundingRect.ts:38-41).
//
// Output (tests/fixtures/advchart-box-merge.json):
//   source, W, H
//   keys       the six box keys in the order every `merged`/`parsed` lists them
//   titles[]   name, input (the title option as run, JSON; text 'Title',
//              subtext 'Sub'), padding [t,r,b,l] (normalised), itemGap,
//              merged    {key: {kind: 'absent'|'null'|'auto'|'value',
//                        type: 'number'|'string'|'boolean' (value only),
//                        value (a string/boolean as itself, a number as hex),
//                        valueText (numbers only)}} -- 'absent' covers a key the
//                        merge left undefined
//              parsed    {key: hex}, parsedText: parse(merged[key], W or H)
//              wordH, wordV
//              text, subtext  {string, font, width, widthText, height, heightText}
//                        from each element's getBoundingRect()
//              block     {width, height} (+ blockText): the stacked text and
//                        subtext before alignment, what install.ts:216-218 hands
//                        getLayoutRect
//              layoutRect  getLayoutRect(params + block, [0,0,W,H], padding)
//              group     {x, y}: the view group, = layoutRect moved by the auto
//                        align (install.ts:225-253)
//              align, verticalAlign  the text style's: the raw (left || right),
//                        'middle' -> 'center', then zrender turns anything that
//                        is not an align into 'left' (`right:10` aligns 'left');
//                        align is null when unset (`left:0,right:10`: 0 || null),
//                        which zrender draws as left. verticalAlign likewise,
//                        falling to 'top'
//              bg        the background Rect, absolute: g.x + shape.x, ...
//                        (shape.x = groupRect.x - padding[3], install.ts:270)
//   legends[]  name, input (the legend option as run), orient, items (the
//              series names S0..S(n-1)), padding, merged, parsed, wordH, wordV,
//              measure   [{string, font, width, widthText, height, heightText}]
//                        per name, in item order
//              maxSize   the first getLayoutRect (LegendView.ts:141): what
//                        layoutInner was handed (captured), = the helper fed
//                        getBoxLayoutParams()
//              mainRect  layoutInner's return (captured through a patched
//                        LegendView.prototype.layoutInner)
//              layoutRect  getLayoutRect(defaults({width, height} of mainRect,
//                        params), [0,0,W,H], padding)
//              group     {x, y} = layoutRect - mainRect (asserted)
//              distinctX, distinctY  distinct item x and y in the content group
//                        (columns and rows)
//              itemAlign what layoutInner was handed
//   scroll[]   name, input, orient, items, padding, merged, parsed, wordH,
//              wordV, maxSize (the pager moves everything else: not recorded)
//   guards[]   one per mutation of the audit's table (section 3 step 5):
//              mutation, named (the cases the table says must turn red),
//              changed (the cases on which the mutated transcription gives a
//              different merged key, word, rect or itemAlign), ok = named is a
//              subset of changed. M12 also lists every double that differs
//              (differs[]: case, field, upstream, mutated, hex + text) and
//              names T20, the case added for it. M13 is a pair check (changed
//              empty, note): LV4 must align its items left and LV5 right.
//              M13b-M16 (a second round): itemAlign from the switch word (red
//              on LV6), a vertical switch without 'center' (T21), a percent
//              test that does not trim (T22), the frame's x in the old port
//              order (g.x + groupRect.x) - padding[3] (T23; the transcribed
//              frame x is also checked against every title's bg.x)
//
// Doubles are written as the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase) with a readable twin beside them (xText beside x, ...).
//
// Self-checks (any failure: nothing is written, exit 1): the transcribed merge
// gives the model's merged keys (Object.is); getBoxLayoutParams() is the merged
// option (a null reads back undefined through getShallow, nothing else moves:
// no root-level leak); the transcribed parse is echarts.number.parsePercent;
// the transcribed getLayoutRect gives the helper's rects; the title group is
// layoutRect moved by the align, and the text's align/verticalAlign follow the
// rule above; the subtext sits at text height + itemGap and aligns like the
// text; every legend item carries its name; the legend's captured maxSize is
// the helper's; g.x = layoutRect.x - mainRect.x and the same for y; every guard
// is ok; two generations give the same bytes.
//
//   node tools/advchart-oracle/box-merge.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-box-merge.json');

const W = 400;
const H = 300;
const KEYS = ['left', 'right', 'top', 'bottom', 'width', 'height'];
const TITLE_DEFAULTS = { left: 'center', top: 15 };
const LEGEND_DEFAULTS = { left: 'center', bottom: 15 };

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const RECT = ['x', 'y', 'width', 'height'];
const hexRect = r => ({ x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) });
const textRect = r => ({ x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) });
const sameRect = (a, b) => RECT.every(k => Object.is(a[k], b[k]));
const hasOwn = (o, k) => Object.prototype.hasOwnProperty.call(o, k);

// ---------- the transcription (with the audit's mutations as switches) ----------

// number.ts:132-175, verbatim
function parsePos(option, base, untrimmed) {
  switch (option) {
    case 'center':
    case 'middle':
      option = '50%';
      break;
    case 'left':
    case 'top':
      option = '0%';
      break;
    case 'right':
    case 'bottom':
      option = '100%';
      break;
  }
  if (typeof option === 'string') {
    if (/%$/.test(untrimmed ? option : option.trim())) return parseFloat(option) / 100 * base + 0;
    return parseFloat(option);
  }
  return option == null ? NaN : +option;
}

// zrender normalizeCssArray
function cssArray(v) {
  if (typeof v === 'number') return [v, v, v, v];
  if (v.length === 2) return [v[0], v[1], v[0], v[1]];
  if (v.length === 3) return [v[0], v[1], v[2], v[1]];
  return v;
}

const wordOf = v => (typeof v === 'string' ? v : '');

// the user's option + the defaults the zrender merge fills in
function withDefaults(own, defaults) {
  const t = Object.assign({}, own);
  for (const k of Object.keys(defaults)) if (!hasOwn(t, k)) t[k] = defaults[k];
  return t;
}

// layout.ts mergeLayoutParam (the init path: newOption = the user's own keys)
const HV = [['width', 'left', 'right'], ['height', 'top', 'bottom']];
function mergeBox(own, defaults, mut) {
  const target = withDefaults(own, defaults);
  const newOption = mut.m8 ? target : own;
  const hasValue = mut.hasValue || ((obj, name) => obj[name] != null && obj[name] !== 'auto');
  const out = {};
  HV.forEach(names => {
    const merged = {};
    const newParams = {};
    let newValueCount = 0;
    let mergedValueCount = 0;
    names.forEach(n => { merged[n] = target[n]; });
    names.forEach(n => {
      if (hasOwn(newOption, n)) newParams[n] = merged[n] = newOption[n];
      if (hasValue(newParams, n)) newValueCount++;
      if (hasValue(merged, n)) mergedValueCount++;
    });
    let res;
    if (mut.m2) {
      // the non-ignoreSize rule (layout.ts:721-748)
      if (mergedValueCount === 2 || !newValueCount) res = merged;
      else if (newValueCount >= 2) res = newParams;
      else {
        for (const n of names) {
          if (!hasOwn(newParams, n) && hasOwn(target, n)) { newParams[n] = target[n]; break; }
        }
        res = newParams;
      }
    } else {
      res = merged;
      if (!mut.m1) {
        const [first, second] = mut.m3 ? [names[2], names[1]] : [names[1], names[2]];
        if (hasValue(newOption, first)) merged[second] = null;
        else if (hasValue(newOption, second)) merged[first] = null;
      }
    }
    names.forEach(n => { out[n] = res[n]; });
  });
  return out;
}

// today's EdgeIn (Title.pas:228-247, Legend.pas:527-543): a value the port
// cannot read falls to the key's default
function portReadable(v) {
  if (v == null || typeof v === 'number') return true;
  if (typeof v !== 'string') return false;
  const s = v.trim();
  if (s === '') return false;
  if (['center', 'centre', 'middle', 'left', 'top', 'right', 'bottom'].includes(s)) return true;
  const num = /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/;
  return s.endsWith('%') ? num.test(s.slice(0, -1)) : num.test(s);
}

// layout.ts:290-388 verbatim. words: the switch words; fill: the port's
// keyword-before-wrap (a keyword with no size fills the container less the
// margins); collapse: an inverted rect collapses to 0 instead of flipping.
function layoutRect(p, margin, words, mut) {
  margin = cssArray(margin || 0);
  const cw = W;
  const ch = H;
  const u = mut.pctUntrimmed;
  let left = parsePos(p.left, cw, u);
  let top = parsePos(p.top, ch, u);
  const right = parsePos(p.right, cw, u);
  const bottom = parsePos(p.bottom, ch, u);
  let width = parsePos(p.width, cw, u);
  let height = parsePos(p.height, ch, u);
  const vm = margin[2] + margin[0];
  const hm = margin[1] + margin[3];
  if (mut.fill) {
    if ((words.h === 'center' || words.h === 'right') && isNaN(width)) return keywordFill(p, margin, words, mut);
    if ((words.v === 'middle' || words.v === 'center' || words.v === 'bottom') && isNaN(height)) {
      return keywordFill(p, margin, words, mut);
    }
  }
  if (isNaN(width)) width = cw - right - hm - left;
  if (isNaN(height)) height = ch - bottom - vm - top;
  if (isNaN(left)) left = cw - right - width - hm;
  if (isNaN(top)) top = ch - bottom - height - vm;
  switch (words.h) {
    case 'center':
      left = cw / 2 - width / 2 - margin[3];
      break;
    case 'right':
      left = cw - width - hm;
      break;
  }
  switch (mut.vOnlyMiddle && words.v === 'center' ? '' : words.v) {
    case 'middle':
    case 'center':
      top = ch / 2 - height / 2 - margin[0];
      break;
    case 'bottom':
      top = ch - height - vm;
      break;
  }
  left = left || 0;
  top = top || 0;
  if (isNaN(width)) width = cw - hm - left - (right || 0);
  if (isNaN(height)) height = ch - vm - top - (bottom || 0);
  return rectSet(0 + left + margin[3], 0 + top + margin[0], width, height, mut);
}
function rectSet(x, y, width, height, mut) {
  if (mut.collapse) {
    if (width < 0) width = 0;
    if (height < 0) height = 0;
  } else {
    if (width < 0) { x = x + width; width = -width; }
    if (height < 0) { y = y + height; height = -height; }
  }
  return { x, y, width, height };
}
// M9: the port rewrites a keyword into the box before the wrap solve, and a
// keyword with no size fills
function keywordFill(p, margin, words, mut) {
  const un = Object.assign({}, mut, { fill: false });
  const r = layoutRect(p, margin, words, un);
  if ((words.h === 'center' || words.h === 'right') && isNaN(parsePos(p.width, W))) {
    r.x = 0 + margin[3];
    r.width = W - margin[1] - r.x;
  }
  if ((words.v === 'middle' || words.v === 'center' || words.v === 'bottom') && isNaN(parsePos(p.height, H))) {
    r.y = 0 + margin[0];
    r.height = H - margin[2] - r.y;
  }
  return r;
}

// M12: the port's SolveAxis (Layout.pas:750-838) fed the same merged values:
// its operation order, its centre formula; the sign flip kept as upstream's so
// only the order differs
function portAxis(s, e, sz, word, centreWords, C, mS, mE) {
  let start, stop, len;
  if (centreWords.includes(word)) {
    if (isNaN(sz)) {
      start = 0 + mS;
      stop = 0 + C - mE;
      return { start, len: stop - start };
    }
    start = 0 + (C - sz) / 2;
    return { start, len: sz };
  }
  if (word === 'right' || word === 'bottom') { s = NaN; e = 0; }
  if (!isNaN(s) && !isNaN(sz)) { start = 0 + mS + s; stop = start + sz; }
  else if (!isNaN(s) && !isNaN(e)) { start = 0 + mS + s; stop = 0 + C - mE - e; }
  else if (!isNaN(e) && !isNaN(sz)) { stop = 0 + C - mE - e; start = stop - sz; }
  else if (!isNaN(s)) { start = 0 + mS + s; stop = 0 + C - mE; }
  else if (!isNaN(e)) { start = 0 + mS; stop = 0 + C - mE - e; }
  else if (!isNaN(sz)) { start = 0 + mS; stop = start + sz; }
  else { start = 0 + mS; stop = 0 + C - mE; }
  len = !isNaN(sz) ? sz : stop - start;
  if (len < 0) { start = start + len; len = -len; }
  return { start, len };
}
function portLayoutRect(p, margin, words) {
  margin = cssArray(margin || 0);
  const h = portAxis(parsePos(p.left, W), parsePos(p.right, W), parsePos(p.width, W), words.h, ['center'],
    W, margin[3], margin[1]);
  const v = portAxis(parsePos(p.top, H), parsePos(p.bottom, H), parsePos(p.height, H), words.v,
    ['middle', 'center'], H, margin[0], margin[2]);
  return { x: h.start, y: v.start, width: h.len, height: v.len };
}

// the whole transcribed pipeline for one case, under a mutation
function pipeline(c, mut) {
  const defaults = c.kind === 'title' ? TITLE_DEFAULTS : LEGEND_DEFAULTS;
  const own = {};
  for (const k of KEYS) if (hasOwn(c.opt, k)) own[k] = c.opt[k];
  let merged = mergeBox(own, defaults, mut);
  if (mut.m6) {
    const m = {};
    for (const k of KEYS) m[k] = portReadable(merged[k]) ? merged[k] : (hasOwn(defaults, k) ? defaults[k] : undefined);
    merged = m;
  }
  const wordSrc = mut.m7 ? withDefaults(own, defaults) : merged;
  const words = { h: wordOf(wordSrc.left || wordSrc.right), v: wordOf(wordSrc.top || wordSrc.bottom) };
  if (mut.m10) {
    for (const d of ['h', 'v']) {
      const w = words[d].trim();
      words[d] = w === 'centre' ? 'center' : w;
    }
  }
  const solve = mut.m12 ? (p, pad, w) => portLayoutRect(p, pad, w) : (p, pad, w, extra) => layoutRect(p, pad, w,
    Object.assign({}, mut, extra));
  const res = { merged, words };
  const pad = c.padding;
  if (c.kind === 'title') {
    const p = Object.assign({}, merged, { width: c.block.width, height: c.block.height });
    const r = solve(p, pad, words, { fill: false });
    res.layoutRect = r;
    // install.ts:225-253: the align is the raw value, the move follows its word
    let a = mut.m7 || mut.m10 ? words.h : (merged.left || merged.right);
    if (a === 'middle') a = 'center';
    let gx = r.x;
    if (a === 'right') gx += r.width;
    else if (a === 'center') gx += r.width / 2;
    let va = mut.m7 || mut.m10 ? words.v : (merged.top || merged.bottom);
    if (va === 'center') va = 'middle';
    let gy = r.y;
    if (va === 'bottom') gy += r.height;
    else if (va === 'middle') gy += r.height / 2;
    res.group = { x: gx, y: gy };
    // the frame (install.ts:268-278): groupRect.x is -w/2 centred, -w right,
    // 0 otherwise (zrender draws an invalid or unset align left); upstream
    // adds (groupRect.x - padding[3]) to g.x, the old port order is
    // (g.x + groupRect.x) - padding[3]
    const za = a == null ? null : (['left', 'center', 'right'].includes(a) ? a : 'left');
    const grx = za === 'center' ? -c.block.width / 2 : za === 'right' ? -c.block.width : 0;
    res.bg = { x: mut.frameOrder ? (gx + grx) - pad[3] : gx + (grx - pad[3]) };
  } else {
    res.maxSize = solve(merged, pad, words, {});
    if (c.mainRect) {
      const p = echarts.util.defaults({ width: c.mainRect.width, height: c.mainRect.height }, merged);
      res.layoutRect = solve(p, pad, words, { fill: false });
    }
    res.itemAlign = (mut.itemAlignWord ? words.h : merged.left) === 'right' && c.orient === 'vertical' ? 'right' : 'left';
  }
  return res;
}

// ---------- recording ----------

function encodeValue(v) {
  if (v === undefined) return { kind: 'absent' };
  if (v === null) return { kind: 'null' };
  if (v === 'auto') return { kind: 'auto' };
  if (typeof v === 'number') return { kind: 'value', type: 'number', value: hex(v), valueText: text(v) };
  if (typeof v === 'string' || typeof v === 'boolean') return { kind: 'value', type: typeof v, value: v };
  throw new OracleError('an unexpected box value: ' + JSON.stringify(v));
}
function encodeMerged(m) {
  const r = {};
  for (const k of KEYS) r[k] = encodeValue(m[k]);
  return r;
}
function parsedOf(m) {
  const r = {};
  const t = {};
  for (const k of KEYS) {
    const base = k === 'left' || k === 'right' || k === 'width' ? W : H;
    const v = parsePos(m[k], base);
    const up = echarts.number.parsePercent(m[k], base);
    must(Object.is(v, up), 'parse(' + JSON.stringify(m[k]) + ', ' + base + ') = ' + v + ', upstream ' + up);
    r[k] = hex(v);
    t[k] = text(v);
  }
  return { parsed: r, parsedText: t };
}
function measured(el) {
  const r = el.getBoundingRect();
  must(typeof el.style.font === 'string' && el.style.font, 'a text element with no font string');
  return { string: el.style.text, font: el.style.font, width: hex(r.width), widthText: text(r.width),
    height: hex(r.height), heightText: text(r.height) };
}
function modelMerged(model, name) {
  const m = {};
  for (const k of KEYS) m[k] = model.option[k];
  const params = model.getBoxLayoutParams();
  // getShallow asks ecModel for a null key (the root-level leak, OUT): with no
  // root box keys a null reads back undefined, nothing else changes
  for (const k of KEYS) {
    must(Object.is(params[k], m[k]) || (m[k] === null && params[k] === undefined),
      name + ': getBoxLayoutParams().' + k + ' is not the merged option');
  }
  return m;
}
function checkMerge(c, m) {
  const own = {};
  for (const k of KEYS) if (hasOwn(c.opt, k)) own[k] = c.opt[k];
  const t = mergeBox(own, c.kind === 'title' ? TITLE_DEFAULTS : LEGEND_DEFAULTS, {});
  for (const k of KEYS) {
    must(Object.is(t[k], m[k]), c.name + ': the transcribed merge gives ' + k + ' = ' + JSON.stringify(t[k])
      + ', the model ' + JSON.stringify(m[k]));
  }
}
function wordsOf(m) {
  return { h: wordOf(m.left || m.right), v: wordOf(m.top || m.bottom) };
}

function newChart() {
  return echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
}

function titleCase(name, box, title) {
  const opt = Object.assign({ text: title || 'Title', subtext: 'Sub' }, box);
  const chart = newChart();
  try {
    chart.setOption({ animation: false, title: opt });
    const model = chart.getModel().getComponent('title', 0);
    const view = chart.getViewOfComponentModel(model);
    const g = view.group;
    const [textEl, subEl, bgEl] = g.children();
    must(g.children().length === 3 && textEl.type === 'text' && subEl.type === 'text' && bgEl.type === 'rect',
      name + ': the title group is not text, subtext, background');
    const c = { kind: 'title', name, opt };
    const m = modelMerged(model, name);
    checkMerge(c, m);
    const padding = cssArray(model.get('padding'));
    const itemGap = model.get('itemGap');
    const tr = textEl.getBoundingRect();
    const sr = subEl.getBoundingRect();
    // the block before the align (install.ts:173-218): text at 0, the subtext's
    // style.y = textRect.height + itemGap; the union of the two
    must(Object.is(subEl.style.y, tr.height + itemGap), name + ': the subtext does not sit at text height + itemGap');
    const block = { width: Math.max(tr.width, sr.width), height: subEl.style.y + sr.height };
    const params = Object.assign(model.getBoxLayoutParams(), { width: block.width, height: block.height });
    const lr = echarts.helper.getLayoutRect(params, { x: 0, y: 0, width: W, height: H }, model.get('padding'));
    const lrPlain = { x: lr.x, y: lr.y, width: lr.width, height: lr.height };
    c.padding = padding;
    c.block = block;
    const t = pipeline(c, {});
    must(sameRect(t.layoutRect, lrPlain), name + ': the transcribed getLayoutRect gives ' + JSON.stringify(t.layoutRect)
      + ', the helper ' + JSON.stringify(lrPlain));
    must(Object.is(g.x, t.group.x) && Object.is(g.y, t.group.y), name + ': the group sits at ' + g.x + ',' + g.y
      + ', layoutRect moved by the align gives ' + t.group.x + ',' + t.group.y);
    const bg = { x: g.x + bgEl.shape.x, y: g.y + bgEl.shape.y, width: bgEl.shape.width, height: bgEl.shape.height };
    must(Object.is(t.bg.x, bg.x), name + ': the transcribed frame x ' + t.bg.x + ', upstream ' + bg.x);
    const words = wordsOf(m);
    must(words.h === t.words.h && words.v === t.words.v, name + ': words');
    const rec = {
      name, input: opt, padding, itemGap,
      merged: encodeMerged(m),
    };
    Object.assign(rec, parsedOf(m));
    rec.wordH = words.h;
    rec.wordV = words.v;
    rec.text = measured(textEl);
    rec.subtext = measured(subEl);
    rec.block = { width: hex(block.width), height: hex(block.height) };
    rec.blockText = { width: text(block.width), height: text(block.height) };
    rec.layoutRect = hexRect(lrPlain);
    rec.layoutRectText = textRect(lrPlain);
    rec.group = { x: hex(g.x), y: hex(g.y) };
    rec.groupText = { x: text(g.x), y: text(g.y) };
    rec.align = textEl.style.align == null ? null : textEl.style.align;
    rec.verticalAlign = textEl.style.verticalAlign;
    must(subEl.style.align === textEl.style.align && subEl.style.verticalAlign === rec.verticalAlign,
      name + ': the subtext aligns differently');
    // install.ts:227-252 then zrender's normalizeStyle (Text.ts:1035-1050): the
    // word, 'middle' -> 'center', anything not a valid align -> 'left', unset
    // stays unset; the vertical one falls to 'top' first
    let a = m.left || m.right;
    if (a === 'middle') a = 'center';
    a = a == null ? null : (['left', 'center', 'right'].includes(a) ? a : 'left');
    let va = m.top || m.bottom;
    if (va === 'center') va = 'middle';
    va = va || 'top';
    va = ['top', 'middle', 'bottom'].includes(va) ? va : 'top';
    must(a === rec.align && va === rec.verticalAlign, name + ': the text aligns ' + rec.align + '/' + rec.verticalAlign
      + ', the rule gives ' + a + '/' + va);
    rec.bg = hexRect(bg);
    rec.bgText = textRect(bg);
    c.rec = rec;
    return c;
  } finally {
    chart.dispose();
  }
}

// layoutInner, captured: the prototype that owns it, from a warm-up chart
let captured = null;
function patchLayoutInner(legendType) {
  const chart = newChart();
  let proto;
  try {
    chart.setOption({ animation: false, legend: { type: legendType }, series: [] });
    const view = chart.getViewOfComponentModel(chart.getModel().getComponent('legend', 0));
    proto = Object.getPrototypeOf(view);
    while (proto && !hasOwn(proto, 'layoutInner')) proto = Object.getPrototypeOf(proto);
    must(proto, legendType + ' legend: no layoutInner on the view chain');
  } finally {
    chart.dispose();
  }
  if (hasOwn(proto, '__boxMergePatched')) return;
  const orig = proto.layoutInner;
  proto.layoutInner = function (legendModel, itemAlign, maxSize) {
    const r = orig.apply(this, arguments);
    captured = { itemAlign, maxSize: { x: maxSize.x, y: maxSize.y, width: maxSize.width, height: maxSize.height },
      mainRect: { x: r.x, y: r.y, width: r.width, height: r.height } };
    return r;
  };
  proto.__boxMergePatched = true;
}

function legendCase(name, box, n, scroll) {
  const series = [];
  const names = [];
  for (let i = 0; i < n; i++) {
    names.push('S' + i);
    series.push({ type: 'line', name: 'S' + i, data: [1, 2] });
  }
  const chart = newChart();
  try {
    captured = null;
    chart.setOption({ animation: false, legend: box, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: {}, series });
    must(captured, name + ': layoutInner was not called');
    const model = chart.getModel().getComponent('legend', 0);
    must(model.type === (scroll ? 'legend.scroll' : 'legend.plain'), name + ': the legend is ' + model.type);
    const view = chart.getViewOfComponentModel(model);
    const g = view.group;
    const orient = model.get('orient');
    const c = { kind: 'legend', name, opt: box, orient };
    const m = modelMerged(model, name);
    checkMerge(c, m);
    const padding = cssArray(model.get('padding'));
    c.padding = padding;
    const params = model.getBoxLayoutParams();
    const ref = { x: 0, y: 0, width: W, height: H };
    const ms = echarts.helper.getLayoutRect(params, ref, model.get('padding'));
    const msPlain = { x: ms.x, y: ms.y, width: ms.width, height: ms.height };
    must(sameRect(msPlain, captured.maxSize), name + ': layoutInner was handed ' + JSON.stringify(captured.maxSize)
      + ', the helper gives ' + JSON.stringify(msPlain));
    if (!scroll) c.mainRect = captured.mainRect;
    const t = pipeline(c, {});
    must(sameRect(t.maxSize, msPlain), name + ': the transcribed maxSize ' + JSON.stringify(t.maxSize));
    const words = wordsOf(m);
    must(words.h === t.words.h && words.v === t.words.v, name + ': words');
    const rec = { name, input: box, orient, items: names, padding, merged: encodeMerged(m) };
    Object.assign(rec, parsedOf(m));
    rec.wordH = words.h;
    rec.wordV = words.v;
    if (!scroll) {
      const items = view.getContentGroup().children();
      must(items.length === n, name + ': ' + items.length + ' items for ' + n + ' names');
      rec.measure = items.map((it, i) => {
        const te = it.children().filter(k => k.type === 'text');
        must(te.length === 1 && te[0].style.text === names[i], name + ': item ' + i + ' does not carry its name');
        return measured(te[0]);
      });
    }
    rec.maxSize = hexRect(msPlain);
    rec.maxSizeText = textRect(msPlain);
    if (scroll) {
      c.rec = rec;
      return c;
    }
    const mr = captured.mainRect;
    const lp = echarts.util.defaults({ width: mr.width, height: mr.height }, params);
    const lr = echarts.helper.getLayoutRect(lp, ref, model.get('padding'));
    const lrPlain = { x: lr.x, y: lr.y, width: lr.width, height: lr.height };
    must(sameRect(t.layoutRect, lrPlain), name + ': the transcribed layoutRect ' + JSON.stringify(t.layoutRect)
      + ', the helper ' + JSON.stringify(lrPlain));
    must(Object.is(g.x, lrPlain.x - mr.x), name + ': g.x ' + g.x + ' is not layoutRect.x - mainRect.x');
    must(Object.is(g.y, lrPlain.y - mr.y), name + ': g.y ' + g.y + ' is not layoutRect.y - mainRect.y');
    must(t.itemAlign === captured.itemAlign, name + ': the transcribed itemAlign ' + t.itemAlign + ', upstream '
      + captured.itemAlign);
    const pos = view.getContentGroup().children().map(it => [it.x, it.y]);
    rec.mainRect = hexRect(mr);
    rec.mainRectText = textRect(mr);
    rec.layoutRect = hexRect(lrPlain);
    rec.layoutRectText = textRect(lrPlain);
    rec.group = { x: hex(g.x), y: hex(g.y) };
    rec.groupText = { x: text(g.x), y: text(g.y) };
    rec.distinctX = new Set(pos.map(p => p[0])).size;
    rec.distinctY = new Set(pos.map(p => p[1])).size;
    rec.itemAlign = captured.itemAlign;
    c.rec = rec;
    return c;
  } finally {
    chart.dispose();
  }
}

// ---------- the cases (audit section 3 step 1) ----------

const TITLES = [
  ['T00 default', {}],
  ['T01 right:10', { right: 10 }],
  ['T02 bottom:10', { bottom: 10 }],
  ['T03 left:10,right:10', { left: 10, right: 10 }],
  ['T04 left:auto,right:10', { left: 'auto', right: 10 }],
  ['T05 left:auto', { left: 'auto' }],
  ['T06 top:auto', { top: 'auto' }],
  ['T07 right:right', { right: 'right' }],
  ['T08 left:0,right:10', { left: 0, right: 10 }],
  ['T09 left:null,right:0', { left: null, right: 0 }],
  ['T10 right:20%', { right: '20%' }],
  ['T11 bottom:10%', { bottom: '10%' }],
  ['T12 top:10,bottom:10', { top: 10, bottom: 10 }],
  ['T13 left:foo,right:right', { left: 'foo', right: 'right' }],
  ['T14 left:centre', { left: 'centre' }],
  ['T15 left:" center"', { left: ' center' }],
  ['T16 left:10px', { left: '10px' }],
  ['T17 left:true', { left: true }],
  ['T18 left:leafDepth', { left: 'leafDepth' }],
  ['T19 right:10,padding:[5,20,5,20]', { right: 10, padding: [5, 20, 5, 20] }],
  // M12's discriminator. No case above tells the two operation orders apart:
  // right-anchored, upstream rounds (C - e) - w once and then moves by exact
  // integers, the port rounds (C - m - e) - w once, and both land in the same
  // binade, so they agree; centred, (C - w)/2 and C/2 - w/2 are the same
  // rounding scaled by 2. They part when the two differences straddle a power
  // of two: here 390 - w >= 256 > 385 - w (w = 131.58, in (129, 134]), and
  // upstream's x is 253.41999999999996 against the port order's 253.42.
  ['T20 right:10,text:Sales by Region', { right: 10 }, 'Sales by Region'],
  // the switch's vertical 'center' (layout.ts:365): 'middle' alone is not enough
  ['T21 top:center', { top: 'center' }],
  // the percent test trims first (number.ts:185): '20% ' is 20% of 400, not 20px
  ['T22 right:"20% "', { right: '20% ' }],
  // the frame's discriminator: centred, groupRect.x = -w/2 and upstream's
  // g.x + (-w/2 - 5) is 166.29000000000002 where (g.x - w/2) - 5 gives 166.29
  // (w = 57.42, found by trying ordinary words; 'Title' does not split them)
  ['T23 frame order,text:Budget', {}, 'Budget'],
];
const LEGENDS = [
  ['L00 default', {}, 13],
  ['L01 right:10', { right: 10 }, 13],
  ['L02 left:10,right:200', { left: 10, right: 200 }, 13],
  ['L03 right:10,width:100', { right: 10, width: 100 }, 13],
  ['L04 bottom:auto', { bottom: 'auto' }, 13],
  ['L05 left:auto,right:10', { left: 'auto', right: 10 }, 13],
  ['L06 left:foo', { left: 'foo' }, 13],
  ['L07 right:right', { right: 'right' }, 13],
  ['L08 right:center', { right: 'center' }, 13],
  ['LV0 vertical top:10', { orient: 'vertical', top: 10 }, 30],
  ['LV1 vertical top:10,bottom:100', { orient: 'vertical', top: 10, bottom: 100 }, 30],
  ['LV2 vertical bottom:bottom', { orient: 'vertical', bottom: 'bottom' }, 13],
  ['LV3 vertical bottom:middle', { orient: 'vertical', bottom: 'middle' }, 13],
  ['LV4 vertical right:10', { orient: 'vertical', right: 10 }, 13],
  ['LV5 vertical left:right', { orient: 'vertical', left: 'right' }, 13],
  // itemAlign reads the merged left (LegendView.ts:118-125), not the switch
  // word: left is null here and the word is 'right'
  ['LV6 vertical right:right', { orient: 'vertical', right: 'right' }, 13],
];
const SCROLLS = [
  ['LS0 scroll vertical right:10,top:20,bottom:20',
    { type: 'scroll', orient: 'vertical', right: 10, top: 20, bottom: 20 }, 13],
];

// ---------- the guards (audit section 3 step 5) ----------

const hvTruthy = (obj, n) => !!obj[n] && obj[n] !== 'auto';
const hvWord = (obj, n) => typeof obj[n] === 'string' && obj[n] !== '' && obj[n] !== 'auto';
const GUARDS = [
  ['M1 no null (today)', { m1: true },
    ['T01 right:10', 'T02 bottom:10', 'T07 right:right', 'L01 right:10', 'LV0 vertical top:10']],
  ['M2 the non-ignoreSize rule', { m2: true }, ['T01 right:10', 'L02 left:10,right:200']],
  ['M3 check right/bottom first', { m3: true }, ['T03 left:10,right:10', 'L02 left:10,right:200']],
  ['M4a hasValue from the word (numbers never count)', { hasValue: hvWord }, ['T01 right:10']],
  ['M4b hasValue from truthiness (0 does not count)', { hasValue: hvTruthy }, ['T08 left:0,right:10']],
  ['M5 auto counts as a value', { hasValue: (obj, n) => obj[n] != null }, ['T04 left:auto,right:10', 'L05 left:auto,right:10']],
  ['M6 auto/unparseable -> the default (today\'s EdgeIn)', { m6: true },
    ['T05 left:auto', 'T06 top:auto', 'T16 left:10px', 'T17 left:true', 'T18 left:leafDepth', 'L04 bottom:auto']],
  ['M7 null the edge but keep its word', { m7: true }, ['T01 right:10']],
  ['M8 presence tested on the merged option', { m8: true }, ['T01 right:10', 'T02 bottom:10', 'T07 right:right']],
  ['M9 keyword applied before the wrap solve (today)', { fill: true },
    ['LV2 vertical bottom:bottom', 'LV3 vertical bottom:middle', 'L08 right:center', 'L07 right:right']],
  ['M10 accept centre / trim before the switch', { m10: true }, ['T14 left:centre', 'T15 left:" center"']],
  ['M11 collapse instead of flip', { collapse: true }, ['L07 right:right']],
  ['M12 SolveAxis operation order', { m12: true }, ['T20 right:10,text:Sales by Region']],
  ['M13b itemAlign read from left || right', { itemAlignWord: true }, ['LV6 vertical right:right']],
  ['M14 the vertical switch accepts only middle', { vOnlyMiddle: true }, ['T21 top:center']],
  ['M15 the percent test does not trim', { pctUntrimmed: true }, ['T22 right:"20% "']],
  ['M16 the frame in the old port order', { frameOrder: true }, ['T23 frame order,text:Budget']],
];

function flat(v) {
  return JSON.stringify(v, (k, x) => (typeof x === 'number' ? hex(x) : x === undefined ? '<undef>' : x));
}
function guardOf(cases, [mutation, mut, named]) {
  const changed = [];
  const differs = [];
  for (const c of cases) {
    const up = pipeline(c, {});
    const mu = pipeline(c, mut);
    let any = false;
    for (const f of ['merged', 'words', 'itemAlign']) if (flat(up[f]) !== flat(mu[f])) any = true;
    for (const f of ['layoutRect', 'maxSize', 'group', 'bg']) {
      if (!up[f]) continue;
      for (const k of Object.keys(up[f])) {
        if (!Object.is(up[f][k], mu[f][k])) {
          any = true;
          if (mut.m12) {
            differs.push({ case: c.name, field: f + '.' + k, upstream: hex(up[f][k]), upstreamText: text(up[f][k]),
              mutated: hex(mu[f][k]), mutatedText: text(mu[f][k]) });
          }
        }
      }
    }
    if (any) changed.push(c.name);
  }
  const g = { mutation, named, changed, ok: named.every(n => changed.includes(n)) };
  if (mut.m12) {
    // and the named title differs where the order does: the layout rect's x
    g.differs = differs;
    g.ok = g.ok && named.every(n => differs.some(d => d.case === n && d.field === 'layoutRect.x'));
  }
  return g;
}

// ---------- the run ----------

function generate() {
  patchLayoutInner('plain');
  patchLayoutInner('scroll');
  const titles = TITLES.map(([n, b, t]) => titleCase(n, b, t));
  const legends = LEGENDS.map(([n, b, k]) => legendCase(n, b, k, false));
  const scrolls = SCROLLS.map(([n, b, k]) => legendCase(n, b, k, true));
  const all = titles.concat(legends, scrolls);
  const guards = GUARDS.map(gd => guardOf(all, gd));
  // M13 (itemAlign): the two vertical cases the table names must answer differently
  const a = legends.find(c => c.name === 'LV4 vertical right:10').rec.itemAlign;
  const b = legends.find(c => c.name === 'LV5 vertical left:right').rec.itemAlign;
  guards.push({ mutation: 'M13 itemAlign not read from the merged left', named: ['LV4 vertical right:10', 'LV5 vertical left:right'],
    changed: [], ok: a === 'left' && b === 'right', note: 'LV4 aligns ' + a + ', LV5 ' + b
      + ': a constant itemAlign is red on one of them' });
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version,
    W, H, keys: KEYS,
    titles: titles.map(c => c.rec),
    legends: legends.map(c => c.rec),
    scroll: scrolls.map(c => c.rec),
    guards,
  };
  return out;
}

// the compact writer of roam.js / scale-align.js
const LINE = 250;
function oneLine(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + v.map(oneLine).join(',') + ']';
  return '{' + Object.keys(v).filter(k => v[k] !== undefined).map(k => JSON.stringify(k) + ':' + oneLine(v[k])).join(',') + '}';
}
function fmt(v, ind) {
  const f = oneLine(v);
  if (f.length + ind.length <= LINE || v === null || typeof v !== 'object') return f;
  const inner = ind + ' ';
  if (Array.isArray(v)) {
    const items = v.map(x => fmt(x, inner));
    if (items.every(t => !t.includes('\n'))) {
      const lines = [];
      let cur = '';
      for (const t of items) {
        if (cur && inner.length + cur.length + 1 + t.length + 1 > LINE) { lines.push(cur); cur = ''; }
        cur += (cur ? ',' : '') + t;
      }
      lines.push(cur);
      return '[\n' + lines.map(l => inner + l).join(',\n') + '\n' + ind + ']';
    }
    return '[\n' + items.map(x => inner + x).join(',\n') + '\n' + ind + ']';
  }
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner))
    .join(',\n') + '\n' + ind + '}';
}

let out1, json1, json2;
try {
  out1 = generate();
  json1 = fmt(out1, '') + '\n';
  json2 = fmt(generate(), '') + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = out1.guards.filter(g => !g.ok);
out1.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.mutation + ': named '
  + (g.named.join(' / ') || '-') + '; changes ' + g.changed.length + ': ' + g.changed.join(', ')
  + (g.note ? ' (' + g.note + ')' : '')));
const m12 = out1.guards.find(g => g.mutation.startsWith('M12'));
m12.differs.forEach(d => console.log('  M12 ' + d.case + ' ' + d.field + ': upstream ' + d.upstreamText + ' ('
  + d.upstream + '), SolveAxis ' + d.mutatedText + ' (' + d.mutated + ')'));
const deterministic = json1 === json2;
console.log(out1.titles.length + ' title, ' + out1.legends.length + ' legend, ' + out1.scroll.length + ' scroll cases; '
  + (out1.guards.length - bad.length) + '/' + out1.guards.length + ' guards; two runs '
  + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
