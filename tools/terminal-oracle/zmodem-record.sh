#!/bin/sh
# Records lrzsz (sz and rz, 0.12.21rc in WSL Ubuntu) talking to itself, for the
# terminal example's ZModem tests (phase 7, spec 19.9). Run from the repository, in WSL:
#
#   wsl.exe -d Ubuntu --cd /mnt/d/Projects/ty-3.1 -- sh tools/terminal-oracle/zmodem-record.sh
#
# Writes tests/fixtures/terminal-zmodem/: cases.json, <id>.sz.bin (what sz sent),
# <id>.rz.bin (what rz sent) and the sources <id>.<n>.src. Each case is its own
# run.sh (zmodem-record.py prepare): two FIFOs between sz and rz, tee copying each
# direction to a file -- none of our code is on the way.
#
# Reproducible up to the files only (see zmodem-record.py): whose first header lands
# first is a race, so a rerun may change the .bin files but not cases.json or what
# rz received. Commit the first run's.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/tests/fixtures/terminal-zmodem"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
python3 "$ROOT/tools/terminal-oracle/zmodem-record.py" prepare "$WORK"
while read -r id; do
  [ -n "$id" ] || continue
  echo "== $id"
  sh "$WORK/$id/run.sh"
done < "$WORK/cases.txt"
python3 "$ROOT/tools/terminal-oracle/zmodem-record.py" finish "$WORK" "$OUT"
