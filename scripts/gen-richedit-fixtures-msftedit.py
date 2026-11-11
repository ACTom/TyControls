#!/usr/bin/env python3
"""Writes tests/fixtures/rtf/re-*.rtf: RTF as WordPad's engine writes it.

WordPad is a window around the system RichEdit (msftedit.dll, class RICHEDIT50W): what it saves
is what that control streams out. This script gives the control a small RTF source (below), lets
it stream the document back out, and keeps that output -- the control's own way of writing
fonts, code pages, lists, pictures and tables -- with the text the control says the document
holds (re-*.expected.txt). The control lives in a message-only window: nothing is shown, the
clipboard is not touched.

Windows only (it needs msftedit.dll), and the bytes depend on the Windows version and the
system code page: the files in the repository were made on Windows 10 19044 with code page 936.
Do not rerun it to "refresh" them; the tests read the files, not this script.

    python scripts/gen-richedit-fixtures-msftedit.py [--show]
"""
import ctypes
import os
import struct
import sys
import zlib
from ctypes import wintypes as w

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RTF = os.path.join(ROOT, 'tests', 'fixtures', 'rtf')

u32 = ctypes.WinDLL('user32', use_last_error=True)
k32 = ctypes.WinDLL('kernel32', use_last_error=True)
k32.LoadLibraryW.restype = w.HMODULE
if not k32.LoadLibraryW('msftedit.dll'):
    raise SystemExit('msftedit.dll does not load')
u32.CreateWindowExW.restype = w.HWND
u32.CreateWindowExW.argtypes = [w.DWORD, w.LPCWSTR, w.LPCWSTR, w.DWORD] + [ctypes.c_int] * 4 + [
    w.HWND, w.HMENU, w.HINSTANCE, w.LPVOID]
u32.SendMessageW.restype = ctypes.c_ssize_t
u32.SendMessageW.argtypes = [w.HWND, w.UINT, ctypes.c_size_t, ctypes.c_void_p]
u32.DestroyWindow.argtypes = [w.HWND]

WM_USER = 0x400
EM_SETTEXTEX, EM_GETTEXTEX, EM_GETTEXTLENGTHEX = WM_USER + 97, WM_USER + 94, WM_USER + 95
EM_STREAMOUT, EM_EXLIMITTEXT = WM_USER + 74, WM_USER + 53
SF_RTF = 2
ES_MULTILINE = 4
HWND_MESSAGE = w.HWND(-3)

EDITSTREAMCALLBACK = ctypes.WINFUNCTYPE(w.DWORD, ctypes.c_size_t, ctypes.POINTER(ctypes.c_ubyte),
                                        ctypes.c_long, ctypes.POINTER(ctypes.c_long))


class EDITSTREAM(ctypes.Structure):
    _pack_ = 4      # richedit.h declares its structures under #pragma pack(4), on Win64 too
    _fields_ = [('dwCookie', ctypes.c_size_t), ('dwError', w.DWORD),
                ('pfnCallback', EDITSTREAMCALLBACK)]


class GETTEXTEX(ctypes.Structure):
    _pack_ = 4
    _fields_ = [('cb', w.DWORD), ('flags', w.DWORD), ('codepage', w.UINT),
                ('lpDefaultChar', ctypes.c_char_p), ('lpUsedDefChar', ctypes.c_void_p)]


def through_richedit(source):
    """(the RTF the control streams out, the text it holds) for an ASCII RTF source."""
    h = u32.CreateWindowExW(0, 'RICHEDIT50W', '', ES_MULTILINE, 0, 0, 800, 600, HWND_MESSAGE,
                            None, None, None)
    if not h:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        u32.SendMessageW(h, EM_EXLIMITTEXT, 0, ctypes.c_void_p(0x7FFFFFF))
        buf = ctypes.create_string_buffer(source.encode('ascii') + b'\0')
        st = ctypes.create_string_buffer(struct.pack('II', 0, 0))   # ST_DEFAULT, CP_ACP
        u32.SendMessageW(h, EM_SETTEXTEX, ctypes.addressof(st), ctypes.addressof(buf))

        chunks = []

        def take(cookie, data, count, done):
            chunks.append(bytes(data[:count]))
            done[0] = count
            return 0
        es = EDITSTREAM(0, 0, EDITSTREAMCALLBACK(take))
        u32.SendMessageW(h, EM_STREAMOUT, SF_RTF, ctypes.addressof(es))
        if es.dwError:
            raise SystemExit('EM_STREAMOUT failed: %d' % es.dwError)

        # GT_RAWTEXT: objects stay U+FFFC and the table marks stay as they are (without it the
        # control hands out a space for a picture and a tab for a cell end).
        gl = ctypes.create_string_buffer(struct.pack('II', 0, 1200))
        n = u32.SendMessageW(h, EM_GETTEXTLENGTHEX, ctypes.addressof(gl), None)
        out = ctypes.create_string_buffer((n + 1) * 2)
        gt = GETTEXTEX((n + 1) * 2, 4, 1200, None, None)
        got = u32.SendMessageW(h, EM_GETTEXTEX, ctypes.addressof(gt), ctypes.addressof(out))
        text = out.raw[:got * 2].decode('utf-16-le', 'surrogatepass')
        text = text.encode('utf-16-le', 'surrogatepass').decode('utf-16-le')
        return b''.join(chunks), text
    finally:
        u32.DestroyWindow(h)


