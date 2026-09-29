// Writes tests/fixtures/terminal-buffer-ops.json for tests/test.terminal.buffer.pas:
// operation scripts run step by step on xterm.js 6.0.0's own BufferLine,
// CircularList and BufferService -- never through the parser -- with the return
// value and the complete state recorded after every step. Upstream path and pin:
// lib-dump.js, through lib-term.js. Inputs: cases/buffer.js.
//
//   node tools/terminal-oracle/buffer-cases.js
//
// Shell: the plan's "夹具格式"; kind "buffer-ops". Each case is
//   { id, target: "line" | "list" | "buffers", init, ops: [[name, ...args] ...],
//     after: [{ ret, state } per op] }
// "ret" is absent when the op returns nothing; "throws" when upstream throws (the
// script goes on with the next op).
//
// Values inside ops:
//   attr = { fg, bg, ext? }        cell = { content, fg, bg, ext?, comb?: [cp...] }
//   ext  = { raw?, urlId?, style?, color?, variant? }: new ExtendedAttrs(raw, urlId),
//          then the underlineStyle / underlineColor / underlineVariantOffset setters
//          in that order for the keys present. A cell with comb has the combined bit
//          in content; combinedData is those code points.
//
// target "line" -- init: { lines: { <name>: { cols, fill?: cell } } },
//   new BufferLine(cols, fill). Ops (upstream call -> ret):
//   ["setCellFromCodepoint", n, col, cp, width, attr]   ["addCodepointToCell", n, col, cp, width]
//   ["setCell", n, col, cell]    ["insertCells" | "deleteCells", n, pos, count, cell]
//   ["replaceCells", n, start, end, cell, respectProtect]
//   ["resize", n, cols, cell] -> the boolean         ["fill", n, cell, respectProtect]
//   ["copyFrom", dst, src, blank]   ["clone", dst, src, blank] (the clone becomes dst)
//   ["copyCellsFrom", dst, src, srcCol, destCol, len, reverse]  ["setWrapped", n, bool]
//   ["translate", n, trimRight, start|null, end|null] -> translateToString, digestable
//   ["trimmed", n] / ["noBgTrimmed", n] -> number
//   ["probe", n, col] -> [getWidth, !!hasWidth, !!hasContent, getCodePoint,
//                          !!isCombined, getString (digestable), !!isProtected]
//   ["load", n, col] -> { content, fg, bg, ext: quad, comb?: [cp...] }
//   state: { lines: [{ name, ...one line as lib-term dumpLineOnly, len always }] }
//
// target "list" -- init: { max }, new CircularList(max) of integer tags. Ops:
//   ["push", tag] ["set", i, tag] ["splice", start, del, [tags]] ["trimStart", n]
//   ["setMax", n] ["setLength", n] ["recycle"] ["pop"] ["get", i] (the last three
//   return the tag or null) ["shift", start, count, offset]
//   state: { length, maxLength, isFull, items: [tag|null for 0..length-1],
//            events: [["insert", i, n] | ["delete", i, n] | ["trim", n] ...] } (this
//   step's events, in order).
//
// target "buffers" -- init: { cols, rows, options: { scrollback?, tabStopWidth?,
//   windowsPty?, reflowCursorLine? } }: a headless terminal, of which only
//   term._core._bufferService (and the OSC link service) is driven. Ops on the
//   ACTIVE buffer unless named:
//   ["scroll", attr, isWrapped]  ["scrollLines", disp]  ["resize", cols, rows]
//   (bufferService.resize: no flush, no minimum)  ["reset"]  ["activateAlt", attr|null]
//   ["activateNormal"]  ["setXY", x, y]  ["setMargins", top, bottom]  ["setYdisp", n]
//   ["saveX", n] ["saveY", n] (savedX / savedY)  ["text", absRow, col, "ascii"]
//   ["setWrapped", absRow, bool]  ["setupTabStops", i|null]  ["tabSet", col]
//   ["tabClear", col]  ["tabClearAll"]  ["nextStop", x|null] / ["prevStop", x|null]
//   -> number  ["addMarker", absRow] -> its index among this case's markers
//   ["disposeMarker", k]  ["clearMarkers", absRow]  ["clearAllMarkers"]
//   ["wrappedRange", absRow] -> [first, last]  ["setOption", name, value]
//   ["fillViewport", attr|null]  ["clear"]  ["registerLink", id|null, uri] -> link id
//   ["addLineToLink", linkId, absRow]  ["getLinkData", linkId] -> [id|null, uri] | null
//   Phase 5 (reflow, the shapes of Buffer.test.ts): ["cells", absRow, col, [[cp, w] ...]]
//   (setCellFromCodepoint cell by cell, default attributes; [0, 0] is a wide
//   character's second half)  ["combine", absRow, col, cp] (addCodepointToCell, width
//   0)  ["insertBlank", index, n] (n times lines.splice(index, 0, getBlankLine(default)))
//   ["setYbase", n]; setOption also takes "reflowCursorLine".
//   state: { active, isUserScrolling, scrolls: [ydisp of each onScroll this step],
//            buffers: { normal: <buf>, alt: <buf> } (no line omitted),
//            markers: [[line, isDisposed] for every marker this case made],
//            links: [...] }
'use strict';
const path = require('path');
const T = require('./lib-term.js');
const L = T.L;
const C = require('./cases/buffer.js');

