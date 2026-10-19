/*
Upstream's own answers for fix batch R2-F (spec section 223): A TEXT BOX'S
PICTURE, `backgroundColor: {image}`. zrender's Text._renderBackground makes a
ZRImage of the box (x, y, width, height of the box) after the box's Rect --
which is made only for a lineHeight or a border, and then holds the common
style (the opacity), the picture keeping its own 1; with no Rect the picture
takes the opacity. parseText widens a token whose width is not written
(none or 'auto') to the picture at the token's height once the picture is
there (isImageReady): max(width, image.width * tokenHeight / image.height).

A browser loads the picture and lays the text out again (the ZRImage's
onload dirties the Text); node loads none. So the picture fed here is an
object with the natural size of the PNG the port is given ('@wide' 20 x 10,
'@tall' 8 x 16 -- isImageReady reads width and height): the state after the
load. Each case is a bar with one labelled bar; the label Text of the first
bar is laid out (zr.storage.getDisplayList(true): no paint) and its children
are recorded in paint order: a Rect's shape, a ZRImage's style box and
opacity, a TSpan's x, y and text; plus every placed token's width and
height (Text._placeToken wrapped).

  node tools/advchart-oracle/rich-image.js

writes tests/fixtures/advchart-rich-image.json (ORACLE_OUT overrides); two
generations byte-identical; ends with process.exit(). Text is measured with
zrender's width table (node has no canvas); the table is in the fixture.
*/
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-rich-image.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}

