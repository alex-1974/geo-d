#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/../../../.." rev-parse --show-toplevel)
cd "$root"

cpu=${1:-0}
notes=${2:-"XPS GEOS work-attribution mechanism run; otherwise idle."}
iterations=${3:-50}

mkdir -p build
task_dir=$(mktemp -d "$root/build/geos-work-probe-xps.XXXXXXXX")
record="$task_dir/record"
archive="$task_dir/geo-geos-work-probe-xps.tar.gz"

python3 -m py_compile \
    benchmarks/segment-polygon/reference/geos-work-probe/apply_geos_work_probe.py \
    benchmarks/segment-polygon/reference/geos-work-probe/analyze_geos_work_probe.py \
    benchmarks/segment-polygon/reference/geos-work-probe/run_geos_work_probe.py

python3 benchmarks/segment-polygon/reference/geos-work-probe/run_geos_work_probe.py \
    --cpu="$cpu" \
    --iterations="$iterations" \
    --notes="$notes" \
    --output="$record"

tar \
    --exclude='record/work' \
    -czf "$archive" \
    -C "$task_dir" \
    record

sha256sum "$archive"
printf 'Record:  %s\n' "$record"
printf 'Archive: %s\n' "$archive"
printf '\n=== SUMMARY ===\n'
cat "$record/summary.md"
