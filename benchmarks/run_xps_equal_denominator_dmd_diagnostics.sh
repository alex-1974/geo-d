#!/usr/bin/env bash
set -euo pipefail
root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
cd "$root"
cpu=${1:-0}
iterations=${2:-20000}
case "$cpu" in (*[!0-9]*|'') echo "CPU must be an integer" >&2; exit 2;; esac
case "$iterations" in (*[!0-9]*|'') echo "iterations must be an integer" >&2; exit 2;; esac
mkdir -p build
task_dir=$(mktemp -d "$root/build/equal-denominator-dmd-diagnostics.XXXXXXXX")
probe=benchmarks/diagnostics/exact_coordinate_codegen_probe.d
imports=()
while IFS= read -r path; do imports+=("-I$path"); done < <(python3 tools/dub-import-paths.py --compiler=dmd)

{
  echo "commit=$(git rev-parse HEAD)"
  echo "tree=$(git rev-parse HEAD^{tree})"
  echo "status=$(git status --porcelain=v1 --untracked-files=no | wc -l)"
  echo "cpu=$cpu"
  echo "iterations=$iterations"
  echo "probe_sha256=$(sha256sum "$probe" | cut -d' ' -f1)"
  dmd --version | head -1
  ldc2 --version | head -1
} > "$task_dir/metadata.txt"

for compiler in dmd ldc2; do
  mapfile -t import_paths < <(python3 tools/dub-import-paths.py --compiler="$compiler")
  flags=()
  for path in "${import_paths[@]}"; do flags+=("-I$path"); done
  if [[ "$compiler" == dmd ]]; then
    opt=(-O -inline -release -boundscheck=safeonly)
  else
    opt=(-O3 -release -boundscheck=safeonly)
  fi
  bin="$task_dir/probe-$compiler"
  "$compiler" -i "${flags[@]}" "$probe" "${opt[@]}" -of="$bin"     >"$task_dir/build-$compiler.stdout" 2>"$task_dir/build-$compiler.stderr"
  taskset -c "$cpu" "$bin" "$iterations" >"$task_dir/run-$compiler.csv"
  nm -C "$bin" >"$task_dir/nm-$compiler.txt" || true
  objdump -drwC "$bin" >"$task_dir/objdump-$compiler.txt" || true
done

tar -czf "$task_dir/geo-equal-denominator-dmd-diagnostics-xps.tar.gz"   -C "$task_dir" metadata.txt run-dmd.csv run-ldc2.csv   nm-dmd.txt nm-ldc2.txt objdump-dmd.txt objdump-ldc2.txt   build-dmd.stdout build-dmd.stderr build-ldc2.stdout build-ldc2.stderr
sha256sum "$task_dir/geo-equal-denominator-dmd-diagnostics-xps.tar.gz"
printf 'Archive: %s\n' "$task_dir/geo-equal-denominator-dmd-diagnostics-xps.tar.gz"
