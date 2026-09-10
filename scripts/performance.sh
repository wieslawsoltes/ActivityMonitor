#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="${1:-.build/performance}"
mkdir -p "$OUTPUT"
# Profiling overrides must never silently weaken a gating run.
unset AM_PERFORMANCE_CASE AM_PERFORMANCE_ITERATIONS AM_RENDER_DIR
AM_PERFORMANCE=1 swift test -c release --filter PerformanceTests > "$OUTPUT/tests.log" 2>&1 || {
  cat "$OUTPUT/tests.log"
  exit 1
}
python3 scripts/check-performance.py "$OUTPUT/tests.log" "$OUTPUT/results.json"
