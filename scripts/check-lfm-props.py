#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Check every example .lfm against the properties source/ actually declares.

WHY THIS EXISTS
---------------
`lazbuild` proves an example COMPILES. It proves nothing about whether its .lfm
STREAMS, because a .lfm is a resource: a property that no longer exists is not a
compile error, it is an EReadError inside CreateForm at startup --

    Error reading PanDemo.AutoScroll: Unknown property: "AutoScroll".

That is exactly what happened after TTyScrollPanel.AutoScroll was renamed to
AutoPan: 46/46 examples built green for several rounds while one of them could
not open its main form. A green build sweep is not a smoke test.

WHAT IT CATCHES
---------------
Renamed and un-published properties -- the failure above. It scans each
`object Foo: TTy...` block in every example .lfm and flags any assigned name that
appears as a `property` declaration nowhere in source/.

WHAT IT DOES NOT CATCH
----------------------
It matches on NAME only, not on the owning class, so it will not notice a
property that still exists somewhere but was moved off the class the .lfm uses
it on. It also cannot see a value whose MEANING changed (a default flip, or
TTyToolBar.Indent becoming horizontal-only) -- those stream fine and look wrong.
Only running the example finds those.

USAGE
-----
    python scripts/check-lfm-props.py
Exit code 1 and one line per suspect if anything is found.
"""
import io
import os
import re
import sys
import glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def declared_properties():
    """Every identifier declared as a `property` anywhere in source/."""
    names = set()
    for path in glob.glob(os.path.join(ROOT, 'source', '*.pas')):
        text = io.open(path, encoding='utf-8', errors='replace').read()
        for m in re.finditer(r'\bproperty\s+([A-Za-z_]\w*)', text):
            names.add(m.group(1).lower())
    return names


def scan(names):
    suspects = []
    pattern = os.path.join(ROOT, 'examples', '*', '*.lfm')
    for path in sorted(glob.glob(pattern)):
        current = None
        rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
        for lineno, line in enumerate(io.open(path, encoding='utf-8', errors='replace'), 1):
            obj = re.match(r'\s*(?:object|inline)\s+\w+:\s*(T\w+)', line)
            if obj:
                current = obj.group(1)
                continue
            assign = re.match(r'\s*([A-Za-z_]\w*)\s*=\s*', line)
            if not (assign and current and current.startswith('TTy')):
                continue
            prop = assign.group(1)
            # Dotted names (Font.Height) are sub-properties of an LCL type.
            if '.' in prop or prop.lower() in names:
                continue
            suspects.append((rel, lineno, current, prop))
    return suspects


def main():
    suspects = scan(declared_properties())
    for rel, lineno, cls, prop in suspects:
        print('%s:%d  %s.%s is assigned but no source/ unit declares that property'
              % (rel, lineno, cls, prop))
    if suspects:
        print('\n%d suspect(s). Each one is a form that will raise EReadError at startup.'
              % len(suspects))
        return 1
    print('OK: every property assigned in an example .lfm is still declared.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