def u(text):
    """Text as ASCII RTF: every character above 7F as \\uN? (two units for one beyond the BMP)."""
    out = []
    for ch in text:
        if ch in '\\{}':
            out.append('\\' + ch)
        elif ord(ch) < 0x80:
            out.append(ch)
        else:
            units = ch.encode('utf-16-le')
            for i in range(0, len(units), 2):
                n = units[i] | (units[i + 1] << 8)
                out.append('\\u%d?' % (n - 65536 if n > 32767 else n))
    return ''.join(out)


def png(width, height):
    """A small PNG made here: a diagonal gradient with a dark frame. No file, no library."""
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            edge = x in (0, width - 1) or y in (0, height - 1)
            if edge:
                row += bytes((40, 40, 40))
            else:
                row += bytes((255 * x // width, 255 * y // height, 160))
        rows.append(bytes(row))

    def chunk(kind, data):
        body = kind + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xFFFFFFFF)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b''))


def name(text):
    """A font name as WordPad writes it in the font table: the code page's bytes, each as a
    backslash, an apostrophe and two hex digits. (The control does not read the Unicode escape
    there: the name would spill into the text.)"""
    return ''.join("\\'%02x" % b for b in text.encode('gbk'))


FONTS = ('{\\fonttbl{\\f0\\fnil\\fcharset134 ' + name('宋体') + ';}{\\f1\\fnil\\fcharset134 ' + name('黑体')
         + ';}{\\f2\\fnil\\fcharset134 ' + name('楷体') + ';}{\\f3\\fswiss\\fcharset0 Arial;}'
         '{\\f4\\fnil\\fcharset2 Symbol;}}')
HEAD = '{\\rtf1\\ansi\\ansicpg936\\deff0\\deflang1033\\deflangfe2052' + FONTS
COLORS = '{\\colortbl ;\\red255\\green0\\blue0;\\red0\\green112\\blue192;\\red255\\green255\\blue0;}'

SOURCES = {}

SOURCES['re-zh-plain'] = (
    HEAD + '\\pard\\f0\\fs24 '
    + u('富文本控件的第一份样本，全部是中文。') + '\\par '
    + u('第二段里有全角标点：“引号”、《书名号》、——破折号，还有省略号……') + '\\par '
    + u('第三段比较长，用来看折行：窗前的树叶被风吹得沙沙作响，远处传来几声犬吠，屋里的灯还亮着，'
        '桌上摊开一本没有写完的笔记。') + '\\par '
    + '\\par '
    + u('上面是一个空段落，这是最后一段。') + '\\par}')

SOURCES['re-zh-mixed'] = (
    HEAD + '\\pard\\f0\\fs24 '
    + u('宋体的中文，接着是 ') + '\\f3 Arial English text\\f0 ' + u('，再回到宋体。') + '\\par '
    + '\\f1 ' + u('黑体的一段：TyControls 版本 ') + '\\f3 4.0\\f1 ' + u(' 的富文本控件。') + '\\par '
    + '\\f2 ' + u('楷体的一段，里面夹着数字 2026 和符号 &、%、@。') + '\\par '
    + '\\f3 Arial paragraph with a few CJK characters: \\f0 ' + u('中文') + '\\f3  and \\f1 '
    + u('黑体') + '\\f3 .\\par '
    + '\\f0 ' + u('宋体里的生僻一点的字：龘、鱻，和一个表情 ') + u('\U0001F600') + u('。') + '\\par}')

SOURCES['re-zh-list'] = (
    HEAD + '\\pard\\f0\\fs24 ' + u('项目符号列表：') + '\\par '
    '\\pard{\\pntext\\f4\\\'B7\\tab}{\\*\\pn\\pnlvlblt\\pnf4\\pnindent0{\\pntxtb\\\'B7}}\\fi-360\\li720 '
    + u('第一项') + '\\par '
    '{\\pntext\\f4\\\'B7\\tab}' + u('第二项，带一点 English') + '\\par '
    '{\\pntext\\f4\\\'B7\\tab}' + u('第三项') + '\\par '
    '\\pard ' + u('数字编号列表：') + '\\par '
    '\\pard{\\pntext\\f0 1.\\tab}{\\*\\pn\\pnlvlbody\\pnf0\\pnindent0\\pnstart1\\pndec{\\pntxta.}}'
    '\\fi-360\\li720 ' + u('甲') + '\\par '
    '{\\pntext\\f0 2.\\tab}' + u('乙') + '\\par '
    '{\\pntext\\f0 3.\\tab}' + u('丙') + '\\par '
    '\\pard ' + u('列表之后的普通段落。') + '\\par}')

