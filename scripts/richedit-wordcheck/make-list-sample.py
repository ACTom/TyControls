#     python scripts/richedit-wordcheck/make-list-sample.py <out.rtf>
# A hand-made file with lists written the way Word writes them (list table, overrides,
# \ls \ilvl), to see what Word reads: nested numbers, the outer list going on after inner
# items, a start other than 1, a second list that starts again, nested bullets.
import sys
B = chr(92)
def cw(s):
    return s.replace('~', B)

levels_num = ''
for n in range(9):
    levels_num += cw("{~listlevel~levelnfc0~levelnfcn0~leveljc0~leveljcn0~levelfollow0~levelstartat1"
                     "{~leveltext~'02~'0%d.;}{~levelnumbers~'01;}~fi-360~li%d}" % (n, 720 + 360 * n))
levels_blt = ''
for n in range(9):
    levels_blt += cw("{~listlevel~levelnfc23~levelnfcn23~leveljc0~leveljcn0~levelfollow0~levelstartat1"
                     "{~leveltext~'01~u-3913 ?;}{~levelnumbers;}~f1~fi-360~li%d}" % (720 + 360 * n))
head = cw("{~rtf1~ansi~ansicpg936~deff0{~fonttbl{~f0~fnil~fcharset0 Arial;}{~f1~fnil~fcharset2 Symbol;}}\r\n"
          "{~*~listtable{~list~listtemplateid1") + levels_num + cw("{~listname ;}~listid1}"
          "{~list~listtemplateid2") + levels_blt + cw("{~listname ;}~listid2}}\r\n"
          "{~*~listoverridetable"
          "{~listoverride~listid1~listoverridecount1{~lfolevel~listoverridestartat~levelstartat3}~ls1}"
          "{~listoverride~listid1~listoverridecount1{~lfolevel~listoverridestartat~levelstartat1}~ls2}"
          "{~listoverride~listid2~listoverridecount0~ls3}}\r\n"
          "~viewkind4~uc1 \r\n")
def item(text, ls, lvl, marker, font='f0'):
    return cw("~pard~plain~f0{~listtext~%s %s~tab}~ls%d~ilvl%d~fi-360~li%d %s~par\r\n"
              % (font, marker, ls, lvl, 720 + 360 * lvl, text))
body = (item('numbered from three', 1, 0, '3.') + item('numbered next', 1, 0, '4.')
        + item('numbered inner', 1, 1, '1.') + item('numbered inner two', 1, 1, '2.')
        + item('numbered third level', 1, 2, '1.')
        + item('numbered outer again', 1, 0, '5.')
        + cw("~pard~plain~f0 a plain paragraph between~par\r\n")
        + item('second list one', 2, 0, '1.') + item('second list two', 2, 0, '2.')
        + cw("~pard~plain~f0 another plain paragraph~par\r\n")
        + item('bullet level one', 3, 0, cw("~'b7"), 'f1') + item('bullet level two', 3, 1, cw("~'b7"), 'f1')
        + item('bullet level one again', 3, 0, cw("~'b7"), 'f1')
        + cw("~pard~plain~f0 the end~par\r\n}"))
open(sys.argv[1], 'wb').write((head + body).encode('latin1'))
print('ok')
