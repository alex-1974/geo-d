#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"

cpu=${1:-6}
rounds=${2:-7}
iterations=${3:-1000}
notes=${4:-"XPS post-#166 LDC double boundary attribution"}

mkdir -p build
task_dir=$(mktemp -d "/var/tmp/geo-d-double-boundary-attribution.XXXXXXXX")
archive="$root/build/geo-post166-double-boundary-attribution-xps.tar.gz"

preserve_result()
{
    status=$?

    tar \
        --exclude='double-boundary-attribution' \
        --exclude='*.o' \
        -czf "$task_dir/archive.tar.gz" \
        -C "$task_dir" \
        $( [[ -e "$task_dir/record" ]] && printf '%s ' record ) \
        $( [[ -e "$task_dir/run.log" ]] && printf '%s ' run.log ) \
        $( [[ -e "$task_dir/dub-test-ldc2.log" ]] && printf '%s ' dub-test-ldc2.log ) \
        2>/dev/null || true

    if [[ -f "$task_dir/archive.tar.gz" ]]; then
        cp "$task_dir/archive.tar.gz" "$archive" || true
        sha256sum "$archive" 2>/dev/null || true
        printf 'Archive: %s\n' "$archive"
    fi

    return "$status"
}
trap preserve_result EXIT

echo "=== PROVENANCE ==="
git status --short --branch
git rev-parse HEAD
git log -1 --oneline --decorate

echo
echo "=== UNIT TESTS LDC ==="
dub test --compiler=ldc2 --force 2>&1 | tee "$task_dir/dub-test-ldc2.log"

echo
echo "=== DOUBLE BOUNDARY ATTRIBUTION ==="
python3 benchmarks/run_double_boundary_attribution.py \
    --cpu="$cpu" \
    --rounds="$rounds" \
    --iterations="$iterations" \
    --notes="$notes" \
    --output="$task_dir/record" \
    | tee "$task_dir/run.log"
