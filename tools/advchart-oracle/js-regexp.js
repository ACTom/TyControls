'use strict';
// What V8 answers for `new RegExp(source).test(text)` -- the answers
// tyControls.AdvanceChart.JsRegExp must give (the dataset filter's `reg`
// operator, util/conditionalExpression.ts RegExpEvaluator). [spec 242]
//
//   node tools/advchart-oracle/js-regexp.js
//
// writes tests/fixtures/advchart-js-regexp.json (ORACLE_OUT overrides).
//
// Rows: [source, text, answer] -- answer true / false, or 'SyntaxError' when
// the constructor throws (the text is then '' and there is one row for the
// source). Two parts:
//   curated  hand-written patterns for each rule the port follows: Annex B's
//            literals and escapes (`{`, `]`, `}`, `\c`, `\8`, the legacy
//            octals, `\u` and `\x` without their digits, identity escapes),
//            the class ranges with a class escape on a side, \s's Unicode
//            spaces, `.` against the four line ends, the code units of a
//            surrogate pair, back references (forward, to a group that did
//            not take part, inside lookbehind -- matched right to left),
//            RepeatMatcher's capture reset and its empty check, lookarounds
//            that are atomic and keep a positive one's captures, named groups
//            and `\k`, and the SyntaxErrors.
//   fuzz     patterns strung from a seeded generator over those pieces and
//            texts over an alphabet with the same corners; every syntax
//            error once, every legal pattern against eight texts.
// Texts never hold U+0000 (fpjson drops it) nor a lone surrogate. Two
// generations in one process give the same bytes.
const fs = require('fs');
const path = require('path');

const OUT = process.env.ORACLE_OUT
  || path.join(__dirname, '..', '..', 'tests', 'fixtures', 'advchart-js-regexp.json');

function answer(src, text) {
  let re;
  try { re = new RegExp(src); } catch (e) {
    if (!(e instanceof SyntaxError)) throw e;
    return 'SyntaxError';
  }
  return re.test(text);
}

