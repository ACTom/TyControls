// Inputs for url-cases.js: URL prefixes (isUrl's parse), single-line web addresses,
// and multi-row scenes with OSC 8 links. The upstream test's own shapes come first
// (addons/addon-web-links/test/WebLinksAddon.test.ts:33-188), then ours.
'use strict';

// ---- prefix: new URL + the parsedBase formula of WebLinkProvider.ts:44-55 ----------
const PREFIX = [
  // ports
  'http://a.com:80/x', 'http://a.com:080/x', 'http://a.com:0080', 'http://a.com:443', 'https://a.com:443/x',
  'https://a.com:80', 'http://a.com:8080/x', 'http://a.com:08080/x', 'http://a.com:65535', 'http://a.com:65536',
  'http://a.com:0', 'http://a.com:/x', 'http://a.com:8a', 'http://a.com:99999999999999999999',
  // user info
  'http://u@a.com/x', 'http://:p@a.com/x', 'http://u:p@a.com/x', 'http://u:p:q@a.com', 'http://a@b@c.com/x',
  'http://u;x@a.com', 'http://u=x@a.com', 'http://u[x@a.com', 'http://%41@a.com', 'http://u:@a.com',
  'http://@a.com', 'http://u%3Ax@a.com', 'http://U:P@A.com', 'http://u!$&\'()*+,x@a.com', 'http://u|x@a.com',
  'http://u^x@a.com', 'http://u`x@a.com', 'http://u{x}@a.com', 'http://u"x@a.com', 'http://u~x@a.com',
  // hosts
  'http://EXAMPLE.COM/x', 'http://ex%41mple.com', 'http://exa_mple.com', 'http://a..b.com', 'http://a.com.',
  'http://127.0.0.1/x', 'http://127.1', 'http://0x7f.0.0.1', 'http://1.2.3.4.', 'http://256.1.1.1',
  'http://1.2.3.08', 'http://1.2.3.07', 'http://0177.0.0.1', 'http://4294967295', 'http://4294967296',
  'http://1.16777215', 'http://1.2.65535', 'http://1.2.3.4.5', 'http://1.2.3.4..', 'http://1..2.3',
  'http://0x.1', 'http://09.com', 'http://a.09', 'http://a.0x1', 'http://1.2.3.4x',
  'http://[::1]/x', 'http://[0:0::1]', 'http://[::FFFF:1.2.3.4]', 'http://[1:2:3:4:5:6:7:8]', 'http://[1::2::3]',
  'http://[::1]:8080', 'http://[::1', 'http://[1:0:0:2:0:0:0:3]', 'http://[1:0:0:0:2:0:0:3]', 'http://[0:0:0:0:0:0:0:0]',
  'http://[1:2:3:4:5:6:7::]', 'http://[::1.2.3.4]', 'http://[1:2:3:4:5:6:1.2.3.4]', 'http://[::1.2.3]', 'http://[12345::]',
  'http://[::g]', 'http://[1:2:3:4:5:6:7:8:9]', 'http://[:1]', 'http://[1:]', 'http://[::01.2.3.4]',
  'http://a%2Fb.com', 'http://a%25b.com', 'http://a b.com', 'http://a<b.com', 'http://a^b.com', 'http://a|b.com',
  'http://a%00b.com', 'http://a%zzb.com', 'http://a%7eb.com', 'http://A%2eCOM',
  // schemes
  'HTTP://A.COM', 'https://', 'http:///x', 'http:\\\\a.com', 'http:/\\/a.com', 'ftp://a.com', 'file:///c:/x',
  'ssh://h', 'mailto:a@b', ' http://a.com ', 'ht\ttp://a.com', 'javascript:alert(1)', 'hTTp://a.com',
  'http://a.com\\x', 'http://a.com?q', 'http://a.com#f', 'http://a.com/p?q#f', 'h2://x', '1http://x', 'http//x',
  // what the regex hands isUrl
  'http://example.com', 'https://ko.wikipedia.org/wiki/x', 'http://test:password@example.com/some_path',
  'HTTP://Ab:xY@abc.com:80/staysUpper', 'HTTP://Example.com:80/staysUpper',
  // hosts that go through IDNA: filtered out of the fixture (the plan's deviation),
  // pinned by hand in TTyTerminalLinksTests instead
  'http://\u4f8b\u5b50.\u6d4b\u8bd5/', 'http://m\u00fcnchen.de', 'http://xn--zz.com', 'http://xn--mnchen-3ya.de',
];

