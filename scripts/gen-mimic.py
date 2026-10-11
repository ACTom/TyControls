#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Generate tests/test.customclasses.mimic.pas, the mimics the G9 guard compares.

    python scripts/gen-mimic.py

Runs from anywhere (it works in the repository this script sits in); no arguments.

WHAT IT WRITES
--------------
For every class in CSplit (the AddAll(GSplit, [...]) block of tests/test.customclasses.pas) it
finds `TTyXxx = class(TTyCustomXxx)` in source/*.pas and source/db/*.pas (the
tycontrols_db package) and writes `TGenXxx = class(TTyCustomXxx)`
with the final class's published section copied line by line (comments dropped). The guard
TestGeneratedMimicsMatchTheirFinalClass then holds each pair to identical RTTI, fresh stream,
type key, default size and resolved style -- i.e. a third party that publishes what the final
class publishes gets exactly the final class. A final class whose published section holds
anything but `property X;` lines is refused (the G3b rule).

WHEN TO RUN IT
--------------
After splitting a new class (G9 reports "split class without a mimic" until you do).

REVIEW THE DIFF
---------------
Regenerating copies each final class's published section AS IT IS NOW. Run on a tree where a
published line moved, was dropped or was added by accident, it writes that change into the
mimic too, and G9 goes green on it. So after every run, read `git diff
tests/test.customclasses.mimic.pas`: it must hold the new classes (a type block, a pair in
CGenMimics, maybe a unit in uses) and nothing else. Any other changed line is a change to a
final class's published section -- that is what decides the .lfm write order -- and needs its
own reason, not a regenerated mimic.
"""
import glob
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUARD = os.path.join('tests', 'test.customclasses.pas')
OUT = os.path.join('tests', 'test.customclasses.mimic.pas')


def strip_comments(src):
    """Blank out { }, (* *) and // comments, keeping line breaks and string literals.
    FPC nests { } comments; none of the class declarations read here needs that."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '{':
            j = src.find('}', i)
            j = n - 1 if j < 0 else j
            out.append('\n' * src[i:j + 1].count('\n'))
            i = j + 1
            continue
        if src.startswith('(*', i):
            j = src.find('*)', i)
            j = n - 2 if j < 0 else j
            out.append('\n' * src[i:j + 2].count('\n'))
            i = j + 2
            continue
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == "'":
            j = src.find("'", i + 1)
            j = n - 1 if j < 0 else j
            out.append(src[i:j + 1])
            i = j + 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def read_source(path):
    # Strict UTF-8: a file that does not decode is an error, not a silently replaced byte.
    with io.open(path, encoding='utf-8') as f:
        return f.read().replace('\r\n', '\n')


def split_names():
    g = read_source(GUARD)
    blocks = re.findall(r'AddAll\(GSplit,\s*\[(.*?)\]\);', g, re.S)
    if len(blocks) != 1:
        sys.exit('expected exactly one AddAll(GSplit, [...]) block in %s, found %d'
                 % (GUARD, len(blocks)))
    body = re.sub(r'//[^\n]*', '', blocks[0])
    names = re.findall(r"'(TTy\w+)'", body)
    dup = sorted(set(n for n in names if names.count(n) > 1))
    if dup:
        sys.exit('CSplit lists these more than once: ' + ', '.join(dup))
    if not names:
        sys.exit('CSplit is empty in ' + GUARD)
    return names


def main():
    os.chdir(ROOT)
    names = split_names()
    wanted = set(names)
    found = {}
    # The library's two packages: tycontrols (source/) and tycontrols_db (source/db/).
    files = (sorted(glob.glob(os.path.join('source', '*.pas')))
             + sorted(glob.glob(os.path.join('source', 'db', '*.pas'))))
    for f in files:
        raw = read_source(f)
        m = re.search(r'^unit\s+([\w.]+)\s*;', raw, re.M | re.I)
        if not m:
            sys.exit('%s: no unit header' % f)
        unit = m.group(1)
        lines = strip_comments(raw).split('\n')
        for i, l in enumerate(lines):
            m = re.match(r'\s*(TTy\w+)\s*=\s*class\((TTyCustom\w+)\)\s*$', l)
            if not m or m.group(1) not in wanted:
                continue
            if m.group(2) != 'TTyCustom' + m.group(1)[3:]:
                continue
            if m.group(1) in found:
                sys.exit('%s: %s is declared twice (also in unit %s)'
                         % (f, m.group(1), found[m.group(1)][0]))
            body, j = [], i + 1
            while not re.match(r'\s*end\s*;', lines[j]):
                t = lines[j].strip()
                if t:
                    if not re.match(r'^(published|property\s+\w+\s*;)$', t, re.I):
                        sys.exit('%s: %s is not property-only: %r' % (f, m.group(1), t))
                    body.append('    ' + t if t.lower().startswith('property') else '  ' + t)
                j += 1
            found[m.group(1)] = (unit, m.group(2), body)
    missing = [n for n in names if n not in found]
    if missing:
        sys.exit('split classes without a declaration in source/ or source/db/: ' + ', '.join(missing))
    assert len(found) == len(names), (len(found), len(names))
    units = sorted(set(v[0] for v in found.values()))
    out = []
    out.append('unit test.customclasses.mimic;')
    out.append('{$mode objfpc}{$H+}')
    out.append('')
    out.append('{ GENERATED by scripts/gen-mimic.py -- do not edit by hand; re-run it after every split,')
    out.append('  then read the diff: it must add the new classes and change nothing else (the script')
    out.append('  copies each final class\'s CURRENT published section, so an accidental reordering would')
    out.append('  be copied too, and G9 would pass it).')
    out.append('')
    out.append('  One mimic per split class: TGenXxx derives from TTyCustomXxx the way a third party does')
    out.append('  (issue #8) and publishes exactly the lines the library\'s TTyXxx publishes. The guard')
    out.append('  TestGeneratedMimicsMatchTheirFinalClass (test.customclasses) holds each pair to the same')
    out.append('  RTTI, fresh stream, type key, default size and resolved style -- so every default, stored')
    out.append('  clause and type key a final class shows must come from its custom class, where a third')
    out.append('  party gets it too. }')
    out.append('')
    out.append('interface')
    out.append('')
    out.append('uses')
    uses = ['Classes'] + units
    line = '  '
    for k, u in enumerate(uses):
        piece = u + (',' if k < len(uses) - 1 else ';')
        if len(line) + len(piece) + 1 > 100:
            out.append(line.rstrip())
            line = '  '
        line += piece + ' '
    out.append(line.rstrip())
    out.append('')
    out.append('type')
    for n in sorted(found):
        unit, cust, body = found[n]
        out.append('  TGen%s = class(%s)' % (n[3:], cust))
        out.extend(body)
        out.append('  end;')
        out.append('')
    out.append('const')
    out.append('  { (mimic, final class) }')
    out.append('  CGenMimics: array[0..%d, 0..1] of TClass = (' % (len(found) - 1))
    pairs = ['    (TGen%s, %s)' % (n[3:], n) for n in sorted(found)]
    out.append(',\n'.join(pairs) + ');')
    out.append('')
    out.append('implementation')
    out.append('')
    out.append('end.')
    text = '\n'.join(out) + '\n'
    with io.open(OUT, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(text)
    with io.open(OUT, 'rb') as f:
        data = f.read()
    assert data.count(b'\r\n') == data.count(b'\n'), 'mixed line endings in ' + OUT
    print('%s: %d mimics -- now review: git diff %s' % (OUT, len(found), OUT.replace(os.sep, '/')))


if __name__ == '__main__':
    main()