// ---------- zrender's width table ----------
const FIRST_CODE = 32;
const LAST_CODE = 126;
function decodeTable(literal, where) {
  const s = Function('"use strict"; return (' + literal + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, where + ': the width table is not 95 characters');
  return s;
}
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = decodeTable(line.slice(line.indexOf('=') + 1).trim().replace(/;$/, ''), DIST);
  if (fs.existsSync(ZRENDER_SRC)) {
    const m = /const defaultWidthMapStr = (`[^`]*`)/.exec(fs.readFileSync(ZRENDER_SRC, 'utf8'));
    must(m && decodeTable(m[1], ZRENDER_SRC) === s, 'the dist and the zrender source disagree on the width table');
  }
  return s;
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);

// ---------- the pictures (the PNGs the port is given) ----------
const CRC = (() => {
  const t = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(w, h, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const raw = [];
  for (let y = 0; y < h; y++) {
    raw.push(0);
    for (let x = 0; x < w; x++) raw.push(...rgba(x, y));
  }
  const idat = zlib.deflateSync(Buffer.from(raw), { level: 9 });
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  return 'data:image/png;base64,' + Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]).toString('base64');
}
const IMAGES = {
  wide: { width: 20, height: 10, url: png(20, 10, x => (x < 10 ? [255, 0, 0, 255] : [0, 0, 255, 255])) },
  tall: { width: 8, height: 16, url: png(8, 16, (x, y) => (y < 8 ? [0, 160, 0, 255] : [0, 0, 0, 255])) },
};
// '@wide' -> the loaded picture (an object isImageReady takes)
function materialize(v) {
  if (typeof v === 'string' && v[0] === '@') {
    const im = IMAGES[v.slice(1)];
    must(im, 'no picture ' + v);
    return { width: im.width, height: im.height };
  }
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[k] = materialize(v[k]);
    return o;
  }
  return v;
}

// ---------- the token log ----------
(function install() {
  const P = echarts.graphic.Text.prototype;
  const upd = P._updateSubTexts;
  const tok = P._placeToken;
  P._updateSubTexts = function () {
    this.__tokLog = [];
    return upd.apply(this, arguments);
  };
  P._placeToken = function (token) {
    this.__tokLog.push({ text: token.text, styleName: token.styleName == null ? null : token.styleName,
      width: hex(token.width), height: hex(token.height) });
    return tok.apply(this, arguments);
  };
})();

function bar(label) {
  return {
    animation: false,
    xAxis: { type: 'category', data: ['a'] }, yAxis: { type: 'value', max: 10 },
    series: [{ type: 'bar', data: [5], label: Object.assign({ show: true, position: 'top' }, label) }],
  };
}
const CASES = [
  { id: 'token', note: 'a token of no width, a picture 20 x 10 at height 20: 40 wide, the picture over its box; no Rect',
    option: bar({ formatter: '{img|}{t|Txt}', rich: { img: { height: 20, backgroundColor: { image: '@wide' } }, t: {} } }) },
  { id: 'token-text', note: 'a token with words: the wider of the words and the picture',
    option: bar({ formatter: '{img|Words that are long}', rich: { img: { height: 10, backgroundColor: { image: '@wide' } } } }) },
  { id: 'token-width', note: 'a written width is kept (15)',
    option: bar({ formatter: '{img|}', rich: { img: { width: 15, height: 20, backgroundColor: { image: '@wide' } } } }) },
  { id: 'token-auto', note: "width 'auto' widens as none does: the tall picture 8 x 16 at 32 is 16",
    option: bar({ formatter: '{img|}', rich: { img: { width: 'auto', height: 32, backgroundColor: { image: '@tall' } } } }) },
  { id: 'token-padding', note: 'padding [2, 4]: the height the picture is fitted to holds the padding',
    option: bar({ formatter: '{img|}', rich: { img: { height: 10, padding: [2, 4], backgroundColor: { image: '@wide' } } } }) },
  { id: 'token-border', note: 'a border and a lineHeight: the Rect (stroked, unfilled) then the picture; the opacity on the Rect, the picture 1',
    option: bar({ formatter: '{img|}', rich: { img: { height: 20, lineHeight: 30, borderColor: '#ff0000', borderWidth: 2,
      opacity: 0.5, backgroundColor: { image: '@wide' } } } }) },
  { id: 'token-opacity', note: 'no Rect: the picture takes the opacity',
    option: bar({ formatter: '{img|}', rich: { img: { height: 20, opacity: 0.5, backgroundColor: { image: '@wide' } } } }) },
  { id: 'block', note: 'the box of a plain label: the picture over it, padding 4; the words do not widen it',
    option: bar({ padding: 4, backgroundColor: { image: '@tall' } }) },
  { id: 'block-rich', note: 'the box of a rich label, a token beside: the box picture, then the token',
    option: bar({ formatter: '{a|Aa}', padding: [2, 6], backgroundColor: { image: '@wide' }, rich: { a: {} } }) },
];

function textOf(chart) {
  const sm = chart.getModel().getSeriesByIndex(0);
  const el = sm.getData().getItemGraphicEl(0);
  const t = el.getTextContent();
  must(t, 'no label');
  return t;
}
const rect4 = (o, x, y, w, h) => Object.assign(o, { x: hex(x), y: hex(y), width: hex(w), height: hex(h) });

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 400, height: 300 });
  try {
    chart.setOption(materialize(c.option));
    chart.getZr().storage.getDisplayList(true);
    const t = textOf(chart);
    const children = t.childrenRef();
    const pieces = children.map(ch => {
      if (ch.type === 'rect') {
        const s = ch.style;
        return rect4({ kind: 'rect', stroke: s.stroke == null ? null : String(s.stroke), fill: s.fill == null ? null : String(s.fill),
          opacity: hex(s.opacity == null ? 1 : s.opacity) }, ch.shape.x, ch.shape.y, ch.shape.width, ch.shape.height);
      }
      if (ch.type === 'image') {
        const s = ch.style;
        return rect4({ kind: 'image', opacity: hex(s.opacity == null ? 1 : s.opacity) }, s.x, s.y, s.width, s.height);
      }
      if (ch.type === 'tspan') return { kind: 'text', text: String(ch.style.text), x: hex(ch.style.x), y: hex(ch.style.y) };
      throw new OracleError(c.id + ': a child of type ' + ch.type);
    });
    return { id: c.id, note: c.note, option: c.option, tokens: t.__tokLog || [], pieces };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    images: { wide: IMAGES.wide, tall: IMAGES.tall },
    cases: CASES.map(runCase),
  };
  const cs = id => out.cases.find(q => q.id === id);
  const img = id => cs(id).pieces.filter(p => p.kind === 'image');
  out.guards = [
    { name: 'token: 40 wide', ok: img('token').length === 1 && num(img('token')[0].width) === 40 && cs('token').pieces.every(p => p.kind !== 'rect') },
    { name: 'token-width: 15 kept', ok: num(img('token-width')[0].width) === 15 },
    { name: 'token-auto: 16', ok: num(img('token-auto')[0].width) === 16 },
    { name: 'token-border: a Rect, then the picture at 1, the Rect at 0.5',
      ok: cs('token-border').pieces[0].kind === 'rect' && cs('token-border').pieces[1].kind === 'image'
        && num(cs('token-border').pieces[1].opacity) === 1 && num(cs('token-border').pieces[0].opacity) === 0.5 },
    { name: 'token-opacity: the picture at 0.5', ok: num(img('token-opacity')[0].opacity) === 0.5 },
    { name: 'block: a picture', ok: img('block').length === 1 },
  ];
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
out1.cases.forEach(c => console.log(c.id + ': ' + c.pieces.map(p => p.kind + (p.width ? '[' + [p.x, p.y, p.width, p.height].map(num).join(',') + ']' : '(' + num(p.x) + ',' + num(p.y) + ')')).join(' ')));
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name));
if (bad.length || json1 !== json2 || json1.includes('\\u0000')) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
