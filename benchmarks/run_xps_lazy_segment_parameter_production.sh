#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

base=7f9237f7c4be993b7ac987a46f40d05bde8355c8
candidate=0ee5bfad156e7f12349bb0ef71754254b787f1b7
cpu=${1:-0}
cycles=${2:-3}
rounds=${3:-7}
target_ms=${4:-50}

if [[ -n "$(git status --porcelain -- source benchmarks tools)" ]]; then
  echo "ERROR: source/benchmarks/tools differ from HEAD; qualifying evidence requires a clean checkout." >&2
  git status --short --untracked-files=all -- source benchmarks tools >&2
  exit 1
fi

git cat-file -e "${base}^{commit}"
git cat-file -e "${candidate}^{commit}"

if ! git merge-base --is-ancestor "$candidate" HEAD; then
  echo "ERROR: current HEAD does not contain pinned candidate $candidate" >&2
  exit 1
fi

mkdir -p build
task_dir=$(mktemp -d "$root/build/lazy-segment-parameter-production-xps.XXXXXXXX")

{
  echo "=== PROVENANCE ==="
  printf 'head:      %s\n' "$(git rev-parse HEAD)"
  printf 'base:      %s\n' "$(git rev-parse "$base")"
  printf 'candidate: %s\n' "$(git rev-parse "$candidate")"
  printf 'cpu:       %s\n' "$cpu"
  printf 'cycles:    %s\n' "$cycles"
  printf 'rounds:    %s\n' "$rounds"
  printf 'target_ms: %s\n' "$target_ms"
  echo
  git status --short --branch
} | tee "$task_dir/provenance.log"

echo
echo "=== UNIT TESTS DMD ==="
dub test --compiler=dmd 2>&1 | tee "$task_dir/dub-test-dmd.log"

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2 2>&1 | tee "$task_dir/dub-test-ldc2.log"

echo
echo "=== PREBUILT ABBA ==="
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
  -czf "$task_dir/geo-lazy-segment-parameter-production-xps.tar.gz" \
  -C "$task_dir" \
  record run.log provenance.log dub-test-dmd.log dub-test-ldc2.log

sha256sum "$task_dir/geo-lazy-segment-parameter-production-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-lazy-segment-parameter-production-xps.tar.gz"