_png = png(48, 32)
SOURCES['re-zh-picture'] = (
    HEAD + '\\pard\\f0\\fs24 ' + u('图片前面的文字。') + '\\par '
    '{\\pict\\pngblip\\picw48\\pich32\\picwgoal720\\pichgoal480 ' + _png.hex() + '}'
    + u('紧跟在图片后面的文字。') + '\\par '
    + u('另一段，图片在行中间：') + '{\\pict\\pngblip\\picw48\\pich32\\picwgoal360\\pichgoal240 '
    + _png.hex() + '}' + u('，然后继续。') + '\\par}')

SOURCES['re-zh-table'] = (
    HEAD + '\\pard\\f0\\fs24 ' + u('表格前的段落。') + '\\par '
    + ''.join(
        '\\trowd\\trgaph108\\cellx2400\\cellx4800\\cellx7200\\pard\\intbl '
        + u(a) + '\\cell ' + u(b) + '\\cell ' + u(c) + '\\cell\\row '
        for a, b, c in (('姓名', '部门', '备注'), ('张三', '研发 R&D', '第一行'),
                        ('李四', '测试', '两个字')))
    + '\\pard ' + u('表格后的段落。') + '\\par}')

SOURCES['re-styles'] = (
    HEAD + COLORS + '\\pard\\f0\\fs24 '
    + u('普通，') + '\\b ' + u('粗体') + '\\b0 ' + u('，') + '\\i ' + u('斜体') + '\\i0 ' + u('，')
    + '\\ul ' + u('下划线') + '\\ulnone ' + u('，') + '\\strike ' + u('删除线') + '\\strike0 '
    + u('，') + '\\b\\i ' + u('粗斜体') + '\\b0\\i0 ' + u('。') + '\\par '
    + 'H\\sub 2\\nosupersub O, E=mc\\super 2\\nosupersub , '
    + '\\cf1 ' + u('红字') + '\\cf0 , \\cf2 ' + u('蓝字') + '\\cf0 , \\highlight3 ' + u('黄底')
    + '\\highlight0 , \\fs36 ' + u('大字') + '\\fs24 , \\fs16 ' + u('小字') + '\\fs24 .\\par '
    + '\\pard\\qc ' + u('居中的一段') + '\\par '
    + '\\pard\\qr ' + u('右对齐的一段') + '\\par '
    + '\\pard\\qj ' + u('两端对齐的一段，要长到能折行才看得出来：' + '文字' * 30) + '\\par '
    + '\\pard\\li720\\ri360\\fi360 ' + u('左缩进 720、右缩进 360、首行缩进 360 的一段。') + '\\par '
    + '\\pard\\fi-360\\li720 ' + u('悬挂缩进的一段。') + '\\par '
    + '\\pard\\sl360\\slmult1 ' + u('一点五倍行距。') + '\\par '
    + '\\pard\\sl480\\slmult1 ' + u('两倍行距。') + '\\par '
    + '\\pard\\sl-400\\slmult0 ' + u('固定 20 磅行距。') + '\\par '
    + '\\pard\\sb240\\sa120 ' + u('段前 12 磅、段后 6 磅。') + '\\par '
    + '\\pard\\tx1440\\tqc\\tx4320\\tqr\\tx8640 ' + u('左') + '\\tab ' + u('中') + '\\tab ' + u('右')
    + '\\par}')


def expected_lines(text):
    """The control's text as paragraphs. CR ends a paragraph; in a table the control marks a
    row start with FFF9 CR, a cell end with 0007 and a row end with FFFB CR -- here a cell end
    ends a paragraph and the row marks are dropped, which is how our model counts them."""
    text = text.replace('￹\r', '').replace('￻\r', '').replace('\x07', '\r')
    return text.split('\r')


def main():
    show = '--show' in sys.argv
    os.makedirs(RTF, exist_ok=True)
    for name, source in SOURCES.items():
        rtf, text = through_richedit(source)
        lines = expected_lines(text)
        exp = ''.join(line + '\n' for line in lines).encode('utf-8')
        with open(os.path.join(RTF, name + '.rtf'), 'wb') as f:
            f.write(rtf)
        with open(os.path.join(RTF, name + '.expected.txt'), 'wb') as f:
            f.write(exp)
        print('%-16s %7d bytes, %d paragraphs' % (name, len(rtf), len(lines)))
        if show:
            print(rtf[:1500].decode('latin-1'))
            print(ascii(text))


if __name__ == '__main__':
    main()
