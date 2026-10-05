#!/usr/bin/env python3
"""Recordings of lrzsz talking to itself, for the terminal example's ZModem tests
(phase 7, spec 19.9). Run by zmodem-record.sh in WSL; never by hand.

  zmodem-record.py prepare WORK      source files (seeded), one run.sh per case,
                                     WORK/cases.txt listing the case ids
  zmodem-record.py finish WORK OUT   checks every received file against its source,
                                     copies <id>.sz.bin, <id>.rz.bin and the sources
                                     into OUT with cases.json

sz and rz are wired to each other through two FIFOs, each direction copied by tee
into a file (run.sh): the bytes are lrzsz's own, none of our code is on the way, so
they are half an oracle for the receiver and the sender (tests/test.terminal.zmodem).

REPRODUCIBLE UP TO THE FILES: both programs start at once, and whose first header
arrives first is a race -- rz may send one more ZRINIT, sz one more ZFILE. A rerun
must give the same received files and the same cases.json; the two .bin files may
differ. The committed ones are the first run's.
"""
import hashlib
import json
import os
import random
import shlex
import shutil
import subprocess
import sys

MTIME = 1700000000

# id, sz options, rz options, [(name, kind, size, seed)]
CASES = [
    ('one-small', [], [], [('one-small.bin', 'cycle', 1500, 0)]),
    ('empty', [], [], [('empty.bin', 'cycle', 0, 0)]),
    ('batch', [], [], [('b1.bin', 'random', 1, 11), ('b2.bin', 'random', 1024, 12), ('b3.bin', 'random', 5000, 13)]),
    ('esc', ['-e'], ['-e'], [('esc.bin', 'random', 3000, 21)]),
    ('big-block', ['-8'], [], [('big.bin', 'random', 20000, 31)]),
    ('window', ['-w', '2048'], [], [('window.bin', 'random', 20000, 41)]),
    ('names', [], [], [('a b 中文.bin', 'random', 100, 51), ('x.y.z', 'random', 100, 52)]),
]


def content(kind, size, seed):
    if kind == 'cycle':
        return bytes(i & 255 for i in range(size))
    return random.Random(seed).randbytes(size)


def version(prog):
    return subprocess.run([prog, '--version'], capture_output=True, text=True).stdout.strip()


def prepare(work):
    ids = []
    for cid, szo, rzo, files in CASES:
        d = os.path.join(work, cid)
        src = os.path.join(d, 'src')
        recv = os.path.join(d, 'recv')
        os.makedirs(src)
        os.makedirs(recv)
        for name, kind, size, seed in files:
            p = os.path.join(src, name)
            with open(p, 'wb') as f:
                f.write(content(kind, size, seed))
            os.utime(p, (MTIME, MTIME))
        q = shlex.quote
        a, b = os.path.join(d, 'a'), os.path.join(d, 'b')
        names = ' '.join(q(n) for n, _, _, _ in files)
        script = '\n'.join([
            'set -u',
            f'mkfifo {q(a)} {q(b)}',
            f'( cd {q(recv)} && timeout 60 rz {" ".join(rzo)} < {q(a)} 2> {q(d + "/rz.err")} | tee {q(d + "/rz.bin")} > {q(b)} ) &',
            f'( cd {q(src)} && timeout 60 sz {" ".join(szo)} {names} < {q(b)} 2> {q(d + "/sz.err")} | tee {q(d + "/sz.bin")} > {q(a)} )',
            'wait',
            '',
        ])
        with open(os.path.join(d, 'run.sh'), 'w') as f:
            f.write(script)
        ids.append(cid)
    with open(os.path.join(work, 'cases.txt'), 'w') as f:
        f.write('\n'.join(ids) + '\n')


def finish(work, out):
    os.makedirs(out, exist_ok=True)
    listing = []
    total = 0
    for cid, szo, rzo, files in CASES:
        d = os.path.join(work, cid)
        entry = {'id': cid, 'szOptions': szo, 'rzOptions': rzo, 'files': []}
        for n, (name, kind, size, seed) in enumerate(files, 1):
            want = content(kind, size, seed)
            got_path = os.path.join(d, 'recv', name)
            if not os.path.exists(got_path):
                sys.exit(f'{cid}: rz did not receive {name}')
            with open(got_path, 'rb') as f:
                got = f.read()
            if got != want:
                sys.exit(f'{cid}: {name} arrived different ({len(got)} bytes, {len(want)} sent)')
            srcname = f'{cid}.{n}.src'
            shutil.copyfile(os.path.join(d, 'src', name), os.path.join(out, srcname))
            entry['files'].append({'name': name, 'size': size, 'md5': hashlib.md5(want).hexdigest(),
                                   'mtime': MTIME, 'source': srcname})
            total += size
        for side in ('sz', 'rz'):
            shutil.copyfile(os.path.join(d, side + '.bin'), os.path.join(out, f'{cid}.{side}.bin'))
            total += os.path.getsize(os.path.join(d, side + '.bin'))
        listing.append(entry)
    doc = {
        'generator': 'tools/terminal-oracle/zmodem-record.sh (wsl.exe -d Ubuntu --cd <repo> -- sh tools/terminal-oracle/zmodem-record.sh)',
        'sz': version('sz'), 'rz': version('rz'),
        'note': 'sz and rz talking to each other through two FIFOs, each direction copied by tee. '
                'Reproducible up to the files: a rerun gives the same received files and this file, '
                'the .bin recordings may differ (which side speaks first is a race).',
        'cases': listing,
    }
    with open(os.path.join(out, 'cases.json'), 'w', newline='\n') as f:
        f.write(json.dumps(doc, ensure_ascii=False, indent=1) + '\n')
    print(f'{len(listing)} cases, {total} bytes')
    if total > 300 * 1024:
        sys.exit('more than 300 KB of fixtures')


if __name__ == '__main__':
    if sys.argv[1] == 'prepare':
        prepare(sys.argv[2])
    elif sys.argv[1] == 'finish':
        finish(sys.argv[2], sys.argv[3])
    else:
        sys.exit('prepare WORK | finish WORK OUT')
