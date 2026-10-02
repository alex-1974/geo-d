#!/usr/bin/env bash
set -euo pipefail
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$root"
base=4828889625ff2dd25b44dc545a5e9addb27310ef
candidate=53799edca99856644a1c520f25b9e37293263f0a
cpu=${1:-0}
notes=${2:-Power/turbo/background settings not attested.}
git fetch origin perf/clipping-equal-denominator perf/clipping-equal-denominator-dmd-equality
mkdir -p build
task_dir=$(mktemp -d "$root/build/equal-denominator-dmd-equality-xps.XXXXXXXX")
python3 benchmarks/run_segment_polygon_comparison.py \
    --base="$base" --candidate="$candidate" --cpu="$cpu" \
    --compiler=dmd --compiler=ldc2 --blocks=2 --rounds=7 --target-ms=20 \
    --notes="$notes" --output="$task_dir/record"
tar --exclude=benchmark --exclude=preflight --exclude='*.o' \
    -czf "$task_dir/geo-equal-denominator-dmd-equality-xps.tar.gz" -C "$task_dir" record
sha256sum "$task_dir/geo-equal-denominator-dmd-equality-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-equal-denominator-dmd-equality-xps.tar.gz"
