#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=${1:?base commit required}
candidate=${2:?candidate commit required}
cpu=${3:-0}
cycles=${4:-6}
rounds=${5:-7}
target_ms=${6:-50}
notes=${7:-"shared-isolated outer boundary specialization"}

mkdir -p build
task_dir=$(mktemp -d "/var/tmp/geo-d-second-boundary-shared-xps.XXXXXXXX")
archive="$root/build/geo-second-boundary-shared-xps.tar.gz"

python3 benchmarks/run_second_boundary_provenance_shared_abba.py \
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
  --exclude='*.so' \
  -czf "$task_dir/geo-second-boundary-shared-xps.tar.gz" \
  -C "$task_dir" \
  record \
  run.log

cp "$task_dir/geo-second-boundary-shared-xps.tar.gz" "$archive"
sha256sum "$archive"
printf 'Archive: %s\n' "$archive"
