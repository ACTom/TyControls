#!/usr/bin/env python3
# Turns a ConPTY recording (tools/terminal-conpty-record: one "SECONDS BASE64" line per
# block the session's reader got) into asciicast v2, written the way wsl-record-pipe.py
# writes the WSL recordings: a header with the size and TERM only, one [seconds, "o",
# text] event per block, text decoded incrementally (a character split across blocks
# goes out whole with the second one), ensure_ascii off.
#
#   python conpty-cast.py IN.raw COLS ROWS > recordings/NAME.cast
#
# What ConPTY sends that names this machine: the window title it sets first (OSC 0) is
# the program's full path -- only the file name is kept. Anything else that would name
# the machine (the user name, the computer name, the profile directory, a path under
# C:\Users) makes it stop: record again with a command that does not print it.
# Standard library only.
import base64
import codecs
import json
import os
import re
import sys

TITLE = re.compile('\x1b\\]([02]);([^\x07\x1b]*)(\x07|\x1b\\\\)')


def title(m):
    name = m.group(2).replace('/', '\\').split('\\')[-1]
    return '\x1b]' + m.group(1) + ';' + name + m.group(3)


def main():
    src, width, height = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    forbidden = [v for v in (os.environ.get('USERNAME'), os.environ.get('COMPUTERNAME'),
                             os.environ.get('USERPROFILE'), os.environ.get('USERDOMAIN'))
                 if v and len(v) >= 3]
    forbidden.append('C:\\Users')
    dec = codecs.getincrementaldecoder('utf-8')(errors='strict')
    out = [json.dumps({"version": 2, "width": width, "height": height,
                       "env": {"TERM": "xterm-256color"}})]
    events = []
    with open(src, encoding='ascii') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            secs, b64 = line.split(' ', 1)
            text = dec.decode(base64.b64decode(b64))
            if text:
                events.append([round(float(secs), 6), text])
    tail = dec.decode(b'', final=True)
    if tail:
        events.append([events[-1][0] if events else 0.0, tail])
    for secs, text in events:
        text = TITLE.sub(title, text)
        for word in forbidden:
            if word.lower() in text.lower():
                sys.exit('conpty-cast: the recording names this machine (%r) -- record again' % word)
        if '\x00' in text:
            sys.exit('conpty-cast: a NUL in the output -- the example cannot replay it')
        out.append(json.dumps([secs, "o", text], ensure_ascii=False))
    sys.stdout.reconfigure(encoding='utf-8', newline='\n')
    sys.stdout.write('\n'.join(out) + '\n')


main()