const curatedSpec = [
  // literals and Annex B
  ['abc', ['abc', 'xabcx', 'ab', 'ABC']],
  ['a{', ['a{', 'a', '{']],
  ['a{,2}', ['a{,2}', 'aa']],
  ['a{1,x}', ['a{1,x}', 'a']],
  ['a{2}', ['aa', 'a', 'aaa']],
  ['a{2,}', ['a', 'aa', 'aaaa']],
  ['^a{2,3}$', ['a', 'aa', 'aaa', 'aaaa']],
  ['^a{0}$', ['', 'a']],
  ['^(?:a{0})+$', ['', 'a']],
  [']', [']', 'x']],
  ['}', ['}', 'x']],
  ['a]b}', ['a]b}', 'ab']],
  ['{2}', ['{2}']],
  ['a{2}{3}', ['aaaaaa']],
  ['a**', ['a']],
  ['*a', ['a']],
  ['a{2,1}', ['aa']],
  ['x{3,2}?', ['x']],
  ['a|*', ['a']],
  ['(', ['(']],
  [')', [')']],
  ['(?', ['(?']],
  ['(?x)', ['x']],
  ['[', ['[']],
  ['[a', ['a']],
  ['[]', ['', 'a', '[]']],
  ['[^]', ['', 'a', '\n']],
  ['a[]b', ['ab']],
  ['[b-a]', ['a']],
  ['\\', ['\\']],
  ['a\\', ['a\\']],
  // escapes
  ['\\cA', ['\x01', 'cA', '\\cA']],
  ['\\cj', ['\n', 'cj']],
  ['\\c', ['\\c', 'c']],
  ['\\c1', ['\\c1', '\x11']],
  ['[\\c1]', ['\x11', '1', 'c', '\\']],
  ['[\\c_]', ['\x1f', '_']],
  ['[\\c*]', ['\\', 'c', '*', '\x0a']],
  ['\\c*', ['\\c*', '\\cc', '\\']],
  ['\\0', ['\x00x'.slice(1), 'x']],
  ['^\\00$', ['\x00'.replace('\x00', '\u0001'), '0']],
  ['\\08', ['8', '\x008'.slice(1)]],
  ['\\1', ['\u0001', '1', '\\1']],
  ['\\12', ['\n', '12']],
  ['\\101', ['A', '101']],
  ['\\377', ['\u00ff']],
  ['\\400', [' 0', ' 0', '@']],
  ['\\8', ['8', '\\8']],
  ['\\9a', ['9a']],
  ['(a)\\1', ['aa', 'a']],
  ['(a)\\2', ['a\u0002', 'aa']],
  ['(a)\\10', ['a\b', 'aa0']],
  ['(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)\\10', ['abcdefghijj', 'abcdefghija0']],
  ['\\1(a)', ['a', 'aa']],
  ['\\x41', ['A', 'x41']],
  ['\\x4', ['x4', 'A']],
  ['\\xg1', ['xg1']],
  ['\\u0061', ['a', 'u0061']],
  ['\\u006', ['u006', 'a']],
  ['\\u{61}', ['a', 'u'.repeat(61), 'u'.repeat(60)]],
  ['\\ud83d\\ude00', ['\ud83d\ude00']],
  ['^.$', ['\ud83d\ude00', 'a', '\u00e9']],
  ['^..$', ['\ud83d\ude00']],
  ['^[\\ud83d][\\ude00]$', ['\ud83d\ude00']],
  ['\\e', ['e']],
  ['\\a\\q', ['aq']],
  ['\\-', ['-']],
  ['\\/', ['/']],
  ['\\k', ['k']],
  ['\\k<a>', ['k<a>']],
  ['(?<a>x)\\k<a>', ['xx', 'x']],
  ['(?<a>x)\\k', ['xk']],
  ['(?<a>x)\\k<b>', ['xx']],
  ['\\k<a>(?<a>x)', ['x', 'xx']],
  ['(?<a>x)(?<a>y)', ['xy']],
  ['(?<a>x)|(?<b>y)\\k<a>', ['y', 'x']],
  ['(?<$a_1>z)', ['z']],
  ['(?<1a>z)', ['z']],
  ['(?<>z)', ['z']],
  ['(?<a>a)[\\k]', ['ak']],
  ['[\\k]', ['k']],
  ['\\t\\n\\v\\f\\r', ['\t\n\v\f\r']],
  ['[\\b]', ['\b', 'b']],
  ['\\bfoo\\b', ['a foo b', 'afoo', 'foo']],
  ['\\Bo\\B', ['foo', 'o']],
  ['^\\b$', ['', 'a']],
  ['^\\B$', ['', 'a']],
  // classes
  ['[a-z]', ['m', 'M', '-']],
  ['[\\d-z]', ['5', 'z', '-', 'a']],
  ['[a-\\d]', ['a', '-', '5', 'b']],
  ['[\\s-\\d]', [' ', '-', '3', 'x']],
  ['[--a]', ['-', '0', 'a', 'b']],
  ['[a-]', ['a', '-', 'b']],
  ['[-a]', ['a', '-']],
  ['[a-c-e]', ['b', '-', 'e', 'd']],
  ['[\\-]', ['-']],
  ['[\\w]', ['_', 'a', '-', '\u00e9']],
  ['[\\W]', ['_', '-', '\u00e9']],
  ['[^\\d]', ['1', 'x']],
  ['[\\D\\d]', ['x', '1']],
  ['[\\S]', [' ', 'x', '\u3000']],
  ['[\\8]', ['8']],
  ['[\\1]', ['\u0001', '1']],
  ['[\\0]', ['0']],
  ['[\\x]', ['x']],
  ['[\\u]', ['u']],
  ['[\\]]', [']']],
  ['[]]', [']', '']],
  ['[^]]', [']', 'a]', 'a']],
  ['[\\cA-\\cZ]', ['\x05']],
  ['[.]', ['.', 'a']],
  ['[$^]', ['$', '^']],
  ['[\\B]', ['B', 'b']],
  // \s and .
  ['\\s', [' ', '\t', '\v', '\f', '\u00a0', '\ufeff', '\u1680', '\u2000', '\u200a',
    '\u200b', '\u2028', '\u2029', '\u202f', '\u205f', '\u3000', '\u180e', '\u0085', 'x']],
  ['\\S', ['\u0085', ' ']],
  ['^.$', ['\n', '\r', '\u2028', '\u2029', '\u0085', '\t', '\v']],
  ['a.b', ['a\nb', 'a b']],
  ['^\\d+$', ['123', '\u0661', '12a']],
  ['^\\w+$', ['abc_09', '\u00e9']],
  // anchors
  ['^a$', ['a', 'a\n', '\na', 'ba']],
  ['a$', ['a\n', 'ba']],
  ['^$', ['', '\n']],
  ['$a', ['a', '']],
  ['a^', ['a']],
  ['^*', ['']],
  ['\\b*', ['']],
  ['(?=a)*', ['', 'b']],
  ['(?=a)+b', ['ab', 'b']],
  ['(?<=a)*', ['a']],
  ['(?<=a){2}', ['a']],
  // back references and captures
  ['(a*)*b', ['aaab', 'b', 'aaa']],
  ['(a*)+b', ['b']],
  ['^(a?)*$', ['', 'aaa']],
  ['^(a+|b)*?c$', ['abac', 'c']],
  ['^(?:(a)|b)*\\1$', ['ab', 'aba', 'aa', 'b']],
  ['^(?:(a)|(b))+\\1\\2$', ['ab', 'abb', 'aba', 'abab']],
  ['^(z)((a+)?(b+)?(c))*\\3$', ['zaacbbbcac', 'zaacbbbcaca', 'zaacbbbcacaa']],
  ['^(z)((a+)?(b+)?(c))*\\4$', ['zaacbbbcac', 'zaacbbbcacb']],
  ['^(a)|\\1b$', ['b', 'ab', 'a']],
  ['^(?:\\1(a))*$', ['aa', 'a', 'aaa']],
  ['(?=(a+))a*b\\1', ['baaabac', 'baaabaac']],
  ['(?=(a+))', ['baaabac']],
  ['(.*?)a(?!(a+)b\\2c)\\2(.*)', ['baaabaac']],
  ['^(?!(a))\\1b$', ['b', 'ab']],
  ['^(?:(?=(a))a)*\\1$', ['aaa', 'aa']],
  ['(?<=(\\d+)(\\d+))$', ['1053']],
  ['^(?<=(\\d+)(\\d+))\\1$', ['1']],
  ['(?<=\\$)\\d+(\\.\\d*)?', ['$10.53', '10.53']],
  ['(?<!\\$)\\b\\d+', ['$10', '10']],
  ['(?<=(a)\\1)b', ['aab', 'ab']],
  ['(?<=\\1(a))b', ['aab', 'ab']],
  ['(?<=([abc])+)d', ['abcd', 'd']],
  ['(?<=^\\w+)c', ['abc', ' c']],
  ['(?<=a(?=b)b)c', ['abc', 'ac']],
  ['(?<=a(?<=a)b)c', ['abc']],
  ['(?<=(a|ab))b', ['ab', 'abb']],
  ['(?<!a)', ['a', '']],
  ['^(?:a|ab)(?:c|bcd)(d*)$', ['abcd', 'abcdd']],
  ['^(a|ab)(c|bcd)(d*)$', ['abcd']],
  ['((a)|b)+', ['ab']],
  ['^(?:()|a)*b$', ['aab', 'b']],
  ['^(|a)*b$', ['aab']],
  ['^(?:a?)*?b$', ['ab', 'b', 'aab']],
  ['^(a?)+?b$', ['aab']],
  ['^(?:)*$', ['', 'a']],
  ['^(?:a|)*?$', ['aa']],
  ['^(a\\1?){4}$', ['aaaaaaaaaa', 'aaaaaaaaa', 'aaaaaaaaaaa']],
  ['^(a(?=b)|b)*$', ['abab', 'aab']],
  ['a+?b', ['aaab']],
  ['a??b', ['ab', 'b']],
  ['^a{2,4}?$', ['aaa']],
  ['^(?:a{1,2}){2}$', ['aaa', 'a', 'aaaaa']],
  ['^(?:x*){3,}$', ['', 'x']],
  ['a|b|', ['', 'c']],
  ['|', ['x']],
  ['^(?:a|b)+$', ['abba', 'abc']],
  ['(\\d{3})-\\1', ['123-123', '123-124']],
  ['^\\d{4}-\\d{2}-\\d{2}$', ['2026-10-27', '2026-1-27']],
  ['^[ab]$', ['a', 'b', 'c', 'ab']],
  ['^(?:Mon|Tue)', ['Monday', 'Wed']],
  ['\u00e9t\u00e9', ['\u00e9t\u00e9', 'ete']],
  ['^\u4e2d', ['\u4e2d\u6587', '\u6587']],
  ['null', ['null']],
  ['^1e\\+21$', ['1e+21']],
  ['undefined', ['undefined']],
  ['\\u2028', ['\u2028']],
  // a lookahead is atomic: the first way its body matches is the one kept,
  // so a lazy and a greedy quantifier in it leave different captures
  ['^(?=(a+?))\\1b', ['aab', 'ab', 'b']],
  ['^(?=(a+))\\1b', ['aab', 'ab']],
  ['^(?=(a{1,3}?))\\1b', ['aab', 'aaab']],
  ['^(?=(a*?))\\1b', ['b', 'ab']],
  ['^(?=(a??))\\1b', ['ab', 'b']],
  // RepeatMatcher resets the atom's captures each go: in a lookbehind the
  // group's end is saved first and a back reference inside the group reads
  // the start the reset left undefined
  ['(?<=(?:(a\\1)c){2})b', ['acacb', 'acaacb', 'aacacb', 'acacacb']],
  ['(?<=(?:c(a\\1)){2})b', ['cacab', 'caacab', 'cacaab']],
  ['^(?:(a)|b(?=\\1))+$', ['abab', 'ab', 'ba']],
];

