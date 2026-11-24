# Prints the text and line records of a metafile Word made of a page (Range.EnhMetaFileBits):
# where each piece of text sits (y is the baseline: TA_BASELINE) and where the table lines are.
# Units: 100 = 12 pt with the measuring scripts of this folder.
#     python scripts/richedit-wordcheck/emf-positions.py <page.emf>
import struct, sys, collections
b = open(sys.argv[1], 'rb').read()
pos = 0
hist = collections.Counter()
align = 0
font_h = None
items = []
win_org = (0, 0); win_ext = None; vp_ext = None
while pos + 8 <= len(b):
    t, sz = struct.unpack_from('<II', b, pos)
    if sz < 8: break
    hist[t] += 1
    rec = b[pos:pos + sz]
    if t == 1:   # header: bounds (device units), frame (0.01 mm)
        bounds = struct.unpack_from('<4i', rec, 8); frame = struct.unpack_from('<4i', rec, 24)
        print('header bounds', bounds, 'frame(0.01mm)', frame)
    elif t == 9: win_ext = struct.unpack_from('<2i', rec, 8)
    elif t == 11: vp_ext = struct.unpack_from('<2i', rec, 8)
    elif t == 10: win_org = struct.unpack_from('<2i', rec, 8)
    elif t == 22: align = struct.unpack_from('<I', rec, 8)[0]
    elif t == 82:  # EXTCREATEFONTINDIRECTW: lfHeight
        font_h = struct.unpack_from('<i', rec, 12)[0]
    elif t == 84:  # EXTTEXTOUTW
        bx = struct.unpack_from('<4i', rec, 8)
        rx, ry, n, off = struct.unpack_from('<iiII', rec, 36)
        s = rec[off:off + 2 * n].decode('utf-16-le', 'replace')
        items.append(('text', ry, rx, s, align, font_h, bx))
    elif t in (27, 54):  # MOVETOEX, LINETO
        x, y = struct.unpack_from('<2i', rec, 8)
        items.append(('move' if t == 27 else 'line', y, x, '', 0, 0, None))
    elif t in (43,):     # RECTANGLE
        items.append(('rect', 0, 0, str(struct.unpack_from('<4i', rec, 8)), 0, 0, None))
    elif t in (85, 86, 87, 88, 89, 90):  # poly*16
        bx = struct.unpack_from('<4i', rec, 8); n = struct.unpack_from('<I', rec, 24)[0]
        pts = struct.unpack_from('<%dh' % (2 * n), rec, 28)
        items.append(('poly16:%d' % t, 0, 0, str(pts[:12]), 0, 0, bx))
    elif t in (2, 3, 4, 5, 6):          # poly* 32
        bx = struct.unpack_from('<4i', rec, 8); n = struct.unpack_from('<I', rec, 24)[0]
        pts = struct.unpack_from('<%di' % (2 * n), rec, 28)
        items.append(('poly:%d' % t, 0, 0, str(pts[:12]), 0, 0, bx))
    elif t == 76:  # BITBLT (pattern fill): bounds, xDest, yDest, cx, cy
        bx = struct.unpack_from('<4i', rec, 8); d = struct.unpack_from('<4i', rec, 24)
        items.append(('bitblt', d[1], d[0], 'w=%d h=%d' % (d[2], d[3]), 0, 0, bx))
    pos += sz
print('window org', win_org, 'ext', win_ext, 'viewport ext', vp_ext)
print('record types', dict(hist))
for it in items:
    if it[0] == 'text':
        print('TEXT y=%d x=%d align=%d fontH=%s bounds=%s %r' % (it[1], it[2], it[4], it[5], it[6], it[3]))
    else:
        print(it[0], 'y=%d x=%d' % (it[1], it[2]), it[3], it[6] if it[6] else '')
