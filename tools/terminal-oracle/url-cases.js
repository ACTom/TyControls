// Writes tests/fixtures/terminal-links.json for tests/test.terminal.links.pas from
// xterm.js 6.0.0's web-links addon, OscLinkProvider and Linkifier (pin and loading
// in lib-dump.js loadBrowserParts). Inputs: cases/links.js.
//
//   node tools/terminal-oracle/url-cases.js
//
// prefix  { text, ok, protocol, base, isUrl } -- node's WHATWG `new URL(text)`
//         (the real oracle), and the parsedBase / startsWith of isUrl
//         (addons/addon-web-links/src/WebLinkProvider.ts:44-55), copied here as a
//         formula because isUrl is not exported. Inputs whose host goes through IDNA
//         (non-ASCII, or an xn-- label) are left out -- the port does not do IDNA
//         (plan, question two #5); their answers are pinned by hand in the tests.
// urls    { text: b64, links: [{ text: b64, range: [sx, sy, ex, ey] }] } -- the text
//         written alone on row 1 of a 300-column terminal, LinkComputer.computeLink(1,
//         strictUrlRegex, terminal) (WebLinkProvider.ts:59-101).
// lines   { id, cols, rows, write: b64, resize?: [c, r], windowsPty?: {...},
//           queries: [{ y, web, osc, oscAll, kept, hits }] } -- written, then resized
//         when `resize` is there (phase 5: the buffer rewraps, or under an old ConPTY
//         keeps lines longer than the grid), then queried
//         web     computeLink(y)
//         osc     OscLinkProvider.provideLinks(y) with no linkHandler
//         oscAll  the same with linkHandler.allowNonHttpProtocols
//         kept    [osc, web] after Linkifier._removeIntersectingLinks(y) (OSC 8 first,
//                 CoreBrowserTerminal.ts:182)
//         hits    for x = 1..cols on row y, the index into kept (osc then web,
//                 flattened) of the first link _linkAtPosition finds in provider
//                 order, or -1. (Upstream checks the first hover of a line before the
//                 overlap removal and every later one after it; the control always
//                 looks after it -- the plan's TyTermFindLinkAt.)
// A link is { text: b64 (UTF-8), range: [sx, sy, ex, ey] } (1-based, inclusive, as
// IBufferRange). Reproducible: no time, fixed key order.
'use strict';
const T = require('./lib-term.js');
const L = T.L;
const C = require('./cases/links.js');

const up = T.loadUpstream();
const B = L.loadBrowserParts();
const b64 = s => Buffer.from(s, 'utf8').toString('base64');
const noop = () => {};

// ---- prefix -----------------------------------------------------------------------
const filtered = [];
const prefix = [];
for (const text of C.PREFIX) {
  let url = null;
  try { url = new URL(text); } catch { url = null; }
  const auth = /^[^:]*:[\/\\]*([^\/\\?#]*)/.exec(text);
  if ((url && url.hostname.includes('xn--')) || (auth && (/[^\x00-\x7f]/.test(auth[1]) || /xn--/i.test(auth[1])))) {
    filtered.push(text);
    continue;
  }
  if (!url) {
    prefix.push({ text, ok: false, protocol: null, base: null, isUrl: false });
    continue;
  }
  // WebLinkProvider.ts:47-52
  const parsedBase = url.password && url.username
    ? `${url.protocol}//${url.username}:${url.password}@${url.host}`
    : url.username
      ? `${url.protocol}//${url.username}@${url.host}`
      : `${url.protocol}//${url.host}`;
  const isUrl = text.toLocaleLowerCase().startsWith(parsedBase.toLocaleLowerCase());
  prefix.push({ text, ok: true, protocol: url.protocol, base: parsedBase, isUrl });
}
// isUrl itself, through the provider, must agree with the copied formula: a line
// holding just the text yields a link exactly when isUrl and the regex agree.

function linkOut(l) {
  const r = l.range;
  return { text: b64(l.text), range: [r.start.x, r.start.y, r.end.x, r.end.y] };
}

// ---- urls -------------------------------------------------------------------------
const urls = [];
{
  const term = T.makeCaseTerminal(up, { cols: 300, rows: 3, options: { scrollback: 0 } });
  for (const text of C.URLS) {
    term.reset();
    term._core.writeSync(Buffer.from(text, 'utf8'));
    if (term.buffer.active.cursorY !== 0) throw new Error('does not fit one row: ' + text);
    const links = B.LinkComputer.computeLink(1, B.strictUrlRegex, term, noop);
    urls.push({ text: b64(text), links: links.map(linkOut) });
  }
  term.dispose();
}

// ---- lines ------------------------------------------------------------------------
const lines = [];
for (const c of C.LINES) {
  const term = T.makeCaseTerminal(up, { cols: c.cols, rows: c.rows,
    options: Object.assign({ scrollback: 0 }, c.windowsPty ? { windowsPty: c.windowsPty } : {}) });
  const core = term._core;
  core.writeSync(Buffer.from(c.write, 'utf8'));
  if (c.resize) term.resize(c.resize[0], c.resize[1]);
  const cols = term.cols;
  const osc = new B.OscLinkProvider(core._bufferService, core.optionsService, core._oscLinkService);
  const provide = y => {
    let got;
    osc.provideLinks(y, links => { got = links; });
    return got;
  };
  const queries = [];
  const ys = c.queries || Array.from({ length: term.rows }, (_, k) => k + 1);
  for (const y of ys) {
    const web = B.LinkComputer.computeLink(y, B.strictUrlRegex, term, noop);
    term.options.linkHandler = null;
    const oscLinks = provide(y);
    term.options.linkHandler = { allowNonHttpProtocols: true, activate() {} };
    const oscAll = provide(y);
    term.options.linkHandler = null;
    // the Linkifier's replies: provider index -> [{ link }]
    const replies = new Map();
    replies.set(0, oscLinks ? oscLinks.map(link => ({ link })) : undefined);
    replies.set(1, web.map(link => ({ link })));
    B.Linkifier.prototype._removeIntersectingLinks.call({ _bufferService: { cols } }, y, replies);
    const kept = [0, 1].map(i => (replies.get(i) || []).map(w => w.link));
    const flat = [...kept[0], ...kept[1]];
    const hits = [];
    for (let x = 1; x <= cols; x++) {
      let found = -1;
      for (let k = 0; k < flat.length && found === -1; k++) {
        if (B.Linkifier.prototype._linkAtPosition.call({ _bufferService: { cols } }, flat[k], { x, y })) found = k;
      }
      hits.push(found);
    }
    queries.push({
      y, web: web.map(linkOut), osc: (oscLinks || []).map(linkOut), oscAll: (oscAll || []).map(linkOut),
      kept: kept.map(k => k.map(linkOut)), hits,
    });
  }
  const entry = { id: c.id, cols: c.cols, rows: c.rows, write: b64(c.write) };
  if (c.resize) entry.resize = c.resize;
  if (c.windowsPty) entry.windowsPty = c.windowsPty;
  entry.queries = queries;
  lines.push(entry);
  term.dispose();
}

L.writeFixture('terminal-links.json', {
  upstream: L.upstreamInfo(), generator: 'tools/terminal-oracle/url-cases.js', kind: 'links',
  prefix, urls, lines,
});
let nq = 0;
for (const l of lines) nq += l.queries.length;
console.log(`links: ${prefix.length} prefixes, ${urls.length} lines of addresses, ${lines.length} scenes / ${nq} queries`);
console.log('left out (IDNA hosts): ' + filtered.map(s => JSON.stringify(s)).join(' '));
