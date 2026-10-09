#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=${1:?base commit required}
candidate=${2:?candidate commit required}
cpu=${3:-6}
cycles=${4:-3}
rounds=${5:-5}
target_ms=${6:-25}
notes=${7:-"quick LDC refargs provenance gate"}

mkdir -p build
task_dir=$(mktemp -d "/var/tmp/geo-d-second-boundary-quick-ldc.XXXXXXXX")
archive="$root/build/geo-second-boundary-quick-ldc-xps.tar.gz"

python3 benchmarks/run_second_boundary_provenance_quick_ldc_abba.py \
  --base="$base" \
  --candidate="$candidate" \
  --cpu="$cpu" \
  --cycles="$cycles" \
  --rounds="$rounds" \
  --target-ms="$target_ms" \
  --notes="$notes" \
  --output="$task_dir/record" \
  | tee "$task_dir/run.log"

tar \
  --exclude='benchmark' \
  --exclude='*.o' \
  -czf "$task_dir/geo-second-boundary-quick-ldc-xps.tar.gz" \
  -C "$task_dir" \
  record \
  run.log

cp "$task_dir/geo-second-boundary-quick-ldc-xps.tar.gz" "$archive"
sha256sum "$archive"
printf 'Archive: %s\n' "$archive"