// seeded generator (xorshift32, the port's own seed)
let rs = 2463534242;
function rnd() {
  rs ^= rs << 13; rs >>>= 0;
  rs ^= rs >>> 17;
  rs ^= rs << 5; rs >>>= 0;
  return rs / 4294967296;
}
function pick(a) { return a[Math.floor(rnd() * a.length)]; }

const pieces = ['a', 'b', 'c', '.', '^', '$', '|', '(', ')', '(?:', '(?=', '(?!', '(?<=', '(?<!',
  '(?<n>', '\\k<n>', '[', ']', '[^', '-', '*', '+', '?', '{', '}', '{2}', '{1,3}', '{0,}', '{2,1}',
  ',', '\\', '\\d', '\\w', '\\s', '\\b', '\\B', '\\1', '\\2', '\\0', '\\12', '\\8', '\\x41',
  '\\u0061', '\\cA', '\\c1', '\\n', '\u00e9', '\\D', '\\W', '\\S', '\\-', '\\.', '\\x4', '\\u00e',
  '\\k', '*?', '+?', '??', 'a', 'b', '(a)', '(b|a)', '[a-c]', '[\\d-]', '\\c', 'a*', 'b+'];
const alphabet = ['a', 'b', 'c', 'A', '1', '_', '-', ' ', '\n', '\r', '\u00e9', '\u2028', '\u00a0',
  '\u3000', '.', '(', ')', '{', '}', '\\', 'k', '<', '>', 'n', 'x', 'u', '\ud83d\ude00', '\u0001', '\b'];

