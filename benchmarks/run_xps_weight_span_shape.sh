#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=7f9237f7c4be993b7ac987a46f40d05bde8355c8
candidate=79e74b0599953172326ec5652ce4e9c8d1b9ee97
cpu=${1:-0}
cycles=${2:-3}
rounds=${3:-7}
target_ms=${4:-50}

if [[ -n "$(git status --porcelain -- source benchmarks tools)" ]]; then
  echo "ERROR: source/benchmarks/tools differ from HEAD" >&2
  exit 1
fi

git cat-file -e "${base}^{commit}"
git cat-file -e "${candidate}^{commit}"

if ! git merge-base --is-ancestor "$candidate" HEAD; then
  echo "ERROR: HEAD does not contain pinned candidate" >&2
  exit 1
fi

mkdir -p build
task_dir=$(mktemp -d "$root/build/weight-span-shape-xps.XXXXXXXX")

{
  printf 'head: %s\n' "$(git rev-parse HEAD)"
  printf 'base: %s\n' "$(git rev-parse "$base")"
  printf 'candidate: %s\n' "$(git rev-parse "$candidate")"
  printf 'cpu: %s\n' "$cpu"
  printf 'cycles: %s\n' "$cycles"
  printf 'rounds: %s\n' "$rounds"
  printf 'target_ms: %s\n' "$target_ms"
  git status --short --branch
} | tee "$task_dir/provenance.log"

dub test --compiler=dmd 2>&1 | tee "$task_dir/dub-test-dmd.log"
dub test --compiler=ldc2 2>&1 | tee "$task_dir/dub-test-ldc2.log"

python3 benchmarks/run_segment_polygon_prebuilt_abba.py \
  --base="$base" \
  --candidate="$candidate" \
  --cpu="$cpu" \
  --cycles="$cycles" \
  --rounds="$rounds" \
  --target-ms="$target_ms" \
  --output="$task_dir/record" \
  | tee "$task_dir/run.log"

tar --exclude=benchmark --exclude='*.o' \
  -czf "$task_dir/geo-weight-span-shape-xps.tar.gz" \
  -C "$task_dir" \
  record run.log provenance.log dub-test-dmd.log dub-test-ldc2.log

sha256sum "$task_dir/geo-weight-span-shape-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-weight-span-shape-xps.tar.gz"
