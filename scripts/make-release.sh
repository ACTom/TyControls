#!/usr/bin/env bash
#
# Build a TyControls release bundle for a GitHub release (macOS / Linux).
# Bash twin of scripts/make-release.ps1 — same manifest, same output.
#
# Ships ONLY what a consumer needs (runtime + design-time source, the Lazarus
# packages, themes, user docs, examples) laid out as in the repo so the .lpk files
# install unchanged. Excludes tests, tools/ (icon generator), scripts/,
# docs/superpowers (specs/plans), designtime/icons (the packed .lrs ships instead),
# the auto-generated package units, and every build artifact.
#
# Output: dist/TyControls-<version>.zip  (dist/ is git-ignored).
# Usage:  bash scripts/make-release.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- version (single source of truth) --------------------------------------
VERSION="$(sed -nE "s/.*TyVersion[[:space:]]*=[[:space:]]*'([^']+)'.*/\1/p" \
  "$ROOT/source/tyControls.Types.pas" | head -1)"
[ -n "$VERSION" ] || { echo "ERROR: could not read TyVersion from source/tyControls.Types.pas" >&2; exit 1; }
echo "== TyControls release v$VERSION =="

# --- staging ---------------------------------------------------------------
DIST="$ROOT/dist"
STAGE="$DIST/TyControls-$VERSION"
ZIP="$DIST/TyControls-$VERSION.zip"
rm -rf "$STAGE" "$ZIP" "$DIST/TyControls-$VERSION.tar.gz"
mkdir -p "$STAGE"

# copy one file, preserving its relative path under STAGE
add_file() {
  local rel="$1"
  if [ -f "$ROOT/$rel" ]; then
    mkdir -p "$STAGE/$(dirname "$rel")"
    cp "$ROOT/$rel" "$STAGE/$rel"
  else
    echo "  (skip, not found: $rel)"
  fi
}

# copy a tree by extension, skipping lib/backup/.git dirs and an optional path pattern
# usage: add_tree <subdir> <skip-regex-or-empty> <ext> [ext ...]
add_tree() {
  local srcrel="$1"; local skip="$2"; shift 2
  local e f rel
  for e in "$@"; do
    find "$ROOT/$srcrel" -type f -name "*.$e" 2>/dev/null | while IFS= read -r f; do
      rel="${f#"$ROOT"/}"
      case "/$rel/" in */lib/*|*/backup/*|*/.git/*) continue ;; esac
      if [ -n "$skip" ] && printf '/%s/' "$rel" | grep -qE "$skip"; then continue; fi
      mkdir -p "$STAGE/$(dirname "$rel")"
      cp "$f" "$STAGE/$rel"
    done
  done
}

echo "-- root + packages"
add_file README.md
add_file README.en.md
add_file CHANGELOG.md
add_file CHANGELOG.zh-CN.md
add_file COPYING.LGPL.txt
add_file COPYING.modifiedLGPL.txt
add_file tycontrols.lpk
add_file tycontrols_dt.lpk

echo "-- runtime source"
add_tree source "" pas inc

echo "-- design-time (Design unit + packed icons .lrs; NOT the png source)"
add_file designtime/tyControls.Design.pas
add_file designtime/tycontrols_icons.lrs

echo "-- themes"
add_tree themes "" tycss

echo "-- docs (excluding docs/superpowers)"
add_tree docs "/superpowers/" md png svg gif

echo "-- examples (source only)"
add_tree examples "" pas lpr lpi lfm ico tycss inc

# --- archive ---------------------------------------------------------------
echo "-- archiving"
cd "$DIST"
if command -v zip >/dev/null 2>&1; then
  zip -rq "TyControls-$VERSION.zip" "TyControls-$VERSION"
else
  echo "  zip not found — falling back to tar.gz" >&2
  tar czf "TyControls-$VERSION.tar.gz" "TyControls-$VERSION"
  ZIP="$DIST/TyControls-$VERSION.tar.gz"
fi
rm -rf "$STAGE"   # keep dist/ tidy: just the archive

SIZE="$(du -k "$ZIP" | cut -f1)"
echo ""
echo "Wrote $ZIP (${SIZE} KB)"
echo "Upload this to the GitHub release for v$VERSION."
