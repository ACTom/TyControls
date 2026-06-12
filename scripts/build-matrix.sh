#!/usr/bin/env bash
# TyControls cross-platform build matrix.
# Run on each target host (Windows/Linux/macOS); lazbuild selects the
# host widgetset by default. Override with TY_WS to force a widgetset.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WS="${TY_WS:-}"
WS_ARG=""
if [ -n "$WS" ]; then
  WS_ARG="--ws=$WS"
fi

echo "== TyControls build matrix =="
echo "Root: $ROOT"
echo "Widgetset override: ${WS:-<host default>}"

echo "-- runtime package --"
lazbuild $WS_ARG "$ROOT/tycontrols.lpk"

echo "-- design-time package --"
lazbuild $WS_ARG "$ROOT/tycontrols_dt.lpk"

echo "-- demo project --"
lazbuild $WS_ARG "$ROOT/examples/demo/demo.lpi"

echo "-- test runner --"
lazbuild $WS_ARG "$ROOT/tests/tytests.lpr"

echo "== matrix OK =="
