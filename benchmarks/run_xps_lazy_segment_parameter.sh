#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

cpu=${1:-0}
rounds=${2:-7}
target_ms=${3:-50}

if [[ -n "$(git status --porcelain -- source benchmarks tools)" ]]; then
  echo "ERROR: source/benchmarks/tools differ from HEAD" >&2
  git status --short --untracked-files=all -- source benchmarks tools >&2
  exit 1
fi

mkdir -p build
task_dir=$(mktemp -d "$root/build/lazy-segment-parameter-xps.XXXXXXXX")
record="$task_dir/record"
archive="$task_dir/geo-lazy-segment-parameter-xps.tar.gz"

PYTHONPYCACHEPREFIX="$task_dir/pycache" python3 -m py_compile \
  benchmarks/run_lazy_segment_parameter.py

python3 benchmarks/run_lazy_segment_parameter.py \
  --compiler=dmd \
  --compiler=ldc2 \
  --cpu="$cpu" \
  --rounds="$rounds" \
  --target-ms="$target_ms" \
  --output="$record"

tar \
  --exclude='record/probe-dmd' \
  --exclude='record/probe-ldc2' \
  --exclude='record/*.o' \
  -czf "$archive" \
  -C "$task_dir" \
  record

sha256sum "$archive"
printf 'Record:  %s\n' "$record"
printf 'Archive: %s\n' "$archive"
