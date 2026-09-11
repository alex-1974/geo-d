#!/usr/bin/env bash
set -euo pipefail

cd "${1:-$HOME/Programmiersprachen/dlang/d-geospatial/libs/geo-d}"

D_SOURCE=benchmarks/expansion_component_bench.d
CPP_SOURCE=benchmarks/reference/cpp/expansion_component_bench.cpp

D_BIN=/tmp/geo-d-expansion-components-ldc
CPP_BIN=/tmp/geo-d-expansion-components-cpp

printf '\n=== toolchains ===\n'
ldc2 --version | head -n 3
g++ --version | head -n 1

printf '\n=== build D/LDC ===\n'
ldc2 \
    -O3 \
    -release \
    -boundscheck=off \
    -mcpu=native \
    -i \
    -Isource \
    "$D_SOURCE" \
    -of="$D_BIN"

printf '\n=== build C++ ===\n'
g++ \
    -O3 \
    -DNDEBUG \
    -march=native \
    -ffp-contract=off \
    -fno-fast-math \
    -fno-stack-protector \
    -std=c++20 \
    "$CPP_SOURCE" \
    -o "$CPP_BIN"

printf '\n=== structural symbols: D ===\n'
nm -S -n "$D_BIN" |
    grep -E \
        'twoSum|twoDiff|fastTwoSum|twoProduct|scaleExpansionZeroElim|fastExpansionSumZeroElim|tryOrientationExactExpansion' ||
    true

printf '\n=== structural symbols: C++ ===\n'
nm -S -n -C "$CPP_BIN" |
    grep -E \
        'two_sum|two_diff|fast_two_sum|two_product|scale_expansion_zero_elim|fast_expansion_sum_zero_elim|try_orientation_exact_expansion' ||
    true

printf '\n=== smoke ===\n'
"$D_BIN" | head -n 12
"$CPP_BIN" | head -n 12

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
        run_one D_LDC "$D_BIN"
        run_one CPP "$CPP_BIN"
    else
        run_one CPP "$CPP_BIN"
        run_one D_LDC "$D_BIN"
    fi
done
