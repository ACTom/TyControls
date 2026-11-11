#!/usr/bin/env python3
"""Writes the hand-made TTyRichEdit samples: tests/fixtures/rtf/hand-*.rtf (with the text each
one must read as, hand-*.expected.txt, UTF-8, one paragraph per LF-ended line) and
tests/fixtures/txt/*.txt.

The other samples in the same folders are NOT made here: re-*.rtf come out of WordPad's engine
(gen-richedit-fixtures-msftedit.py), wp-*.rtf and word-*.rtf were saved by those programs
(tests/fixtures/rtf/README.md says how). Every byte these files hold is spelled out below, so a
rerun gives the same files; the tests read the files, not this script.

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

# ---------------------------------------------------------------- hand-word-*.rtf
# RTF the way Word writes it, by hand: the long header (\stshf..., \panose and \falt in the
# font table, \defchp, a style sheet, \rsidtbl, \info), \pard\plain with the full property
# list on every paragraph, one group per run with \rtlch\fcs1 ... \ltrch\fcs0, and the three
# font slots -- the run's own class takes \fN, the other two \afN:
#     Latin text        \hich\af37\dbch\af13\loch\f37 text
#     East Asian text   \loch\af37\hich\af37\dbch\f13 \'xx\'xx
#     high ANSI text    \loch\af37\dbch\af13\hich\f37 \'xx
# The header says \uc2, so a \uN is followed by the character's two GBK bytes. These files are
# NOT saved by Word; the ones Word saved are word-*.rtf (README.md).


def gbk(text):
    return hexed(text, 'gbk')


W_FONTS = (
    '{\\fonttbl{\\f0\\fbidi \\froman\\fcharset0\\fprq2{\\*\\panose 02020603050405020304}Times New Roman;}'
    '{\\f13\\fbidi \\fnil\\fcharset134\\fprq2{\\*\\panose 02010600030101010101}' + gbk('宋体')
    + '{\\*\\falt SimSun};}\r\n'
    '{\\f34\\fbidi \\froman\\fcharset0\\fprq2{\\*\\panose 02040503050406030204}Cambria Math;}'
    '{\\f37\\fbidi \\fswiss\\fcharset0\\fprq2{\\*\\panose 020f0502020204030204}Calibri;}'
    '{\\f38\\fbidi \\fnil\\fcharset134\\fprq2{\\*\\panose 02010600030101010101}@' + gbk('宋体') + ';}}')
W_PAPF = ('\\li0\\ri0\\nowidctlpar\\wrapdefault\\aspalpha\\aspnum\\faauto\\adjustright\\rin0\\lin0\\itap0 ')
W_CHPF = ('\\rtlch\\fcs1 \\af0\\afs24\\alang1025 \\ltrch\\fcs0 \\fs21\\lang1033\\langfe2052\\kerning2'
          '\\loch\\af37\\hich\\af37\\dbch\\af13\\cgrid\\langnp1033\\langfenp2052 ')
W_STYLES = (
    '{\\stylesheet{\\qj ' + W_PAPF + '\\rtlch\\fcs1 \\af0\\afs24\\alang1025 \\ltrch\\fcs0 '
    '\\fs21\\lang1033\\langfe2052\\kerning2\\loch\\f37\\hich\\af37\\dbch\\af13\\cgrid\\langnp1033\\langfenp2052 '
    '\\snext0 \\sqformat \\spriority0 Normal;}\r\n'
    '{\\s1\\qj \\li0\\ri0\\sb340\\sa330\\sl578\\slmult1\\keep\\keepn\\nowidctlpar\\wrapdefault\\aspalpha\\aspnum'
    '\\faauto\\outlinelevel0\\adjustright\\rin0\\lin0\\itap0 \\rtlch\\fcs1 \\ab\\af0\\afs44\\alang1025 \\ltrch\\fcs0 '
    '\\b\\fs44\\lang1033\\langfe2052\\kerning44\\loch\\f37\\hich\\af37\\dbch\\af13\\cgrid\\langnp1033\\langfenp2052 '
    '\\sbasedon0 \\snext0 \\slink19 \\sqformat \\spriority9 heading 1;}'
    '{\\*\\cs10 \\additive \\ssemihidden \\sunhideused \\spriority1 Default Paragraph Font;}\r\n'
    '{\\*\\cs15 \\additive \\rtlch\\fcs1 \\af0 \\ltrch\\fcs0 \\ul\\cf2 \\sbasedon10 \\sunhideused Hyperlink;}'
    '{\\*\\cs16 \\additive \\rtlch\\fcs1 \\af0\\afs21 \\ltrch\\fcs0 \\fs21 \\sbasedon10 \\ssemihidden '
    '\\sunhideused annotation reference;}'
    '{\\*\\cs17 \\additive \\rtlch\\fcs1 \\af0 \\ltrch\\fcs0 \\super \\sbasedon10 \\ssemihidden \\sunhideused '
    'footnote reference;}}')


def w_head(extra=''):
    return (
        '{\\rtf1\\adeflang1025\\ansi\\ansicpg936\\uc2\\adeff0\\deff0\\stshfdbch13\\stshfloch37\\stshfhich37'
        '\\stshfbi0\\deflang1033\\deflangfe2052' + W_FONTS
        + '{\\colortbl;\\red0\\green0\\blue0;\\red0\\green0\\blue255;\\red255\\green0\\blue0;}\r\n'
        '{\\*\\defchp \\fs21\\kerning2\\loch\\af37\\hich\\af37\\dbch\\af13 }'
        '{\\*\\defpap \\ql \\li0\\ri0\\widctlpar\\wrapdefault\\aspalpha\\aspnum\\faauto\\adjustright\\rin0\\lin0\\itap0 }'
        '\\noqfpromote ' + W_STYLES + extra
        + '{\\*\\rsidtbl \\rsid2103427\\rsid9764852}{\\*\\generator hand-written for TyControls;}\r\n'
        '{\\info{\\author TyControls}{\\operator TyControls}{\\creatim\\yr2026\\mo11\\dy11\\hr10\\min0}'
        '{\\version1}{\\edmins0}{\\nofpages1}{\\nofwords0}{\\nofchars0}{\\vern49167}}'
        '\\paperw11906\\paperh16838\\margl1800\\margr1800\\margt1440\\margb1440\\gutter0\\ltrsect \r\n'
        '\\deftab420\\ftnbj\\aenddoc\\formshade\\horzdoc\\dghspace180\\dgvspace156\\dghorigin1800\\dgvorigin1440'
        '\\dghshow0\\dgvshow2\\jcompress\\viewkind1\\viewscale100\\rsidroot2103427 \\fet0'
        '{\\*\\wgrffmtfilter 2450}\\ilfomacatclnup0\\ltrpar \\sectd \\ltrsect\\linex0\\headery851\\footery992'
        '\\colsx425\\endnhere\\sectlinegrid312\\sectspecifyl\\sectrsid2103427\\sftnbj ')


# What Word puts after the last paragraph: blocks no reader of ours knows.
W_TAIL = ('{\\*\\themedata 504b030414000600080000002100}\r\n'
          '{\\*\\colorschememapping 3c3f786d6c2076657273696f6e3d22312e30223f3e}\r\n'
          '{\\*\\latentstyles\\lsdstimax371\\lsdlockeddef0\\lsdsemihiddendef0\\lsdunhideuseddef0\\lsdqformatdef0'
          '\\lsdprioritydef99{\\lsdlockedexcept \\lsdqformat1 \\lsdpriority0 \\lsdlocked0 Normal;'
          '\\lsdqformat1 \\lsdpriority9 \\lsdlocked0 heading 1;}}{\\*\\datastore 0105000002000000}}')
W_PARD = '\\pard\\plain \\ltrpar\\qj ' + W_PAPF + W_CHPF
W_RUN = '{\\rtlch\\fcs1 \\af0 \\ltrch\\fcs0 \\insrsid2103427 '
W_PAR = W_RUN + '\\par }'


def w_latin(text, props=''):
    return (W_RUN[:-1] + props + ' ' if props else W_RUN) + '\\hich\\af37\\dbch\\af13\\loch\\f37 ' + text + '}'


def w_cjk(text, props=''):
    return (W_RUN[:-1] + props + ' ' if props else W_RUN) + '\\loch\\af37\\hich\\af37\\dbch\\f13 ' + gbk(text) + '}'


def w_high(text):
    return W_RUN + '\\loch\\af37\\dbch\\af13\\hich\\f37 ' + hexed(text, 'cp1252') + '}'


# hand-word-zh.rtf: the three font slots, \uc2 with its two fallback bytes, and one character
# outside the code page under a local \uc1.
wzh_paras = [
    'TyControls 的富文本控件 4.0',
    'café 和 naïve 里的重音字母',
    '中文也可以这样写',
    '表情 \U0001F600 不在代码页里',
    '最后一段，后面跟着 Word 的收尾块。',
]
wzh = (
    w_head()
    + W_PARD + w_latin('TyControls ') + w_cjk('的富文本控件') + w_latin(' 4.0') + '\r\n' + W_PAR
    + W_PARD + w_latin('caf') + w_high('é') + w_latin(' ') + w_cjk('和') + w_latin(' na')
    + w_high('ï') + w_latin('ve ') + w_cjk('里的重音字母') + W_PAR + '\r\n'
    + W_PARD + W_RUN + '\\loch\\af37\\hich\\af37\\dbch\\f13 '
    + ''.join("\\u%d%s" % (u16(c)[0], hexed(c, 'gbk')) for c in '中文也可以这样写') + '}' + W_PAR
    + W_PARD + w_cjk('表情') + w_latin(' ') + W_RUN + '\\hich\\af37\\dbch\\af13\\loch\\f37 \\uc1\\u%d?\\u%d?}' % tuple(u16('\U0001F600'))
    + w_latin(' ') + w_cjk('不在代码页里') + W_PAR + '\r\n'
    + W_PARD + w_cjk('最后一段，后面跟着') + w_latin(' Word ') + w_cjk('的收尾块。') + W_PAR
    + W_TAIL)
put(RTF, 'hand-word-zh.rtf', wzh.encode('ascii'))
expected('hand-word-zh.expected.txt', wzh_paras)

# hand-word-unknown.rtf: one each of what phase 1 does not understand and must keep -- a style
# (\s1 and the style sheet), a field, a tracked insertion and deletion, a comment, a footnote,
# a formula, a bookmark. hand-word-unknown.visible.txt is the text of the paragraphs with every
# object character (U+FFFC) taken out: how many objects the blocks become is the reader's
# business, the text around them is not.
W_REVTBL = '{\\*\\revtbl {Unknown;}{TyControls;}}'
W_FIELD = (
    '{\\field{\\*\\fldinst ' + W_RUN + '\\hich\\af37\\dbch\\af13\\loch\\f37  HYPERLINK "https://example.com/" }}'
    '{\\fldrslt ' + w_cjk('链接', '\\cs15\\ul\\cf2') + '}}')
W_COMMENT = (
    '{\\*\\atrfstart 1}' + w_cjk('这几个字') + '{\\*\\atrfend 1}{\\*\\atnid TY}{\\*\\atnauthor TyControls}\\chatn '
    '{\\*\\annotation{\\*\\atnref 1}{\\*\\atndate \\yr2026\\mo11\\dy11\\hr10\\min0}\\pard\\plain \\ltrpar\\ql '
    + W_PAPF + W_CHPF + '{\\rtlch\\fcs1 \\af0\\afs21 \\ltrch\\fcs0 \\cs16\\fs21\\insrsid2103427 \\chatn }'
    + w_cjk('批注的内容') + '}')
W_FOOTNOTE = (
    '{\\rtlch\\fcs1 \\af0 \\ltrch\\fcs0 \\cs17\\super\\insrsid2103427 \\chftn {\\footnote \\ltrpar \\pard\\plain '
    '\\ltrpar\\ql ' + W_PAPF + W_CHPF + '{\\rtlch\\fcs1 \\af0 \\ltrch\\fcs0 \\cs17\\super\\insrsid2103427 \\chftn }'
    + w_cjk('脚注的内容') + '}}')
W_MATH = (
    '{\\mmath {\\*\\moMath {\\mr\\mscr0\\msty2 \\rtlch\\fcs1 \\af34 \\ltrch\\fcs0 \\i\\f34\\insrsid2103427 E=m}'
    '{\\msSup{\\msSupPr{\\mctrlPr\\rtlch\\fcs1 \\af34 \\ltrch\\fcs0 \\i\\f34 }}{\\me{\\mr\\mscr0\\msty2 '
    '\\rtlch\\fcs1 \\af34 \\ltrch\\fcs0 \\i\\f34\\insrsid2103427 c}}{\\msup{\\mr\\mscr0\\msty2 \\rtlch\\fcs1 '
    '\\af34 \\ltrch\\fcs0 \\i\\f34\\insrsid2103427 2}}}}}')
wun_visible = [
    '不认识的内容',
    '这里有一个。',
    '修订：新加的字删掉的字',
    '批注在这几个字上。',
    '脚注在这里。',
    '公式：。',
    '书签里的字',
]
wun = (
    w_head(W_REVTBL)
    + '\\pard\\plain \\ltrpar\\s1\\qj \\li0\\ri0\\sb340\\sa330\\sl578\\slmult1\\keep\\keepn\\nowidctlpar\\wrapdefault'
    '\\aspalpha\\aspnum\\faauto\\outlinelevel0\\adjustright\\rin0\\lin0\\itap0 \\rtlch\\fcs1 \\ab\\af0\\afs44\\alang1025 '
    '\\ltrch\\fcs0 \\b\\fs44\\lang1033\\langfe2052\\kerning44\\loch\\af37\\hich\\af37\\dbch\\af13\\cgrid\\langnp1033'
    '\\langfenp2052 ' + w_cjk('不认识的内容') + W_PAR + '\r\n'
    + W_PARD + w_cjk('这里有一个') + W_FIELD + w_cjk('。') + W_PAR + '\r\n'
    + W_PARD + w_cjk('修订：')
    + w_cjk('新加的字', '\\revised\\revauth1\\revdttm1184567890')
    + w_cjk('删掉的字', '\\deleted\\revauthdel1\\revdttmdel1184567890') + W_PAR + '\r\n'
    + W_PARD + w_cjk('批注在') + W_COMMENT + w_cjk('上。') + W_PAR + '\r\n'
    + W_PARD + w_cjk('脚注在这里') + W_FOOTNOTE + w_cjk('。') + W_PAR + '\r\n'
    + W_PARD + w_cjk('公式：') + W_MATH + w_cjk('。') + W_PAR + '\r\n'
    + W_PARD + '{\\*\\bkmkstart mark1}' + w_cjk('书签里的字') + '{\\*\\bkmkend mark1}' + W_PAR
    + W_TAIL)
put(RTF, 'hand-word-unknown.rtf', wun.encode('ascii'))
put(RTF, 'hand-word-unknown.visible.txt', ''.join(p + '\n' for p in wun_visible).encode('utf-8'))

# hand-word-table-merged.rtf: a 3 x 3 table. Row 1: the first cell spans two columns (\clmgf,
# then \clmrg on the cell it swallowed, which still has its own empty \cell). Rows 2 and 3:
# the first column is merged down (\clvmgf, \clvmrg). The last cell holds a nested 1 x 2 table
# (\itap2, \nestcell, \nesttableprops ... \nestrow) and then its own empty last paragraph.
W_TROW = ('\\ltrrow\\ts11\\trgaph108\\trleft-108\\trbrdrt\\brdrs\\brdrw10 \\trbrdrl\\brdrs\\brdrw10 \\trbrdrb'
          '\\brdrs\\brdrw10 \\trbrdrr\\brdrs\\brdrw10 \\trbrdrh\\brdrs\\brdrw10 \\trbrdrv\\brdrs\\brdrw10 \r\n'
          '\\trftsWidth1\\trftsWidthB3\\trautofit1\\trpaddl108\\trpaddr108\\trpaddfl3\\trpaddfr3\\tblind0\\tblindtype3 ')
W_CELLB = ('\\clbrdrt\\brdrs\\brdrw10 \\clbrdrl\\brdrs\\brdrw10 \\clbrdrb\\brdrs\\brdrw10 \\clbrdrr\\brdrs\\brdrw10 '
           '\\cltxlrtb\\clftsWidth3\\clwWidth2840\\clshdrawnil ')


def w_rowdef(index, merges, last=False, edges=(2732, 5572, 8412)):
    return ('\\trowd \\irow%d\\irowband%d' % (index, index) + ('\\lastrow ' if last else '') + W_TROW
            + ''.join(m + '\\clvertalt' + W_CELLB + '\\cellx%d' % x for m, x in zip(merges, edges)))


W_TPAPF = '\\li0\\ri0\\nowidctlpar\\intbl\\wrapdefault\\aspalpha\\aspnum\\faauto\\adjustright\\rin0\\lin0 '


def w_cell(run):
    """One cell holding one run: Word closes it with \\cell inside the run's group."""
    return run[:-1] + '\\cell }' if run else W_RUN + '\\cell }'


