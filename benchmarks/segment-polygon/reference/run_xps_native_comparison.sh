#!/usr/bin/env bash
# Run from any directory; preserve the complete measurement record and archive.
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "$repo_root"
cpu=${1:-0}
notes=${2:-"Power/turbo/background settings not attested."}
mkdir -p "$repo_root/build"
task_dir=$(mktemp -d "$repo_root/build/native-xps.XXXXXXXX")
python3 -m venv "$task_dir/venv"
"$task_dir/venv/bin/pip" install --only-binary=:all: -r benchmarks/segment-polygon/reference/requirements.txt
"$task_dir/venv/bin/python" benchmarks/segment-polygon/reference/prepare_geos_wheel.py --output="$task_dir/headers"
native_lib=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["library"])' "$task_dir/headers/installation.json")
python3 benchmarks/segment-polygon/reference/run_native_comparison.py \
    --compiler=dmd --compiler=ldc2 --cpu="$cpu" --rounds=7 --target-ms=20 \
    --geos-header="$task_dir/headers/geos_c.h" --geos-library="$native_lib" \
    --notes="$notes" --output="$task_dir/record"
archive="$task_dir/geo-native-xps.tar.gz"
# Exclude only regenerable executables and objects; all provenance/raw data stays.
tar -czf "$archive" --exclude='*/native' --exclude='*/native-debug' \
    --exclude='*/preflight' --exclude='*/benchmark' --exclude='*.o' \
    -C "$task_dir" record
sha256sum "$archive"
printf 'record: %s\narchive: %s\n' "$task_dir/record" "$archive"
