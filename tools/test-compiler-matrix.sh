#!/usr/bin/env bash
set -uo pipefail

DEFAULT_COMPILERS=(
    dmd-2.111.0
    dmd-2.112.1
    dmd-2.113.0
    ldc-1.41.0
    ldc-1.42.0
    ldc-1.43.0
)

if (( $# > 0 )); then
    COMPILERS=("$@")
else
    COMPILERS=("${DEFAULT_COMPILERS[@]}")
fi

ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
)"

cd "$ROOT"

BASELINE_DUB_COMMAND="${GEO_D_MATRIX_DUB:-dub-dlang-baseline}"

BASELINE_DUB="$(
    command -v "$BASELINE_DUB_COMMAND" || true
)"

if [[ -z "$BASELINE_DUB" ]]; then
    echo "ERROR: controlled DUB command not found: $BASELINE_DUB_COMMAND" >&2
    exit 1
fi

TMP_BIN="$(
    mktemp -d \
        "${TMPDIR:-/tmp}/geo-d-toolchain-bin.XXXXXX"
)"

RESULTS="$(
    mktemp \
        "${TMPDIR:-/tmp}/geo-d-toolchain-results.XXXXXX"
)"

cleanup()
{
    rm -rf "$TMP_BIN" "$RESULTS"
}

trap cleanup EXIT

ln -s "$BASELINE_DUB" "$TMP_BIN/dub"
export PATH="$TMP_BIN:$PATH"

if [[ "$(command -v dub)" != "$TMP_BIN/dub" ]]; then
    echo 'ERROR: controlled DUB is not first in PATH' >&2
    exit 1
fi

echo '=== CONTROLLED MATRIX ENVIRONMENT ==='
printf 'repository: %s\n' "$ROOT"
printf 'HEAD:       %s\n' "$(git rev-parse HEAD)"
printf 'DUB:        %s\n' "$(command -v dub)"
dub --version

echo
echo '=== COMPILERS ==='

for compiler in "${COMPILERS[@]}"
do
    path="$(command -v "$compiler" || true)"

    if [[ -z "$path" ]]; then
        echo "ERROR: compiler not found: $compiler" >&2
        exit 1
    fi

    printf '%-16s %s\n' "$compiler" "$path"
done

failures=0

record()
{
    local compiler="$1"
    local step="$2"
    local result="$3"

    printf '%-16s %-28s %s\n' \
        "$compiler" \
        "$step" \
        "$result" \
        | tee -a "$RESULTS"
}

run_step()
{
    local compiler="$1"
    local step="$2"

    shift 2

    echo
    echo "--- $compiler :: $step ---"

    if "$@"; then
        record "$compiler" "$step" PASS
        return 0
    fi

    local status=$?

    record "$compiler" "$step" "FAIL($status)"
    failures=$((failures + 1))

    return 0
}

for compiler in "${COMPILERS[@]}"
do
    echo
    echo
    echo '============================================================'
    echo "COMPILER: $compiler"
    echo '============================================================'

    "$compiler" --version | sed -n '1,5p'

    echo
    printf 'DUB: '
    dub --version

    run_step \
        "$compiler" \
        'unit-tests' \
        dub test \
            --compiler="$compiler" \
            --force

    run_step \
        "$compiler" \
        'compile-negative' \
        bash tests/compile-negative/run.sh \
            "$compiler"

    run_step \
        "$compiler" \
        'external-consumer' \
        bash -c '
            set -euo pipefail
            cd tests/consumer
            dub run \
                --compiler="$1" \
                --force
        ' bash "$compiler"

    run_step \
        "$compiler" \
        'family-consumer' \
        bash tests/family-consumer/run.sh \
            "$compiler"

    run_step \
        "$compiler" \
        'release-build' \
        dub build \
            --build=release \
            --compiler="$compiler" \
            --force
done

echo
echo
echo '=== MATRIX SUMMARY ==='

cat "$RESULTS"

expected_checks=$(( ${#COMPILERS[@]} * 5 ))
actual_checks="$(grep -cve '^[[:space:]]*$' "$RESULTS")"
passed="$(grep -cE '[[:space:]]PASS$' "$RESULTS" || true)"
failed="$(grep -cE '[[:space:]]FAIL\(' "$RESULTS" || true)"

echo
printf 'checks: %d\n' "$actual_checks"
printf 'pass:   %d\n' "$passed"
printf 'fail:   %d\n' "$failed"

if (( actual_checks != expected_checks )); then
    echo "ERROR: expected $expected_checks checks, got $actual_checks" >&2
    exit 1
fi

if (( failures != 0 )); then
    echo
    printf \
        'RESULT: GEO_D_CONTROLLED_COMPILER_MATRIX_FAIL (%d failing checks)\n' \
        "$failures"
    exit 1
fi

echo
echo 'RESULT: GEO_D_CONTROLLED_COMPILER_MATRIX_PASS'