const up = T.loadUpstream();
const out = p => require(path.join(L.XTERM, L.OUT_DIR, p));
const { BufferLine, DEFAULT_ATTR_DATA } = out('common/buffer/BufferLine.js');
const { CellData } = out('common/buffer/CellData.js');
const { AttributeData, ExtendedAttrs } = out('common/buffer/AttributeData.js');
const { CircularList } = out('common/CircularList.js');

function extOf(e) {
  const x = new ExtendedAttrs(e.raw || 0, e.urlId || 0);
  if (e.style !== undefined) x.underlineStyle = e.style;
  if (e.color !== undefined) x.underlineColor = e.color;
  if (e.variant !== undefined) x.underlineVariantOffset = e.variant;
  return x;
}
function attrOf(a) {
  const r = new AttributeData();
  r.fg = a.fg;
  r.bg = a.bg;
  if (a.ext) r.extended = extOf(a.ext);
  return r;
}
function cellOf(c) {
  const r = new CellData();
  r.content = c.content;
  r.fg = c.fg;
  r.bg = c.bg;
  if (c.ext) r.extended = extOf(c.ext);
  if (c.comb) r.combinedData = String.fromCodePoint(...c.comb);
  return r;
}
const quad = e => [e.ext >>> 0, e.urlId, e.underlineColor >>> 0, e.underlineVariantOffset];

// ---- line ------------------------------------------------------------------------

function runLineCase(c) {
  const lines = {};
  for (const [name, spec] of Object.entries(c.init.lines)) lines[name] = new BufferLine(spec.cols, spec.fill ? cellOf(spec.fill) : undefined);
  const after = [];
  for (const op of c.ops) {
    const [name, n, ...a] = op;
    const ln = lines[n];
    let ret;
    switch (name) {
      case 'setCellFromCodepoint': ln.setCellFromCodepoint(a[0], a[1], a[2], attrOf(a[3])); break;
      case 'addCodepointToCell': ln.addCodepointToCell(a[0], a[1], a[2]); break;
      case 'setCell': ln.setCell(a[0], cellOf(a[1])); break;
      case 'insertCells': ln.insertCells(a[0], a[1], cellOf(a[2])); break;
      case 'deleteCells': ln.deleteCells(a[0], a[1], cellOf(a[2])); break;
      case 'replaceCells': ln.replaceCells(a[0], a[1], cellOf(a[2]), a[3]); break;
      case 'resize': ret = ln.resize(a[0], cellOf(a[1])); break;
      case 'fill': ln.fill(cellOf(a[0]), a[1]); break;
      case 'copyFrom': ln.copyFrom(lines[a[0]], a[1]); break;
      case 'clone': lines[n] = lines[a[0]].clone(a[1]); break;
      case 'copyCellsFrom': ln.copyCellsFrom(lines[a[0]], a[1], a[2], a[3], a[4]); break;
      case 'setWrapped': ln.isWrapped = a[0]; break;
      case 'translate': ret = T.digestable(ln.translateToString(a[0], a[1] ?? undefined, a[2] ?? undefined)); break;
      case 'trimmed': ret = ln.getTrimmedLength(); break;
      case 'noBgTrimmed': ret = ln.getNoBgTrimmedLength(); break;
      case 'probe': {
        const col = a[0];
        ret = [ln.getWidth(col), !!ln.hasWidth(col), !!ln.hasContent(col), ln.getCodePoint(col),
          !!ln.isCombined(col), T.digestable(ln.getString(col)), !!ln.isProtected(col)];
        break;
      }
      case 'load': {
        const cell = ln.loadCell(a[0], new CellData());
        ret = { content: cell.content >>> 0, fg: cell.fg >>> 0, bg: cell.bg >>> 0, ext: quad(cell.extended) };
        if (cell.content & 0x200000) ret.comb = T.cps(cell.combinedData);
        break;
      }
      default: throw new Error(c.id + ': unknown line op ' + name);
    }
    const state = { lines: Object.keys(lines).sort().map(k => Object.assign({ name: k }, T.dumpLineOnly(lines[k], -1, true))) };
    after.push(ret === undefined ? { state } : { ret, state });
  }
  return Object.assign({}, c, { after });
}

