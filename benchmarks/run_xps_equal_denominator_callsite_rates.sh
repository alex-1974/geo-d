#!/usr/bin/env bash
set -euo pipefail
root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"
cpu=${1:-0}
mkdir -p build
task=$(mktemp -d "$root/build/equal-denominator-callsite-rates-xps.XXXXXXXX")
dub test --compiler=dmd 2>&1 | tee "$task/dub-test-dmd.log"
python3 benchmarks/profile_equal_denominator_callsites.py --cpu="$cpu" --output="$task/record" | tee "$task/run.log"
tar -czf "$task/geo-equal-denominator-callsite-rates-xps.tar.gz" -C "$task" record run.log dub-test-dmd.log
sha256sum "$task/geo-equal-denominator-callsite-rates-xps.tar.gz"
printf 'Archive: %s\n' "$task/geo-equal-denominator-callsite-rates-xps.tar.gz"
