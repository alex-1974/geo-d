#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${1:-$(cd "$script_dir/../.." && pwd)}"
cd "$repo_root"

BENCH=benchmarks/expansion_component_bench.d

TOPREC_BIN=/tmp/geo-d-expansion-rounding-toprec
DIRECT_BIN=/tmp/geo-d-expansion-rounding-direct
IR_BIN=/tmp/geo-d-expansion-rounding-ir

TMP=/tmp/geo-d-ir-rounding-probe
rm -rf "$TMP"
mkdir -p "$TMP/toprec" "$TMP/direct"

cp -a source "$TMP/toprec/source"
cp -a source "$TMP/direct/source"

python3 - "$TMP" <<'PY'
from pathlib import Path
import sys

tmp = Path(sys.argv[1])

def replace_exact(path, old, new, label):
    text = path.read_text()
    count = text.count(old)

    if count != 1:
        raise SystemExit(
            f"{label}: expected exactly one match in {path}, found {count}"
        )

    path.write_text(text.replace(old, new, 1))


ir_add = """        return __ir_pure!(
            `%r = fadd double %0, %1
             ret double %r`,
            double
        )(lhs, rhs);"""

ir_sub = """        return __ir_pure!(
            `%r = fsub double %0, %1
             ret double %r`,
            double
        )(lhs, rhs);"""

ir_mul = """        return __ir_pure!(
            `%r = fmul double %0, %1
             ret double %r`,
            double
        )(lhs, rhs);"""


# ------------------------------------------------------------------
# Portable toPrec reference variant.
# ------------------------------------------------------------------

toprec = (
    tmp
    / "toprec"
    / "source"
    / "geo"
    / "internal"
    / "binary64_rounding.d"
)

replace_exact(
    toprec,
    "    import ldc.llvmasm : __ir_pure;",
    "    import core.math : toPrec;",
    "toPrec import",
)

replace_exact(
    toprec,
    ir_add,
    "        return toPrec!double(lhs + rhs);",
    "toPrec add",
)

replace_exact(
    toprec,
    ir_sub,
    "        return toPrec!double(lhs - rhs);",
    "toPrec sub",
)

replace_exact(
    toprec,
    ir_mul,
    "        return toPrec!double(lhs * rhs);",
    "toPrec mul",
)


# ------------------------------------------------------------------
# Direct-D diagnostic variant.
# ------------------------------------------------------------------

direct = (
    tmp
    / "direct"
    / "source"
    / "geo"
    / "internal"
    / "binary64_rounding.d"
)

replace_exact(
    direct,
    "    import ldc.llvmasm : __ir_pure;",
    "    // Direct-arithmetic diagnostic variant.",
    "direct import",
)

replace_exact(
    direct,
    ir_add,
    "        return lhs + rhs;",
    "direct add",
)

replace_exact(
    direct,
    ir_sub,
    "        return lhs - rhs;",
    "direct sub",
)

replace_exact(
    direct,
    ir_mul,
    "        return lhs * rhs;",
    "direct mul",
)
PY

cat > "$TMP/ir_semantic_probe.d" <<'D'
module ir_semantic_probe;

import core.math : toPrec;
import geo.internal.binary64_rounding :
    roundedAdd,
    roundedMul,
    roundedSub;
import std.stdio : writeln, writefln;

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

private bool checkPair(
    double a,
    double b,
    ref ulong checked
)
{
    const double refAdd = toPrec!double(a + b);
    const double gotAdd = roundedAdd(a, b);

    if (bits(refAdd) != bits(gotAdd))
    {
        writefln(
            "ADD mismatch a=%016x b=%016x ref=%016x got=%016x",
            bits(a), bits(b), bits(refAdd), bits(gotAdd)
        );
        return false;
    }

    const double refSub = toPrec!double(a - b);
    const double gotSub = roundedSub(a, b);

    if (bits(refSub) != bits(gotSub))
    {
        writefln(
            "SUB mismatch a=%016x b=%016x ref=%016x got=%016x",
            bits(a), bits(b), bits(refSub), bits(gotSub)
        );
        return false;
    }

    const double refMul = toPrec!double(a * b);
    const double gotMul = roundedMul(a, b);

    if (bits(refMul) != bits(gotMul))
    {
        writefln(
            "MUL mismatch a=%016x b=%016x ref=%016x got=%016x",
            bits(a), bits(b), bits(refMul), bits(gotMul)
        );
        return false;
    }

    ++checked;
    return true;
}

