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

A name is also accepted when an LCL root class publishes it itself: TComponent
(Name, Tag) and TControl (Left, Top, Width, Height, Hint, Cursor, AnchorSide*,
Help*). Since 4.0 the Ty base classes publish nothing, the LCL way, so the
`property Hint;` line that used to sit in the base class is gone and Hint is
published by TControl alone -- it must not read as "declared nowhere". The list
is read from the Lazarus sources (lcl/controls.pp, and the FPC rtl's
classesh.inc for TComponent) rather than written here, so it follows the
installed LCL. The Lazarus directory comes from LAZARUS_DIR, then from lazbuild
on PATH, then the usual install locations; when none has lcl/controls.pp the
script stops with exit code 2 instead of guessing.

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
Exit code 1 and one line per suspect if anything is found; 2 when the Lazarus
sources cannot be found.
"""
import io
import os
import re
import shutil
import sys
import glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The LCL classes every Ty control sits on. TWinControl, TCustomControl and
# TGraphicControl publish nothing in Lazarus 3.0-4.4; they are read anyway, so an
# LCL that gives one of them a published section is picked up.
LCL_ROOTS = ('TControl', 'TWinControl', 'TCustomControl', 'TGraphicControl')


def declared_properties():
    """Every identifier declared as a `property` anywhere in source/ or source/db/ (the
    tycontrols_db package)."""
    names = set()
    for path in (glob.glob(os.path.join(ROOT, 'source', '*.pas'))
                 + glob.glob(os.path.join(ROOT, 'source', 'db', '*.pas'))):
        text = io.open(path, encoding='utf-8', errors='replace').read()
        for m in re.finditer(r'\bproperty\s+([A-Za-z_]\w*)', text):
            names.add(m.group(1).lower())
    return names


def lazarus_dir():
    """The Lazarus install whose lcl/controls.pp the examples are built against."""
    candidates = []
    for var in ('LAZARUS_DIR', 'LAZARUSDIR'):
        if os.environ.get(var):
            candidates.append(os.environ[var])
    lb = shutil.which('lazbuild')
    if lb:
        candidates.append(os.path.dirname(os.path.realpath(lb)))
    candidates += ['C:/lazarus', '/usr/lib/lazarus/default', '/usr/share/lazarus',
                   '/usr/lib/lazarus', '/Applications/Lazarus', '/Developer/lazarus']
    candidates += sorted(glob.glob('/usr/share/lazarus/*'), reverse=True)
    candidates += sorted(glob.glob('/usr/lib/lazarus/*'), reverse=True)
    for c in candidates:
        if os.path.isfile(os.path.join(c, 'lcl', 'controls.pp')):
            return c
    return None


def published_in_class(text, cls):
    """Property names in the published sections of the declaration of `cls`, or
    None when the declaration is not in text."""
    m = re.search(r'^  %s\s*=\s*class\b[^;\n]*$' % re.escape(cls), text, re.M)
    if not m:
        return None
    names = set()
    section = 'published'   # a class's first section is published by default
    for line in text[m.end():].split('\n')[1:]:
        if re.match(r'^  end;', line):
            break
        sec = re.match(r'^  (?:strict\s+)?(private|protected|public|published)\b', line)
        if sec:
            section = sec.group(1)
            continue
        p = re.match(r'\s*property\s+([A-Za-z_]\w*)', line)
        if p and section == 'published':
            names.add(p.group(1).lower())
    return names


def lcl_root_published(lazdir):
    """Names the LCL roots publish themselves (TComponent, TControl, ...)."""
    path = os.path.join(lazdir, 'lcl', 'controls.pp')
    text = io.open(path, encoding='utf-8', errors='replace').read().replace('\r\n', '\n')
    names = set()
    for cls in LCL_ROOTS:
        found = published_in_class(text, cls)
        if found is None:
            sys.exit('check-lfm-props: %s is not declared in %s' % (cls, path))
        names |= found
    # TComponent lives in the FPC rtl. The Windows installer ships its source under
    # fpc/<version>/source; where it is absent, use the two names TComponent has
    # published in every FPC since 2.x.
    comp = None
    pattern = os.path.join(lazdir, 'fpc', '*', 'source', 'rtl', 'objpas', 'classes',
                           'classesh.inc')
    for inc in sorted(glob.glob(pattern), reverse=True):
        t = io.open(inc, encoding='utf-8', errors='replace').read().replace('\r\n', '\n')
        comp = published_in_class(t, 'TComponent')
        if comp:
            break
    names |= comp if comp else {'name', 'tag'}
    return names


def scan(names):
    suspects = []
    paths = (glob.glob(os.path.join(ROOT, 'examples', '*', '*.lfm'))
             + glob.glob(os.path.join(ROOT, 'tools', '*', '*.lfm')))
    for path in sorted(paths):
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
    lazdir = lazarus_dir()
    if lazdir is None:
        print('check-lfm-props: cannot find the Lazarus sources (lcl/controls.pp); set '
              'LAZARUS_DIR to the Lazarus install directory.')
        return 2
    suspects = scan(declared_properties() | lcl_root_published(lazdir))
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
