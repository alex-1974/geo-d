#!/usr/bin/env bash
set -euo pipefail

cd "${1:-$HOME/Programmiersprachen/dlang/d-geospatial/libs/geo-d}"

BENCH=benchmarks/expansion_component_bench.d

PROD_BIN=/tmp/geo-d-expansion-rounding-prod
DIRECT_BIN=/tmp/geo-d-expansion-rounding-direct
IR_BIN=/tmp/geo-d-expansion-rounding-ir

TMP=/tmp/geo-d-ir-rounding-probe
rm -rf "$TMP"
mkdir -p "$TMP/direct" "$TMP/ir"

cp -a source "$TMP/direct/source"
cp -a source "$TMP/ir/source"

python3 - "$TMP" <<'PY'
from pathlib import Path
import sys

tmp = Path(sys.argv[1])

def replace_all(path, replacements, label):
    text = path.read_text()
    for old, new in replacements:
        if old not in text:
            raise SystemExit(f"{label}: expected text not found in {path}: {old}")
        text = text.replace(old, new)
    path.write_text(text)

direct_root = tmp / "direct" / "source" / "geo" / "internal"

replace_all(
    direct_root / "expansion.d",
    [
        ("return toPrec!double(lhs + rhs);", "return lhs + rhs;"),
        ("return toPrec!double(lhs - rhs);", "return lhs - rhs;"),
        ("return toPrec!double(lhs * rhs);", "return lhs * rhs;"),
    ],
    "direct expansion",
)

replace_all(
    direct_root / "orientation_exact.d",
    [
        ("return toPrec!double(lhs - rhs);", "return lhs - rhs;"),
    ],
    "direct orientation",
)

ir_root = tmp / "ir" / "source" / "geo" / "internal"

ir_add = "\n".join([
    "return __ir_pure!(",
    "        `%r = fadd double %0, %1",
    "         ret double %r`,",
    "        double",
    "    )(lhs, rhs);",
])

ir_sub = "\n".join([
    "return __ir_pure!(",
    "        `%r = fsub double %0, %1",
    "         ret double %r`,",
    "        double",
    "    )(lhs, rhs);",
])

ir_mul = "\n".join([
    "return __ir_pure!(",
    "        `%r = fmul double %0, %1",
    "         ret double %r`,",
    "        double",
    "    )(lhs, rhs);",
])

expansion = ir_root / "expansion.d"
replace_all(
    expansion,
    [
        ("import core.math : toPrec;", "import ldc.llvmasm : __ir_pure;"),
        ("return toPrec!double(lhs + rhs);", ir_add),
        ("return toPrec!double(lhs - rhs);", ir_sub),
        ("return toPrec!double(lhs * rhs);", ir_mul),
    ],
    "IR expansion",
)

orientation = ir_root / "orientation_exact.d"
replace_all(
    orientation,
    [
        ("import core.math : toPrec;", "import ldc.llvmasm : __ir_pure;"),
        ("return toPrec!double(lhs - rhs);", ir_sub),
    ],
    "IR orientation",
)
PY

cat > "$TMP/ir_semantic_probe.d" <<'D'
module ir_semantic_probe;

import core.math : toPrec;
import ldc.llvmasm : __ir_pure;
import std.stdio : writeln, writefln;

private double irAdd(double a, double b)
    pure nothrow @safe @nogc
{
    return __ir_pure!(
        `%r = fadd double %0, %1
         ret double %r`,
        double
    )(a, b);
}

private double irSub(double a, double b)
    pure nothrow @safe @nogc
{
    return __ir_pure!(
        `%r = fsub double %0, %1
         ret double %r`,
        double
    )(a, b);
}

private double irMul(double a, double b)
    pure nothrow @safe @nogc
{
    return __ir_pure!(
        `%r = fmul double %0, %1
         ret double %r`,
        double
    )(a, b);
}

private ulong bits(double value)
    @trusted pure nothrow @nogc
{
    return *cast(const(ulong)*) &value;
}

private double fromBits(ulong value)
    @trusted pure nothrow @nogc
{
    return *cast(const(double)*) &value;
}