private ulong nextRandom(ref ulong state)
    pure nothrow @safe @nogc
{
    state ^= state >> 12;
    state ^= state << 25;
    state ^= state >> 27;
    return state * 0x2545_F491_4F6C_DD1DUL;
}

int main()
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
            if (!checkPair(
                fromBits(aBits),
                fromBits(bBits),
                checked
            ))
                return 1;
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

        if (!checkPair(
            fromBits(aBits),
            fromBits(bBits),
            checked
        ))
            return 1;

        ++generated;
    }

    writeln("IR semantic probe: PASS");
    writefln("checked finite pairs: %s", checked);
    return 0;
}
D

printf '\n=== patch summary ===\n'

printf '\n-- toPrec reference backend --\n'
grep -nE \
    'return toPrec!double\(lhs [+\*-] rhs\);' \
    "$TMP/toprec/source/geo/internal/binary64_rounding.d"

printf '\n-- direct diagnostic backend --\n'
grep -nE \
    'return lhs [+\*-] rhs;' \
    "$TMP/direct/source/geo/internal/binary64_rounding.d"

printf '\n-- production explicit IR backend --\n'
grep -nE \
    'f(add|sub|mul) double' \
    source/geo/internal/binary64_rounding.d

printf '\n=== build semantic probe ===\n'
ldc2 \
    -O3 \
    -release \
    -i \
    -Isource \
    "$TMP/ir_semantic_probe.d" \
    -of="$TMP/ir_semantic_probe"

printf '\n=== run semantic probe ===\n'
"$TMP/ir_semantic_probe"

printf '\n=== semantic probe negative control ===\n'

rm -rf "$TMP/negative"
mkdir -p "$TMP/negative"
cp -a source "$TMP/negative/source"

python3 - "$TMP/negative/source/geo/internal/binary64_rounding.d" <<'PYNEG'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old = "%r = fadd double %0, %1"
new = "%r = fsub double %0, %1"

count = text.count(old)

if count != 1:
    raise SystemExit(
        f"negative control: expected exactly one production fadd, found {count}"
    )

path.write_text(text.replace(old, new, 1))
PYNEG

ldc2 \
    -O3 \
    -release \
    -i \
    -I"$TMP/negative/source" \
    "$TMP/ir_semantic_probe.d" \
    -of="$TMP/ir_semantic_probe_negative"

if "$TMP/ir_semantic_probe_negative"; then
    printf 'error: negative semantic control unexpectedly returned success\n' >&2
    false
else
    rc=$?

    if [[ "$rc" -ne 1 ]]; then
        printf \
            'error: negative semantic control returned unexpected status %s\n' \
            "$rc" >&2
        false
    fi
fi

printf 'PASS: semantic mismatch detected under -release with status 1\n'

printf '\n=== build toPrec reference ===\n'
ldc2 \
    -O3 \
    -release \
    -boundscheck=off \
    -mcpu=native \
    -i \
    -I"$TMP/toprec/source" \
    "$BENCH" \
    -of="$TOPREC_BIN"

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

printf '\n=== build production explicit IR ===\n'
ldc2 \
    -O3 \
    -release \
    -boundscheck=off \
    -mcpu=native \
    -i \
    -Isource \
    "$BENCH" \
    -of="$IR_BIN"

printf '\n=== toPrec references ===\n'
for item in \
    "TOPREC:$TOPREC_BIN" \
    "DIRECT:$DIRECT_BIN" \
    "IR_PRODUCTION:$IR_BIN"
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
run_one TOPREC_REFERENCE "$TOPREC_BIN"
run_one IR_PRODUCTION "$IR_BIN"
run_one DIRECT_DIAGNOSTIC "$DIRECT_BIN"

printf '\n================ ROUND 2 ================\n'
run_one IR_PRODUCTION "$IR_BIN"
run_one DIRECT_DIAGNOSTIC "$DIRECT_BIN"
run_one TOPREC_REFERENCE "$TOPREC_BIN"

printf '\n================ ROUND 3 ================\n'
run_one DIRECT_DIAGNOSTIC "$DIRECT_BIN"
run_one TOPREC_REFERENCE "$TOPREC_BIN"
run_one IR_PRODUCTION "$IR_BIN"
