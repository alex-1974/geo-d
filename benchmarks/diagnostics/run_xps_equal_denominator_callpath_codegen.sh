#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)
cd "$root"

develop=7deb69f074208ddabe2b18316820965b16cf2966
candidate=4828889625ff2dd25b44dc545a5e9addb27310ef
cpu=${1:-0}

command -v dmd >/dev/null
command -v dub >/dev/null
command -v objdump >/dev/null
command -v nm >/dev/null
command -v size >/dev/null
command -v readelf >/dev/null

allowed=$(taskset -pc $$ | sed 's/.*: //')
echo "allowed CPUs: $allowed"
echo "requested CPU: $cpu"

out=$(mktemp -d "$root/build/equal-denominator-callpath-codegen.XXXXXXXX")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "output: $out"

git worktree add --detach "$tmp/develop" "$develop"
git worktree add --detach "$tmp/candidate" "$candidate"
trap 'git worktree remove --force "$tmp/develop" >/dev/null 2>&1 || true; git worktree remove --force "$tmp/candidate" >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT

build_one() {
    local label=$1
    local src="$tmp/$label"
    local dst="$out/$label"
    mkdir -p "$dst"

    echo "[build] $label"
    (
        cd "$src"
        git status --short --branch > "$dst/git-status.txt"
        git rev-parse HEAD > "$dst/commit.txt"
        dmd --version > "$dst/dmd-version.txt"
        dub --version > "$dst/dub-version.txt"

        python3 tools/dub-import-paths.py --compiler="$(command -v dmd)" > "$dst/import-paths.txt"
        mapfile -t imports < "$dst/import-paths.txt"

        args=(dmd -i)
        for p in "${imports[@]}"; do
            args+=("-I$p")
        done
        args+=(
            benchmarks/segment_polygon_bench.d
            -O -inline -release -boundscheck=safeonly
            "-of=$dst/benchmark"
        )

        printf '%q ' "${args[@]}" > "$dst/build-command.txt"
        printf '\n' >> "$dst/build-command.txt"
        "${args[@]}" >"$dst/build.stdout" 2>"$dst/build.stderr"

        echo "[preflight] $label"
        taskset -c "$cpu" "$dst/benchmark" --check >"$dst/preflight.stdout" 2>"$dst/preflight.stderr"

        echo "[symbols] $label"
        nm -S -n "$dst/benchmark" > "$dst/nm.raw.txt"
        nm -S -n -C "$dst/benchmark" > "$dst/nm.demangled.txt" || true
        size "$dst/benchmark" > "$dst/size.txt"
        readelf -SW "$dst/benchmark" > "$dst/sections.txt"

        echo "[disassembly] $label"
        objdump -drw "$dst/benchmark" > "$dst/objdump.raw.txt"
        objdump -drwC "$dst/benchmark" > "$dst/objdump.demangled.txt" || true

        grep -nE -C 8           'compareExactCoordinates|compareExactOverlayPoints|compareExactOverlayPointsAlongSegment|sortUniqueExactEdgeEvents|siftDownExactEdgeEvents|findExactEventIndex|multiplyUnsigned|compareUnsigned'           "$dst/objdump.demangled.txt" > "$dst/hotpath-disassembly.txt" || true

        grep -nE           'compareExactCoordinates|compareExactOverlayPoints|compareExactOverlayPointsAlongSegment|sortUniqueExactEdgeEvents|siftDownExactEdgeEvents|findExactEventIndex|multiplyUnsigned|compareUnsigned'           "$dst/nm.demangled.txt" > "$dst/hotpath-symbols.txt" || true

        sha256sum "$dst/benchmark" > "$dst/benchmark.sha256"
    )
}

build_one develop
build_one candidate

echo "[diff] symbols / codegen"
diff -u "$out/develop/hotpath-symbols.txt" "$out/candidate/hotpath-symbols.txt" > "$out/hotpath-symbols.diff" || true
diff -u "$out/develop/size.txt" "$out/candidate/size.txt" > "$out/size.diff" || true
diff -u "$out/develop/hotpath-disassembly.txt" "$out/candidate/hotpath-disassembly.txt" > "$out/hotpath-disassembly.diff" || true

cat > "$out/README.txt" <<EOF
Purpose: DMD production call-path codegen comparison for geo-d PR #89.
Develop:   $develop
Candidate: $candidate
Flags: -O -inline -release -boundscheck=safeonly
CPU: $cpu

Interpretation:
- This archive is code-generation evidence, not wall-clock performance evidence.
- Both revisions are built from detached immutable worktrees with identical flags.
- preflight.stdout must end in PASS for both revisions.
- hotpath-symbols.txt records surviving out-of-line symbols.
- hotpath-disassembly.txt records context around comparator/sort/multiply symbols and calls.
- Full raw/demangled objdump output is retained for inspection if inlining removes named call sites.
EOF

archive="$out/geo-equal-denominator-callpath-codegen-xps.tar.gz"
tar -czf "$archive" -C "$out"     README.txt     hotpath-symbols.diff size.diff hotpath-disassembly.diff     develop candidate

sha256sum "$archive"
printf 'Archive: %s\n' "$archive"
