#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=${1:?base commit required}
candidate=${2:?candidate commit required}
cpu=${3:-6}
cycles=${4:-6}
rounds=${5:-7}
target_ms=${6:-50}
notes=${7:-"broad static ABI bridge validation"}

mkdir -p build
task_dir=$(mktemp -d "/var/tmp/geo-d-second-boundary-static-broad.XXXXXXXX")
archive="$root/build/geo-second-boundary-static-broad-xps.tar.gz"

python3 benchmarks/run_second_boundary_provenance_static_broad_abba.py \
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
  -czf "$task_dir/geo-second-boundary-static-broad-xps.tar.gz" \
  -C "$task_dir" \
  record \
  run.log

cp "$task_dir/geo-second-boundary-static-broad-xps.tar.gz" "$archive"
sha256sum "$archive"
printf 'Archive: %s\n' "$archive"