function generate() {
  const rows = [];
  const seenErr = new Set();
  const push = (src, texts) => {
    for (const t of texts) {
      if (t.indexOf('\u0000') >= 0) throw new Error('js-regexp: a NUL in a text');
      const a = answer(src, t);
      if (a === 'SyntaxError') {
        if (seenErr.has(src)) continue;
        seenErr.add(src);
        rows.push([src, '', a]);
        continue;
      }
      rows.push([src, t, a]);
    }
  };
  rs = 2463534242;
  for (const [src, texts] of curatedSpec) push(src, texts);
  const curated = rows.length;
  const seenSrc = new Set(curatedSpec.map(c => c[0]));
  let made = 0;
  while (made < 4000) {
    const n = 1 + Math.floor(rnd() * 7);
    let src = '';
    for (let i = 0; i < n; i++) src += pick(pieces);
    const texts = [];
    for (let k = 0; k < 8; k++) {
      const len = Math.floor(rnd() * 9);
      let t = '';
      for (let i = 0; i < len; i++) t += pick(alphabet);
      texts.push(t);
    }
    if (seenSrc.has(src)) continue;
    seenSrc.add(src);
    made++;
    push(src, texts);
  }
  return { curated, rows };
}

const g1 = generate();
const g2 = generate();
const out = {
  source: 'node ' + process.version + ' (V8 ' + process.versions.v8 + ') RegExp',
  curated: g1.curated,
  rows: g1.rows,
};
const text = JSON.stringify(out) + '\n';
if (text !== JSON.stringify({ source: out.source, curated: g2.curated, rows: g2.rows }) + '\n')
  throw new Error('js-regexp: two generations differ');
if (text.indexOf('\\u0000') >= 0) throw new Error('js-regexp: \\u0000 in the output');
JSON.parse(text);
// guards: the rules the curated part is there for hold on this V8
const G = (name, cond) => { if (!cond) throw new Error('js-regexp guard: ' + name); };
G('a lone { is a literal', answer('a{', 'a{') === true);
G('a braced quantifier alone is an error', answer('{2}', '') === 'SyntaxError');
G('\\8 with no groups is 8', answer('\\8', '8') === true);
G('\\12 with no groups is octal LF', answer('\\12', '\n') === true);
G('the empty check stops (a*)* with a capture reset', answer('^(?:(a)|b)*\\1$', 'ab') === true);
G('lookbehind runs right to left', answer('(?<=\\1(a))b', 'aab') === true);
G('. does not cross LS', answer('^.$', '\u2028') === false);
G('\\s is Unicode', answer('\\s', '\u3000') === true);
G('a surrogate pair is two units', answer('^.$', '\ud83d\ude00') === false);
G('\\k with no named group is k', answer('\\k<a>', 'k<a>') === true);
fs.writeFileSync(OUT, text);
const errs = g1.rows.filter(r => r[2] === 'SyntaxError').length;
console.log(g1.rows.length, 'rows,', g1.curated, 'curated,', errs, 'syntax errors ->', OUT);
process.exit(0);
