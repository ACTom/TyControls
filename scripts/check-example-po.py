#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Lint every example .po:
 1. an entry with msgid AND msgstr both empty (other than the header) raises a
    modal error inside CreateForm -> startup blocker (test.i18n pins it)
 2. object-pascal-format entries whose msgstr placeholder sequence differs from
    the msgid's (a broken Format at runtime raises EConvertError)
 3. flags claiming object-pascal-format on a placeholder-less msgid are noise
 4. duplicate identifiers in one file
Usage: python check-example-po.py <repo_root>
"""
import io, os, re, sys, glob

FMT = re.compile(r'%(?:\*?[0-9.\-]*[sdufgxenpc]|%)')

def specs(s):
    return [m for m in FMT.findall(s) if m != '%%']

def parse(path):
    text = io.open(path, encoding='utf-8').read()
    blocks = re.split(r'\n\s*\n', text)
    out = []
    for b in blocks:
        ident = None; flags = ''
        m = re.search(r'^#:\s*(.+)$', b, re.M)
        if m: ident = m.group(1).strip()
        m = re.search(r'^#,\s*(.+)$', b, re.M)
        if m: flags = m.group(1)
        mi = re.search(r'^msgid\s+"(.*)"\s*$', b, re.M)
        ms = re.search(r'^msgstr\s+"(.*)"\s*$', b, re.M)
        if mi is None and ms is None: continue
        out.append((ident, flags,
                    mi.group(1) if mi else None,
                    ms.group(1) if ms else None))
    return out

def main():
    root = sys.argv[1]
    bad = 0
    files = sorted(glob.glob(os.path.join(root, 'examples', '*', 'languages', '*.po')))
    for f in files:
        rel = os.path.relpath(f, root)
        seen = {}
        first = True
        for ident, flags, mi, ms in parse(f):
            if mi is None or ms is None:
                print('%s: %s: half an entry (msgid or msgstr missing)' % (rel, ident)); bad += 1
                continue
            if mi == '' and ms == '':
                if first and ident is None:
                    first = False; continue   # the po header
                print('%s: %s: EMPTY msgid AND msgstr (startup blocker)' % (rel, ident)); bad += 1
            first = False
            if ident:
                # TStrings items legitimately repeat one identifier with different
                # msgids (runtime matches by original value); only same-msgid
                # conflicts are real.
                key = (ident, mi)
                if key in seen and seen[key] != ms:
                    print('%s: conflicting msgstr for %s / "%s"' % (rel, ident, mi)); bad += 1
                seen[key] = ms
            if ms and specs(mi) != specs(ms):
                print('%s: %s: placeholder mismatch  msgid%s  msgstr%s'
                      % (rel, ident, specs(mi), specs(ms))); bad += 1
            if 'object-pascal-format' in flags and not specs(mi) and mi:
                print('%s: %s: object-pascal-format flag on placeholder-less msgid' % (rel, ident)); bad += 1
    print('%d file(s) checked, %d problem(s)' % (len(files), bad))
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    main()