// ---- urls: one line each, in a 300-column terminal ---------------------------------
const CC = ['.ac', '.cn', '.de', '.io', '.jp', '.kr', '.nl', '.ru', '.sh', '.tv', '.uk', '.zw'];
const HOSTS = [...CC.map(t => 'foo' + t), 'foo.com', ...['.cn', '.jp', '.uk'].map(t => 'foo.com' + t)];
const hostLines = h => [
  `  http://${h}  `,
  `  http://${h}/a~b#c~d?e~f  `,
  `  http://${h}/colon:test  `,
  `  http://${h}/colon:test:  `,
  `"http://${h}/"`,
  `'http://${h}/'`,
  `http://${h}/subpath/+/id`,
];
const URLS = [
  ...HOSTS.flatMap(hostLines),
  // upstream #4964
  '  HTTP://EXAMPLE.COM  ', '  HTTPS://Example.com  ', '  HTTP://Example.com:80  ',
  '  HTTP://Example.com:80/staysUpper  ', '  HTTP://Ab:xY@abc.com:80/staysUpper  ',
  // upstream's offset tests, unwrapped here (wrapped in LINES)
  'aaa http://example.com aaa http://example.com aaa',
  '\uffe5\uffe5\uffe5 http://example.com \uffe5\uffe5\uffe5 http://example.com aaa',
  '\uffe5\uffe5\uffe5 https://ko.wikipedia.org/wiki/\uc704\ud0a4\ubc31\uacfc:\ub300\ubb38 aaa https://ko.wikipedia.org/wiki/\uc704\ud0a4\ubc31\uacfc:\ub300\ubb38 \uffe5\uffe5\uffe5',
  '\uffe5\uffe5\uffe5cafe\u0301 http://test:password@example.com/some_path',
  '\uffe5\uffe5\uffe5cafe\u0301 http://test:password@example.com/some_path?param=1%202%3',
  // ours: where an address ends
  'a http://a.com/x\u3000y b', 'a http://a.com/x\u00a0y b', 'a http://a.com/x\u2003y', 'a http://a.com/x\u2028y',
  'a http://a.com/x\ufeffy', 'a http://a.com/x\u1680y', 'a http://a.com/x\u205fy', 'a http://a.com/x\u200by',
  'see http://a.com.', 'see http://a.com,', 'see http://a.com!', 'see http://a.com?', 'see http://a.com:',
  'see http://a.com/x.,!?:', '(http://a.com)', '<http://a.com>', '"http://a.com"', '\'http://a.com\'',
  '[http://a.com]', '{http://a.com}', 'http://a.com*', 'http://a.com**', 'http://a.com/*x', 'http://a.com/x*y*',
  'xhttp://a.com', 'Http://a.com', 'hTTP://a.com', 'HTTPs://a.com', 'httpS://a.com', 'https:/a.com',
  'https://a.com', 'HTTPS://A.COM', 'http://a.com/~u', 'http://a.com/p(1)', 'http://a.com/p(1)x',
  'http://a.com/a,b', 'http://a.com/a;b=c', 'http://a.com/[x]', 'http://[::1]/x', 'http://[::1]:80/x',
  'http://a.com/x http://b.com/y http://c.com/z', 'http://a.comhttp://b.com', 'http://http://a.com',
  'http://', 'http:// x', 'http://.', 'http://-', 'http://a', 'http://a.com/\u00e9t\u00e9', 'http://a.com/\u4e2d\u6587',
  'http://a.com/\u{1F600}x', 'http://a.com:80', 'http://a.com:80/x', 'http://a.com:8080', 'http://a.com:65536/x',
  'http://u:p@a.com/x', 'http://:p@a.com/x', 'http://u;x@a.com/x', 'http://a@b@c.com/x', 'http://127.1/x',
  'http://127.0.0.1:8000/x', 'http://0x7f.0.0.1/x', 'http://ex%41mple.com/x', 'http://a.com/%41',
  'http://a.com\\x', 'http://a.com/x\\y', 'http://a.com/x|y', 'http://a.com/x^y', 'http://a.com/x`y',
  'http://a.com/x{y}', 'http://a.com/x<y>', 'http://a.com/x"y', 'http://a.com/x\'y', 'http://a.com/x!y',
  // every printable ASCII character inside an address and at its end: the regex's
  // two classes, character by character
  ...Array.from({ length: 94 }, (_, i) => String.fromCharCode(33 + i)).flatMap(c => [`http://a.com/x${c}y z`, `http://a.com/x${c}`]),
  // IDNA hosts: isUrl's real answer is "no" (not a deviation)
  'http://\u4f8b\u5b50.\u6d4b\u8bd5', 'http://m\u00fcnchen.de', 'go http://m\u00fcnchen.de/x now',
];