def w_row(index, merges, cells, last=False):
    rowdef = w_rowdef(index, merges, last)
    return (rowdef + '\\pard\\plain \\ltrpar\\qj ' + W_TPAPF + W_CHPF + ''.join(cells)
            + '\\pard\\plain \\ltrpar\\ql \\li0\\ri0\\widctlpar\\intbl\\wrapdefault\\aspalpha\\aspnum\\faauto'
            '\\adjustright\\rin0\\lin0 ' + W_CHPF + W_RUN + rowdef + '\\row }\r\n')


W_NESTED = (
    '\\pard\\plain \\ltrpar\\qj \\li0\\ri0\\nowidctlpar\\intbl\\wrapdefault\\aspalpha\\aspnum\\faauto\\adjustright'
    '\\rin0\\lin0\\itap2 ' + W_CHPF
    + w_cjk('内一')[:-1] + '\\nestcell }' + w_cjk('内二')[:-1] + '\\nestcell }'
    + '\\pard\\plain \\ltrpar\\ql \\li0\\ri0\\widctlpar\\intbl\\wrapdefault\\aspalpha\\aspnum\\faauto\\adjustright'
    '\\rin0\\lin0\\itap2 ' + W_CHPF + W_RUN
    + '{\\*\\nesttableprops\\trowd \\irow0\\irowband0\\lastrow ' + W_TROW
    + '\\clvertalt' + W_CELLB + '\\cellx1300\\clvertalt' + W_CELLB + '\\cellx2600\\nestrow}'
    '{\\nonesttables\\par }}'
    + '\\pard\\plain \\ltrpar\\qj ' + W_TPAPF + W_CHPF + W_RUN + '\\cell }')
