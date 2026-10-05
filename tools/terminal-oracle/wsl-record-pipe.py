#!/usr/bin/env python3
# Turns a pane's raw output (stdin, from tmux pipe-pane) into asciicast v2 on stdout.
#
#   wsl-record-pipe.py WIDTH HEIGHT > name.cast
#
# The header carries the size and TERM only -- no "timestamp": the recording is a
# fixed input for the oracle and must not say when or where it was made. Each block
# read becomes one [seconds, "o", text] event; seconds are monotonic from the start
# with six decimals. Text is decoded incrementally, so a character split across two
# blocks goes out whole with the second one. asciicast holds UTF-8 text and cannot
# carry an invalid byte: one would be replaced by U+FFFD and counted on stderr, and
# such a recording is to be thrown away and made again (the environment is
# LANG=C.UTF-8, so it should not happen). Standard library only.
import codecs
import json
import os
import sys
import time

replaced = 0


def count_replace(err):
    global replaced
    replaced += err.end - err.start
    return ('�', err.end)


codecs.register_error('tyrec-count', count_replace)


def main():
    width, height = int(sys.argv[1]), int(sys.argv[2])
    out = sys.stdout
    out.write(json.dumps({"version": 2, "width": width, "height": height,
                          "env": {"TERM": "xterm-256color"}}) + "\n")
    out.flush()
    dec = codecs.getincrementaldecoder('utf-8')(errors='tyrec-count')
    start = time.monotonic()
    fd = sys.stdin.fileno()
    while True:
        block = os.read(fd, 65536)
        if not block:
            break
        text = dec.decode(block)
        if text:
            out.write(json.dumps([round(time.monotonic() - start, 6), "o", text], ensure_ascii=False) + "\n")
            out.flush()
    tail = dec.decode(b'', final=True)
    if tail:
        out.write(json.dumps([round(time.monotonic() - start, 6), "o", tail], ensure_ascii=False) + "\n")
    out.flush()
    if replaced:
        sys.stderr.write("wsl-record-pipe: %d invalid bytes replaced -- record again\n" % replaced)


main()
