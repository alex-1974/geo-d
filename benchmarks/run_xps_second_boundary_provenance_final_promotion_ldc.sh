#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=${1:?base commit required}
candidate=${2:?candidate commit required}
cpu=${3:-6}
cycles=${4:-8}
rounds=${5:-9}
target_ms=${6:-75}
notes=${7:-"final LDC second-boundary promotion confirmation"}

mkdir -p build
task_dir=$(mktemp -d "/var/tmp/geo-d-second-boundary-final-promotion-ldc.XXXXXXXX")
archive="$root/build/geo-second-boundary-final-promotion-ldc-xps.tar.gz"

preserve_result()
{
  status=$?
  if [[ -d "$task_dir" ]]; then
    tar \
      --exclude='benchmark' \
      --exclude='*.o' \
      -czf "$task_dir/geo-second-boundary-final-promotion-ldc-xps.tar.gz" \
      -C "$task_dir" \
      $( [[ -e "$task_dir/record" ]] && printf '%s ' record ) \
      $( [[ -e "$task_dir/run.log" ]] && printf '%s ' run.log ) \
      2>/dev/null || true

    if [[ -f "$task_dir/geo-second-boundary-final-promotion-ldc-xps.tar.gz" ]]; then
      cp "$task_dir/geo-second-boundary-final-promotion-ldc-xps.tar.gz" "$archive" || true
      sha256sum "$archive" 2>/dev/null || true
      printf 'Archive: %s\n' "$archive"
    else
      printf 'No archive could be created. Temporary data: %s\n' "$task_dir" >&2
    fi
  fi
  return "$status"
}
trap preserve_result EXIT

python3 benchmarks/run_second_boundary_provenance_final_promotion_ldc_abba.py \
  --base="$base" \
  --candidate="$candidate" \
  --cpu="$cpu" \
  --cycles="$cycles" \
  --rounds="$rounds" \
  --target-ms="$target_ms" \
  --notes="$notes" \
  --output="$task_dir/record" \
  | tee "$task_dir/run.log"