wtb_paras = ['表格前', '跨两列', '', 'C', '跨两行', 'E', 'F', '', 'G', '内一', '内二', '', '表格后']
wtb = (
    w_head()
    + W_PARD + w_cjk('表格前') + W_PAR + '\r\n'
    + w_row(0, ('\\clmgf', '\\clmrg', ''), [w_cell(w_cjk('跨两列')), w_cell(''), w_cell(w_latin('C'))])
    + w_row(1, ('\\clvmgf', '', ''), [w_cell(w_cjk('跨两行')), w_cell(w_latin('E')), w_cell(w_latin('F'))])
    + w_rowdef(2, ('\\clvmrg', '', ''), True) + '\\pard\\plain \\ltrpar\\qj ' + W_TPAPF + W_CHPF
    + w_cell('') + w_cell(w_latin('G')) + W_NESTED
    + '\\pard\\plain \\ltrpar\\ql \\li0\\ri0\\widctlpar\\intbl\\wrapdefault\\aspalpha\\aspnum\\faauto\\adjustright'
    '\\rin0\\lin0 ' + W_CHPF + W_RUN + w_rowdef(2, ('\\clvmrg', '', ''), True) + '\\row }\r\n'
    + W_PARD + w_cjk('表格后') + W_PAR
    + W_TAIL)
put(RTF, 'hand-word-table-merged.rtf', wtb.encode('ascii'))
expected('hand-word-table-merged.expected.txt', wtb_paras)

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
