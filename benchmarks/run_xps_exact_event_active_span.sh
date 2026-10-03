#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

cpu=${1:-0}
rounds=${2:-7}
target_ms=${3:-50}

mkdir -p build
task_dir=$(mktemp -d "$root/build/exact-event-active-span-xps.XXXXXXXX")
record="$task_dir/record"
archive="$task_dir/geo-exact-event-active-span-xps.tar.gz"

PYTHONPYCACHEPREFIX="$task_dir/pycache" python3 -m py_compile     benchmarks/run_exact_event_active_span.py

python3 benchmarks/run_exact_event_active_span.py     --compiler=dmd     --compiler=ldc2     --cpu="$cpu"     --rounds="$rounds"     --target-ms="$target_ms"     --output="$record"

tar     --exclude='record/probe-dmd'     --exclude='record/probe-ldc2'     -czf "$archive"     -C "$task_dir"     record

sha256sum "$archive"
printf 'Record:  %s\n' "$record"
printf 'Archive: %s\n' "$archive"