// ---- list ------------------------------------------------------------------------

function runListCase(c) {
  const list = new CircularList(c.init.max);
  let events = [];
  list.onInsert(e => events.push(['insert', e.index, e.amount]));
  list.onDelete(e => events.push(['delete', e.index, e.amount]));
  list.onTrim(n => events.push(['trim', n]));
  const tag = v => (v === undefined ? null : v);
  const after = [];
  for (const op of c.ops) {
    events = [];
    const [name, ...a] = op;
    let ret;
    try {
      switch (name) {
        case 'push': list.push(a[0]); break;
        case 'set': list.set(a[0], a[1]); break;
        case 'splice': list.splice(a[0], a[1], ...a[2]); break;
        case 'trimStart': list.trimStart(a[0]); break;
        case 'setMax': list.maxLength = a[0]; break;
        case 'setLength': list.length = a[0]; break;
        case 'recycle': ret = tag(list.recycle()); break;
        case 'pop': ret = tag(list.pop()); break;
        case 'get': ret = tag(list.get(a[0])); break;
        case 'shift': list.shiftElements(a[0], a[1], a[2]); break;
        default: throw new Error(c.id + ': unknown list op ' + name);
      }
    } catch (e) {
      if (/unknown list op/.test(e.message)) throw e;
      ret = 'throws';
    }
    const items = [];
    for (let i = 0; i < list.length; i++) items.push(tag(list.get(i)));
    const state = { length: list.length, maxLength: list.maxLength, isFull: list.isFull, items, events };
    after.push(ret === undefined ? { state } : { ret, state });
  }
  return Object.assign({}, c, { after });
}

// ---- buffers ---------------------------------------------------------------------

