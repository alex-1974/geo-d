#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

cpu=${1:-0}
rounds=${2:-7}
target_ms=${3:-50}

mkdir -p build
task_dir=$(mktemp -d "$root/build/dense-event-provenance-cost-xps.XXXXXXXX")

python3 benchmarks/run_dense_event_provenance_cost.py \
  --cpu="$cpu" \
  --rounds="$rounds" \
  --target-ms="$target_ms" \
  --output="$task_dir/record" \
  | tee "$task_dir/run.log"

tar --exclude='probe-*' \
  -czf "$task_dir/geo-dense-event-provenance-cost-xps.tar.gz" \
  -C "$task_dir" record run.log

sha256sum "$task_dir/geo-dense-event-provenance-cost-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-dense-event-provenance-cost-xps.tar.gz"
