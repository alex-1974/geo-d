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
notes=${7:-"XPS small boundary contact reuse ABBA"}

mkdir -p build
task_dir=$(mktemp -d "/var/tmp/geo-d-small-boundary-contact-xps.XXXXXXXX")
archive="$root/build/geo-small-boundary-contact-xps.tar.gz"

echo "=== PROVENANCE ==="
git status --short --branch
git rev-parse HEAD
git log -1 --oneline --decorate

echo
echo "=== ABBA ==="
python3 benchmarks/run_small_boundary_contact_abba.py   --base="$base"   --candidate="$candidate"   --cpu="$cpu"   --cycles="$cycles"   --rounds="$rounds"   --target-ms="$target_ms"   --notes="$notes"   --output="$task_dir/record"   | tee "$task_dir/run.log"

tar   --exclude='benchmark'   --exclude='*.o'   -czf "$task_dir/geo-small-boundary-contact-xps.tar.gz"   -C "$task_dir"   record   run.log

cp "$task_dir/geo-small-boundary-contact-xps.tar.gz" "$archive"
sha256sum "$archive"
printf 'Scratch: %s\n' "$task_dir"
printf 'Archive: %s\n' "$archive"
