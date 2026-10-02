#!/usr/bin/env bash
set -euo pipefail
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$root"
base=7deb69f074208ddabe2b18316820965b16cf2966
candidate=4828889625ff2dd25b44dc545a5e9addb27310ef
cpu=${1:-0}
notes=${2:-Power/turbo/background settings not attested.}
git fetch origin develop perf/clipping-equal-denominator
mkdir -p build
task_dir=$(mktemp -d "$root/build/equal-denominator-xps.XXXXXXXX")
python3 benchmarks/run_segment_polygon_comparison.py \
    --base="$base" --candidate="$candidate" --cpu="$cpu" \
    --compiler=dmd --compiler=ldc2 --blocks=2 --rounds=7 --target-ms=20 \
    --notes="$notes" --output="$task_dir/record"
tar --exclude=benchmark --exclude=preflight --exclude='*.o' \
    -czf "$task_dir/geo-equal-denominator-xps.tar.gz" -C "$task_dir" record
sha256sum "$task_dir/geo-equal-denominator-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-equal-denominator-xps.tar.gz"
