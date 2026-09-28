#!/usr/bin/env bash

main()
{
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 2
    repo_root="${1:-$(cd "$script_dir/.." && pwd)}"

    cd "$repo_root" || return 2

    D_SOURCE=benchmarks/boolean_overlay_cgal_reference_probe.d
    CPP_SOURCE=benchmarks/reference/cpp/boolean_overlay_cgal_reference.cpp

    D_BIN=/tmp/geo-d-boolean-overlay-reference-ldc
    CPP_BIN=/tmp/geo-d-boolean-overlay-reference-cgal

    D_OUT=/tmp/geo-d-boolean-overlay-reference-d.txt
    CPP_OUT=/tmp/geo-d-boolean-overlay-reference-cgal.txt

    D_SET_OUT=/tmp/geo-d-boolean-overlay-reference-d-set.txt
    CPP_SET_OUT=/tmp/geo-d-boolean-overlay-reference-cgal-set.txt

    #
    # Never allow a failed build/run to leave previous probe output looking
    # like current differential evidence.
    #
    rm -f \
        "$D_OUT" \
        "$CPP_OUT" \
        "$D_SET_OUT" \
        "$CPP_SET_OUT"

    if ! command -v ldc2 >/dev/null 2>&1; then
        echo 'error: ldc2 is required' >&2
        return 2
    fi

    if ! command -v dub >/dev/null 2>&1; then
        echo 'error: dub is required' >&2
        return 2
    fi

    if ! command -v g++ >/dev/null 2>&1; then
        echo 'error: g++ is required' >&2
        return 2
    fi

    if [ ! -r /usr/include/CGAL/Exact_predicates_exact_constructions_kernel.h ]; then
        echo 'error: CGAL development headers were not found' >&2
        return 2
    fi

    echo
    echo '=== toolchains ==='
    ldc2 --version | head -n 3
    g++ --version | head -n 1

    import_args=()

    while IFS= read -r import_path
    do
        [ -n "$import_path" ] || continue
        import_args+=("-I$import_path")
    done < <(
        python3 tools/dub-import-paths.py \
            --compiler=ldc2
    )

    echo
    echo '=== build geo-d research Boolean-overlay probe ==='

    if ! ldc2 \
        -O3 \
        -release \
        -boundscheck=off \
        -i \
        "${import_args[@]}" \
        "$D_SOURCE" \
        -of="$D_BIN"
    then
        echo 'FAIL: geo-d Boolean-overlay research probe build' >&2
        return 1
    fi

    echo
    echo '=== build independent CGAL/EPECK Boolean oracle ==='

    if ! g++ \
        -O2 \
        -DNDEBUG \
        -std=c++20 \
        "$CPP_SOURCE" \
        -lgmp \
        -lmpfr \
        -o "$CPP_BIN"
    then
        echo 'FAIL: CGAL/EPECK Boolean oracle build' >&2
        return 1
    fi

    echo
    echo '=== run probes ==='

    if ! "$D_BIN" >"$D_OUT"; then
        echo 'FAIL: geo-d research probe execution' >&2
        return 1
    fi

    if ! "$CPP_BIN" >"$CPP_OUT"; then
        echo 'FAIL: CGAL/EPECK oracle execution' >&2
        return 1
    fi

    echo
    echo '=== raw result counts ==='
    printf 'geo-d lines: '
    wc -l <"$D_OUT"
    printf 'CGAL lines:  '
    wc -l <"$CPP_OUT"

    if [ "$(wc -l <"$D_OUT")" -ne 45 ] ||
       [ "$(wc -l <"$CPP_OUT")" -ne 45 ]; then
        echo 'FAIL: expected 45 differential cases per implementation' >&2
        return 1
    fi

    if grep -n '|status=' "$D_OUT"; then
        echo 'FAIL: geo-d research P1 returned a non-success status' >&2
        return 1
    fi

    #
    # Cross-library oracle contract:
    #
    # Compare the regularized result set, not one library's decomposition of
    # that set into polygon-with-holes objects.
    #
    # geo-d's own component/hole decomposition is checked explicitly inside
    # the D probe above. CGAL component/hole counts remain diagnostic output.
    #
    sed -E \
        -e 's/\|geo_components=[0-9]+//' \
        -e 's/\|holes=[0-9]+//' \
        "$D_OUT" \
        >"$D_SET_OUT"

    sed -E \
        -e 's/\|cgal_polygons_with_holes=[0-9]+//' \
        -e 's/\|holes=[0-9]+//' \
        "$CPP_OUT" \
        >"$CPP_SET_OUT"

    echo
    echo '=== representation policy ==='
    echo 'geo-d component/hole counts: checked internally against research expectations'
    echo 'CGAL component/hole counts:  diagnostic only'
    echo 'cross-library comparison:    operation + area2 + classified result set'

    echo
    echo '=== normalized signatures ==='
    sha256sum \
        "$D_SET_OUT" \
        "$CPP_SET_OUT"

    echo
    echo '=== sample ==='
    head -n 10 "$D_OUT"

    echo
    echo '=== differential regularized-set comparison ==='

    if diff -u "$CPP_SET_OUT" "$D_SET_OUT"; then
        echo
        echo 'PASS: geo-d research Boolean overlay matches CGAL/EPECK'
        echo '      9 fixtures x 5 operations = 45 differential results'
        return 0
    fi

    echo
    echo 'FAIL: geo-d research Boolean overlay differs from CGAL/EPECK' >&2
    return 1
}

main "$@"
