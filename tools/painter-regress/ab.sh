#!/usr/bin/env bash
# The same-session A/B of tools/painter-regress (see the header of painterregress.lpr).
#
#   tools/painter-regress/ab.sh <base-commit> [--files "a b ..."] [--rounds N] [--out DIR] [--only TEXT]
#
#   <base-commit>  the commit whose version of the files under test is "before"
#   --files        the files under test, repo-relative (default: source/tyControls.Painter.pas)
#   --rounds       timing rounds a side, run alternately A B A B ... (default 3; 0 = no timing)
#   --out          where the hashes, the logs and the timing files go (default: a new
#                  temporary folder, printed)
#   --only         only the scenes whose name contains TEXT (passed to the tool)
#
# A = a temporary git worktree of HEAD with the files under test checked out as <base-commit>
# has them; B = this working tree. Both build the SAME tool from HEAD's sources, so nothing
# but the files under test differs: every scene must come out identical. The worktree lives
# under the temporary folder and is removed at the end (git worktree remove), whatever
# happens. Run from the repository root, on the machine and in the session the numbers are
# for: the hashes carry the machine's fingerprint and are good for this run only. A new
# machine, a ClearType change, a font update -- run it again.
#
# Exit code: 0 identical, 1 differing scenes, 2 a build or a run failed.
set -u
base=""
files="source/tyControls.Painter.pas"
rounds=3
out=""
only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --files) files="$2"; shift 2 ;;
    --rounds) rounds="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --only) only="$2"; shift 2 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) base="$1"; shift ;;
  esac
done
if [ -z "$base" ]; then echo "usage: $0 <base-commit> [--files ...] [--rounds N] [--out DIR] [--only TEXT]" >&2; exit 2; fi
root=$(git rev-parse --show-toplevel) || exit 2
cd "$root" || exit 2
git rev-parse --verify --quiet "$base^{commit}" > /dev/null || { echo "no commit $base" >&2; exit 2; }
if [ -z "$out" ]; then out=$(mktemp -d "${TMPDIR:-/tmp}/painter-ab.XXXXXX"); fi
mkdir -p "$out"
# Git Bash on Windows: a mixed path (C:/...) is one both bash and the Windows tool read
if command -v cygpath > /dev/null 2>&1; then out=$(cygpath -m "$out"); fi
wt="$out/base-tree"
onlyArgs=()
if [ -n "$only" ]; then onlyArgs=(--only "$only"); fi

cleanup() {
  git worktree remove --force "$wt" > /dev/null 2>&1
  git worktree prune > /dev/null 2>&1
}
trap cleanup EXIT

echo "A: HEAD $(git rev-parse --short HEAD) with $files from $(git rev-parse --short "$base")"
echo "B: this working tree"
echo "out: $out"
git worktree add --detach "$wt" HEAD > "$out/worktree.log" 2>&1 || { cat "$out/worktree.log"; exit 2; }
# shellcheck disable=SC2086
git -C "$wt" checkout "$base" -- $files || exit 2
git -C "$wt" status --short > "$out/a-changes.txt"

echo "building A and B"
lazbuild -B "$wt/tools/painter-regress/painterregress.lpi" > "$out/build-a.log" 2>&1 || { tail -20 "$out/build-a.log"; exit 2; }
lazbuild -B tools/painter-regress/painterregress.lpi > "$out/build-b.log" 2>&1 || { tail -20 "$out/build-b.log"; exit 2; }
A="$wt/tools/painter-regress/painterregress.exe"
B="tools/painter-regress/painterregress.exe"
[ -x "$A" ] || A="$wt/tools/painter-regress/painterregress"
[ -x "$B" ] || B="tools/painter-regress/painterregress"

echo "A: the hashes"
"$A" --hashes "$out/hashes-a.txt" "${onlyArgs[@]}" > "$out/run-a.log" 2>&1 || { tail -5 "$out/run-a.log"; exit 2; }
echo "B: the check"
"$B" --check "$out/hashes-a.txt" "${onlyArgs[@]}" > "$out/run-b.log" 2>&1
code=$?
tail -3 "$out/run-b.log"
if [ $code -eq 2 ]; then exit 2; fi
result=$code

if [ "$rounds" -gt 0 ]; then
  echo "timing: $rounds rounds a side, alternately"
  la=""; lb=""
  for i in $(seq 1 "$rounds"); do
    "$A" --perf --perf-out "$out/perf-a-$i.txt" > "$out/perf-a-$i.log" 2>&1 || exit 2
    "$B" --perf --perf-out "$out/perf-b-$i.txt" > "$out/perf-b-$i.log" 2>&1 || exit 2
    la="$la${la:+,}$out/perf-a-$i.txt"; lb="$lb${lb:+,}$out/perf-b-$i.txt"
  done
  "$B" --perf-compare "$la" "$lb" | tee "$out/perf-compare.md"
fi
exit $result