// ---- lines: several rows, OSC 8, overlap, hits ----------------------------------------
const osc8 = (uri, text, id) => `\x1b]8;${id ? 'id=' + id : ''};${uri}\x1b\\${text}\x1b]8;;\x1b\\`;
const LINES = [
  // upstream's offset tests as they wrap at 40 columns
  { id: 'upstream-half-width', cols: 40, rows: 4, write: 'aaa http://example.com aaa http://example.com aaa' },
  { id: 'upstream-after-full-width', cols: 40, rows: 4, write: '\uffe5\uffe5\uffe5 http://example.com \uffe5\uffe5\uffe5 http://example.com aaa' },
  { id: 'upstream-full-width-in-url', cols: 40, rows: 4, write: '\uffe5\uffe5\uffe5 https://ko.wikipedia.org/wiki/\uc704\ud0a4\ubc31\uacfc:\ub300\ubb38 aaa https://ko.wikipedia.org/wiki/\uc704\ud0a4\ubc31\uacfc:\ub300\ubb38 \uffe5\uffe5\uffe5' },
  { id: 'upstream-password-combining', cols: 40, rows: 4, write: '\uffe5\uffe5\uffe5cafe\u0301 http://test:password@example.com/some_path' },
  { id: 'upstream-encoded-params', cols: 40, rows: 4, write: '\uffe5\uffe5\uffe5cafe\u0301 http://test:password@example.com/some_path?param=1%202%3' },
  { id: 'upstream-20-cols', cols: 20, rows: 4, write: 'aaa http://example.com aaa' },
  // ours
  { id: 'three-rows', cols: 20, rows: 5, write: 'see http://example.com/a/very/long/path/here ok' },
  { id: 'wide-char-wrapped-early', cols: 20, rows: 4, write: 'go http://a.com/abc\u4e2d\u6587/x y' },
  { id: 'wide-char-wrapped-early-2', cols: 10, rows: 4, write: 'http://a.\u4e2d.com x' },
  { id: 'wide-char-wrapped-early-path', cols: 10, rows: 4, write: 'http://a.c/\u4e2d\u6587\u5b57 x' },
  { id: 'up-stops-at-a-space', cols: 10, rows: 5, write: 'aa bb cc dhttp://a.com/x yy' },
  { id: 'up-stops-at-a-space-2', cols: 10, rows: 5, write: 'q http://a.com/abcdefghijklmn yy' },
  { id: 'row-starts-with-a-space', cols: 10, rows: 5, write: 'http://a.c om/x' },
  { id: 'down-stops-at-a-space', cols: 10, rows: 5, write: 'http://a.com/abcdefgh ij http://b.com' },
  { id: 'the-2048-limit', cols: 200, rows: 14, write: 'go http://a.com/' + 'x'.repeat(2380) + ' end', queries: [1, 2, 6, 11, 12, 13] },
  { id: 'the-2048-limit-up', cols: 200, rows: 14, write: 'http://a.com/' + 'y'.repeat(2500), queries: [1, 12, 13] },
  { id: 'osc-two-adjacent', cols: 30, rows: 3, write: 'x ' + osc8('http://a.com', 'AAA') + osc8('http://b.com', 'BBB') + ' tail' },
  { id: 'osc-same-id-apart', cols: 30, rows: 3, write: osc8('http://a.com', 'one', 'k') + ' mid ' + osc8('http://a.com', 'two', 'k') },
  { id: 'osc-same-id-adjacent', cols: 30, rows: 3, write: osc8('http://a.com', 'one', 'k') + osc8('http://a.com', 'two', 'k') + ' z' },
  { id: 'osc-at-the-line-end', cols: 12, rows: 3, write: 'abcd' + osc8('http://a.com', 'LINKTEXT') },
  { id: 'osc-before-trailing-cells', cols: 20, rows: 3, write: 'abcd' + osc8('http://a.com', 'LINK') },
  { id: 'osc-then-spaces', cols: 20, rows: 3, write: 'abcd' + osc8('http://a.com', 'LINK') + '   ' },
  { id: 'osc-wrapped', cols: 10, rows: 4, write: 'abcdef' + osc8('https://x.org/p', 'LINKLINK') + ' tail' },
  { id: 'osc-wrapped-three-rows', cols: 10, rows: 5, write: 'abcdefgh' + osc8('https://x.org/p', 'L'.repeat(15)) + ' t' },
  { id: 'osc-schemes', cols: 30, rows: 8, write: [
    osc8('file:///tmp/a', 'file'), osc8('ssh://h', 'ssh'), osc8('mailto:a@b', 'mail'),
    osc8('http://', 'bad'), osc8('HTTP://X', 'upper'), osc8('https://ok.org', 'fine'), osc8('javascript:x', 'js'),
  ].join('\r\n') },
  { id: 'osc-text-is-a-url', cols: 40, rows: 3, write: 'go ' + osc8('http://a.com', 'http://b.com/x') + ' ok' },
  { id: 'osc-covers-half-a-url', cols: 40, rows: 3, write: 'see http://a.com/' + osc8('http://z.com', 'abc') + '/def more' },
  { id: 'osc-then-url', cols: 40, rows: 3, write: osc8('http://z.com', 'zz') + ' http://a.com/x' },
  // the two share only the link's last cell: the ranges are closed at both ends
  { id: 'url-starts-in-the-last-osc-cell', cols: 40, rows: 3, write: osc8('http://z.com', 'abcdh') + 'ttp://a.com/x z' },
  { id: 'url-ends-in-the-first-osc-cell', cols: 40, rows: 3, write: 'go http://a.com/' + osc8('http://z.com', 'x zz') },
  { id: 'osc-empty-uri-ends', cols: 30, rows: 3, write: 'a\x1b]8;;http://a.com\x1b\\bc\x1b]8;;\x1b\\d http://b.com' },
  { id: 'osc-with-wide-chars', cols: 20, rows: 3, write: osc8('http://a.com', '\u4e2d\u6587link') + ' x' },
  { id: 'url-in-the-alt-cells', cols: 20, rows: 3, write: '\x1b[31mhttp://a.com\x1b[0m/x' },
];

module.exports = { PREFIX, URLS, LINES };