private bool finiteBits(ulong value)
    pure nothrow @safe @nogc
{
    return (value & 0x7ff0_0000_0000_0000UL)
        != 0x7ff0_0000_0000_0000UL;
}

private void checkPair(
    double a,
    double b,
    ref ulong checked
)
{
    const double refAdd = toPrec!double(a + b);
    const double gotAdd = irAdd(a, b);

    if (bits(refAdd) != bits(gotAdd))
    {
        writefln(
            "ADD mismatch a=%016x b=%016x ref=%016x got=%016x",
            bits(a), bits(b), bits(refAdd), bits(gotAdd)
        );
        assert(false);
    }

    const double refSub = toPrec!double(a - b);
    const double gotSub = irSub(a, b);

    if (bits(refSub) != bits(gotSub))
    {
        writefln(
            "SUB mismatch a=%016x b=%016x ref=%016x got=%016x",
            bits(a), bits(b), bits(refSub), bits(gotSub)
        );
        assert(false);
    }

    const double refMul = toPrec!double(a * b);
    const double gotMul = irMul(a, b);

    if (bits(refMul) != bits(gotMul))
    {
        writefln(
            "MUL mismatch a=%016x b=%016x ref=%016x got=%016x",
            bits(a), bits(b), bits(refMul), bits(gotMul)
        );
        assert(false);
    }

    ++checked;
}

private ulong nextRandom(ref ulong state)
    pure nothrow @safe @nogc
{
    state ^= state >> 12;
    state ^= state << 25;
    state ^= state >> 27;
    return state * 0x2545_F491_4F6C_DD1DUL;
}

void main()
{
    immutable ulong[] edgeBits =
    [
        0x0000_0000_0000_0000UL,
        0x8000_0000_0000_0000UL,
        0x0000_0000_0000_0001UL,
        0x8000_0000_0000_0001UL,
        0x000f_ffff_ffff_ffffUL,
        0x800f_ffff_ffff_ffffUL,
        0x0010_0000_0000_0000UL,
        0x8010_0000_0000_0000UL,
        0x3fef_ffff_ffff_ffffUL,
        0x3ff0_0000_0000_0000UL,
        0x3ff0_0000_0000_0001UL,
        0xbff0_0000_0000_0000UL,
        0x4340_0000_0000_0000UL,
        0xc340_0000_0000_0000UL,
        0x7fef_ffff_ffff_ffffUL,
        0xffef_ffff_ffff_ffffUL
    ];

    ulong checked = 0;

    foreach (aBits; edgeBits)
    {
        foreach (bBits; edgeBits)
        {
            checkPair(
                fromBits(aBits),
                fromBits(bBits),
                checked
            );
        }
    }

    ulong state = 0x4d59_5df4_d0f3_3173UL;

    enum size_t targetPairs = 1_000_000;
    size_t generated = 0;

    while (generated < targetPairs)
    {
        const ulong aBits = nextRandom(state);
        const ulong bBits = nextRandom(state);

        if (!finiteBits(aBits) || !finiteBits(bBits))
            continue;

        checkPair(
            fromBits(aBits),
            fromBits(bBits),
            checked
        );

        ++generated;
    }

    writeln("IR semantic probe: PASS");
    writefln("checked finite pairs: %s", checked);
}
D

printf '\n=== patch summary ===\n'
printf '\n-- direct --\n'
grep -nE \
    'return (lhs \+ rhs|lhs - rhs|lhs \* rhs);' \
    "$TMP/direct/source/geo/internal/expansion.d" \
    "$TMP/direct/source/geo/internal/orientation_exact.d"

printf '\n-- IR --\n'
grep -nE \
    'f(add|sub|mul) double' \
    "$TMP/ir/source/geo/internal/expansion.d" \
    "$TMP/ir/source/geo/internal/orientation_exact.d"

printf '\n=== build semantic probe ===\n'
ldc2 \
    -O3 \
    -release \
    "$TMP/ir_semantic_probe.d" \
    -of="$TMP/ir_semantic_probe"

printf '\n=== run semantic probe ===\n'
"$TMP/ir_semantic_probe"

