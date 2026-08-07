#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Merge compiler-emitted .rsj resourcestrings into an example's zh_CN .po.

lazbuild does NOT run the IDE's i18n collection step (verified 2026-08-07: a
build with EnableI18N touches no .pot/.po; only lib/<cpu>-<os>/<unit>.rsj is
written). So the .po files are maintained by THIS script:

  python example-rsj2po.py <example_dir> <project_name> <translations.json>

- reads every .rsj under <example_dir>/lib/**/ whose unit is NOT tycontrols.*
  (library strings live in tycontrols.zh_CN.po, not the example catalogue)
- appends entries missing from languages/<project_name>.zh_CN.po
- msgstr comes from translations.json {identifier: chinese}; missing -> ERROR
- adds `#, object-pascal-format` when the msgid carries %-placeholders
- refuses empty msgid (an entry empty on both sides raises inside CreateForm)
- updates msgid in place if the Pascal source string changed for a known id
"""
import io, json, os, re, sys, glob

def po_escape(s):
    return (s.replace('\\', '\\\\').replace('"', '\\"')
             .replace('\r', '\\r').replace('\n', '\\n'))

FMT = re.compile(r'%(\*?[0-9.\-]*[sdufgxenpc]|%)')  # object-pascal Format specs
def has_format(s):
    m = [g for g in FMT.findall(s) if g != '%']
    return len(m) > 0

def parse_po(path):
    """Return (header_lines, entries, raw_lines). entries: list of dicts with
    ident, flags, msgid, msgstr, start, end (line spans)."""
    lines = io.open(path, encoding='utf-8').read().splitlines()
    entries = []
    cur = None
    def flush(cur):
        if cur and (cur.get('msgid') is not None):
            entries.append(cur)
    i = 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith('#:'):
            flush(cur)
            cur = {'ident': ln[2:].strip(), 'flags': [], 'msgid': None,
                   'msgstr': None, 'start': i}
        elif ln.startswith('#,') and cur is not None:
            cur['flags'] += [f.strip() for f in ln[2:].split(',')]
        elif ln.startswith('msgid ') and cur is not None:
            cur['msgid'] = ln[6:].strip()
        elif ln.startswith('msgstr ') and cur is not None:
            cur['msgstr'] = ln[7:].strip()
            cur['end'] = i
        i += 1
    flush(cur)
    return entries, lines

def main():
    exdir, proj, trjson = sys.argv[1], sys.argv[2], sys.argv[3]
    tr = json.load(io.open(trjson, encoding='utf-8'))
    po_path = os.path.join(exdir, 'languages', proj + '.zh_CN.po')
    if not os.path.exists(po_path):
        print('FATAL: missing ' + po_path); sys.exit(2)
    strings = {}
    for rsj in glob.glob(os.path.join(exdir, 'lib', '*', '*.rsj')):
        unit = os.path.basename(rsj)[:-4]
        if unit.lower().startswith('tycontrols.'):
            continue
        data = json.load(io.open(rsj, encoding='utf-8'))
        for s in data.get('strings', []):
            # FPC writes `value` byte-mangled for non-ASCII (UTF-8 bytes spread
            # over Latin-1 chars); `sourcebytes` holds the true UTF-8 bytes.
            if 'sourcebytes' in s:
                s['value'] = bytes(s['sourcebytes']).decode('utf-8')
            if s['value'] == '':
                print('FATAL: resourcestring %s is EMPTY (would block startup '
                      'if paired with an empty msgstr)' % s['name'])
                sys.exit(2)
            strings[s['name']] = s['value']
    if not strings:
        print('NOTE: no example-owned .rsj strings found under ' + exdir)
    entries, lines = parse_po(po_path)
    have = {e['ident']: e for e in entries}
    added, updated, missing_tr = [], [], []
    out = list(lines)
    # update msgids of known identifiers whose source string changed
    for name, val in strings.items():
        if name in have:
            e = have[name]
            want = '"%s"' % po_escape(val)
            if e['msgid'] != want:
                out[ [i for i in range(e['start'], e['end']+1)
                      if out[i].startswith('msgid ')][0] ] = 'msgid ' + want
                updated.append(name)
    new_names = [n for n in sorted(strings) if n not in have]
    if new_names:
        block = ['', '# --- code resourcestrings (msgid=Pascal source) ---']
        for name in new_names:
            val = strings[name]
            if name not in tr:
                missing_tr.append(name); continue
            zh = tr[name]
            block.append('')
            block.append('#: ' + name)
            if has_format(val):
                block.append('#, object-pascal-format')
            block.append('msgid "%s"' % po_escape(val))
            block.append('msgstr "%s"' % po_escape(zh))
            added.append(name)
        if added:
            while out and out[-1] == '':
                out.pop()
            out += block
    if missing_tr:
        print('FATAL: no zh translation supplied for:')
        for n in missing_tr: print('  ' + n)
        sys.exit(2)
    io.open(po_path, 'w', encoding='utf-8', newline='\n').write(
        '\n'.join(out) + '\n')
    print('po=%s  rsj-strings=%d  added=%d  msgid-updated=%d'
          % (os.path.basename(po_path), len(strings), len(added), len(updated)))
    for n in added: print('  + ' + n)
    for n in updated: print('  ~ ' + n)

if __name__ == '__main__':
    main()
