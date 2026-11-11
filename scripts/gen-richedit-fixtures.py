#!/usr/bin/env python3
"""Writes the hand-made TTyRichEdit samples: tests/fixtures/rtf/hand-*.rtf (with the text each
one must read as, hand-*.expected.txt, UTF-8, one paragraph per LF-ended line) and
tests/fixtures/txt/*.txt.

The WordPad and Word samples in the same folders are NOT made here: they were saved by those
programs (tests/fixtures/rtf/README.md says how). Every byte these files hold is spelled out
below, so a rerun gives the same files; the tests read the files, not this script.

    python scripts/gen-richedit-fixtures.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RTF = os.path.join(ROOT, 'tests', 'fixtures', 'rtf')
TXT = os.path.join(ROOT, 'tests', 'fixtures', 'txt')


def put(folder, name, data):
    # The bytes are complete before the file is opened: open(..., 'wb') truncates first.
    assert isinstance(data, bytes)
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, name), 'wb') as f:
        f.write(data)
    print('%-28s %6d bytes' % (name, len(data)))


def hexed(text, codec):
    """RTF as WordPad writes a double-byte font's text: ASCII stays, the rest is \\'xx per byte."""
    out = []
    for ch in text:
        if ord(ch) < 0x80:
            assert ch not in '\\{}'
            out.append(ch)
        else:
            out.append(''.join("\\'%02x" % b for b in ch.encode(codec)))
    return ''.join(out)


def u16(ch):
    """One character as the RTF \\uN numbers of its UTF-16 units (signed 16 bit)."""
    units = ch.encode('utf-16-le')
    nums = []
    for i in range(0, len(units), 2):
        n = units[i] | (units[i + 1] << 8)
        nums.append(n - 65536 if n > 32767 else n)
    return nums


def expected(name, paragraphs):
    put(RTF, name, ''.join(p + '\n' for p in paragraphs).encode('utf-8'))


# ---------------------------------------------------------------- hand-big5.rtf
# Traditional Chinese, \ansicpg950. f0 says \fcharset136; f2 gives no charset, so its text can
# only be decoded through \ansicpg950. Two of the characters end in a byte that is an RTF
# special in ASCII: 許 = B3 5C (backslash) and 功 = A5 5C.
big5_paras = [
    '這是一份繁體中文的範例文件。',
    '許多功能都需要測試，包括標點符號「」與數字 2026。',
    '混排 TyControls 與 RichEdit 兩個英文單字。',
    '沒有字元集的字型也要讀對：臺灣、香港。',
]
big5 = (
    '{\\rtf1\\ansi\\ansicpg950\\deff0\\nouicompat\\deflang1033\\deflangfe1028'
    '{\\fonttbl{\\f0\\fnil\\fcharset136 ' + hexed('新細明體', 'big5') + ';}'
    '{\\f1\\fswiss\\fcharset0 Arial;}'
    '{\\f2\\fnil ' + hexed('細明體', 'big5') + ';}}\r\n'
    '{\\*\\generator hand-written for TyControls;}\\viewkind4\\uc1 \r\n'
    '\\pard\\sa200\\sl276\\slmult1\\f0\\fs24\\lang1028 ' + hexed(big5_paras[0], 'big5') + '\\par\r\n'
    + hexed(big5_paras[1], 'big5') + '\\par\r\n'
    + hexed('混排 ', 'big5') + '\\f1 TyControls\\f0  ' + hexed('與', 'big5') + ' \\f1 RichEdit\\f0  '
    + hexed('兩個英文單字。', 'big5') + '\\par\r\n'
    '\\f2 ' + hexed(big5_paras[3], 'big5') + '\\par\r\n'
    '}\r\n\x00')
put(RTF, 'hand-big5.rtf', big5.encode('ascii'))
expected('hand-big5.expected.txt', big5_paras)

# ---------------------------------------------------------------- hand-sjis.rtf
# Japanese, \ansicpg932, \fcharset128. ソ = 83 5C and 表 = 95 5C end in a backslash byte; the
# half-width katakana ｱｲｳ are single bytes B1 B2 B3 and must not be taken for lead bytes.
sjis_paras = [
    'これは日本語のサンプル文書です。',
    'ソフトウェアの表示を確認します。',
    '半角カタカナ ｱｲｳ と全角 ＡＢＣ と ASCII abc。',
]
sjis = (
    '{\\rtf1\\ansi\\ansicpg932\\deff0\\nouicompat\\deflang1033\\deflangfe1041'
    '{\\fonttbl{\\f0\\fnil\\fcharset128 ' + hexed('ＭＳ 明朝', 'cp932') + ';}'
    '{\\f1\\fswiss\\fcharset0 Arial;}}\r\n'
    '{\\*\\generator hand-written for TyControls;}\\viewkind4\\uc1 \r\n'
    '\\pard\\sa200\\sl276\\slmult1\\f0\\fs24\\lang1041 ' + hexed(sjis_paras[0], 'cp932') + '\\par\r\n'
    + hexed(sjis_paras[1], 'cp932') + '\\par\r\n'
    + hexed('半角カタカナ ｱｲｳ と全角 ＡＢＣ と ', 'cp932') + '\\f1 ASCII abc\\f0 ' + hexed('。', 'cp932')
    + '\\par\r\n'
    '}\r\n\x00')
put(RTF, 'hand-sjis.rtf', sjis.encode('ascii'))
expected('hand-sjis.expected.txt', sjis_paras)

# ---------------------------------------------------------------- hand-uc.rtf
# \uN and \ucN. 中 = U+4E2D = 20013; ， = U+FF0C = 65292, written -244; the fallback of 中 in
# GBK is d6 d0 (two bytes, so \uc2 skips both; each \'xx counts as one).
ZHONG, WEN, COMMA = u16('中')[0], u16('文')[0], u16('，')[0]
assert (ZHONG, COMMA) == (20013, -244)
hi, lo = u16('\U0001F600')
uc_paras = [
    '，a',            # \uc0: nothing is skipped, the a stays
    '中b',            # \uc2: both fallback bytes are skipped
    '中c',            # \uc1: the ? is skipped
    '中文',           # \uc2 inside a group ends with the group; outside it is 1 again
    '€d',             # the fallback is a \'xx: it counts as one
    '\U0001F600e',    # a surrogate pair is one character
    'plain ASCII',
]
uc = (
    '{\\rtf1\\ansi\\ansicpg936\\deff0\\nouicompat\\deflang1033\\deflangfe2052'
    '{\\fonttbl{\\f0\\fnil\\fcharset134 ' + hexed('宋体', 'gbk') + ';}'
    '{\\f1\\fswiss\\fcharset0 Arial;}}\r\n'
    '{\\*\\generator hand-written for TyControls;}\\viewkind4\\uc1 \r\n'
    '\\pard\\f0\\fs24\\lang2052 '
    '{\\uc0\\u%d a}\\par\r\n' % COMMA +
    '{\\uc2\\u%d\\\'d6\\\'d0b}\\par\r\n' % ZHONG +
    '\\u%d?c\\par\r\n' % ZHONG +
    '{\\uc2\\u%d\\\'d6\\\'d0}\\u%d?\\par\r\n' % (ZHONG, WEN) +
    '\\u8364\\\'80d\\par\r\n'
    '\\u%d?\\u%d?e\\par\r\n' % (hi, lo) +
    '\\f1 plain ASCII\\par\r\n'
    '}\r\n\x00')
put(RTF, 'hand-uc.rtf', uc.encode('ascii'))
expected('hand-uc.expected.txt', uc_paras)

# ---------------------------------------------------------------- hand-split-dbcs.rtf
# The two bytes of 中 (d6 d0 in GBK) kept apart. Paragraphs 1-3: both halves are in the
# double-byte font f0, so they join although a group end, a control word or a group start
# stands between them. (The system RichEdit does not manage these three: it pairs the d6 with
# whatever byte follows, a brace included. We read them; nothing writes them on purpose.)
# Paragraph 4: the second half is in f1 (\fcharset0), so they must NOT join: the lone lead
# byte is a question mark and the d0 read in f1 is U+00D0 -- which is what RichEdit gives.
split_paras = ['x中y', 'x中y', 'x中y', 'x?Ðy']
split = (
    '{\\rtf1\\ansi\\ansicpg936\\deff0\\nouicompat\\deflang1033\\deflangfe2052'
    '{\\fonttbl{\\f0\\fnil\\fcharset134 ' + hexed('宋体', 'gbk') + ';}'
    '{\\f1\\fswiss\\fcharset0 Arial;}}\r\n'
    '{\\*\\generator hand-written for TyControls;}\\viewkind4\\uc1 \r\n'
    '\\pard\\f0\\fs24\\lang2052 '
    "x{\\b\\'d6}\\'d0y\\par\r\n"
    "x\\'d6\\b \\'d0\\b0 y\\par\r\n"
    "x\\'d6{\\i\\'d0}y\\par\r\n"
    "x\\'d6\\f1\\'d0\\f0 y\\par\r\n"
    '}\r\n\x00')
put(RTF, 'hand-split-dbcs.rtf', split.encode('ascii'))
expected('hand-split-dbcs.expected.txt', split_paras)

# ---------------------------------------------------------------- txt
lines = [
    'TyControls 富文本控件的文本样本。',
    '第二行：中英混排 mixed text，全角标点“”，和一个表情 \U0001F600。',
    '',
    '第四行前面是一个空行。',
    'The last line is plain ASCII.',
]
crlf = '\r\n'.join(lines) + '\r\n'
lf = '\n'.join(lines) + '\n'

put(TXT, 'utf8-bom.txt', b'\xef\xbb\xbf' + crlf.encode('utf-8'))
put(TXT, 'utf8-nobom.txt', lf.encode('utf-8'))
put(TXT, 'utf16le.txt', b'\xff\xfe' + crlf.encode('utf-16-le'))
put(TXT, 'utf16be.txt', b'\xfe\xff' + crlf.encode('utf-16-be'))

# GBK has no emoji: the second line goes without it. The bytes must not happen to be valid UTF-8.
gbk_lines = list(lines)
gbk_lines[1] = '第二行：中英混排 mixed text，全角标点“”。'
gbk = ('\r\n'.join(gbk_lines) + '\r\n').encode('gbk')
try:
    gbk.decode('utf-8')
    raise SystemExit('gbk.txt would pass for UTF-8')
except UnicodeDecodeError:
    pass
put(TXT, 'gbk.txt', gbk)

# Mixed line ends, UTF-8 BOM, no line end after the last line. LF is the majority (5 against
# 2), and it is not what Windows would pick by default.
mixed = ('第一行\n' 'second line\r\n' '第三行\n' '第四行\n' 'fifth line\r\n' '第六行\n' '第七行\n'
         '最后一行，后面没有换行')
assert mixed.count('\r\n') == 2 and mixed.count('\n') - 2 == 5
put(TXT, 'mixed-eol.txt', b'\xef\xbb\xbf' + mixed.encode('utf-8'))

# Bytes that are not text in the file's encoding still have to come back as they were.
# gbk-badbytes: a lone FF (never valid in GBK), and a lead byte 81 with the line end after it.
put(TXT, 'gbk-badbytes.txt',
    '第一行'.encode('gbk') + b'\xff' + '还有字'.encode('gbk') + b'\r\n'
    + '第二行'.encode('gbk') + b'\x81\r\n' + '第三行'.encode('gbk') + b'\r\n')
# utf8-badbytes (read with the encoding forced to UTF-8): an overlong C0 AF, a lone
# continuation byte 80, and a three-byte sequence cut short at the end of the file.
put(TXT, 'utf8-badbytes.txt',
    '第一行'.encode('utf-8') + b'\xc0\xaf' + 'ok\n'.encode('utf-8')
    + b'\x80' + '第二行\n'.encode('utf-8') + '第三'.encode('utf-8') + b'\xe8\xa1')