function runBuffersCase(c) {
  const o = c.init.options || {};
  const term = new up.Terminal({ allowProposedApi: true, logLevel: 'off', cols: c.init.cols, rows: c.init.rows,
    scrollback: o.scrollback ?? 1000, tabStopWidth: o.tabStopWidth ?? 8, windowsPty: o.windowsPty ?? {},
    reflowCursorLine: o.reflowCursorLine ?? false });
  const core = term._core;
  const bs = core._bufferService;
  const links = core._oscLinkService;
  const markers = [];
  let scrolls = [];
  bs.onScroll(y => scrolls.push(y));
  const after = [];
  for (const op of c.ops) {
    scrolls = [];
    const [name, ...a] = op;
    const buf = bs.buffer;
    let ret;
    switch (name) {
      case 'scroll': bs.scroll(attrOf(a[0]), a[1]); break;
      case 'scrollLines': bs.scrollLines(a[0]); break;
      case 'resize': bs.resize(a[0], a[1]); break;
      case 'reset': bs.reset(); break;
      case 'activateAlt': bs.buffers.activateAltBuffer(a[0] ? attrOf(a[0]) : undefined); break;
      case 'activateNormal': bs.buffers.activateNormalBuffer(); break;
      case 'setXY': buf.x = a[0]; buf.y = a[1]; break;
      case 'setMargins': buf.scrollTop = a[0]; buf.scrollBottom = a[1]; break;
      case 'setYdisp': buf.ydisp = a[0]; break;
      case 'saveX': buf.savedX = a[0]; break;
      case 'saveY': buf.savedY = a[0]; break;
      case 'text': { const ln = buf.lines.get(a[0]); let col = a[1]; for (const ch of a[2]) ln.setCellFromCodepoint(col++, ch.codePointAt(0), 1, DEFAULT_ATTR_DATA); break; }
      case 'setWrapped': buf.lines.get(a[0]).isWrapped = a[1]; break;
      case 'cells': { const ln = buf.lines.get(a[0]); let col = a[1]; for (const [cp, w] of a[2]) ln.setCellFromCodepoint(col++, cp, w, DEFAULT_ATTR_DATA); break; }
      case 'combine': buf.lines.get(a[0]).addCodepointToCell(a[1], a[2], 0); break;
      case 'insertBlank': for (let k = 0; k < a[1]; k++) buf.lines.splice(a[0], 0, buf.getBlankLine(DEFAULT_ATTR_DATA)); break;
      case 'setYbase': buf.ybase = a[0]; break;
      case 'setupTabStops': buf.setupTabStops(a[0] ?? undefined); break;
      case 'tabSet': buf.tabs[a[0]] = true; break;
      case 'tabClear': delete buf.tabs[a[0]]; break;
      case 'tabClearAll': buf.tabs = {}; break;
      case 'nextStop': ret = buf.nextStop(a[0] ?? undefined); break;
      case 'prevStop': ret = buf.prevStop(a[0] ?? undefined); break;
      case 'addMarker': markers.push(buf.addMarker(a[0])); ret = markers.length - 1; break;
      case 'disposeMarker': markers[a[0]].dispose(); break;
      case 'clearMarkers': buf.clearMarkers(a[0]); break;
      case 'clearAllMarkers': buf.clearAllMarkers(); break;
      case 'wrappedRange': { const r = buf.getWrappedRangeForLine(a[0]); ret = [r.first, r.last]; break; }
      case 'setOption': term.options[a[0]] = a[1]; break;
      case 'fillViewport': buf.fillViewportRows(a[0] ? attrOf(a[0]) : undefined); break;
      case 'clear': buf.clear(); break;
      case 'registerLink': ret = links.registerLink(a[0] === null ? { uri: a[1] } : { id: a[0], uri: a[1] }); break;
      case 'addLineToLink': links.addLineToLink(a[0], a[1]); break;
      case 'getLinkData': { const d = links.getLinkData(a[0]); ret = d ? [d.id === undefined ? null : d.id, d.uri] : null; break; }
      default: throw new Error(c.id + ': unknown buffers op ' + name);
    }
    const state = {
      active: bs.buffers.active === bs.buffers.alt ? 'alt' : 'normal',
      isUserScrolling: bs.isUserScrolling,
      scrolls: scrolls.slice(),
      buffers: { normal: T.dumpBuffer(up, term, bs.buffers.normal, true), alt: T.dumpBuffer(up, term, bs.buffers.alt, true) },
      markers: markers.map(m => [m.line, m.isDisposed]),
      links: T.dumpLinks(term),
    };
    after.push(ret === undefined ? { state } : { ret, state });
  }
  term.dispose();
  return Object.assign({}, c, { after });
}

const cases = [
  ...C.lineCases.map(runLineCase),
  ...C.listCases.map(runListCase),
  ...C.bufferCases.map(runBuffersCase),
];
const written = L.writeFixture('terminal-buffer-ops.json', {
  upstream: up.info, generator: 'tools/terminal-oracle/buffer-cases.js', kind: 'buffer-ops', cases,
});
console.log(`line ${C.lineCases.length}, list ${C.listCases.length}, buffers ${C.bufferCases.length} cases; files ${written.join(', ')}`);
process.exit(0);
