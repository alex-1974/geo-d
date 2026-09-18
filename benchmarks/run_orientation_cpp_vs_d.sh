#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${1:-$(cd "$script_dir/.." && pwd)}"
cd "$repo_root"

CPP_SOURCE=benchmarks/reference/cpp/orientation_robust_double_bench.cpp
D_BIN=/tmp/geo-d-orientation-fair-ldc
CPP_BIN=/tmp/geo-d-orientation-robust-double-cpp

printf '\n=== toolchains ===\n'
ldc2 --version | head -n 3
g++ --version | head -n 1

printf '\n=== build D/LDC current tree ===\n'
ldc2 \
    -O3 \
    -release \
    -boundscheck=off \
    -mcpu=native \
    -i \
    -Isource \
    benchmarks/orientation_bench.d \
    -of="$D_BIN"

printf '\n=== build algorithm-equivalent C++ ===\n'
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

printf '\n=== C++ structural check ===\n'
nm -S -n -C "$CPP_BIN" |
    grep -E \
        'orientation_filter|try_orientation_exact_expansion|orientation_determinant_dyadic|robust_double_fallback|build_difference|multiply_difference_expansions|fast_expansion_sum_zero_elim|scale_expansion_zero_elim|multiply_unsigned|decode_binary64_coordinate|subtract_dyadic_coordinates|subtract_dyadic_products'

printf '\n=== C++ self-test / smoke run ===\n'
"$CPP_BIN" >/tmp/geo-d-cpp-robust-smoke.txt
head -n 10 /tmp/geo-d-cpp-robust-smoke.txt

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
        grep -E '^double (filter fast|expansion|dyadic)'
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
