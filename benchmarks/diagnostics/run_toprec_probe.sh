#!/usr/bin/env bash
set -euo pipefail

cd "${1:-$HOME/Programmiersprachen/dlang/d-geospatial/libs/geo-d}"

BENCH=benchmarks/expansion_component_bench.d
BASE_BIN=/tmp/geo-d-expansion-toprec-prod
DIRECT_BIN=/tmp/geo-d-expansion-toprec-direct
TMP=/tmp/geo-d-toprec-probe

rm -rf "$TMP"
mkdir -p "$TMP"
cp -a source "$TMP/source"

python3 - "$TMP" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]) / "source" / "geo" / "internal"

replacements = {
    root / "expansion.d": {
        "return toPrec!double(lhs + rhs);": "return lhs + rhs;",
        "return toPrec!double(lhs - rhs);": "return lhs - rhs;",
        "return toPrec!double(lhs * rhs);": "return lhs * rhs;",
    },
    root / "orientation_exact.d": {
        "return toPrec!double(lhs - rhs);": "return lhs - rhs;",
    },
}

for path, reps in replacements.items():
    text = path.read_text()
    before = text

    for old, new in reps.items():
        if old not in text:
            raise SystemExit(f"expected text not found in {path}: {old}")
        text = text.replace(old, new)

    if text == before:
        raise SystemExit(f"no replacements made in {path}")

    path.write_text(text)
PY

printf '\n=== diagnostic patch ===\n'
grep -nE \
    'return (lhs \+ rhs|lhs - rhs|lhs \* rhs);' \
    "$TMP/source/geo/internal/expansion.d" \
    "$TMP/source/geo/internal/orientation_exact.d"

printf '\n=== build production ===\n'
ldc2 \
    -O3 \
    -release \
    -boundscheck=off \
    -mcpu=native \
    -i \
    -Isource \
    "$BENCH" \
    -of="$BASE_BIN"

printf '\n=== build diagnostic direct-arithmetic copy ===\n'
ldc2 \
    -O3 \
    -release \
    -boundscheck=off \
    -mcpu=native \
    -i \
    -I"$TMP/source" \
    "$BENCH" \
    -of="$DIRECT_BIN"

printf '\n=== verify toPrec references ===\n'
printf 'production references:\n'
nm -n "$BASE_BIN" | grep 'toPrec' || true
printf '\ndiagnostic references:\n'
nm -n "$DIRECT_BIN" | grep 'toPrec' || true

CPU=2
SIBLING=8

PSTATE=/sys/devices/system/cpu/intel_pstate
CPU_PATH=/sys/devices/system/cpu/cpu${CPU}/cpufreq
SIBLING_ONLINE=/sys/devices/system/cpu/cpu${SIBLING}/online

old_turbo="$(cat "$PSTATE/no_turbo")"
old_gov="$(cat "$CPU_PATH/scaling_governor")"
old_epp="$(cat "$CPU_PATH/energy_performance_preference")"
old_sibling_online="$(cat "$SIBLING_ONLINE")"

restore_cpu()
{
    printf '%s\n' "$old_sibling_online" |
        sudo tee "$SIBLING_ONLINE" >/dev/null

    printf '%s\n' "$old_gov" |
        sudo tee "$CPU_PATH/scaling_governor" >/dev/null

    printf '%s\n' "$old_epp" |
        sudo tee "$CPU_PATH/energy_performance_preference" >/dev/null

    printf '%s\n' "$old_turbo" |
        sudo tee "$PSTATE/no_turbo" >/dev/null
}

trap restore_cpu EXIT

printf '0\n' |
    sudo tee "$SIBLING_ONLINE" >/dev/null

printf 'performance\n' |
    sudo tee "$CPU_PATH/scaling_governor" >/dev/null

printf 'performance\n' |
    sudo tee "$CPU_PATH/energy_performance_preference" >/dev/null

printf '1\n' |
    sudo tee "$PSTATE/no_turbo" >/dev/null

run_one()
{
    label="$1"
    bin="$2"

    printf '\n--- %s ---\n' "$label"
    printf 'freq: '
    cat "$CPU_PATH/scaling_cur_freq" 2>/dev/null || true

    taskset -c "$CPU" "$bin" |
        grep -E \
            '^(twoSum|twoDiff|fastTwoSum|twoProduct|scaleExpansion|fastExpansionSum|orientation exact)'
}

for round in 1 2 3 4
do
    printf '\n================ ROUND %s ================\n' "$round"

    if (( round % 2 == 1 )); then
        run_one PROD_TOPREC "$BASE_BIN"
        run_one DIRECT_DIAGNOSTIC "$DIRECT_BIN"
    else
        run_one DIRECT_DIAGNOSTIC "$DIRECT_BIN"
        run_one PROD_TOPREC "$BASE_BIN"
    fi
done