printf '\n=== build production ===\n'
ldc2 \
    -O3 \
    -release \
    -boundscheck=off \
    -mcpu=native \
    -i \
    -Isource \
    "$BENCH" \
    -of="$PROD_BIN"

printf '\n=== build direct diagnostic ===\n'
ldc2 \
    -O3 \
    -release \
    -boundscheck=off \
    -mcpu=native \
    -i \
    -I"$TMP/direct/source" \
    "$BENCH" \
    -of="$DIRECT_BIN"

printf '\n=== build explicit IR diagnostic ===\n'
ldc2 \
    -O3 \
    -release \
    -boundscheck=off \
    -mcpu=native \
    -i \
    -I"$TMP/ir/source" \
    "$BENCH" \
    -of="$IR_BIN"

printf '\n=== toPrec references ===\n'
for item in \
    "PROD:$PROD_BIN" \
    "DIRECT:$DIRECT_BIN" \
    "IR:$IR_BIN"
do
    label="${item%%:*}"
    bin="${item#*:}"

    printf '%s: ' "$label"

    if nm -n "$bin" | grep 'toPrec' >/dev/null; then
        printf 'present\n'
    else
        printf 'none\n'
    fi
done

printf '\n=== IR hotpath instruction check ===\n'

check_ir_symbol()
{
    pattern="$1"

    sym="$(
        nm -n "$IR_BIN" |
        awk -v p="$pattern" '
            $3 ~ p && !found {
                print $3
                found = 1
            }
        '
    )"

    printf '\n-- %s --\n' "$pattern"

    if [[ -z "$sym" ]]; then
        printf 'symbol not found (possibly inlined)\n'
        return
    fi

    tmpasm="$TMP/asm-${pattern//[^A-Za-z0-9]/_}.txt"

    objdump \
        -d \
        -Mintel \
        --disassemble="$sym" \
        "$IR_BIN" > "$tmpasm"

    printf 'FMA: '
    if grep -Eiq \
        '\bv(fmadd|fmsub|fnmadd|fnmsub)[0-9]*sd\b' \
        "$tmpasm"
    then
        printf 'FOUND\n'
        grep -Ei \
            '\bv(fmadd|fmsub|fnmadd|fnmsub)[0-9]*sd\b' \
            "$tmpasm"
    else
        printf 'none\n'
    fi

    printf 'x87: '
    if grep -Eiq \
        '\b(fld|fst|fadd|fsub|fmul|fdiv)[a-z]*\b' \
        "$tmpasm"
    then
        printf 'FOUND\n'
        grep -Ei \
            '\b(fld|fst|fadd|fsub|fmul|fdiv)[a-z]*\b' \
            "$tmpasm"
    else
        printf 'none\n'
    fi

    printf 'toPrec calls: '
    if grep -q 'toPrec' "$tmpasm"; then
        printf 'FOUND\n'
        grep 'toPrec' "$tmpasm"
    else
        printf 'none\n'
    fi

    printf 'scalar binary64 op count: '
    grep -Eic \
        '\b(v?addsd|v?subsd|v?mulsd)\b' \
        "$tmpasm" ||
        true
}

check_ir_symbol 'scaleExpansionZeroElim'
check_ir_symbol 'fastExpansionSumZeroElim'
check_ir_symbol 'benchTwoSum'
check_ir_symbol 'benchTwoDiff'
check_ir_symbol 'benchFastTwoSum'
check_ir_symbol 'benchTwoProduct'

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

printf '\n================ ROUND 1 ================\n'
run_one PROD_TOPREC "$PROD_BIN"
run_one IR_EXPLICIT "$IR_BIN"
run_one DIRECT_DIAGNOSTIC "$DIRECT_BIN"

printf '\n================ ROUND 2 ================\n'
run_one IR_EXPLICIT "$IR_BIN"
run_one DIRECT_DIAGNOSTIC "$DIRECT_BIN"
run_one PROD_TOPREC "$PROD_BIN"

printf '\n================ ROUND 3 ================\n'
run_one DIRECT_DIAGNOSTIC "$DIRECT_BIN"
run_one PROD_TOPREC "$PROD_BIN"
run_one IR_EXPLICIT "$IR_BIN"
